import json
import os
import sys
import time
from pathlib import Path

STATE_DIR = Path.home() / ".cache" / "island" / "claude"
BLOCKING = {
    "permission_prompt",
    "elicitation_dialog",
    "elicitation_url_dialog",
    "agent_needs_input",
}
STATUS = {
    "SessionStart": "idle",
    "UserPromptSubmit": "busy",
    "PostToolUse": "busy",
    "PermissionRequest": "blocked",
    "Stop": "done",
    "StopFailure": "error",
}


def claude_process():
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
            name in ("claude", "claude.exe")
            or "/@anthropic-ai/claude-code/" in executable
            or "/@anthropic-ai/claude-code/" in command
        ):
            return pid, stat[21]
        pid = int(stat[3])
    return None


def driven_by_t3(pid):
    try:
        parent = int(Path(f"/proc/{pid}/stat").read_text().split()[3])
        command = Path(f"/proc/{parent}/cmdline").read_bytes()
    except (OSError, ValueError, IndexError):
        return False
    return b"t3code" in command


def state_path(session_id):
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    return STATE_DIR / f"{session_id}.json"


def write_state(payload, status):
    process = claude_process()
    if not process:
        return
    pid, started = process
    target = state_path(payload["session_id"])
    if driven_by_t3(pid):
        target.unlink(missing_ok=True)
        return
    state = {
        "pid": pid,
        "procStart": started,
        "status": status,
        "sessionId": payload["session_id"],
        "updatedAt": time.time(),
    }
    notification = payload.get("notification_type")
    if status == "blocked" and notification:
        state["waitingFor"] = notification
    temporary = target.with_suffix(".tmp")
    temporary.write_text(json.dumps(state, separators=(",", ":")))
    temporary.replace(target)


def main():
    try:
        payload = json.load(sys.stdin)
        event = payload["hook_event_name"]
        payload["session_id"]
    except (KeyError, TypeError, ValueError):
        return
    if event == "SessionEnd":
        state_path(payload["session_id"]).unlink(missing_ok=True)
        return
    if event == "Notification":
        if payload.get("notification_type") not in BLOCKING:
            return
        write_state(payload, "blocked")
        return
    status = STATUS.get(event)
    if status:
        write_state(payload, status)


if __name__ == "__main__":
    main()
