import base64
import calendar
import colorsys
import glob
import hashlib
import html
import json
import os
import queue
import re
import fcntl
import signal
import socket
import shutil
import stat
import sqlite3
import shlex
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request
from datetime import date, datetime

HOME = os.path.expanduser("~")
PLUGIN_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_DIR = f"{HOME}/.config/island"
CONFIG = os.environ.get("ISLAND_CONFIG", f"{CONFIG_DIR}/island.json")
STATE_DIR = os.environ.get("ISLAND_DIR", f"{HOME}/.cache/island")
STATE_HOME = os.environ.get("XDG_STATE_HOME", f"{HOME}/.local/state")
OMARCHY_COLORS = f"{STATE_HOME}/omarchy/current/theme/colors.toml"
USER_COLORS = f"{CONFIG_DIR}/colors.css"
LEGACY_COLORS = f"{HOME}/.config/waybar/colors.css"
BUNDLED_COLORS = f"{PLUGIN_DIR}/assets/colors.css"
RUNCAT_SRC = f"{PLUGIN_DIR}/assets/runcat"
RUNCAT_DIR = f"{STATE_DIR}/runcat"
LOCK_FILE = f"{STATE_DIR}/daemon.lock"
TOOLS = (
    "playerctl",
    "ffmpeg",
    "ffprobe",
    "gh",
    "nmcli",
    "bluetoothctl",
    "busctl",
    "wl-paste",
    "wl-copy",
    "ssh",
)
EVENTS_DIR = f"{STATE_DIR}/events"
TASKS_DIR = f"{STATE_DIR}/tasks"
DATE_FLAG = f"{STATE_DIR}/showdate"
GH_SEEN = f"{STATE_DIR}/github-seen.json"
NTFY_TOPIC_FILE = f"{CONFIG_DIR}/ntfy-topic"
SOUND = "/usr/share/sounds/freedesktop/stereo/dialog-warning.oga"
SOUNDS = {
    "warning": "/usr/share/sounds/freedesktop/stereo/dialog-warning.oga",
    "complete": "/usr/share/sounds/freedesktop/stereo/complete.oga",
    "bell": "/usr/share/sounds/freedesktop/stereo/bell.oga",
    "message": "/usr/share/sounds/freedesktop/stereo/message-new-instant.oga",
}
TICK = 0.1
TELEGRAM_HOLD = 3.0
SCENE_FILE = f"{STATE_DIR}/scene.json"
BUBBLE_CLICK = f"{STATE_DIR}/bubble-click"
DATE_SECONDS = 4
T3_DB = os.environ.get("ISLAND_T3_DB", f"{HOME}/.t3/userdata/state.sqlite")
CLAUDE_SESSIONS = os.environ.get("ISLAND_CLAUDE_DIR", f"{HOME}/.cache/island/claude")
CLAUDE_STALE = 300.0
REMOTE_STALE = 90.0
RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
GRAB_TOOLS = ("slurp", "hyprshot", "grim", "hyprpicker")


def remote_shell():
    override = os.environ.get("ISLAND_REMOTE")
    if override is not None:
        return override
    host = str(load_config().get("remote") or "").strip()
    if not host or not shutil.which("ssh"):
        return ""
    return (
        "ssh -o BatchMode=yes -o ConnectTimeout=3 -o ControlMaster=auto"
        f" -o ControlPath={RUNTIME_DIR}/island-remote.sock -o ControlPersist=120"
        f" {shlex.quote(host)} sh -s"
    )


def probe_target():
    raw = str(load_config().get("probe_host") or "").strip()
    if not raw:
        return None
    host, _, port = raw.rpartition(":")
    if not host or not port.isdigit():
        return (raw, 22)
    return (host, int(port))


TELEGRAM_BLUE = "#229ED9"
CLAUDE_ORANGE = "#D97757"
TELEGRAM_MESSAGES = queue.SimpleQueue()
CHILDREN = set()
CHILDREN_LOCK = threading.Lock()
ART_DIR = f"{STATE_DIR}/art"
COVER_TILE = (
    "scale=512:512:force_original_aspect_ratio=increase:flags=lanczos,"
    "crop=512:512,format=rgba,"
    "geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':"
    "a='if(gt(hypot(max(0,abs(X-255.5)-122.5),max(0,abs(Y-255.5)-122.5)),133),0,255)'"
)
SHELF_DIR = os.environ.get("ISLAND_SHELF", f"{HOME}/.local/share/island/shelf")
SHELF_THUMBS = f"{SHELF_DIR}/.thumbs"
SHELF_ASK = f"{STATE_DIR}/shelf-ask"
SHELF_LIMIT = 24
SHELF_LONG_TEXT = 400
IMAGE_TYPES = (".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp")
TEXT_TYPES = (".txt", ".md", ".log", ".json", ".csv")
MUSIC_PREV = f"{STATE_DIR}/music-prev"
MUSIC_VOLUME = f"{STATE_DIR}/music-volume"
MUSIC_RESTART = 1.4
MUSIC = {}
MUSIC_LOCK = threading.Lock()
FULLSCREEN = False
REMOTE_ACTIONS = {"t3": [], "claude": []}
REMOTE_ACTIONS_LOCK = threading.Lock()
REMOTE_ACTIONS_VERSION = 0
REMOTE_ACTIONS_AT = None
ICONS = {
    "charging": "\U000f0084",
    "low": "\U000f007b",
    "critical": "\U000f0083",
    "date": "\U000f00ed",
    "full": "\U000f0085",
    "wifi": "\U000f05a9",
    "wifi_off": "\U000f05aa",
    "wifi_change": "\U000f16c7",
    "tailnet_down": "\U000f0319",
    "tailnet_up": "\U000f0318",
    "github": "\U000f02a4",
    "bt": "\U000f00b1",
    "bt_off": "\U000f00b2",
    "ram": "\U000f07c6",
    "t3": "\ue000",
    "claude": "\ue001",
    "telegram": "\uf2c6",
}
DEFAULT = {
    "sound": True,
    "seconds": 3.0,
    "font": "",
    "remote": "",
    "probe_host": "",
    "usage": {"providers": [], "pinned": []},
    "history_ignore": [
        "charging",
        "low",
        "critical",
        "full",
        "wifi",
        "bt-",
        "btb-",
        "ram",
        "date",
        "test",
    ],
    "producers": {
        "charging": True,
        "low": True,
        "critical": True,
        "external": True,
        "wifi": True,
        "tailnet": True,
        "ram": True,
        "bluetooth": True,
        "battery_full": True,
        "github": True,
        "t3": True,
        "claude": True,
        "telegram": True,
        "music": True,
    },
}
LOW_AT = 15
CRITICAL_AT = 5
RAM_AT = 90
RAM_REARM = 85
BUBBLE_RANK = {"blocked": 2, "done": 1, "working": 0}
SEVERITY_RANK = {"task": 0, "info": 1, "good": 2, "bad": 3, "crit": 4}
SEV_ALIAS = {"ok": "info", "warn": "info", "low": "info"}


CONFIG_CACHE = {"stamp": None, "value": None}


def live_config():
    try:
        stamp = os.path.getmtime(CONFIG)
    except OSError:
        stamp = 0
    if CONFIG_CACHE["stamp"] != stamp:
        cfg = load_config()
        CONFIG_CACHE["stamp"] = stamp
        CONFIG_CACHE["value"] = {
            "sound": cfg["sound"],
            "seconds": cfg["seconds"],
            "font": cfg.get("font") or "",
            "remote": cfg.get("remote") or "",
            "probe_host": cfg.get("probe_host") or "",
            "usage": dict(cfg["usage"]),
            "producers": dict(cfg["producers"]),
        }
    return CONFIG_CACHE["value"]


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


def load_config():
    try:
        raw = read_json(CONFIG)
    except (OSError, ValueError):
        raw = {}
    cfg = json.loads(json.dumps(DEFAULT))
    cfg.update({k: v for k, v in raw.items() if k not in ("producers", "usage")})
    cfg["producers"].update(raw.get("producers") or {})
    cfg["usage"].update(raw.get("usage") or {})
    return cfg


def save_config(cfg):
    os.makedirs(os.path.dirname(CONFIG), exist_ok=True)
    tmp = CONFIG + ".tmp"
    with open(tmp, "w") as handle:
        json.dump(cfg, handle, indent=2)
    os.replace(tmp, CONFIG)


COLORS_CACHE = {"stamp": None, "value": None}
FALLBACK_PALETTE = {
    "bg": "#181616",
    "bg_alt": "#282727",
    "fg": "#c5c9c5",
    "fg_alt": "#a6a69c",
    "muted": "#625e5a",
    "accent": "#658594",
    "hover": "#a292a3",
    "ok": "#87a987",
    "warn": "#c4b28a",
    "crit": "#c4746e",
}


def hex_rgb(value):
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) for i in (0, 2, 4))


def mix_hex(base, tint, amount):
    a = hex_rgb(base)
    b = hex_rgb(tint)
    return "#%02x%02x%02x" % tuple(
        round(a[i] + (b[i] - a[i]) * amount) for i in range(3)
    )


def palette_source():
    forced = os.environ.get("ISLAND_COLORS")
    if forced:
        return forced
    for path in (OMARCHY_COLORS, USER_COLORS, LEGACY_COLORS):
        if os.path.exists(path):
            return path
    return BUNDLED_COLORS


def css_palette(text):
    found = dict(re.findall(r"@define-color\s+(\w+)\s+(#[0-9a-fA-F]{6})", text))
    palette = dict(FALLBACK_PALETTE)
    for key, source in (
        ("bg", "bg"),
        ("bg_alt", "bg_alt"),
        ("fg", "fg"),
        ("fg_alt", "fg_alt"),
        ("muted", "fg_muted"),
        ("accent", "accent"),
        ("hover", "hover"),
        ("ok", "ok"),
        ("warn", "warn"),
        ("crit", "critical"),
    ):
        if source in found:
            palette[key] = found[source]
    return palette


def toml_palette(text):
    found = dict(
        re.findall(r"^\s*([A-Za-z0-9_-]+)\s*=\s*[\"']?(#[0-9a-fA-F]{6})", text, re.M)
    )
    fg = found.get("foreground", FALLBACK_PALETTE["fg"])
    bg = found.get("background", FALLBACK_PALETTE["bg"])
    accent = found.get("accent") or found.get("color4") or FALLBACK_PALETTE["accent"]
    urgent = found.get("urgent") or found.get("color1") or FALLBACK_PALETTE["crit"]
    return {
        "bg": bg,
        "bg_alt": mix_hex(bg, fg, 0.07),
        "fg": fg,
        "fg_alt": mix_hex(fg, bg, 0.18),
        "muted": found.get("muted") or mix_hex(fg, bg, 0.55),
        "accent": accent,
        "hover": mix_hex(accent, fg, 0.4),
        "ok": found.get("color2") or accent,
        "warn": found.get("color3") or mix_hex(accent, urgent, 0.5),
        "crit": urgent,
    }


