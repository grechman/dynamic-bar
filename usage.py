import fcntl
import glob
import json
import os
import re
import stat
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

HOME = os.path.expanduser("~")
CLAUDE_DIR = os.environ.get("CLAUDE_CONFIG_DIR", f"{HOME}/.claude")
CODEX_HOME = os.environ.get("CODEX_HOME", f"{HOME}/.codex")
STATE_DIR = os.environ.get("ISLAND_DIR", f"{HOME}/.cache/island")
STATE_HOME = os.environ.get("XDG_STATE_HOME", f"{HOME}/.local/state")
CONFIG = os.environ.get("ISLAND_CONFIG", f"{HOME}/.config/island/island.json")
CACHE = f"{STATE_DIR}/usage.json"
LOG = f"{STATE_DIR}/usage.log"
EVENTS_DIR = f"{STATE_DIR}/events"
OMARCHY_USAGE = f"{STATE_HOME}/omarchy/agents/usage"
STALE_AFTER = 1800
MIN_INTERVAL = 110
BACKOFF_START = 300
BACKOFF_MAX = 3600
LOG_LIMIT = 512 * 1024
CLAUDE_USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
CLAUDE_UA = "claude-code/2.1.250"
CLAUDE_TOKEN_URLS = (
    "https://platform.claude.com/v1/oauth/token",
    "https://console.anthropic.com/v1/oauth/token",
)
CLAUDE_CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
CODEX_USAGE_URLS = (
    "https://chatgpt.com/backend-api/codex/usage",
    "https://chatgpt.com/backend-api/wham/usage",
)
CODEX_APP_SERVER_EVERY = 600
GEMINI_QUOTA_URL = "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota"
GEMINI_ASSIST_URL = "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist"
GEMINI_TOKEN_URL = "https://oauth2.googleapis.com/token"
KIMI_HOME = os.environ.get("KIMI_CODE_HOME", f"{HOME}/.kimi-code")
KIMI_USAGE_URL = (
    os.environ.get("KIMI_CODE_BASE_URL", "https://api.kimi.com").rstrip("/")
    + "/coding/v1/usages"
)
ZAI_GLOBAL = "https://api.z.ai"
ZAI_CN = "https://open.bigmodel.cn"
ZAI_QUOTA_PATH = "/api/monitor/usage/quota/limit"
ZAI_CN_ENV = ("BIGMODEL_API_KEY", "ZHIPU_API_KEY", "ZHIPUAI_API_KEY", "GLM_API_KEY")
ZAI_CN_FILES = (
    ".coding-relay/glm-api-key",
    ".config/bigmodel/api_key",
    ".config/zhipu/api_key",
)
GROK_HOME = os.environ.get("GROK_HOME", f"{HOME}/.grok")
GROK_BILLING_URL = "https://cli-chat-proxy.grok.com/v1/billing?format=credits"
GROK_SETTINGS_URL = "https://cli-chat-proxy.grok.com/v1/settings"
COPILOT_DIR = f"{HOME}/.config/github-copilot"
COPILOT_USAGE_URL = "https://api.github.com/copilot_internal/user"
MINIMAX_HOSTS = ("https://api.minimax.io", "https://api.minimaxi.com")
MINIMAX_REMAINS_PATH = "/v1/token_plan/remains"
MODEL_TAGS = {"fable": "fb", "opus": "op", "sonnet": "sn", "haiku": "hk"}
TAG_WORDS = (
    ("session", "5h"),
    ("5-hour", "5h"),
    ("5h", "5h"),
    ("weekly", "wk"),
    ("7-day", "wk"),
    ("week", "wk"),
    ("monthly", "mo"),
    ("30-day", "mo"),
    ("month", "mo"),
    ("daily", "1d"),
    ("day", "1d"),
)


class Skip(Exception):
    pass


class HttpError(Exception):
    def __init__(self, code, retry_after=None, body=""):
        super().__init__(f"HTTP {code}")
        self.code = code
        self.retry_after = retry_after
        self.body = body


def log(message):
    os.makedirs(STATE_DIR, exist_ok=True)
    try:
        if os.path.getsize(LOG) > LOG_LIMIT:
            os.replace(LOG, LOG + ".1")
    except OSError:
        pass
    with open(LOG, "a") as handle:
        handle.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {message}\n")


FILE_CAP = 1 << 20
RESPONSE_CAP = 1 << 20


def safe_open(path, cap=None, any_owner=False, binary=False):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode):
            raise OSError(f"not a regular file: {path}")
        if not any_owner and info.st_uid != os.getuid():
            raise OSError(f"not owned by us: {path}")
        if cap is not None and info.st_size > cap:
            raise OSError(f"too large: {path}")
    except OSError:
        os.close(fd)
        raise
    if binary:
        return os.fdopen(fd, "rb")
    return os.fdopen(fd, "r", encoding="utf-8", errors="replace")


def read_text(path, cap=FILE_CAP, any_owner=False):
    with safe_open(path, cap, any_owner) as handle:
        return handle.read(cap + 1)


def read_json(path, cap=FILE_CAP):
    return json.loads(read_text(path, cap))


def read_body(response, cap=RESPONSE_CAP):
    raw = response.read(cap + 1)
    if len(raw) > cap:
        raise ValueError("response too large")
    return raw


