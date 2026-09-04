import json
import os
import sys
import time
from pathlib import Path

STATE_DIR = Path.home() / ".cache" / "island" / "codex"
STATUS = {
    "SessionStart": "idle",
    "UserPromptSubmit": "busy",
    "PostToolUse": "busy",
    "PermissionRequest": "blocked",
    "Stop": "done",
}


def codex_process():
    pid = os.getppid()
    while pid > 1:
        proc = Path(f"/proc/{pid}")
        try:
            stat = (proc / "stat").read_text().split()
            command = (proc / "cmdline").read_bytes().replace(b"\0", b" ").decode()
            executable = os.readlink(proc / "exe")
        except (OSError, UnicodeDecodeError):
            return None
        name = stat[1].strip("()")
        if (
            name.startswith("codex")
            or executable.endswith("/codex")
            or "codex app-server" in command
        ):
            return pid, stat[21]
        pid = int(stat[3])
    return None


def main():
    try:
        payload = json.load(sys.stdin)
        event = payload.get("hook_event_name") or payload.get("hookEventName")
        session_id = str(
            payload.get("session_id")
            or payload.get("thread_id")
            or payload.get("conversation_id")
            or payload.get("sessionId")
            or ""
        )
    except (AttributeError, TypeError, ValueError):
        return
    if not event or not session_id:
        return
    status = STATUS.get(event)
    if not status:
        return
    process = codex_process()
    pid, started = process or (0, "")
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    target = STATE_DIR / f"{session_id}.json"
    state = {
        "pid": pid,
        "procStart": started,
        "status": status,
        "sessionId": session_id,
        "updatedAt": time.time(),
    }
    temporary = target.with_suffix(".tmp")
    temporary.write_text(json.dumps(state, separators=(",", ":")))
    temporary.replace(target)


if __name__ == "__main__":
    main()