def colors():
    path = palette_source()
    try:
        stamp = (path, os.stat(path).st_mtime_ns)
    except OSError:
        stamp = (path, None)
    if COLORS_CACHE["stamp"] == stamp and COLORS_CACHE["value"]:
        return COLORS_CACHE["value"]
    try:
        text = read_text(path, 256 << 10, any_owner=True)
        palette = toml_palette(text) if path.endswith(".toml") else css_palette(text)
    except OSError:
        palette = dict(FALLBACK_PALETTE)
    COLORS_CACHE["stamp"] = stamp
    COLORS_CACHE["value"] = palette
    return palette


def battery():
    for bat in glob.glob("/sys/class/power_supply/BAT*"):
        try:
            with open(f"{bat}/capacity") as handle:
                cap = int(handle.read())
            with open(f"{bat}/status") as handle:
                status = handle.read().strip()
            return cap, status
        except (OSError, ValueError):
            continue
    return None, None


def run(cmd, timeout=5):
    try:
        r = subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout, check=False
        )
        return r.stdout if r.returncode == 0 else ""
    except Exception:
        return ""


def clean_notification_text(value):
    text = html.unescape(re.sub(r"<[^>]*>", "", str(value or "")))
    return re.sub(r"\s+", " ", text).strip()


def claude_session_activity(session):
    status = session.get("status")
    state = session.get("state")
    tempo = session.get("tempo")
    blocked = bool(
        status in ("blocked", "waiting")
        or tempo == "blocked"
        or session.get("waitingFor")
        or session.get("needs")
    )
    working = bool(
        status in ("blocked", "busy", "shell", "waiting", "working")
        or state == "working"
        or tempo in ("active", "blocked")
    )
    return working, blocked


def raw_pixels(path, size=48):
    result = subprocess.run(
        [
            "ffmpeg",
            "-v",
            "error",
            "-i",
            path,
            "-vf",
            f"scale={size}:{size}",
            "-f",
            "rawvideo",
            "-pix_fmt",
            "rgb24",
            "-",
        ],
        capture_output=True,
        check=False,
    )
    data = result.stdout
    return [tuple(data[i : i + 3]) for i in range(0, len(data) - 2, 3)]


def as_hex(rgb):
    return "#%02x%02x%02x" % tuple(round(min(1.0, max(0.0, c)) * 255) for c in rgb)


def accent_of(path):
    pixels = raw_pixels(path)
    if not pixels:
        return None
    buckets = {}
    for red, green, blue in pixels:
        hue, sat, value = colorsys.rgb_to_hsv(red / 255, green / 255, blue / 255)
        cell = buckets.setdefault(
            (round(hue * 12), round(sat * 4), round(value * 4)), [0, 0.0, 0.0, 0.0]
        )
        cell[0] += 1
        cell[1] += hue
        cell[2] += sat
        cell[3] += value
    lit = [px for px in pixels if max(px) >= 26]
    if not lit:
        return None
    means = [sum(px[i] for px in lit) / len(lit) / 255 for i in range(3)]
    plain_hue, plain_sat, plain_value = colorsys.rgb_to_hsv(*means)
    plain = colorsys.hsv_to_rgb(
        plain_hue, min(plain_sat, 0.06), min(0.92, max(plain_value, 0.62))
    )
    best = None
    for count, hues, sats, values in buckets.values():
        hue, sat, value = hues / count, sats / count, values / count
        if value < 0.10 or sat < 0.18:
            continue
        score = sat * sat * count
        if best is None or score > best[0]:
            best = (score, hue, sat, value, count)
    if best is None:
        return as_hex(plain)
    _, hue, sat, value, count = best
    vivid = colorsys.hsv_to_rgb(
        hue, min(1.0, max(sat, 0.55)), min(0.92, max(value, 0.78))
    )
    share = count / len(pixels)
    weight = min(1.0, max(0.0, (share - 0.01) / 0.035))
    return as_hex(tuple(plain[i] + (vivid[i] - plain[i]) * weight for i in range(3)))


COVER_TTL = 14 * 86400
COVER_MISS_TTL = 3 * 3600
COVER_MIN = 200
COVER_GRACE = 2.5


def source_edge(path):
    out = run(
        [
            "ffprobe",
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=width,height",
            "-of",
            "csv=p=0",
            path,
        ],
        4,
    ).strip()
    try:
        width, height = (int(part) for part in out.split(",")[:2])
    except ValueError:
        return 0
    return max(width, height)


COVER_PENDING = set()
COVER_READY = {}
RIPE_PENDING = set()


def ripen(term, url):
    if not url or term in COVER_READY or term in RIPE_PENDING:
        return
    RIPE_PENDING.add(term)

    def work():
        try:
            image, tint, edge = art_asset(url)
            if image and edge >= COVER_MIN:
                COVER_READY[term] = (image, tint, edge)
        finally:
            RIPE_PENDING.discard(term)

    threading.Thread(target=work, daemon=True).start()


def cover_lookup(artist, album, title):
    term = " ".join(part for part in (artist, album or title) if part).strip()
    if not term:
        return ""
    key = hashlib.sha1(term.lower().encode()).hexdigest()[:16]
    memo = f"{ART_DIR}/cover-{key}.txt"
    try:
        age = time.time() - os.path.getmtime(memo)
        remembered = read_text(memo, 8192).strip()
        if remembered and age < COVER_TTL:
            ripen(term, remembered)
            return remembered
        if not remembered and age < COVER_MISS_TTL:
            return ""
    except OSError:
        pass
    if term in COVER_PENDING:
        return ""
    COVER_PENDING.add(term)
    threading.Thread(
        target=cover_fetch, args=(term, artist, album, title, memo), daemon=True
    ).start()
    return ""


def fetch_json(url, timeout=5):
    try:
        with urllib.request.urlopen(url, timeout=timeout) as response:
            return json.loads(read_body(response, 512 << 10))
    except Exception:
        return None


def deezer_cover(query):
    params = urllib.parse.urlencode({"limit": 1, "q": query})
    data = fetch_json(f"https://api.deezer.com/search?{params}")
    if data is None:
        raise LookupError("deezer unreachable")
    hits = data.get("data") or []
    if not hits:
        return ""
    album = hits[0].get("album") or {}
    return album.get("cover_xl") or album.get("cover_big") or ""


def itunes_cover(query):
    params = urllib.parse.urlencode({"term": query, "limit": 1, "media": "music"})
    data = fetch_json(f"https://itunes.apple.com/search?{params}")
    if data is None:
        raise LookupError("itunes unreachable")
    hits = data.get("results") or []
    if not hits:
        return ""
    return (hits[0].get("artworkUrl100") or "").replace("100x100", "600x600")


def archive_cover(query):
    params = urllib.parse.urlencode({"query": query, "fmt": "json", "limit": 1})
    data = fetch_json(f"https://musicbrainz.org/ws/2/release/?{params}")
    if data is None:
        raise LookupError("musicbrainz unreachable")
    releases = data.get("releases") or []
    if not releases:
        return ""
    return f"https://coverartarchive.org/release/{releases[0]['id']}/front-500"


COVER_SOURCES = (deezer_cover, itunes_cover, archive_cover)
YANDEX_FIRST = True


def cover_fetch(term, artist, album, title, memo):
    lead = (artist or "").split(",")[0].strip()
    tries = []
    for query in (f"{artist} {title}", f"{lead} {title}", term, title):
        query = (query or "").strip()
        if query and query not in tries:
            tries.append(query)
    found = ""
    answered = False
    if YANDEX_FIRST:
        found = yandex_cover(artist, title, album or "")
        if found:
            answered = True
    for source in COVER_SOURCES if not found else ():
        try:
            for query in tries:
                found = source(query)
                answered = True
                if found:
                    break
        except LookupError:
            continue
        if found:
            break
    if found or answered:
        os.makedirs(ART_DIR, exist_ok=True)
        with open(memo, "w") as handle:
            handle.write(found)
    COVER_PENDING.discard(term)
    if found:
        ripen(term, found)


def art_asset(url):
    if not url:
        return "", "", 0
    key = hashlib.sha1(url.encode()).hexdigest()[:16]
    image = f"{ART_DIR}/{key}.png"
    meta = f"{ART_DIR}/{key}.txt"
    if os.path.exists(image) and os.path.exists(meta):
        try:
            parts = read_text(meta, 4096).split()
        except OSError:
            parts = []
        tint = parts[0] if parts else ""
        edge = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else 0
        return image, tint, edge
    os.makedirs(ART_DIR, exist_ok=True)
    source = None
    if url.startswith("file://"):
        source = urllib.parse.unquote(urllib.parse.urlparse(url).path)
        if not os.path.exists(source):
            return "", "", 0
    else:
        try:
            with urllib.request.urlopen(url, timeout=6) as response:
                payload = read_body(response, 8 << 20)
        except Exception:
            return "", "", 0
        source = f"{ART_DIR}/{key}.{os.getpid()}.{threading.get_ident()}.src"
        with open(source, "wb") as handle:
            handle.write(payload)
    edge = source_edge(source)
    stage = f"{image}.{os.getpid()}.{threading.get_ident()}.part.png"
    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", source, "-vf", COVER_TILE, stage],
        capture_output=True,
        check=False,
    )
    if source.endswith(".src"):
        try:
            os.remove(source)
        except OSError:
            pass
    if result.returncode != 0 or not os.path.exists(stage):
        try:
            os.remove(stage)
        except OSError:
            pass
        return "", "", 0
    os.replace(stage, image)
    tint = accent_of(image) or ""
    with open(meta, "w") as handle:
        handle.write(f"{tint} {edge}")
    return image, tint, edge


def micros(value):
    try:
        return int(value) / 1000000.0
    except (TypeError, ValueError):
        return 0.0


SERVICES = (
    ("youtube", "youtube"),
    ("youtu.be", "youtube"),
    ("music.yandex", "yandex"),
    ("yandex", "yandex"),
    ("spotify", "spotify"),
    ("music.apple", "apple"),
    ("cider", "apple"),
    ("deezer", "deezer"),
    ("tidal", "tidal"),
    ("soundcloud", "soundcloud"),
    ("bandcamp", "bandcamp"),
)


def service_of(url, player=""):
    host = urllib.parse.urlparse(url or "").hostname or ""
    for needle, name in SERVICES:
        if needle in host:
            return name
    lowered = (player or "").lower()
    for needle, name in SERVICES:
        if needle in lowered:
            return name
    return ""


def browser_art(pid, since):
    if not pid:
        return ""
    newest = None
    for base in glob.glob(f"{HOME}/.config/*/firefox-mpris"):
        for path in glob.glob(f"{base}/{pid}_*.png"):
            try:
                stamped = os.path.getmtime(path)
            except OSError:
                continue
            if stamped + 2.0 < since:
                continue
            if newest is None or stamped > newest[0]:
                newest = (stamped, path)
    return newest[1] if newest else ""


def shelf_kind(name):
    lowered = name.lower()
    if lowered.endswith(IMAGE_TYPES):
        return "image"
    if lowered.endswith(TEXT_TYPES):
        return "text"
    return "file"


THUMB_GIVEN_UP = set()


