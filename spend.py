import datetime
import glob
import json
import os
import stat
import sys

HOME = os.path.expanduser("~")
CLAUDE_DIR = os.environ.get("CLAUDE_CONFIG_DIR", f"{HOME}/.claude")
ROOTS = [f"{CLAUDE_DIR}/projects"]
STATE_DIR = os.environ.get("ISLAND_DIR", f"{HOME}/.cache/island")
RATES = f"{HOME}/.t3/userdata/usage-model-rates.json"
CACHE = f"{STATE_DIR}/spend.json"
BLOCK_HOURS = 5
LOOKBACK_DAYS = 95
PER_MILLION = 1e-6
BUILTIN_RATES = {
    "claude-fable-5": (10.0, 1.0, 12.5, 50.0),
    "claude-opus-5": (5.0, 0.5, 6.25, 25.0),
    "claude-sonnet-5": (2.0, 0.2, 2.5, 10.0),
    "claude-opus-4-5": (5.0, 0.5, 6.25, 25.0),
    "claude-opus-4-1": (15.0, 1.5, 18.75, 75.0),
    "claude-opus-4": (15.0, 1.5, 18.75, 75.0),
    "claude-sonnet-4-5": (3.0, 0.3, 3.75, 15.0),
    "claude-sonnet-4": (3.0, 0.3, 3.75, 15.0),
    "claude-haiku-4-5": (1.0, 0.1, 1.25, 5.0),
    "claude-3-7-sonnet": (3.0, 0.3, 3.75, 15.0),
    "claude-3-5-haiku": (0.8, 0.08, 1.0, 4.0),
}


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


def rates():
    try:
        doc = read_json(RATES, 64 << 20)["document"]
    except (OSError, KeyError, ValueError):
        return {}
    if isinstance(doc, str):
        doc = json.loads(doc)
    return doc if isinstance(doc, dict) else {}


def builtin_price(model):
    name = model.lower()
    for key in sorted(BUILTIN_RATES, key=len, reverse=True):
        if key in name:
            return tuple(v * PER_MILLION for v in BUILTIN_RATES[key])
    return None


def price(table, model):
    for key in (model, f"anthropic/{model}", f"openai/{model}"):
        if key in table:
            row = table[key]
            base = row.get("input_cost_per_token", 0) or 0
            return (
                base,
                row.get("cache_read_input_token_cost", base * 0.1) or 0,
                row.get("cache_creation_input_token_cost", base * 1.25) or 0,
                row.get("output_cost_per_token", 0) or 0,
            )
    return builtin_price(model)


def load_cache():
    try:
        return read_json(CACHE, 64 << 20)
    except (OSError, ValueError):
        return {"files": {}}


def save_cache(data):
    tmp = f"{CACHE}.tmp"
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    with open(tmp, "w") as handle:
        json.dump(data, handle)
    os.replace(tmp, CACHE)


def harvest(path):
    out = []
    try:
        handle = safe_open(path)
    except OSError:
        return out
    with handle:
        for line in handle:
            if len(line) > RESPONSE_CAP or '"usage"' not in line:
                continue
            try:
                row = json.loads(line)
            except ValueError:
                continue
            message = row.get("message") or {}
            usage = message.get("usage") or row.get("usage")
            if not isinstance(usage, dict):
                continue
            stamp = row.get("timestamp")
            if not stamp:
                continue
            try:
                when = datetime.datetime.fromisoformat(stamp.replace("Z", "+00:00"))
            except ValueError:
                continue
            out.append(
                [
                    when.timestamp(),
                    message.get("model") or "?",
                    usage.get("input_tokens") or 0,
                    usage.get("cache_read_input_tokens") or 0,
                    usage.get("cache_creation_input_tokens") or 0,
                    usage.get("output_tokens") or 0,
                    f"{message.get('id')}:{row.get('requestId')}",
                ]
            )
    return out


def collect():
    cache = load_cache()
    files = cache.get("files", {})
    floor = (datetime.datetime.now() - datetime.timedelta(days=LOOKBACK_DAYS)).timestamp()
    fresh = {}
    for root in ROOTS:
        for path in glob.glob(f"{root}/**/*.jsonl", recursive=True):
            try:
                stat = os.stat(path)
            except OSError:
                continue
            if stat.st_mtime < floor:
                continue
            known = files.get(path)
            if known and known.get("m") == stat.st_mtime and known.get("s") == stat.st_size:
                fresh[path] = known
                continue
            fresh[path] = {"m": stat.st_mtime, "s": stat.st_size, "r": harvest(path)}
    cache["files"] = fresh
    save_cache(cache)
    return fresh


def summarise():
    table = rates()
    seen = set()
    events = []
    for entry in collect().values():
        for row in entry.get("r", []):
            if row[6] in seen:
                continue
            seen.add(row[6])
            events.append(row)
    events.sort(key=lambda r: r[0])

    days = {}
    for row in events:
        cost = 0.0
        tariff = price(table, row[1])
        if tariff:
            cost = row[2] * tariff[0] + row[3] * tariff[1] + row[4] * tariff[2] + row[5] * tariff[3]
        day = datetime.datetime.fromtimestamp(row[0]).strftime("%Y-%m-%d")
        bucket = days.setdefault(day, {"date": day, "cost": 0.0, "tokens": 0})
        bucket["cost"] += cost
        bucket["tokens"] += row[2] + row[3] + row[4] + row[5]
        row.append(cost)

    block = None
    if events:
        span = BLOCK_HOURS * 3600
        start = None
        previous = None
        members = []
        for row in events:
            if start is None or row[0] - previous > span or row[0] - start > span:
                start = datetime.datetime.fromtimestamp(row[0]).replace(
                    minute=0, second=0, microsecond=0
                ).timestamp()
                members = []
            members.append(row)
            previous = row[0]
        now = datetime.datetime.now().timestamp()
        if now - previous <= span and now - start <= span:
            cost = sum(r[7] for r in members)
            tokens = sum(r[2] + r[3] + r[4] + r[5] for r in members)
            elapsed = max(1.0, now - start)
            block = {
                "start": start,
                "end": start + span,
                "cost": cost,
                "tokens": tokens,
                "rate": cost / (elapsed / 3600),
                "projected": cost / (elapsed / 3600) * BLOCK_HOURS,
            }

    return {
        "daily": sorted(days.values(), key=lambda d: d["date"]),
        "block": block,
        "ts": datetime.datetime.now().timestamp(),
    }


if __name__ == "__main__":
    json.dump(summarise(), sys.stdout)