def config():
    try:
        raw = read_json(CONFIG)
    except (OSError, ValueError):
        raw = {}
    usage = raw.get("usage") if isinstance(raw, dict) else None
    usage = usage if isinstance(usage, dict) else {}
    return {
        "providers": [str(p) for p in usage.get("providers") or []],
        "pinned": [str(p) for p in usage.get("pinned") or []],
    }


def retry_after_seconds(headers):
    raw = (headers.get("Retry-After") or "").strip() if headers else ""
    if not raw:
        return None
    if raw.isdigit():
        return int(raw)
    try:
        from email.utils import parsedate_to_datetime

        return max(0, int(parsedate_to_datetime(raw).timestamp() - time.time()))
    except (TypeError, ValueError):
        return None


def http_json(url, data=None, headers=None, method=None, timeout=15):
    body = data
    if isinstance(data, (dict, list)):
        body = json.dumps(data).encode()
    req = urllib.request.Request(
        url,
        data=body,
        headers=headers or {},
        method=method or ("POST" if body else "GET"),
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            raw = read_body(response)
    except urllib.error.HTTPError as error:
        text = ""
        try:
            text = error.read(400).decode("utf-8", "replace")
        except (OSError, ValueError):
            pass
        raise HttpError(error.code, retry_after_seconds(error.headers), text) from None
    if not raw:
        return {}
    return json.loads(raw)


def state(p):
    return "ok" if p < 70 else "warn" if p <= 90 else "crit"


def clamp(value):
    try:
        return max(0, min(100, int(round(float(value)))))
    except (TypeError, ValueError):
        return None


def parse_iso(value):
    if not value:
        return None
    text = str(value).strip()
    if text.isdigit():
        ts = int(text)
        return ts / 1000 if ts > 1e12 else ts
    try:
        return (
            datetime.fromisoformat(text.replace("Z", "+00:00"))
            .astimezone(timezone.utc)
            .timestamp()
        )
    except ValueError:
        return None


def epoch(value):
    if value is None or value == "":
        return None
    if isinstance(value, (int, float)):
        return value / 1000 if value > 1e12 else float(value)
    return parse_iso(value)


def tag_for(label):
    text = str(label or "").lower()
    for word, tag in TAG_WORDS:
        if word in text:
            return tag
    hours = re.search(r"(\d+)\s*h", text)
    if hours:
        return f"{hours.group(1)}h"
    days = re.search(r"(\d+)\s*d", text)
    if days:
        return f"{days.group(1)}d"
    return text[:2] or "lim"


def window(key, tag, name, pct, reset=None, **extra):
    if pct is None:
        return None
    out = {"key": key, "tag": tag, "name": name, "pct": pct, "reset": epoch(reset)}
    out.update(extra)
    return out


def duration_tag(minutes):
    if not minutes:
        return "lim"
    if minutes % 1440 == 0:
        days = minutes // 1440
        return "wk" if days == 7 else "mo" if days >= 28 else f"{days}d"
    if minutes % 60 == 0:
        return f"{minutes // 60}h"
    return f"{minutes}m"


def plan_label(tier, subscription):
    match = re.search(r"max_(\d+x)", tier or "", re.IGNORECASE)
    if match:
        return "Max " + match.group(1)
    if subscription:
        return subscription[0].upper() + subscription[1:]
    return ""


def detect_claude():
    return os.path.exists(f"{CLAUDE_DIR}/.credentials.json")


def claude_cli_running():
    try:
        probe = subprocess.run(
            ["pgrep", "-x", "claude"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except OSError:
        return False
    return probe.returncode == 0


def claude_dead(entry, stamp):
    entry["auth_stamp"] = stamp
    return Skip("sign-in expired, start claude")


def refresh_claude(entry, path):
    try:
        stamp = os.stat(path).st_mtime_ns
    except OSError:
        raise Skip("not signed in")
    if entry.get("auth_stamp") == stamp:
        raise Skip("sign-in expired, start claude")
    if claude_cli_running():
        raise Skip("sign-in expired, start claude")
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(f"{STATE_DIR}/claude-refresh.lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        creds = read_json(path)
        login = creds.get("claudeAiOauth") or {}
        token = str(login.get("accessToken") or "")
        expires = float(login.get("expiresAt") or 0) / 1000
        if token and expires > time.time() + 120:
            return token, login
        refresh = str(login.get("refreshToken") or "")
        if not refresh:
            raise claude_dead(entry, stamp)
        d = None
        last = None
        dead = True
        for url in CLAUDE_TOKEN_URLS:
            try:
                d = http_json(
                    url,
                    {
                        "grant_type": "refresh_token",
                        "refresh_token": refresh,
                        "client_id": CLAUDE_CLIENT_ID,
                    },
                    {"Content-Type": "application/json", "User-Agent": CLAUDE_UA},
                )
                break
            except HttpError as error:
                last = error
                if error.code not in (400, 401, 403):
                    dead = False
            except urllib.error.URLError as error:
                last = error
                dead = False
        if d is None:
            if dead:
                raise claude_dead(entry, stamp)
            raise last
        token = str(d.get("access_token") or "")
        if not token:
            raise claude_dead(entry, stamp)
        login["accessToken"] = token
        login["refreshToken"] = str(d.get("refresh_token") or refresh)
        login["expiresAt"] = int(
            (time.time() + float(d.get("expires_in") or 28800)) * 1000
        )
        creds["claudeAiOauth"] = login
        tmp = path + ".tmp"
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as handle:
            json.dump(creds, handle)
        os.replace(tmp, path)
        entry.pop("auth_stamp", None)
        log("claude: token refreshed")
        return token, login


def claude_token(entry):
    path = f"{CLAUDE_DIR}/.credentials.json"
    try:
        login = read_json(path).get("claudeAiOauth") or {}
    except (OSError, ValueError, AttributeError):
        raise Skip("not signed in")
    token = str(login.get("accessToken") or "")
    if not token:
        raise Skip("not signed in")
    expires = float(login.get("expiresAt") or 0) / 1000
    if not expires or expires > time.time() + 120:
        entry.pop("auth_stamp", None)
        return token, login
    try:
        return refresh_claude(entry, path)
    except (Skip, HttpError, urllib.error.URLError):
        if expires > time.time():
            return token, login
        raise


def fetch_claude(entry):
    token, login = claude_token(entry)
    d = http_json(
        CLAUDE_USAGE_URL,
        headers={
            "Authorization": f"Bearer {token}",
            "anthropic-beta": "oauth-2025-04-20",
            "Accept": "application/json",
            "User-Agent": CLAUDE_UA,
        },
    )
    windows = []
    five = d.get("five_hour") if isinstance(d.get("five_hour"), dict) else None
    seven = d.get("seven_day") if isinstance(d.get("seven_day"), dict) else None
    if five and five.get("utilization") is not None:
        windows.append(
            window(
                "claude:5h",
                "5h",
                "claude 5h",
                clamp(five["utilization"]),
                five.get("resets_at"),
            )
        )
    if seven and seven.get("utilization") is not None:
        windows.append(
            window(
                "claude:wk",
                "wk",
                "claude weekly",
                clamp(seven["utilization"]),
                seven.get("resets_at"),
            )
        )
    for lim in d.get("limits") or []:
        if not isinstance(lim, dict) or lim.get("percent") is None:
            continue
        kind = str(lim.get("kind") or "")
        model = ((lim.get("scope") or {}).get("model") or {}).get("display_name") or ""
        entry = (clamp(lim["percent"]), lim.get("resets_at"))
        if kind == "session":
            windows = [w for w in windows if w["key"] != "claude:5h"]
            windows.insert(0, window("claude:5h", "5h", "claude 5h", *entry))
        elif kind == "weekly_all":
            windows = [w for w in windows if w["key"] != "claude:wk"]
            windows.append(window("claude:wk", "wk", "claude weekly", *entry))
        elif kind == "weekly_scoped" and model:
            slug = re.sub(r"[^a-z0-9]", "", model.lower())[:12] or "model"
            windows.append(
                window(
                    f"claude:{slug}",
                    MODEL_TAGS.get(slug, slug[:2]),
                    f"{model.lower()} weekly",
                    *entry,
                )
            )
    return {
        "plan": plan_label(
            str(login.get("rateLimitTier") or ""),
            str(login.get("subscriptionType") or ""),
        ),
        "windows": [w for w in windows if w],
    }


def detect_codex():
    return os.path.exists(f"{CODEX_HOME}/auth.json")


def codex_http():
    auth = read_json(f"{CODEX_HOME}/auth.json")
    tokens = auth.get("tokens") or {}
    token = tokens.get("access_token")
    if not token:
        raise Skip("not signed in")
    account = tokens.get("account_id") or ""
    last = None
    for url in CODEX_USAGE_URLS:
        try:
            d = http_json(
                url,
                headers={
                    "Authorization": f"Bearer {token}",
                    "chatgpt-account-id": account,
                    "User-Agent": "codex-cli",
                    "Accept": "application/json",
                },
            )
            break
        except (HttpError, urllib.error.URLError, ValueError) as error:
            last = error
    else:
        raise last
    rl = d.get("rate_limit") or {}
    wins = [w for w in (rl.get("primary_window"), rl.get("secondary_window")) if w]
    if not wins:
        raise ValueError("no rate windows")
    short = min(wins, key=lambda w: w.get("limit_window_seconds", 0))
    weekly = max(wins, key=lambda w: w.get("limit_window_seconds", 0))
    out = {
        "plan": str(d.get("plan_type") or ""),
        "windows": [
            window(
                "codex:5h",
                "5h",
                "codex 5h",
                clamp(short.get("used_percent")),
                short.get("reset_at"),
            )
        ],
    }
    if weekly is not short:
        extra = {}
        credits = d.get("rate_limit_reset_credits") or {}
        if "available_count" in credits:
            extra["resets_available"] = int(credits.get("available_count") or 0)
        out["windows"].append(
            window(
                "codex:wk",
                "wk",
                "codex weekly",
                clamp(weekly.get("used_percent")),
                weekly.get("reset_at"),
                **extra,
            )
        )
    return out


def codex_app_server():
    p = subprocess.Popen(
        ["codex", "app-server", "--stdio"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    try:

        def send(o):
            p.stdin.write(json.dumps(o) + "\n")
            p.stdin.flush()

        send(
            {
                "id": 1,
                "method": "initialize",
                "params": {
                    "clientInfo": {
                        "name": "island",
                        "title": "island",
                        "version": "1.0.0",
                    }
                },
            }
        )
        send({"method": "initialized"})
        send({"id": 2, "method": "account/rateLimits/read", "params": {}})
        deadline = time.time() + 15
        while time.time() < deadline:
            line = p.stdout.readline()
            if not line:
                break
            try:
                o = json.loads(line)
            except ValueError:
                continue
            if o.get("id") != 2:
                continue
            if "result" not in o:
                raise RuntimeError(f"app-server: {json.dumps(o.get('error'))[:200]}")
            rl = o["result"]["rateLimits"]
            wins = [w for w in (rl.get("primary"), rl.get("secondary")) if w]
            short = min(wins, key=lambda w: w.get("windowDurationMins", 0))
            weekly = max(wins, key=lambda w: w.get("windowDurationMins", 0))
            credits = o["result"].get("rateLimitResetCredits") or {}
            out = {
                "plan": "",
                "windows": [
                    window(
                        "codex:5h",
                        "5h",
                        "codex 5h",
                        clamp(short.get("usedPercent")),
                        short.get("resetsAt"),
                    )
                ],
            }
            if weekly is not short:
                out["windows"].append(
                    window(
                        "codex:wk",
                        "wk",
                        "codex weekly",
                        clamp(weekly.get("usedPercent")),
                        weekly.get("resetsAt"),
                        resets_available=int(credits.get("availableCount") or 0),
                    )
                )
            return out
        raise RuntimeError("app-server timeout")
    finally:
        p.kill()


def codex_sessions():
    files = sorted(
        glob.glob(f"{CODEX_HOME}/sessions/*/*/*/*.jsonl"),
        key=os.path.getmtime,
        reverse=True,
    )[:3]
    for path in files:
        last = None
        try:
            handle = safe_open(path)
        except OSError:
            continue
        with handle:
            for line in handle:
                if len(line) > RESPONSE_CAP:
                    continue
                if '"rate_limits"' in line:
                    last = line
        if not last:
            continue
        try:
            obj = json.loads(last)
        except ValueError:
            continue
        rl = None
        stack = [obj]
        while stack:
            cur = stack.pop()
            if isinstance(cur, dict):
                if "rate_limits" in cur:
                    rl = cur["rate_limits"]
                    break
                stack.extend(cur.values())
            elif isinstance(cur, list):
                stack.extend(cur)
        wins = [
            w for w in ((rl or {}).get("primary"), (rl or {}).get("secondary")) if w
        ]
        if not wins:
            continue
        short = min(wins, key=lambda w: w.get("window_minutes", 0))
        weekly = max(wins, key=lambda w: w.get("window_minutes", 0))
        stamp = os.path.getmtime(path)
        out = {
            "plan": "",
            "ts": stamp,
            "windows": [
                window(
                    "codex:5h",
                    "5h",
                    "codex 5h",
                    clamp(short.get("used_percent")),
                    short.get("resets_at"),
                )
            ],
        }
        if weekly is not short:
            out["windows"].append(
                window(
                    "codex:wk",
                    "wk",
                    "codex weekly",
                    clamp(weekly.get("used_percent")),
                    weekly.get("resets_at"),
                )
            )
        return out
    raise Skip("no session data")


def fetch_codex(entry):
    try:
        return codex_http()
    except Skip:
        raise
    except Exception as error:
        log(f"codex(http): {type(error).__name__}: {error}")
    last_rpc = float(entry.get("rpc_at") or 0)
    if time.time() - last_rpc >= CODEX_APP_SERVER_EVERY:
        entry["rpc_at"] = time.time()
        try:
            return codex_app_server()
        except Exception as error:
            log(f"codex(app-server): {type(error).__name__}: {error}")
    return codex_sessions()


def detect_gemini():
    return os.path.exists(f"{HOME}/.gemini/oauth_creds.json")


def gemini_client():
    binary = None
    for directory in os.environ.get("PATH", "").split(":"):
        candidate = os.path.join(directory, "gemini")
        if os.access(candidate, os.X_OK):
            binary = os.path.realpath(candidate)
            break
    if not binary:
        return None
    current = os.path.dirname(binary)
    for _ in range(8):
        for root in (
            current,
            os.path.join(current, "lib", "node_modules", "@google", "gemini-cli"),
        ):
            for rel in (
                "dist/src/code_assist/oauth2.js",
                "node_modules/@google/gemini-cli-core/dist/src/code_assist/oauth2.js",
            ):
                path = os.path.join(root, rel)
                found = gemini_client_from(path)
                if found:
                    return found
            bundle = os.path.join(root, "bundle")
            if os.path.isdir(bundle):
                for name in sorted(os.listdir(bundle)):
                    if name.endswith(".js"):
                        found = gemini_client_from(os.path.join(bundle, name))
                        if found:
                            return found
        parent = os.path.dirname(current)
        if parent == current:
            break
        current = parent
    return None


def gemini_client_from(path):
    try:
        text = read_text(path, 32 << 20, any_owner=True)
    except OSError:
        return None
    cid = re.search(r"OAUTH_CLIENT_ID\s*=\s*['\"]([\w\-.]+)['\"]", text)
    secret = re.search(r"OAUTH_CLIENT_SECRET\s*=\s*['\"]([\w\-]+)['\"]", text)
    if cid and secret:
        return cid.group(1), secret.group(1)
    return None


def gemini_token():
    creds = read_json(f"{HOME}/.gemini/oauth_creds.json")
    try:
        auth = (
            read_json(f"{HOME}/.gemini/settings.json")
            .get("security", {})
            .get("auth", {})
            .get("selectedType")
        )
    except (OSError, ValueError, AttributeError):
        auth = None
    if auth in ("api-key", "vertex-ai"):
        raise Skip(f"{auth} auth has no quota")
    token = creds.get("access_token")
    expiry = float(creds.get("expiry_date") or 0) / 1000
    if token and expiry > time.time() + 60:
        return token
    refresh = creds.get("refresh_token")
    client = gemini_client()
    if not refresh or not client:
        raise Skip("sign-in expired, run gemini")
    body = urllib.parse.urlencode(
        {
            "client_id": client[0],
            "client_secret": client[1],
            "refresh_token": refresh,
            "grant_type": "refresh_token",
        }
    ).encode()
    d = http_json(
        GEMINI_TOKEN_URL, body, {"Content-Type": "application/x-www-form-urlencoded"}
    )
    token = d.get("access_token")
    if not token:
        raise Skip("token refresh failed")
    return token


def fetch_gemini():
    token = gemini_token()
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    project = None
    plan = ""
    try:
        assist = http_json(
            GEMINI_ASSIST_URL,
            {"metadata": {"ideType": "GEMINI_CLI", "pluginType": "GEMINI"}},
            headers,
        )
        raw = assist.get("cloudaicompanionProject")
        project = raw.get("id") if isinstance(raw, dict) else raw
        tier = assist.get("currentTier") or {}
        plan = str(tier.get("name") or tier.get("id") or "")
    except (HttpError, urllib.error.URLError, ValueError):
        pass
    d = http_json(GEMINI_QUOTA_URL, {"project": project} if project else {}, headers)
    buckets = d.get("buckets") or []
    groups = {}
    for bucket in buckets:
        model = str(bucket.get("modelId") or "")
        fraction = bucket.get("remainingFraction")
        if not model or fraction is None:
            continue
        tier = (
            "lite"
            if "flash-lite" in model
            else "flash"
            if "flash" in model
            else "pro"
            if "pro" in model
            else model[:5]
        )
        current = groups.get(tier)
        if current is None or float(fraction) < current[0]:
            groups[tier] = (float(fraction), bucket.get("resetTime"))
    order = ("pro", "flash", "lite")
    windows = []
    for tier in sorted(groups, key=lambda t: order.index(t) if t in order else 9):
        fraction, reset = groups[tier]
        tag = {"pro": "pro", "flash": "fl", "lite": "lt"}.get(tier, tier[:2])
        windows.append(
            window(
                f"gemini:{tier}",
                tag,
                f"gemini {tier}",
                clamp((1 - fraction) * 100),
                reset,
            )
        )
    if not windows:
        raise ValueError("no quota buckets")
    return {"plan": plan, "windows": windows}


def kimi_token():
    env = os.environ.get("KIMI_CODE_API_KEY")
    if env:
        return env.strip()
    cred = read_json(f"{KIMI_HOME}/credentials/kimi-code.json")
    token = str(cred.get("access_token") or "")
    expires = float(cred.get("expires_at") or 0)
    if not token:
        raise Skip("not signed in")
    if expires and expires <= time.time() + 60:
        raise Skip("sign-in expired, run kimi")
    return token


def detect_kimi():
    return bool(os.environ.get("KIMI_CODE_API_KEY")) or os.path.exists(
        f"{KIMI_HOME}/credentials/kimi-code.json"
    )


def fetch_kimi():
    headers = {
        "Authorization": f"Bearer {kimi_token()}",
        "Accept": "application/json",
        "User-Agent": "island/1.0",
        "X-Msh-Platform": "kimi_code_cli",
    }
    try:
        headers["X-Msh-Device-Id"] = read_text(f"{KIMI_HOME}/device_id", 4096).strip()
    except OSError:
        pass
    d = http_json(KIMI_USAGE_URL, headers=headers)
    windows = []

    def pct_of(detail):
        limit = float(detail.get("limit") or 0)
        used = detail.get("used")
        if used is None and detail.get("remaining") is not None:
            used = limit - float(detail["remaining"])
        if limit <= 0 or used is None:
            return None
        return clamp(float(used) / limit * 100)

    for lim in d.get("limits") or []:
        win = lim.get("window") or {}
        detail = lim.get("detail") or {}
        unit = {"TIME_UNIT_MINUTE": 1, "TIME_UNIT_HOUR": 60, "TIME_UNIT_DAY": 1440}.get(
            str(win.get("timeUnit")), 0
        )
        minutes = int(win.get("duration") or 0) * unit
        tag = duration_tag(minutes)
        reset = (
            detail.get("resetTime")
            or detail.get("reset_time")
            or detail.get("resetAt")
            or detail.get("reset_at")
        )
        windows.append(window(f"kimi:{tag}", tag, f"kimi {tag}", pct_of(detail), reset))
    usage = d.get("usage") or {}
    if usage:
        reset = (
            usage.get("resetTime")
            or usage.get("reset_time")
            or usage.get("resetAt")
            or usage.get("reset_at")
        )
        windows.append(window("kimi:wk", "wk", "kimi weekly", pct_of(usage), reset))
    windows = [w for w in windows if w]
    if not windows:
        raise ValueError("no usage windows")
    return {"plan": "", "windows": windows}


def zai_credential():
    token = os.environ.get("Z_AI_API_KEY")
    if token:
        return token.strip(), ZAI_GLOBAL
    for key in ZAI_CN_ENV:
        if os.environ.get(key):
            return os.environ[key].strip(), ZAI_CN
    for rel in ZAI_CN_FILES:
        try:
            token = read_text(f"{HOME}/{rel}", 4096).splitlines()[0].strip()
            if token:
                return token, ZAI_CN
        except OSError:
            continue
    return None, None


def detect_zai():
    return zai_credential()[0] is not None


def fetch_zai():
    token, host = zai_credential()
    if not token:
        raise Skip("no api key")
    host = os.environ.get("Z_AI_API_HOST") or host
    if not host.startswith("http"):
        host = "https://" + host
    d = http_json(
        host.rstrip("/") + ZAI_QUOTA_PATH,
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
    )
    data = d.get("data") if isinstance(d.get("data"), dict) else d
    windows = []
    plan = ""
    for key in ("planName", "plan", "plan_type", "packageName", "level"):
        if data.get(key):
            plan = str(data[key])
            break
    for lim in data.get("limits") or []:
        if not isinstance(lim, dict):
            continue
        kind = str(lim.get("type") or "")
        pct = None
        for key in ("percentage", "percent", "usedPercent", "used_percent"):
            if lim.get(key) is not None:
                pct = clamp(lim[key])
                break
        if pct is None:
            total = lim.get("total") or lim.get("limit")
            used = lim.get("usage") if lim.get("usage") is not None else lim.get("used")
            if total and used is not None:
                pct = clamp(float(used) / float(total) * 100)
        unit = str(lim.get("unit") or "").lower()
        number = lim.get("number")
        minutes = 0
        if number:
            minutes = int(number) * (
                60
                if "hour" in unit
                else 1440
                if "day" in unit
                else 1
                if "min" in unit
                else 0
            )
        tag = (
            duration_tag(minutes)
            if minutes
            else ("mcp" if kind == "TIME_LIMIT" else "lim")
        )
        if kind == "TIME_LIMIT":
            tag = "mcp"
        windows.append(
            window(f"zai:{tag}", tag, f"glm {tag}", pct, lim.get("nextResetTime"))
        )
    windows = [w for w in windows if w]
    if not windows:
        raise ValueError("no limits")
    return {"plan": plan, "windows": windows}


def grok_credential():
    root = read_json(f"{GROK_HOME}/auth.json")
    chosen = None
    for scope, entry in root.items():
        if not isinstance(entry, dict) or not entry.get("key"):
            continue
        if scope.startswith("https://auth.x.ai::"):
            chosen = entry
            break
        if chosen is None:
            chosen = entry
    if not chosen:
        raise Skip("not signed in")
    expires = parse_iso(chosen.get("expires_at"))
    if expires and expires <= time.time():
        raise Skip("sign-in expired, run grok login")
    return chosen["key"]


def detect_grok():
    return os.path.exists(f"{GROK_HOME}/auth.json")


def fetch_grok():
    headers = {
        "Authorization": f"Bearer {grok_credential()}",
        "x-xai-token-auth": "xai-grok-cli",
        "Accept": "application/json",
        "User-Agent": "island/1.0",
    }
    d = http_json(GROK_BILLING_URL, headers=headers)
    cfg = d.get("config") or {}
    pct = None
    if cfg.get("creditUsagePercent") is not None:
        pct = clamp(cfg["creditUsagePercent"])
    else:
        cap = (cfg.get("onDemandCap") or {}).get("val")
        used = (cfg.get("onDemandUsed") or {}).get("val")
        if cap and used is not None:
            pct = clamp(float(used) / float(cap) * 100)
    reset = (cfg.get("currentPeriod") or {}).get("end") or cfg.get("billingPeriodEnd")
    plan = str(cfg.get("subscriptionTier") or d.get("subscriptionTier") or "")
    try:
        settings = http_json(GROK_SETTINGS_URL, headers=headers, timeout=5)
        plan = str(settings.get("subscription_tier_display") or plan)
    except (HttpError, urllib.error.URLError, ValueError):
        pass
    win = window("grok:mo", "mo", "grok credits", pct, reset)
    if not win:
        raise ValueError("no credit usage")
    return {"plan": plan, "windows": [win]}


def copilot_token():
    for name in ("apps.json", "hosts.json"):
        try:
            data = read_json(f"{COPILOT_DIR}/{name}")
        except (OSError, ValueError):
            continue
        for key, entry in data.items():
            if (
                isinstance(entry, dict)
                and entry.get("oauth_token")
                and "github.com" in key
            ):
                return entry["oauth_token"]
    raise Skip("not signed in")


def detect_copilot():
    return os.path.exists(f"{COPILOT_DIR}/apps.json") or os.path.exists(
        f"{COPILOT_DIR}/hosts.json"
    )


def fetch_copilot():
    d = http_json(
        COPILOT_USAGE_URL,
        headers={
            "Authorization": f"token {copilot_token()}",
            "Accept": "application/json",
            "Editor-Version": "vscode/1.96.2",
            "Editor-Plugin-Version": "copilot-chat/0.26.7",
            "User-Agent": "GitHubCopilotChat/0.26.7",
            "X-Github-Api-Version": "2025-04-01",
        },
    )
    snaps = d.get("quota_snapshots") or {}
    reset = d.get("quota_reset_date")
    windows = []
    for key, tag, name in (
        ("premium_interactions", "pr", "copilot premium"),
        ("chat", "ch", "copilot chat"),
    ):
        snap = snaps.get(key) or {}
        if not snap or snap.get("unlimited"):
            continue
        pct = None
        if snap.get("percent_remaining") is not None:
            pct = clamp(100 - float(snap["percent_remaining"]))
        elif snap.get("entitlement") and snap.get("remaining") is not None:
            pct = clamp(
                100 - float(snap["remaining"]) / float(snap["entitlement"]) * 100
            )
        windows.append(window(f"copilot:{tag}", tag, name, pct, reset))
    windows = [w for w in windows if w]
    if not windows:
        raise ValueError("no metered quota")
    return {"plan": str(d.get("copilot_plan") or ""), "windows": windows}


def detect_minimax():
    return bool(os.environ.get("MINIMAX_API_KEY"))


def fetch_minimax():
    token = os.environ.get("MINIMAX_API_KEY", "").strip()
    hosts = (
        [os.environ["MINIMAX_HOST"]]
        if os.environ.get("MINIMAX_HOST")
        else list(MINIMAX_HOSTS)
    )
    last = None
    d = None
    for host in hosts:
        if not host.startswith("http"):
            host = "https://" + host
        try:
            d = http_json(
                host.rstrip("/") + MINIMAX_REMAINS_PATH,
                headers={
                    "Authorization": f"Bearer {token}",
                    "Accept": "application/json",
                },
            )
            break
        except HttpError as error:
            last = error
            if error.code not in (401, 403, 404):
                raise
    if d is None:
        raise last
    found = []
    stack = [d]
    while stack:
        cur = stack.pop()
        if isinstance(cur, dict):
            if (
                "current_interval_remaining_percent" in cur
                or "current_weekly_remaining_percent" in cur
            ):
                found.append(cur)
            else:
                stack.extend(cur.values())
        elif isinstance(cur, list):
            stack.extend(cur)
    if not found:
        raise ValueError("no remains")
    item = found[0]
    windows = []
    if item.get("current_interval_remaining_percent") is not None:
        windows.append(
            window(
                "minimax:5h",
                "5h",
                "minimax 5h",
                clamp(100 - float(item["current_interval_remaining_percent"])),
                item.get("end_time"),
            )
        )
    if item.get("current_weekly_remaining_percent") is not None:
        windows.append(
            window(
                "minimax:wk",
                "wk",
                "minimax weekly",
                clamp(100 - float(item["current_weekly_remaining_percent"])),
                item.get("weekly_end_time"),
            )
        )
    windows = [w for w in windows if w]
    if not windows:
        raise ValueError("no remains")
    return {"plan": str(item.get("model_name") or ""), "windows": windows}


PROVIDERS = [
    ("claude", "Claude", detect_claude, fetch_claude),
    ("codex", "Codex", detect_codex, fetch_codex),
    ("gemini", "Gemini", detect_gemini, lambda entry: fetch_gemini()),
    ("kimi", "Kimi", detect_kimi, lambda entry: fetch_kimi()),
    ("zai", "GLM", detect_zai, lambda entry: fetch_zai()),
    ("grok", "Grok", detect_grok, lambda entry: fetch_grok()),
    ("copilot", "Copilot", detect_copilot, lambda entry: fetch_copilot()),
    ("minimax", "MiniMax", detect_minimax, lambda entry: fetch_minimax()),
]
MIN_INTERVALS = {
    "gemini": 600,
    "kimi": 300,
    "zai": 300,
    "grok": 600,
    "copilot": 600,
    "minimax": 300,
}


def omarchy_records(skip):
    out = []
    for path in sorted(glob.glob(f"{OMARCHY_USAGE}/*.json")):
        try:
            record = read_json(path)
        except (OSError, ValueError):
            continue
        pid = str(record.get("id") or os.path.basename(path)[:-5])
        if pid in skip or not isinstance(record, dict):
            continue
        windows = []
        for lim in record.get("limits") or []:
            if not isinstance(lim, dict) or lim.get("percent") is None:
                continue
            title = str(lim.get("title") or lim.get("label") or "")
            tag = tag_for(title)
            if lim.get("title") and " " in title:
                tag = re.sub(r"[^a-z0-9]", "", title.split(" ")[0].lower())[:2] or tag
            pct = float(lim["percent"])
            pct = pct * 100 if pct <= 1 else pct
            windows.append(
                window(
                    f"{pid}:{tag}",
                    tag,
                    f"{pid} {title.lower()}".strip(),
                    clamp(pct),
                    lim.get("resetsAt"),
                )
            )
        windows = [w for w in windows if w]
        if not windows:
            continue
        out.append(
            {
                "id": pid,
                "name": str(record.get("name") or pid.capitalize()),
                "plan": str(record.get("tierLabel") or ""),
                "windows": windows,
                "ts": parse_iso(record.get("updatedAt")) or os.path.getmtime(path),
                "source": "omarchy",
            }
        )
    return out


def load_cache():
    try:
        data = read_json(CACHE)
        if isinstance(data, dict) and isinstance(data.get("providers"), dict):
            return data
    except (OSError, ValueError):
        pass
    return {"providers": {}}


def save_cache(cache):
    os.makedirs(STATE_DIR, exist_ok=True)
    tmp = CACHE + ".tmp"
    with open(tmp, "w") as handle:
        json.dump(cache, handle)
    os.replace(tmp, CACHE)


def live_windows(windows, now):
    out = []
    for win in windows:
        reset = win.get("reset")
        if reset and reset < now - 60:
            continue
        out.append(win)
    return out


def backoff(entry, now, retry_after=None):
    failures = int(entry.get("failures") or 0) + 1
    delay = min(BACKOFF_MAX, BACKOFF_START * 2 ** min(failures - 1, 10))
    if retry_after:
        delay = max(delay, int(retry_after))
    entry["failures"] = failures
    entry["retry_at"] = now + delay
    return delay


def post_reset_events(pid, name, old, new):
    old_map = {w["key"]: w for w in old or []}
    for win in new:
        prev = old_map.get(win["key"])
        if not prev or not prev.get("reset") or not win.get("reset"):
            continue
        if win["reset"] > prev["reset"] + 60 and int(prev.get("pct") or 0) >= 25:
            os.makedirs(EVENTS_DIR, exist_ok=True)
            event = {
                "id": f"reset-{win['key']}",
                "icon": "",
                "text": f"{win['name']} reset",
                "severity": "good",
                "ttl": 5,
            }
            with open(
                f"{EVENTS_DIR}/reset-{win['key'].replace(':', '-')}.json", "w"
            ) as handle:
                json.dump(event, handle)


def collect(force=False):
    cfg = config()
    cache = load_cache()
    entries = cache["providers"]
    now = time.time()
    errors = []
    wanted = cfg["providers"]
    active = []
    for pid, name, detect, fetch in PROVIDERS:
        if wanted and pid not in wanted:
            continue
        if not wanted and not detect():
            continue
        entry = entries.setdefault(pid, {})
        entry["name"] = name
        active.append(pid)
        due = now >= float(entry.get("next_at") or 0) or force
        blocked = now < float(entry.get("retry_at") or 0) and not force
        if blocked:
            wait = max(1, int(entry["retry_at"] - now + 59) // 60)
            entry["error"] = f"{entry.get('reason') or 'failed'}, retry in {wait} min"
            continue
        if not due:
            continue
        try:
            result = fetch(entry)
            windows = [w for w in result.get("windows") or [] if w]
            stamp = float(result.get("ts") or now)
            if entry.get("windows") and stamp < float(entry.get("ts") or 0):
                continue
            post_reset_events(pid, name, entry.get("windows"), windows)
            entry.update(
                {
                    "windows": windows,
                    "plan": result.get("plan") or "",
                    "ts": stamp,
                    "error": "",
                }
            )
            entry.pop("failures", None)
            entry.pop("retry_at", None)
            entry.pop("reason", None)
            entry["next_at"] = now + MIN_INTERVALS.get(pid, MIN_INTERVAL)
        except Skip as skip:
            entry["error"] = str(skip)
            entry["next_at"] = now + MIN_INTERVAL
        except HttpError as error:
            reason = f"HTTP {error.code}"
            delay = backoff(
                entry, now, error.retry_after if error.code == 429 else None
            )
            entry["reason"] = reason
            entry["error"] = f"{reason}, retry in {max(1, delay // 60)} min"
            log(
                f"{pid}: {reason} retry-after={error.retry_after} body={error.body[:200]!r}"
            )
        except Exception as error:
            reason = f"{type(error).__name__}: {error}"[:80]
            delay = backoff(entry, now)
            entry["reason"] = reason
            entry["error"] = f"{reason}, retry in {max(1, delay // 60)} min"
            log(f"{pid}: {reason}")
    providers = []
    for pid, name, _, _ in PROVIDERS:
        if pid not in active:
            continue
        entry = entries[pid]
        stamp = float(entry.get("ts") or 0)
        windows = live_windows(entry.get("windows") or [], now)
        stale = now - stamp > STALE_AFTER
        for win in windows:
            win["state"] = state(win["pct"])
            win["stale"] = stale
        if entry.get("error"):
            errors.append(f"{pid}: {entry['error']}")
        providers.append(
            {
                "id": pid,
                "name": name,
                "plan": entry.get("plan") or "",
                "windows": windows,
                "error": entry.get("error") or "",
                "stale": stale,
                "ts": stamp,
            }
        )
    for record in omarchy_records(set(active)):
        stale = now - float(record["ts"]) > STALE_AFTER
        for win in record["windows"]:
            win["state"] = state(win["pct"])
            win["stale"] = stale
        record["error"] = ""
        record["stale"] = stale
        providers.append(record)
    cache["providers"] = {pid: entries[pid] for pid in entries if pid in active}
    save_cache(cache)
    pinned = [p for p in cfg["pinned"] if any(prov["id"] == p for prov in providers)]
    if not pinned:
        pinned = [prov["id"] for prov in providers if prov["windows"]][:2]
    return {
        "ts": now,
        "providers": providers,
        "pinned": pinned,
        "windows": [
            dict(win, provider=prov["id"])
            for prov in providers
            for win in prov["windows"]
        ],
        "errors": errors,
    }


def listing():
    cfg = config()
    wanted = cfg["providers"]
    out = []
    for pid, name, detect, _ in PROVIDERS:
        detected = bool(detect())
        out.append(
            {
                "id": pid,
                "name": name,
                "detected": detected,
                "enabled": pid in wanted if wanted else detected,
                "pinned": pid in cfg["pinned"],
            }
        )
    if not cfg["pinned"]:
        for entry in [e for e in out if e["enabled"]][:2]:
            entry["pinned"] = True
    return {"providers": out, "auto": not wanted}


def main():
    if "--list" in sys.argv:
        print(json.dumps(listing()))
        return
    payload = collect(force="--force" in sys.argv)
    print(json.dumps(payload))


if __name__ == "__main__":
    main()