def shelf_thumb(path, stamp):
    key = hashlib.sha1(f"{path}:{stamp}".encode()).hexdigest()[:16]
    thumb = f"{SHELF_THUMBS}/{key}.png"
    if os.path.exists(thumb):
        return thumb
    if key in THUMB_GIVEN_UP:
        return ""
    os.makedirs(SHELF_THUMBS, exist_ok=True)
    result = subprocess.run(
        [
            "ffmpeg",
            "-v",
            "error",
            "-y",
            "-i",
            path,
            "-vf",
            "scale=128:128:force_original_aspect_ratio=increase,crop=128:128",
            thumb,
        ],
        capture_output=True,
        check=False,
    )
    if result.returncode == 0 and os.path.exists(thumb):
        return thumb
    THUMB_GIVEN_UP.add(key)
    return ""


def shelf_preview(path):
    try:
        with safe_open(path) as handle:
            return re.sub(r"\s+", " ", handle.read(400)).strip()[:180]
    except OSError:
        return ""


def shelf_text(path):
    try:
        with safe_open(path) as handle:
            return handle.read(4096)
    except OSError:
        return ""


def human_size(count):
    for unit in ("B", "K", "M", "G"):
        if count < 1024 or unit == "G":
            return f"{count:.0f}{unit}" if unit == "B" else f"{count:.1f}{unit}"
        count /= 1024
    return ""


def shelf_slug(text):
    words = re.sub(r"[^\w\s-]", "", text, flags=re.UNICODE).split()
    slug = "-".join(words)[:32].strip("-")
    return slug or "note"


def shelf_unique(name):
    base, dot, ext = name.rpartition(".")
    base = base or name
    ext = f".{ext}" if dot else ""
    candidate = f"{base}{ext}"
    index = 2
    while os.path.exists(f"{SHELF_DIR}/{candidate}"):
        candidate = f"{base}-{index}{ext}"
        index += 1
    return f"{SHELF_DIR}/{candidate}"


def shelf_paste():
    os.makedirs(SHELF_DIR, exist_ok=True)
    types = run(["wl-paste", "--list-types"]).split()
    picture = next((t for t in types if t.startswith("image/")), "")
    if picture:
        suffix = picture.split("/")[-1].split("+")[0]
        target = shelf_unique(f"shot-{datetime.now():%H%M%S}.{suffix}")
        blob = subprocess.run(
            ["wl-paste", "--type", picture], capture_output=True, check=False
        ).stdout
        if not blob:
            return
        with open(target, "wb") as handle:
            handle.write(blob)
        return
    text = subprocess.run(
        ["wl-paste", "--no-newline"], capture_output=True, text=True, check=False
    ).stdout
    if not text.strip():
        return
    target = shelf_unique(f"{shelf_slug(text[:60])}.txt")
    with open(target, "w") as handle:
        handle.write(text)
    if len(text) > SHELF_LONG_TEXT:
        with open(SHELF_ASK, "w") as handle:
            handle.write(os.path.basename(target))


SHELF_MAX_FETCH = 25 * 1024 * 1024
MIME_SUFFIX = {
    "image/png": "png",
    "image/jpeg": "jpg",
    "image/webp": "webp",
    "image/gif": "gif",
    "image/avif": "avif",
    "image/svg+xml": "svg",
    "application/pdf": "pdf",
    "text/plain": "txt",
}


IMAGE_MIME = {
    "png": "image/png",
    "jpg": "image/jpeg",
    "jpeg": "image/jpeg",
    "webp": "image/webp",
    "gif": "image/gif",
    "avif": "image/avif",
    "bmp": "image/bmp",
    "svg": "image/svg+xml",
}
MAGIC = [
    (b"\x89PNG", "png"),
    (b"\xff\xd8\xff", "jpg"),
    (b"GIF8", "gif"),
    (b"%PDF", "pdf"),
]


def image_mime(path):
    return IMAGE_MIME.get(path.rsplit(".", 1)[-1].lower(), "image/png")


def sniff_suffix(payload):
    for magic, suffix in MAGIC:
        if payload.startswith(magic):
            return suffix
    if payload[8:12] == b"WEBP":
        return "webp"
    return ""


def fetch_into_shelf(url, parts):
    request = urllib.request.Request(url, headers={"User-Agent": "island-shelf"})
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            payload = response.read(SHELF_MAX_FETCH + 1)
            mime = response.headers.get_content_type()
    except Exception:
        return
    if not payload or len(payload) > SHELF_MAX_FETCH:
        return
    name = os.path.basename(urllib.parse.unquote(parts.path)) or "download"
    name = re.sub(r"[^\w.\-]", "-", name)[:48]
    suffix = MIME_SUFFIX.get(mime, "") or sniff_suffix(payload)
    if suffix and not name.lower().endswith(f".{suffix}"):
        name = f"{name.rsplit('.', 1)[0] or 'download'}.{suffix}"
    with open(shelf_unique(name), "wb") as handle:
        handle.write(payload)


def shelf_command(action, argument=""):
    os.makedirs(SHELF_DIR, exist_ok=True)
    target = f"{SHELF_DIR}/{os.path.basename(argument)}" if argument else ""
    if action == "paste":
        shelf_paste()
    elif action == "drop" and argument:
        for entry in argument.split("\n"):
            entry = entry.strip()
            if not entry:
                continue
            parts = urllib.parse.urlparse(entry)
            if parts.scheme in ("http", "https"):
                fetch_into_shelf(entry, parts)
                continue
            source = urllib.parse.unquote(parts.path)
            if source and os.path.isfile(source):
                shutil.copy2(source, shelf_unique(os.path.basename(source)))
    elif action == "portal" and argument.strip():
        reply = run(
            [
                "busctl",
                "--user",
                "call",
                "org.freedesktop.portal.Documents",
                "/org/freedesktop/portal/documents",
                "org.freedesktop.portal.FileTransfer",
                "RetrieveFiles",
                "sa{sv}",
                argument.strip(),
                "0",
            ],
            timeout=8,
        )
        for source in re.findall(r'"([^"]+)"', reply):
            if os.path.isfile(source):
                shutil.copy2(source, shelf_unique(os.path.basename(source)))
    elif action == "blob":
        try:
            raw = base64.b64decode(sys.stdin.read())
        except (ValueError, OSError):
            return
        if not raw:
            return
        os.makedirs(SHELF_DIR, exist_ok=True)
        suffix = re.sub(r"[^a-z0-9]", "", (argument or "png").lower())[:5] or "png"
        target = shelf_unique(f"shot-{datetime.now():%H%M%S}.{suffix}")
        with open(target, "wb") as handle:
            handle.write(raw)
    elif action == "note" and argument.strip():
        target = shelf_unique(f"{shelf_slug(argument[:60])}.txt")
        with open(target, "w") as handle:
            handle.write(argument)
        if len(argument) > SHELF_LONG_TEXT:
            with open(SHELF_ASK, "w") as handle:
                handle.write(os.path.basename(target))
    elif action == "remove" and target and os.path.exists(target):
        os.remove(target)
    elif action == "copy" and target and os.path.exists(target):
        kind = shelf_kind(target)
        if kind == "text":
            with safe_open(target, SHELF_MAX_FETCH) as handle:
                subprocess.run(["wl-copy"], input=handle.read(), text=True, check=False)
        elif kind == "image":
            with safe_open(target, SHELF_MAX_FETCH, binary=True) as handle:
                subprocess.run(
                    ["wl-copy", "--type", image_mime(target)],
                    input=handle.read(),
                    check=False,
                )
        else:
            subprocess.run(
                ["wl-copy", "--type", "text/uri-list"],
                input=f"file://{target}\n",
                text=True,
                check=False,
            )
    elif action == "open" and target and os.path.exists(target):
        subprocess.Popen(["xdg-open", target], start_new_session=True)
    elif action == "rename" and argument:
        name, _, fresh = argument.partition("\t")
        source = f"{SHELF_DIR}/{os.path.basename(name)}"
        if fresh.strip() and os.path.exists(source):
            _, dot, ext = name.rpartition(".")
            os.replace(source, shelf_unique(f"{shelf_slug(fresh)}{dot and '.' + ext}"))
        try:
            os.remove(SHELF_ASK)
        except OSError:
            pass
    elif action == "keep":
        try:
            os.remove(SHELF_ASK)
        except OSError:
            pass


def player_pid(name):
    if not name:
        return ""
    result = subprocess.run(
        [
            "busctl",
            "--user",
            "call",
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "GetConnectionUnixProcessID",
            "s",
            f"org.mpris.MediaPlayer2.{name}",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    parts = result.stdout.split()
    return parts[1] if len(parts) == 2 and parts[1].isdigit() else ""


YOUTUBE_LIVE = ("/watch", "/shorts/", "/live/", "/embed/", "/clip/")


def playing_page(url):
    parts = urllib.parse.urlparse(url or "")
    host = parts.hostname or ""
    if host.endswith("youtu.be"):
        return len(parts.path.strip("/")) > 0
    if "youtube" not in host:
        return True
    return parts.path.startswith(YOUTUBE_LIVE)


def player_name(state=None):
    result = subprocess.run(
        [
            "playerctl",
            "--all-players",
            "metadata",
            "--format",
            "{{playerInstance}}\t{{status}}\t{{artist}}\t{{title}}",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    wanted_artist = str((state or {}).get("artist") or "")
    wanted_title = str((state or {}).get("title") or "")
    first = ""
    playing = ""
    for line in result.stdout.splitlines():
        parts = line.split("\t", 3)
        if len(parts) != 4:
            continue
        name, status, artist, title = parts
        first = first or name
        if status == "Playing" and not playing:
            playing = name
        if wanted_title and title == wanted_title and artist == wanted_artist:
            return name
    return playing or first


def player_command(player, *args):
    command = ["playerctl"]
    if player:
        command += ["--player", player]
    return command + list(args)


def focus_player(player=""):
    pid = player_pid(player)
    if not pid:
        return
    subprocess.run(
        ["hyprctl", "eval", 'hl.dispatch(hl.dsp.focus({window="pid:' + pid + '"}))'],
        capture_output=True,
        check=False,
    )


YANDEX_TOKEN_FILES = (
    f"{CONFIG_DIR}/yandex-token",
    f"{HOME}/.local/share/island/yandex-token",
)
YANDEX_API = "https://api.music.yandex.net"
YANDEX_AGENT = "Yandex-Music-API"
YANDEX_CACHE = {
    "uid": None,
    "liked": set(),
    "at": 0.0,
    "ids": {},
    "covers": {},
    "albums": {},
}
YANDEX_TTL = 600.0
LIKE_DIRTY = f"{STATE_DIR}/like-dirty"


def yandex_token():
    for path in YANDEX_TOKEN_FILES:
        try:
            return read_text(path, 4096).strip()
        except OSError:
            continue
    return ""


def yandex_call(path, data=None):
    token = yandex_token()
    if not token:
        return None
    body = urllib.parse.urlencode(data).encode() if data else None
    request = urllib.request.Request(
        f"{YANDEX_API}{path}",
        data=body,
        headers={
            "Authorization": f"OAuth {token}",
            "User-Agent": YANDEX_AGENT,
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=6) as response:
            return json.loads(read_body(response, 8 << 20)).get("result")
    except Exception:
        return None


def yandex_uid():
    if YANDEX_CACHE["uid"]:
        return YANDEX_CACHE["uid"]
    status = yandex_call("/account/status")
    if not status:
        return None
    YANDEX_CACHE["uid"] = (status.get("account") or {}).get("uid")
    return YANDEX_CACHE["uid"]


def plain(text):
    return re.sub(r"[^\w]+", "", (text or "").lower())


def yandex_track_id(artist, title):
    key = f"{artist}\u241f{title}"
    if key in YANDEX_CACHE["ids"]:
        return YANDEX_CACHE["ids"][key]
    YANDEX_CACHE["covers"].pop(key, None)
    query = urllib.parse.urlencode(
        {"type": "track", "text": f"{artist} {title}", "page": 0}
    )
    found = yandex_call(f"/search?{query}")
    hits = ((found or {}).get("tracks") or {}).get("results") or []
    wanted = plain(title)
    track = None
    for hit in hits[:5]:
        if plain(hit.get("title")) == wanted:
            track = hit
            break
    resolved = str(track["id"]) if track else ""
    if resolved:
        YANDEX_CACHE["ids"][key] = resolved
    if track:
        albums = track.get("albums") or []
        art = albums[0].get("coverUri") if albums else track.get("coverUri")
        if art:
            YANDEX_CACHE["covers"][key] = "https://" + art.replace("%%", "1000x1000")
    return resolved


def yandex_cover(artist, title, album=""):
    if not yandex_token():
        return ""
    shelf = f"{artist}\u241f{album}".lower()
    if album and shelf in YANDEX_CACHE["albums"]:
        return YANDEX_CACHE["albums"][shelf]
    key = f"{artist}\u241f{title}"
    if key not in YANDEX_CACHE["covers"]:
        yandex_track_id(artist, title)
    found = YANDEX_CACHE["covers"].get(key, "")
    if found and album:
        YANDEX_CACHE["albums"][shelf] = found
    return found


def yandex_liked():
    now = time.monotonic()
    if os.path.exists(LIKE_DIRTY):
        try:
            os.unlink(LIKE_DIRTY)
        except OSError:
            pass
        YANDEX_CACHE["at"] = 0.0
    if now - YANDEX_CACHE["at"] < YANDEX_TTL:
        return YANDEX_CACHE["liked"]
    uid = yandex_uid()
    if not uid:
        return YANDEX_CACHE["liked"]
    library = yandex_call(f"/users/{uid}/likes/tracks")
    tracks = ((library or {}).get("library") or {}).get("tracks")
    if tracks is None:
        return YANDEX_CACHE["liked"]
    YANDEX_CACHE["liked"] = {str(t.get("id")) for t in tracks}
    YANDEX_CACHE["at"] = now
    return YANDEX_CACHE["liked"]


LIKE_PENDING = set()


def resolve_like(artist, title, key):
    try:
        yandex_track_id(artist, title)
        yandex_liked()
    finally:
        LIKE_PENDING.discard(key)


def track_is_liked():
    with MUSIC_LOCK:
        state = dict(MUSIC)
    if state.get("service") != "yandex" or not yandex_token():
        return False
    artist = state.get("artist")
    title = state.get("title")
    if not title:
        return False
    key = f"{artist}\u241f{title}"
    if key not in YANDEX_CACHE["ids"]:
        if key not in LIKE_PENDING:
            LIKE_PENDING.add(key)
            threading.Thread(
                target=resolve_like, args=(artist, title, key), daemon=True
            ).start()
        return False
    known = YANDEX_CACHE["ids"][key]
    return bool(known) and known in yandex_liked()


def playing_now():
    with MUSIC_LOCK:
        state = dict(MUSIC)
    if state.get("title"):
        return state
    try:
        return read_json(SCENE_FILE, 4 << 20).get("music") or {}
    except (OSError, ValueError):
        return {}


def toggle_liked():
    state = playing_now()
    uid = yandex_uid()
    if not uid:
        return
    track = yandex_track_id(state.get("artist"), state.get("title"))
    if not track:
        return
    liked = yandex_liked()
    if track in liked:
        yandex_call(f"/users/{uid}/likes/tracks/remove", {"track-ids": track})
        liked.discard(track)
    else:
        yandex_call(f"/users/{uid}/likes/tracks/add-multiple", {"track-ids": track})
        liked.add(track)
    open(LIKE_DIRTY, "w").close()


def player_volume(player=""):
    raw = run(player_command(player, "volume"), 3).strip()
    try:
        return float(raw)
    except ValueError:
        return 1.0


def toggle_mute(player=""):
    now = player_volume(player)
    if now > 0.001:
        with open(MUSIC_VOLUME, "w") as handle:
            handle.write(f"{now:.3f}")
        run(player_command(player, "volume", "0"), 3)
        return
    back = 1.0
    try:
        back = max(0.05, float(read_text(MUSIC_VOLUME, 64).strip()))
    except (OSError, ValueError):
        pass
    run(player_command(player, "volume", f"{back:.3f}"), 3)


def music_control(action):
    state = playing_now()
    player = str(state.get("player") or "") or player_name(state)
    if action == "mute":
        toggle_mute(player)
        return
    if action == "like":
        toggle_liked()
        return
    if action == "focus":
        focus_player(player)
        return
    if action == "prev":
        now = time.time()
        try:
            last = float(read_text(MUSIC_PREV, 64).strip())
        except (OSError, ValueError):
            last = 0.0
        os.makedirs(STATE_DIR, exist_ok=True)
        with open(MUSIC_PREV, "w") as handle:
            handle.write(str(now))
        if now - last <= MUSIC_RESTART:
            run(player_command(player, "previous"))
        else:
            run(player_command(player, "position", "0"))
        return
    if action.startswith("seek:"):
        run(player_command(player, "position", action[5:]))
        return
    command = {"next": "next", "toggle": "play-pause"}.get(action, "play-pause")
    run(player_command(player, command))


def music_thread():
    global MUSIC
    fields = "\t".join(
        [
            "{{status}}",
            "{{artist}}",
            "{{title}}",
            "{{album}}",
            "{{mpris:artUrl}}",
            "{{xesam:url}}",
            "{{position}}",
            "{{mpris:length}}",
            "{{playerInstance}}",
        ]
    )
    while True:
        try:
            child = subprocess.Popen(
                player_command(
                    player_name(playing_now()),
                    "--follow",
                    "--format",
                    fields,
                    "metadata",
                ),
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
            )
        except OSError:
            time.sleep(10)
            continue
        with CHILDREN_LOCK:
            CHILDREN.add(child)
        carried = {
            "key": None,
            "length": 0.0,
            "position": 0.0,
            "art": "",
            "edge": 0,
            "raw": "",
            "shown": "",
            "shownEdge": 0,
            "accent": "",
            "since": 0.0,
            "pid": None,
            "player": "",
        }
        for line in child.stdout:
            parts = line.rstrip("\n").split("\t")
            if len(parts) != 9 or not parts[0]:
                with MUSIC_LOCK:
                    MUSIC = {}
                continue
            status, artist, title, album, art_url, page, at, span, player = parts
            if not playing_page(page):
                with MUSIC_LOCK:
                    MUSIC = {}
                continue
            if not artist and carried["key"] and carried["key"][0]:
                artist, title = carried["key"]
            key = (artist, title)
            if key != carried["key"]:
                first = carried["key"] is None
                carried.update(
                    {
                        "key": key,
                        "length": 0.0,
                        "position": 0.0,
                        "art": "",
                        "edge": 0,
                        "raw": "",
                        "shown": "",
                        "shownEdge": 0,
                        "since": 0.0 if first else time.time(),
                    }
                )
            length = micros(span) or carried["length"]
            position = micros(at) or carried["position"]
            if length > 0 and position > length:
                position = carried["position"] if carried["position"] <= length else 0.0
            carried["length"] = length
            carried["position"] = position
            carried["player"] = player or carried["player"]
            if not art_url and not carried["art"]:
                if carried["pid"] is None:
                    carried["pid"] = player_pid(carried["player"])
                local = browser_art(carried["pid"], carried["since"])
                art_url = f"file://{local}" if local else ""
            raw_art = ""
            if art_url.startswith("file://"):
                candidate = urllib.parse.unquote(urllib.parse.urlparse(art_url).path)
                if os.path.exists(candidate):
                    raw_art = candidate
            if raw_art:
                carried["raw"] = raw_art
            else:
                raw_art = carried["raw"]

            def publish(art, cover):
                global MUSIC
                with MUSIC_LOCK:
                    MUSIC = {
                        "playing": status == "Playing",
                        "artist": artist,
                        "title": title,
                        "album": album,
                        "art": art,
                        "raw": raw_art,
                        "cover": cover,
                        "accent": carried["accent"],
                        "service": service_of(page, carried["player"]),
                        "player": carried["player"],
                        "position": position,
                        "length": length,
                        "stamp": time.time(),
                    }

            publish(
                carried["art"],
                carried["shown"] if carried["shownEdge"] >= COVER_MIN else "",
            )
            image, tint, edge = art_asset(art_url)
            if not image:
                image, edge = carried["art"], carried["edge"]
            if edge < COVER_MIN and title:
                cover_lookup(artist, album, title)
            carried["art"] = image
            carried["edge"] = edge
            if edge >= COVER_MIN or time.time() - carried["since"] > COVER_GRACE:
                carried["shown"] = image
                carried["shownEdge"] = edge
            if tint:
                carried["accent"] = tint
            publish(
                image,
                carried["shown"] if carried["shownEdge"] >= COVER_MIN else "",
            )
        child.wait()
        with CHILDREN_LOCK:
            CHILDREN.discard(child)
        with MUSIC_LOCK:
            MUSIC = {}
        time.sleep(3)


TOOL_CACHE = {}


def have(tool):
    if tool not in TOOL_CACHE:
        TOOL_CACHE[tool] = shutil.which(tool) is not None
    return TOOL_CACHE[tool]


def missing_tools():
    return [tool for tool in TOOLS if not have(tool)]


SYS = {}
SYS_LOCK = threading.Lock()
CAT_FRAMES = ["cat-0", "cat-1", "cat-2", "cat-3", "cat-4", "cat-idle"]
CAT_SLEEP_BELOW = 5
CAT_SLOWEST_MS = 500
CAT_FASTEST_MS = 50


def system_state():
    with SYS_LOCK:
        return dict(SYS) if SYS else None


def render_cat(color):
    os.makedirs(RUNCAT_DIR, exist_ok=True)
    for name in CAT_FRAMES:
        try:
            svg = read_text(
                f"{RUNCAT_SRC}/{name}.svg", 256 << 10, any_owner=True
            ).replace("#bebebe", color)
        except OSError:
            continue
        tmp = f"{RUNCAT_DIR}/{name}.svg.tmp"
        with open(tmp, "w") as handle:
            handle.write(svg)
        os.replace(tmp, f"{RUNCAT_DIR}/{name}.svg")


def cpu_stat():
    total = None
    cores = []
    with open("/proc/stat") as handle:
        for line in handle:
            if not line.startswith("cpu"):
                break
            vals = [int(x) for x in line.split()[1:]]
            pair = (vals[3] + vals[4], sum(vals))
            if line[3] == " ":
                total = pair
            else:
                cores.append(pair)
    return total, cores


def cpu_pct(prev, cur):
    dt = cur[1] - prev[1]
    return 100.0 * (1 - (cur[0] - prev[0]) / dt) if dt else 0.0


def top_process():
    out = run(["ps", "-eo", "pcpu,comm", "--sort=-pcpu", "--no-headers"], 2)
    try:
        share, name = out.strip().splitlines()[0].split(None, 1)
        return f"{name} {float(share):.0f}%"
    except (IndexError, ValueError):
        return ""


def meminfo():
    d = {}
    with open("/proc/meminfo") as handle:
        for line in handle:
            k, v = line.split(":")
            d[k] = int(v.split()[0]) * 1024
    return d


def gb(n):
    return f"{n / 2**30:.1f}G"


def system_thread():
    global SYS
    painted = None
    prev_total, prev_cores = cpu_stat()
    load = 0.0
    cpu_tip = "cpu 0%"
    last_tip = 0.0
    while True:
        fg = colors()["fg_alt"]
        if fg != painted:
            render_cat(fg)
            painted = fg
        now = time.monotonic()
        total, cores = cpu_stat()
        load = load * 0.5 + cpu_pct(prev_total, total) * 0.5
        per_core = [cpu_pct(p, c) for p, c in zip(prev_cores, cores)]
        prev_total, prev_cores = total, cores
        if now - last_tip >= 3.0:
            top = top_process()
            core_txt = "  ".join(f"{c:3.0f}%" for c in per_core)
            cpu_tip = f"cpu {load:3.0f}%\ncores {core_txt}" + (
                f"\ntop {top}" if top else ""
            )
            last_tip = now
        m = meminfo()
        used = m["MemTotal"] - m["MemAvailable"]
        ram = 100 * used / m["MemTotal"]
        ram_tip = f"ram {ram:.0f}%  {gb(used)} / {gb(m['MemTotal'])}\ncached {gb(m.get('Cached', 0))}"
        if m.get("SwapTotal"):
            ram_tip += f"\nswap {gb(m['SwapTotal'] - m.get('SwapFree', 0))} / {gb(m['SwapTotal'])}"
        if load < CAT_SLEEP_BELOW:
            cat_ms = 0
        else:
            span = (min(load, 100) - CAT_SLEEP_BELOW) / (100 - CAT_SLEEP_BELOW)
            cat_ms = int(CAT_SLOWEST_MS - span * (CAT_SLOWEST_MS - CAT_FASTEST_MS))
        with SYS_LOCK:
            SYS = {
                "cpu": round(load),
                "ram": round(ram),
                "cat_ms": cat_ms,
                "cat_dir": RUNCAT_DIR,
                "cpu_tip": cpu_tip,
                "ram_tip": ram_tip,
            }
        time.sleep(1.0)


def hypr_events_socket():
    base = f"{RUNTIME_DIR}/hypr"
    signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    names = [signature] if signature else []
    try:
        names += sorted(os.listdir(base))
    except OSError:
        return None
    for name in names:
        path = f"{base}/{name}/.socket2.sock"
        if name and os.path.exists(path):
            return path
    return None


def workspace_is_full():
    try:
        return bool(
            json.loads(run(["hyprctl", "activeworkspace", "-j"]))["hasfullscreen"]
        )
    except (KeyError, TypeError, ValueError):
        return False


def fullscreen_thread():
    global FULLSCREEN
    watched = (
        "fullscreen>>",
        "workspace>>",
        "focusedmon>>",
        "openwindow>>",
        "closewindow>>",
        "movewindow>>",
        "changefloatingmode>>",
    )
    while True:
        path = hypr_events_socket()
        if not path:
            time.sleep(10)
            continue
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as events:
                events.connect(path)
                FULLSCREEN = workspace_is_full()
                rest = b""
                while True:
                    chunk = events.recv(4096)
                    if not chunk:
                        break
                    rest += chunk
                    while b"\n" in rest:
                        line, rest = rest.split(b"\n", 1)
                        if line.decode(errors="ignore").startswith(watched):
                            FULLSCREEN = workspace_is_full()
        except OSError:
            pass
        time.sleep(3)


GRAB_CACHE = {"at": 0.0, "value": False}


def grabbing():
    now = time.monotonic()
    if now - GRAB_CACHE["at"] < 0.3:
        return GRAB_CACHE["value"]
    GRAB_CACHE["at"] = now
    found = False
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/comm") as handle:
                if handle.read().strip() in GRAB_TOOLS:
                    found = True
                    break
        except OSError:
            continue
    GRAB_CACHE["value"] = found
    return found


def stop_children(_signum, _frame):
    with CHILDREN_LOCK:
        children = tuple(CHILDREN)
    for child in children:
        child.terminate()
    raise SystemExit(0)


class Island:
    def __init__(self):
        os.makedirs(EVENTS_DIR, exist_ok=True)
        os.makedirs(TASKS_DIR, exist_ok=True)
        self.queue = []
        self.current = None
        self.started = 0.0
        self.last_scene = None
        self.last_scene_at = -10.0
        self.prev_status = None
        self.low_fired_at = None
        self.full_fired = False
        self.date_until = 0.0
        self.wifi = self.wifi_state()
        self.wifi_next = 0.0
        self.tail_next = 30.0
        self.tail_fails = 0
        self.tail_down = False
        self.ram_fired = False
        self.bt = self.bt_state()
        self.bt_next = 0.0
        self.bt_batt_next = 0.0
        self.bt_batt_fired = set()
        self.gh_next = 20.0
        self.t3_stamp = None
        self.t3_active = None
        self.remote_t3_active = None
        self.t3_action = None
        self.claude_active = None
        self.remote_claude_active = None
        self.claude_action = None
        self.music_now = None
        self.shelf_now = {"count": 0, "items": [], "ask": ""}
        self.shelf_seen = None
        self.shelf_ask = ""
        self.remote_actions_version = -1
        self.remote_stale = False
        self.action_primary = None
        self.action_notice = None
        self.action_changes = {}
        self.telegram_sender = ""
        self.calendar_day = None
        self.calendar_text = ""
        self.event_seq = 0
        self.telegram_count = 0

    def push(self, ev):
        if any(e["id"] == ev["id"] for e in self.queue) or (
            self.current and self.current["id"] == ev["id"]
        ):
            return
        self.queue.append(ev)
        self.queue.sort(key=lambda e: -SEVERITY_RANK.get(e.get("severity"), 0))

    def wifi_state(self):
        for line in run(
            ["nmcli", "-t", "-f", "TYPE,STATE,CONNECTION", "d"], 4
        ).splitlines():
            parts = line.split(":")
            if parts[0] == "wifi":
                return (
                    parts[2]
                    if len(parts) > 2 and parts[1] == "connected" and parts[2]
                    else None
                )
        return None

    def bt_state(self):
        out = {}
        for line in run(["bluetoothctl", "devices", "Connected"], 4).splitlines():
            parts = line.split(None, 2)
            if len(parts) == 3 and parts[0] == "Device":
                out[parts[1]] = parts[2]
        return out

    def battery_producers(self, p):
        cap, status = battery()
        if cap is None:
            return
        if (
            status != self.prev_status
            and self.prev_status is not None
            and status == "Charging"
            and p["charging"]
        ):
            self.push(
                {
                    "id": "charging",
                    "icon": ICONS["charging"],
                    "text": f"{cap}%",
                    "severity": "good",
                }
            )
        self.prev_status = status
        if status == "Discharging":
            self.full_fired = False
            if cap <= CRITICAL_AT and p["critical"]:
                if self.low_fired_at is None or self.low_fired_at > cap:
                    self.push(
                        {
                            "id": "critical",
                            "icon": ICONS["critical"],
                            "text": f"{cap}%",
                            "severity": "crit",
                            "sound": True,
                        }
                    )
                    self.low_fired_at = cap
            elif cap <= LOW_AT and p["low"]:
                step = (cap // 5) * 5
                if self.low_fired_at is None or self.low_fired_at > step:
                    self.push(
                        {
                            "id": "low",
                            "icon": ICONS["low"],
                            "text": f"{cap}%",
                            "severity": "bad",
                        }
                    )
                    self.low_fired_at = step
        else:
            self.low_fired_at = None
            if cap >= 100 and p["battery_full"] and not self.full_fired:
                self.push(
                    {
                        "id": "full",
                        "icon": ICONS["full"],
                        "text": "100%, unplug",
                        "severity": "info",
                    }
                )
                self.full_fired = True

    def wifi_producer(self, now):
        if now < self.wifi_next:
            return
        self.wifi_next = now + 2.0
        cur = self.wifi_state()
        if cur == self.wifi:
            return
        if cur and not self.wifi:
            self.push(
                {"id": "wifi", "icon": ICONS["wifi"], "text": cur, "severity": "info"}
            )
        elif cur and self.wifi:
            self.push(
                {
                    "id": "wifi",
                    "icon": ICONS["wifi_change"],
                    "text": cur,
                    "severity": "info",
                }
            )
        else:
            self.push(
                {
                    "id": "wifi",
                    "icon": ICONS["wifi_off"],
                    "text": "no wifi",
                    "severity": "bad",
                }
            )
        self.wifi = cur

    def tailnet_producer(self, now):
        if now < self.tail_next:
            return
        self.tail_next = now + 60.0
        target = probe_target()
        if not self.wifi or not target:
            return
        ok = False
        try:
            with socket.create_connection(target, timeout=1.5):
                ok = True
        except OSError:
            pass
        if ok:
            if self.tail_down:
                self.push(
                    {
                        "id": "tailnet",
                        "icon": ICONS["tailnet_up"],
                        "text": "tailnet back",
                        "severity": "good",
                    }
                )
            self.tail_down = False
            self.tail_fails = 0
        else:
            self.tail_fails += 1
            if self.tail_fails >= 2 and not self.tail_down:
                self.tail_down = True
                self.push(
                    {
                        "id": "tailnet",
                        "icon": ICONS["tailnet_down"],
                        "text": "tailnet silent",
                        "severity": "bad",
                    }
                )

    def ram_producer(self):
        d = {}
        with open("/proc/meminfo") as handle:
            for line in handle:
                k, v = line.split(":")
                d[k] = int(v.split()[0])
                if k == "MemAvailable":
                    break
        pct = 100 * (1 - d["MemAvailable"] / d["MemTotal"])
        if pct >= RAM_AT and not self.ram_fired:
            self.push(
                {
                    "id": "ram",
                    "icon": ICONS["ram"],
                    "text": f"ram {pct:.0f}%",
                    "severity": "bad",
                }
            )
            self.ram_fired = True
        elif pct < RAM_REARM:
            self.ram_fired = False

    def bt_producer(self, now):
        if now >= self.bt_next:
            self.bt_next = now + 3.0
            cur = self.bt_state()
            for mac, name in cur.items():
                if mac not in self.bt:
                    self.push(
                        {
                            "id": f"bt-{mac}",
                            "icon": ICONS["bt"],
                            "text": name[:24],
                            "severity": "info",
                        }
                    )
            for mac, name in self.bt.items():
                if mac not in cur:
                    self.push(
                        {
                            "id": f"bt-{mac}",
                            "icon": ICONS["bt_off"],
                            "text": name[:24],
                            "severity": "info",
                        }
                    )
                    self.bt_batt_fired.discard(mac)
            self.bt = cur
        if now >= self.bt_batt_next:
            self.bt_batt_next = now + 60.0
            for mac, name in self.bt.items():
                if mac in self.bt_batt_fired:
                    continue
                m = re.search(
                    r"Battery Percentage.*\((\d+)\)",
                    run(["bluetoothctl", "info", mac], 4),
                )
                if m and int(m.group(1)) <= 20:
                    self.push(
                        {
                            "id": f"btb-{mac}",
                            "icon": ICONS["bt"],
                            "text": f"{name[:18]} {m.group(1)}%",
                            "severity": "bad",
                        }
                    )
                    self.bt_batt_fired.add(mac)

    def github_producer(self, now):
        if now < self.gh_next or not have("gh"):
            return
        self.gh_next = now + 180.0
        out = run(["gh", "api", "notifications"], 15)
        if not out:
            return
        try:
            seen = set(read_json(GH_SEEN))
        except (OSError, ValueError):
            seen = set()
        try:
            items = json.loads(out)
        except ValueError:
            return
        new = [n for n in items if n.get("id") not in seen]
        for n in new[:2]:
            repo = n.get("repository", {}).get("name", "")
            title = n.get("subject", {}).get("title", "")
            sev = "info"
            low = title.lower()
            if (
                n.get("reason") == "ci_activity"
                or n.get("subject", {}).get("type") == "CheckSuite"
            ):
                sev = (
                    "bad"
                    if ("fail" in low or "cancel" in low)
                    else "good"
                    if "succe" in low
                    else "info"
                )
            self.push(
                {
                    "id": f"gh-{n['id']}",
                    "icon": ICONS["github"],
                    "text": f"{repo}: {title[:26]}",
                    "severity": sev,
                    "ttl": 6,
                }
            )
        if new:
            seen |= {n["id"] for n in items}
            with open(GH_SEEN, "w") as handle:
                json.dump(sorted(seen)[-500:], handle)

    def t3_producer(self):
        try:
            stamp = max(
                os.stat(path).st_mtime_ns
                for path in (T3_DB, f"{T3_DB}-wal")
                if os.path.exists(path)
            )
        except (OSError, ValueError):
            return
        if stamp == self.t3_stamp:
            return
        self.t3_stamp = stamp
        try:
            with sqlite3.connect(f"file:{T3_DB}?mode=ro", uri=True, timeout=0.2) as db:
                rows = db.execute(
                    """
                    SELECT s.thread_id, COALESCE(v.state, s.status),
                           COALESCE(t.pending_approval_count, 0),
                           COALESCE(t.pending_user_input_count, 0),
                           s.status
                    FROM projection_thread_sessions s
                    JOIN projection_threads t ON t.thread_id = s.thread_id
                    LEFT JOIN projection_turns v
                      ON v.turn_id = COALESCE(s.active_turn_id, t.latest_turn_id)
                    """
                ).fetchall()
        except (OSError, sqlite3.Error):
            return
        states = {row[0]: row[1] for row in rows}
        active = {row[0]: bool(row[2] or row[3]) for row in rows if row[4] == "running"}
        self.note_sessions("t3", self.t3_active, active, states)
        self.t3_active = active

    def claude_producer(self):
        active = {}
        states = {}
        for path in glob.glob(f"{CLAUDE_SESSIONS}/*.json"):
            try:
                session = read_json(path, 64 << 10)
                pid = int(session["pid"])
                proc_start = str(session["procStart"])
            except (KeyError, OSError, TypeError, ValueError):
                continue
            try:
                with open(f"/proc/{pid}/stat") as stat_file:
                    live_start = stat_file.read().split()[21]
            except (OSError, IndexError):
                live_start = None
            session_id = str(session.get("sessionId") or pid)
            states[session_id] = session.get("status")
            if live_start != proc_start:
                if time.time() - float(session.get("updatedAt") or 0) > CLAUDE_STALE:
                    try:
                        os.remove(path)
                    except OSError:
                        pass
                continue
            working, blocked = claude_session_activity(session)
            if working:
                active[session_id] = blocked
        self.note_sessions("claude", self.claude_active, active, states)
        self.claude_active = active

    def remote_action_producer(self, now):
        with REMOTE_ACTIONS_LOCK:
            version = REMOTE_ACTIONS_VERSION
            polled = REMOTE_ACTIONS_AT
            snapshot = {
                provider: [dict(item) for item in REMOTE_ACTIONS[provider]]
                for provider in ("t3", "claude")
            }
        if polled is not None and now - polled > REMOTE_STALE:
            self.remote_t3_active = None
            self.remote_claude_active = None
            self.remote_actions_version = version
            self.remote_stale = True
            return
        if version == self.remote_actions_version and not self.remote_stale:
            return
        self.remote_actions_version = version
        self.remote_stale = False
        t3_states = {
            str(item.get("sessionId")): item.get("state")
            for item in snapshot["t3"]
            if item.get("sessionId")
        }
        t3_active = {
            str(item["sessionId"]): bool(item.get("blocked"))
            for item in snapshot["t3"]
            if item.get("sessionId") and item.get("status") == "running"
        }
        self.note_sessions("t3", self.remote_t3_active, t3_active, t3_states)
        self.remote_t3_active = t3_active
        claude_states = {
            str(item.get("sessionId")): item.get("status")
            for item in snapshot["claude"]
            if item.get("sessionId")
        }
        claude_active = {}
        for item in snapshot["claude"]:
            working, blocked = claude_session_activity(item)
            if working and item.get("sessionId"):
                claude_active[str(item["sessionId"])] = blocked
        self.note_sessions(
            "claude", self.remote_claude_active, claude_active, claude_states
        )
        self.remote_claude_active = claude_active

    def note_sessions(self, provider, previous, active, states):
        if previous is None:
            return
        ended = set(previous) - set(active)
        started = set(active) - set(previous)
        ended_states = {states.get(session_id) for session_id in ended}
        change = self.action_changes.setdefault(
            provider, {"completion": None, "started": False}
        )
        if "error" in ended_states:
            change["completion"] = ("error", "bad")
        elif ended_states & {"completed", "done"} and not change["completion"]:
            change["completion"] = ("done", "good")
        if started:
            change["started"] = True

    def sync_actions(self):
        for provider in ("t3", "claude"):
            local = getattr(self, f"{provider}_active") or {}
            remote = getattr(self, f"remote_{provider}_active") or {}
            blocked_remote = sum(1 for value in remote.values() if value)
            blocked = sum(1 for value in local.values() if value) + blocked_remote
            if blocked:
                state, count, remote_count = "blocked", blocked, blocked_remote
            else:
                state, count, remote_count = (
                    "working",
                    len(local) + len(remote),
                    len(remote),
                )
            setattr(
                self,
                f"{provider}_action",
                self.make_action(provider, state, count, remote_count),
            )

    def settle_actions(self, previous):
        self.sync_actions()
        changes = self.action_changes
        self.action_changes = {}
        for provider in ("t3", "claude"):
            completion = changes.get(provider, {}).get("completion")
            if completion:
                self.finish_action(provider, *completion)
        if self.task():
            return
        if not any(self.actions().values()):
            self.action_notice = None
        action = self.current_action()
        started = {name for name, change in changes.items() if change["started"]}
        for provider in started:
            other = self.actions().get(provider)
            if action and other and provider != action["provider"]:
                self.push_action_event(provider, other["text"], "info", "glance", 1.4)

    def make_action(self, provider, state, count, remote_count=0):
        if not state or not count:
            return None
        blocked = state == "blocked"
        word = ("questions" if count > 1 else "question") if blocked else "working"
        if remote_count == count:
            count_text = f"{count} " if count > 1 else ""
            text = f"{count_text}remote {word}"
        elif remote_count:
            text = f"{count} {word} · {remote_count} remote"
        else:
            count_text = f"{count} " if count > 1 else ""
            text = f"{count_text}{word}"
        return {
            "provider": provider,
            "icon": ICONS[provider],
            "text": text,
            "state": state,
            "count": count,
            "dot": "crit" if blocked else "ok",
            "severity": "bad" if blocked else "info",
        }

    def push_action_event(self, provider, text, severity, kind, ttl):
        if self.current and SEVERITY_RANK.get(self.current.get("severity"), 0) < 2:
            self.current = None
        self.push(
            {
                "id": f"action-{time.time_ns()}",
                "provider": provider,
                "icon": ICONS[provider],
                "text": text,
                "severity": severity,
                "ttl": ttl,
                "kind": kind,
            }
        )

    def set_action_notice(self, provider, text, severity):
        self.action_notice = {
            "provider": provider,
            "icon": ICONS[provider],
            "text": text,
            "severity": severity,
            "kind": "done" if text == "done" else "blocked",
        }

    def finish_action(self, provider, text, severity):
        persist_notice = any(self.actions().values()) and not self.task()
        if persist_notice:
            self.set_action_notice(provider, text, severity)
            return
        self.action_notice = None
        event = {
            "id": f"action-{time.time_ns()}",
            "provider": provider,
            "icon": ICONS[provider],
            "text": text,
            "severity": severity,
            "ttl": 2.2,
            "kind": "done" if text == "done" else "question",
        }
        if self.current and SEVERITY_RANK.get(self.current.get("severity"), 0) < 2:
            self.current = None
        self.push(event)

    def actions(self):
        return {"t3": self.t3_action, "claude": self.claude_action}

    def reconcile_actions(self):
        actions = self.actions()
        primary = actions.get(self.action_primary)
        working = [
            name
            for name in ("t3", "claude")
            if actions.get(name) and actions[name]["state"] != "blocked"
        ]
        if primary and (primary["state"] != "blocked" or not working):
            return
        self.action_primary = (
            working[0]
            if working
            else next((name for name in ("t3", "claude") if actions.get(name)), None)
        )

    def current_action(self):
        self.reconcile_actions()
        return self.actions().get(self.action_primary)

    def bubble_entries(self):
        self.reconcile_actions()
        actions = self.actions()
        task = self.task()
        notice = self.action_notice
        order = []
        for provider in (self.action_primary, "t3", "claude"):
            if provider and provider not in order:
                order.append(provider)
        entries = []
        for index, provider in enumerate(order):
            action = actions.get(provider)
            best = None
            if action and (task or provider != self.action_primary):
                best = {
                    "provider": provider,
                    "icon": action["icon"],
                    "text": action["text"],
                    "severity": action["severity"],
                    "kind": "blocked" if action["state"] == "blocked" else "working",
                    "notice": False,
                }
            if notice and notice["provider"] == provider:
                candidate = dict(notice, notice=True)
                if (
                    best is None
                    or BUBBLE_RANK[candidate["kind"]] >= BUBBLE_RANK[best["kind"]]
                ):
                    best = candidate
            if best:
                entries.append((BUBBLE_RANK[best["kind"]], index, best))
        entries.sort(key=lambda item: (-item[0], item[1]))
        return [item[2] for item in entries[:2]]

    def bubble_state(self):
        entries = self.bubble_entries()
        return entries[0] if entries else None

    def shelf(self):
        try:
            stamp = os.stat(SHELF_DIR).st_mtime_ns
        except OSError:
            self.shelf_seen = None
            return {"count": 0, "items": [], "ask": ""}
        ask = ""
        try:
            ask = read_text(SHELF_ASK, 4096).strip()
        except OSError:
            pass
        if stamp == self.shelf_seen and ask == self.shelf_ask:
            return self.shelf_now
        self.shelf_seen = stamp
        self.shelf_ask = ask
        found = []
        for name in os.listdir(SHELF_DIR):
            if name.startswith("."):
                continue
            path = f"{SHELF_DIR}/{name}"
            try:
                info = os.stat(path)
            except OSError:
                continue
            if not os.path.isfile(path):
                continue
            found.append((info.st_mtime, name, path, info.st_size))
        found.sort(reverse=True)
        items = []
        for changed, name, path, size in found[:SHELF_LIMIT]:
            kind = shelf_kind(name)
            thumb = shelf_thumb(path, int(changed)) if kind == "image" else ""
            given_up = (
                hashlib.sha1(f"{path}:{int(changed)}".encode()).hexdigest()[:16]
                in THUMB_GIVEN_UP
            )
            items.append(
                {
                    "name": name,
                    "path": path,
                    "kind": kind,
                    "size": human_size(size),
                    "thumb": thumb,
                    "retry": kind == "image" and not thumb and not given_up,
                    "preview": shelf_preview(path) if kind == "text" else "",
                    "text": shelf_text(path) if kind == "text" else "",
                }
            )
        if any(
            item["kind"] == "image" and not item["thumb"] and item["retry"]
            for item in items
        ):
            self.shelf_seen = None
        self.shelf_now = {"count": len(found), "items": items, "ask": ask}
        return self.shelf_now

    def music(self, cfg):
        if not cfg["producers"]["music"]:
            return None
        with MUSIC_LOCK:
            state = dict(MUSIC)
        if not state or not state.get("title"):
            return None
        state["muted"] = (
            player_volume(state.get("player") or player_name(state)) <= 0.001
        )
        state["liked"] = track_is_liked()
        if not state.get("cover"):
            term = " ".join(
                part
                for part in (
                    state.get("artist"),
                    state.get("album") or state.get("title"),
                )
                if part
            ).strip()
            ripe = COVER_READY.get(term)
            if ripe:
                state["cover"] = ripe[0]
                if ripe[1]:
                    state["accent"] = ripe[1]
        return state

    def scene(self, clock):
        c = colors()
        task = self.task()
        action = self.current_action() if not task else None
        entries = self.bubble_entries()
        bubble = entries[0] if entries else None
        labels = {"t3": "T3 Code", "claude": "Claude Code"}
        main = None
        if task:
            text = " ".join(
                x for x in [task.get("text", ""), task.get("progress", "")] if x
            )
            if task["count"]:
                text += f" +{task['count']}"
            main = {
                "kind": "task",
                "icon": task["icon"],
                "provider": None,
                "text": text,
                "note": f"eta {task['eta']}" if task.get("eta") else "",
                "dot": task["dot"],
                "tone": "plain",
            }
        elif action:
            main = {
                "kind": "action",
                "icon": action["icon"],
                "provider": action["provider"],
                "text": action["text"],
                "note": "",
                "dot": action["dot"],
                "tone": "bad" if action["state"] == "blocked" else "plain",
            }
        event = None
        if self.current:
            ev = self.current
            severity = ev.get("severity", "info")
            event = {
                "id": ev.get("id", ""),
                "icon": ev.get("icon", ""),
                "text": re.sub(r"<[^>]+>", "", ev.get("text", "")),
                "severity": SEV_ALIAS.get(severity, severity),
                "kind": ev.get("kind"),
                "provider": ev.get("provider"),
                "layout": ev.get("layout"),
            }
            if ev.get("layout") == "telegram":
                event["sender"] = self.telegram_sender
                event["count"] = self.telegram_count
        return {
            "ts": time.time(),
            "seq": self.event_seq,
            "clock": clock,
            "tooltip": self.calendar(),
            "palette": {
                "bg": c["bg"],
                "bg_alt": c["bg_alt"],
                "fg": c["fg"],
                "fg_alt": c["fg_alt"],
                "muted": c["muted"],
                "ok": c["ok"],
                "warn": c["warn"],
                "crit": c["crit"],
                "accent": c["accent"],
                "hover": c["hover"],
                "claude": CLAUDE_ORANGE,
                "telegram": TELEGRAM_BLUE,
            },
            "main": main,
            "fullscreen": FULLSCREEN,
            "hold": grabbing(),
            "settings": live_config(),
            "missing": missing_tools(),
            "sys": system_state(),
            "shelf": self.shelf(),
            "music": self.music_now,
            "event": event,
            "bubble": (
                {
                    "provider": bubble["provider"],
                    "icon": bubble["icon"],
                    "kind": bubble["kind"],
                    "tooltip": "\n".join(
                        f"{labels[entry['provider']]}: {entry['text']}"
                        for entry in entries
                    ),
                    "second": (
                        {
                            "provider": entries[1]["provider"],
                            "icon": entries[1]["icon"],
                            "kind": entries[1]["kind"],
                        }
                        if len(entries) > 1
                        else None
                    ),
                }
                if bubble
                else None
            ),
        }

    def handle_bubble_click(self, half=0):
        entries = self.bubble_entries()
        if not entries:
            return
        bubble = entries[half] if half < len(entries) else entries[0]
        if self.task():
            if bubble.get("notice"):
                self.action_notice = None
                return
            self.push(
                {
                    "id": f"action-{time.time_ns()}",
                    "provider": bubble["provider"],
                    "icon": bubble["icon"],
                    "text": bubble["text"],
                    "severity": bubble["severity"],
                    "ttl": 1.8,
                    "kind": "question" if bubble["kind"] == "blocked" else "glance",
                }
            )
            return
        if bubble.get("notice"):
            self.action_notice = None
            kind = "done" if bubble["text"] == "done" else "question"
            self.push_action_event(
                bubble["provider"], bubble["text"], bubble["severity"], kind, 1.9
            )
            return
        source = self.current_action()
        if not source:
            return
        if bubble["kind"] == "working":
            target = self.actions().get(bubble["provider"])
            if target and source["provider"] != target["provider"]:
                self.action_primary = target["provider"]
            return
        self.push_action_event(bubble["provider"], "question", "bad", "question", 1.9)

    def telegram_producer(self, now):
        senders = []
        while True:
            try:
                senders.append(TELEGRAM_MESSAGES.get_nowait())
            except queue.Empty:
                break
        if not senders:
            return
        target = (
            self.current
            if self.current and self.current.get("id") == "telegram-live"
            else None
        )
        if target is None:
            target = next(
                (event for event in self.queue if event.get("id") == "telegram-live"),
                None,
            )
        if target is None:
            self.telegram_count = 0
            target = {
                "id": "telegram-live",
                "icon": ICONS["telegram"],
                "text": "",
                "severity": "info",
                "layout": "telegram",
                "live_until": now + TELEGRAM_HOLD,
            }
            self.push(target)
        self.telegram_count += len(senders)
        self.telegram_sender = senders[-1]
        target["text"] = f"{senders[-1]}  {self.telegram_count}"
        target["live_until"] = now + TELEGRAM_HOLD

    def external_producer(self):
        for path in sorted(glob.glob(f"{EVENTS_DIR}/*.json")):
            try:
                ev = read_json(path, 64 << 10)
                os.remove(path)
            except (OSError, ValueError):
                continue
            if isinstance(ev, dict) and ev.get("text"):
                ev.setdefault("id", os.path.basename(path)[:-5])
                ev.setdefault("icon", "")
                ev.setdefault("severity", "info")
                ev["severity"] = SEV_ALIAS.get(ev["severity"], ev["severity"])
                self.push(ev)

    def producers(self, cfg):
        now = time.monotonic()
        p = cfg["producers"]
        self.battery_producers(p)
        if p["wifi"] and have("nmcli"):
            self.wifi_producer(now)
        if p["tailnet"]:
            self.tailnet_producer(now)
        if p["ram"]:
            self.ram_producer()
        if p["bluetooth"] and have("bluetoothctl"):
            self.bt_producer(now)
        if p["github"]:
            self.github_producer(now)
        previous = self.current_action()
        previous = dict(previous) if previous else None
        if p["t3"]:
            self.t3_producer()
        else:
            self.t3_active = None
        if p["claude"]:
            self.claude_producer()
        else:
            self.claude_active = None
        self.remote_action_producer(now)
        self.settle_actions(previous)
        if p["external"]:
            self.external_producer()

    def task(self):
        files = sorted(glob.glob(f"{TASKS_DIR}/*.json"), key=os.path.getmtime)
        if not files:
            return None
        try:
            t = read_json(files[-1], 64 << 10)
        except (OSError, ValueError):
            return None
        if not isinstance(t, dict):
            return None
        t.setdefault("icon", "")
        t.setdefault("dot", "ok")
        t["count"] = len(files) - 1
        t["_id"] = os.path.basename(files[-1])
        return t

    def calendar(self):
        today = date.today()
        if self.calendar_day != today:
            self.calendar_day = today
            self.calendar_text = (
                calendar.TextCalendar(calendar.MONDAY)
                .formatmonth(today.year, today.month)
                .rstrip("\n")
            )
        return self.calendar_text

    def alert_pop(self, cfg, now):
        if not self.current and now < self.date_until:
            self.current = {
                "id": "date",
                "icon": ICONS["date"],
                "text": datetime.now().strftime("%A %d %B"),
                "severity": "info",
                "ttl": DATE_SECONDS,
            }
            self.started = now
            self.date_until = 0.0
        if not self.current and self.queue:
            self.current = self.queue.pop(0)
            self.started = now
            self.event_seq += 1
            if self.current.get("live_until") is not None:
                self.current["live_until"] = max(
                    self.current["live_until"], now + TELEGRAM_HOLD
                )
            snd = self.current.get("sound")
            if snd and cfg["sound"]:
                spath = SOUNDS.get(snd, SOUND) if isinstance(snd, str) else SOUND
                subprocess.Popen(
                    ["pw-play", spath],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
            eid = self.current.get("id", "")
            if not any(eid.startswith(p) for p in cfg.get("history_ignore", [])):
                try:
                    with open(f"{STATE_DIR}/history.jsonl", "a") as f:
                        f.write(json.dumps(dict(self.current, at=time.time())) + "\n")
                except OSError:
                    pass

    def expire_event(self, cfg, now):
        ev = self.current
        if not ev:
            return
        live_until = ev.get("live_until")
        if live_until is not None:
            if now >= live_until:
                self.current = None
                self.telegram_count = 0
            return
        if now - self.started >= float(ev.get("ttl") or cfg["seconds"]):
            self.current = None

    def loop(self):
        last_prod = 0.0
        last_cfg = 0.0
        cfg = load_config()
        while True:
            now = time.monotonic()
            if now - last_cfg >= 1.0:
                cfg = load_config()
                last_cfg = now
            self.telegram_producer(now)
            if now - last_prod >= 1.0:
                self.producers(cfg)
                last_prod = now
            elif cfg["producers"]["external"]:
                self.external_producer()
            if os.path.exists(DATE_FLAG):
                os.remove(DATE_FLAG)
                self.date_until = now + DATE_SECONDS
            if os.path.exists(BUBBLE_CLICK):
                try:
                    half = 1 if read_text(BUBBLE_CLICK, 16).strip() == "1" else 0
                except OSError:
                    half = 0
                os.remove(BUBBLE_CLICK)
                self.handle_bubble_click(half)
            self.expire_event(cfg, now)
            self.alert_pop(cfg, now)
            self.music_now = self.music(cfg)
            scene_out = self.scene(datetime.now().strftime("%H:%M"))
            payload = {k: v for k, v in scene_out.items() if k != "ts"}
            if payload != self.last_scene or now - self.last_scene_at >= 5.0:
                tmp = SCENE_FILE + ".tmp"
                with open(tmp, "w") as f:
                    json.dump(scene_out, f)
                os.replace(tmp, SCENE_FILE)
                self.last_scene = payload
                self.last_scene_at = now
            time.sleep(TICK)


def remote_pull_thread():
    global REMOTE_ACTIONS, REMOTE_ACTIONS_VERSION, REMOTE_ACTIONS_AT
    mirror = set()
    delay = 3.0
    shell = remote_shell()
    script = (
        'for f in "$HOME"/.cache/island/events/*.json; do\n'
        '[ -f "$f" ] || continue\n'
        "printf 'EVENT\\t%s\\n' \"$(tr -d '\\n' < \"$f\")\"\n"
        'rm -f "$f"\n'
        "done\n"
        'for f in "$HOME"/.cache/island/tasks/*.json; do\n'
        '[ -f "$f" ] || continue\n'
        'b=$(basename "$f" .json)\n'
        'printf \'TASK\\t%s\\t%s\\n\' "$b" "$(tr -d \'\\n\' < "$f")"\n'
        "done\n"
        'if [ -r "$HOME/.t3/userdata/state.sqlite" ]; then\n'
        't3=$(sqlite3 -json "$HOME/.t3/userdata/state.sqlite" '
        '"SELECT s.thread_id AS sessionId, COALESCE(v.state,s.status) AS state, '
        "CASE WHEN COALESCE(t.pending_approval_count,0) > 0 OR "
        "COALESCE(t.pending_user_input_count,0) > 0 THEN 1 ELSE 0 END AS blocked, "
        "s.status AS status FROM projection_thread_sessions s JOIN projection_threads t "
        "ON t.thread_id=s.thread_id LEFT JOIN projection_turns v ON "
        'v.turn_id=COALESCE(s.active_turn_id,t.latest_turn_id);" '
        "2>/dev/null | tr -d '\\n')\n"
        "printf 'T3\\t%s\\n' \"${t3:-[]}\"\n"
        "fi\n"
        'for f in "$HOME"/.cache/island/claude/*.json; do\n'
        '[ -f "$f" ] || continue\n'
        "raw=$(tr -d '\\n' < \"$f\")\n"
        "pid=$(printf '%s' \"$raw\" | jq -r '.pid // empty')\n"
        "start=$(printf '%s' \"$raw\" | jq -r '.procStart // empty')\n"
        '[ -n "$pid" ] && [ -n "$start" ] || continue\n'
        "live=$(awk '{print $22}' \"/proc/$pid/stat\" 2>/dev/null)\n"
        'if [ "$live" != "$start" ]; then\n'
        '[ -n "$(find "$f" -mmin +1)" ] && rm -f "$f" && continue\n'
        "fi\n"
        "printf 'CLAUDE\\t%s\\n' \"$raw\"\n"
        "done\n"
    )
    while True:
        time.sleep(delay)
        if not shell:
            shell = remote_shell()
            delay = 15.0
            continue
        try:
            r = subprocess.run(
                shell,
                shell=True,
                input=script,
                capture_output=True,
                text=True,
                timeout=10,
                check=False,
            )
            if r.returncode != 0 or len(r.stdout) > (8 << 20):
                delay = min(delay * 2, 60.0)
                continue
            delay = 3.0
            alive = set()
            remote_actions = {"t3": [], "claude": []}
            for line in r.stdout.splitlines():
                parts = line.split("\t")
                if parts[0] == "EVENT" and len(parts) == 2:
                    try:
                        ev = json.loads(parts[1])
                    except ValueError:
                        continue
                    ev["id"] = f"rmt-{ev.get('id', 'ev')}-{time.time():.0f}"
                    with open(f"{EVENTS_DIR}/{ev['id']}.json", "w") as f:
                        json.dump(ev, f)
                elif parts[0] == "TASK" and len(parts) == 3:
                    name = f"rmt-{parts[1]}"
                    alive.add(name)
                    try:
                        t = json.loads(parts[2])
                    except ValueError:
                        continue
                    tmp = f"{TASKS_DIR}/{name}.tmp"
                    with open(tmp, "w") as f:
                        json.dump(t, f)
                    os.replace(tmp, f"{TASKS_DIR}/{name}.json")
                elif parts[0] == "T3" and len(parts) == 2:
                    try:
                        remote_actions["t3"] = json.loads(parts[1])
                    except ValueError:
                        continue
                elif parts[0] == "CLAUDE" and len(parts) == 2:
                    try:
                        remote_actions["claude"].append(json.loads(parts[1]))
                    except ValueError:
                        continue
            for name in mirror - alive:
                try:
                    os.remove(f"{TASKS_DIR}/{name}.json")
                except OSError:
                    pass
            mirror = alive
            with REMOTE_ACTIONS_LOCK:
                REMOTE_ACTIONS_AT = time.monotonic()
                if remote_actions != REMOTE_ACTIONS:
                    REMOTE_ACTIONS = remote_actions
                    REMOTE_ACTIONS_VERSION += 1
        except Exception:
            delay = min(delay * 2, 60.0)


def ntfy_thread():
    try:
        topic = read_text(NTFY_TOPIC_FILE, 4096).strip()
    except OSError:
        return
    if not topic:
        return
    while True:
        try:
            req = urllib.request.Request(
                f"https://ntfy.sh/{topic}/json", headers={"User-Agent": "island"}
            )
            with urllib.request.urlopen(req, timeout=300) as r:
                while True:
                    raw = r.readline(65536)
                    if not raw:
                        break
                    if len(raw) >= 65536:
                        continue
                    try:
                        m = json.loads(raw)
                    except ValueError:
                        continue
                    if m.get("event") != "message":
                        continue
                    sev = "crit" if m.get("priority", 3) >= 4 else "info"
                    ev = {
                        "id": f"ntfy-{m.get('id')}",
                        "icon": ICONS["tailnet_up"],
                        "text": (m.get("title") or m.get("message") or "")[:30],
                        "severity": sev,
                        "ttl": 6,
                    }
                    if sev == "crit":
                        ev["sound"] = True
                    path = f"{EVENTS_DIR}/ntfy-{m.get('id')}.json"
                    with open(path, "w") as handle:
                        json.dump(ev, handle)
        except Exception:
            pass
        time.sleep(15)


def telegram_thread():
    match = (
        "type='method_call',path='/org/freedesktop/Notifications',"
        "interface='org.freedesktop.Notifications',member='Notify'"
    )
    while True:
        proc = None
        try:
            proc = subprocess.Popen(
                ["busctl", "--user", "monitor", f"--match={match}", "--json=short"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                bufsize=1,
            )
            with CHILDREN_LOCK:
                CHILDREN.add(proc)
            for line in proc.stdout or ():
                try:
                    message = json.loads(line)
                    data = message["payload"]["data"]
                except (KeyError, TypeError, ValueError):
                    continue
                if len(data) < 4:
                    continue
                app_name, app_icon, summary = data[0], data[2], data[3]
                if "telegram" not in f"{app_name} {app_icon}".lower():
                    continue
                if not load_config()["producers"]["telegram"]:
                    continue
                sender = clean_notification_text(summary)
                if not sender:
                    continue
                short_sender = (
                    sender if len(sender) <= 20 else f"{sender[:19].rstrip()}…"
                )
                TELEGRAM_MESSAGES.put(short_sender)
            proc.wait(timeout=1)
        except (OSError, subprocess.SubprocessError):
            time.sleep(2)
        finally:
            if proc is not None:
                with CHILDREN_LOCK:
                    CHILDREN.discard(proc)
        time.sleep(2)


def setting_command(key):
    cfg = load_config()
    if key == "sound":
        cfg["sound"] = not cfg["sound"]
    elif key == "seconds":
        cfg["seconds"] = 2.0 if cfg["seconds"] >= 5 else cfg["seconds"] + 0.5
    elif key == "clear":
        for stale in glob.glob(f"{TASKS_DIR}/*.json"):
            os.remove(stale)
        return
    elif key == "notifications":
        subprocess.Popen(["swaync-client", "-t", "-sw"])
        return
    elif key in cfg["producers"]:
        cfg["producers"][key] = not cfg["producers"][key]
    elif key.startswith("usage:") or key.startswith("pin:"):
        kind, _, pid = key.partition(":")
        listing = usage_listing()
        if kind == "usage":
            chosen = list(cfg["usage"].get("providers") or [])
            if not chosen:
                chosen = [p["id"] for p in listing if p["enabled"]]
            if pid in chosen:
                chosen.remove(pid)
            else:
                chosen.append(pid)
            cfg["usage"]["providers"] = chosen
        else:
            pinned = list(cfg["usage"].get("pinned") or [])
            if not pinned:
                pinned = [p["id"] for p in listing if p["pinned"]]
            if pid in pinned:
                pinned.remove(pid)
            else:
                pinned.append(pid)
            cfg["usage"]["pinned"] = pinned[-2:]
    elif "=" in key and key.split("=", 1)[0] in ("remote", "probe_host", "font"):
        name, _, value = key.partition("=")
        cfg[name] = value.strip()
    else:
        return
    save_config(cfg)


def usage_listing():
    out = run([sys.executable, f"{PLUGIN_DIR}/usage.py", "--list"], 20)
    try:
        return json.loads(out).get("providers") or []
    except ValueError:
        return []


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "set":
        setting_command(sys.argv[2])
    elif len(sys.argv) > 2 and sys.argv[1] == "shelf":
        shelf_command(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "")
    elif len(sys.argv) > 2 and sys.argv[1] == "music":
        music_control(sys.argv[2])
    elif len(sys.argv) > 1 and sys.argv[1] == "bubble":
        os.makedirs(STATE_DIR, exist_ok=True)
        with open(BUBBLE_CLICK, "w") as click:
            click.write(sys.argv[2] if len(sys.argv) > 2 else "0")
    elif len(sys.argv) > 1 and sys.argv[1] == "date":
        os.makedirs(STATE_DIR, exist_ok=True)
        open(DATE_FLAG, "w").close()
    else:
        os.makedirs(STATE_DIR, exist_ok=True)
        lock = open(LOCK_FILE, "w")
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            sys.exit(0)
        signal.signal(signal.SIGTERM, stop_children)
        signal.signal(signal.SIGINT, stop_children)
        threading.Thread(target=ntfy_thread, daemon=True).start()
        threading.Thread(target=telegram_thread, daemon=True).start()
        threading.Thread(target=music_thread, daemon=True).start()
        threading.Thread(target=fullscreen_thread, daemon=True).start()
        threading.Thread(target=system_thread, daemon=True).start()
        threading.Thread(target=remote_pull_thread, daemon=True).start()
        Island().loop()
