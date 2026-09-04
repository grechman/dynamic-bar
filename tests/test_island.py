import importlib.util
import json
import os
import tempfile
import unittest

ROOT = tempfile.mkdtemp(prefix="island-test-")
os.environ["ISLAND_DIR"] = ROOT
os.environ["ISLAND_REMOTE"] = ""
os.environ["ISLAND_CONFIG"] = f"{ROOT}/island.json"
SPEC = importlib.util.spec_from_file_location(
    "island", os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "island.py")
)
island = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(island)


def kinds(isl):
    return [event["kind"] for event in isl.queue]


class Actions(unittest.TestCase):
    def setUp(self):
        self.isl = island.Island()
        for path in os.listdir(f"{ROOT}/tasks"):
            os.remove(f"{ROOT}/tasks/{path}")

    def step(self, t3=None, claude=None, t3_states=None, claude_states=None, codex=None):
        isl = self.isl
        previous = isl.current_action()
        previous = dict(previous) if previous else None
        if t3 is not None:
            isl.note_sessions("t3", isl.t3_active, t3, t3_states or {})
            isl.t3_active = t3
        if claude is not None:
            isl.note_sessions("claude", isl.claude_active, claude, claude_states or {})
            isl.claude_active = claude
        if codex is not None:
            isl.note_sessions("codex", isl.codex_active, codex, {})
            isl.codex_active = codex
        isl.settle_actions(previous)

    def test_codex_is_a_third_provider(self):
        self.step(t3={"a": False}, claude={}, codex={})
        self.step(codex={"x": False})
        self.assertEqual(kinds(self.isl), ["glance"])
        self.assertEqual(self.isl.queue[0]["provider"], "codex")
        self.assertEqual(self.isl.bubble_state()["provider"], "codex")
        self.step(t3={})
        self.assertEqual(self.isl.current_action()["provider"], "codex")
        self.assertEqual(self.isl.current_action()["text"], "working")

    def test_session_producer_reads_codex_files(self):
        directory = f"{ROOT}/codex-sessions"
        os.makedirs(directory, exist_ok=True)
        with open(f"/proc/{os.getpid()}/stat") as handle:
            started = handle.read().split()[21]
        with open(f"{directory}/live.json", "w") as handle:
            json.dump({"pid": os.getpid(), "procStart": started, "status": "busy", "sessionId": "live", "updatedAt": 0}, handle)
        with open(f"{directory}/nopid.json", "w") as handle:
            json.dump({"pid": 0, "procStart": "", "status": "blocked", "sessionId": "nopid", "updatedAt": island.time.time()}, handle)
        with open(f"{directory}/stale.json", "w") as handle:
            json.dump({"pid": 0, "procStart": "", "status": "busy", "sessionId": "stale", "updatedAt": 0}, handle)
        with open(f"{directory}/dead.json", "w") as handle:
            json.dump({"pid": os.getpid(), "procStart": "1", "status": "busy", "sessionId": "dead", "updatedAt": 0}, handle)
        self.isl.session_producer("codex", directory)
        self.assertEqual(self.isl.codex_active, {"live": False, "nopid": True})
        self.assertFalse(os.path.exists(f"{directory}/dead.json"))

    def test_first_poll_is_silent(self):
        self.step(t3={"a": False})
        self.assertEqual(kinds(self.isl), [])
        self.assertEqual(self.isl.current_action()["text"], "working")

    def test_second_session_resizes_with_flash(self):
        self.step(t3={"a": False})
        self.step(t3={"a": False, "b": False})
        self.assertEqual(kinds(self.isl), [])
        self.assertEqual(self.isl.current_action()["text"], "2 working")

    def test_other_provider_glances_then_stays_in_bubble(self):
        self.step(t3={"a": False}, claude={})
        self.step(claude={"c": False})
        self.assertEqual(kinds(self.isl), ["glance"])
        self.assertEqual(self.isl.queue[0]["provider"], "claude")
        self.assertEqual(self.isl.current_action()["provider"], "t3")
        self.assertEqual(self.isl.bubble_state()["provider"], "claude")

    def test_click_done_plays_done_event(self):
        self.step(t3={"a": False, "b": False})
        self.step(t3={"a": False}, t3_states={"b": "completed"})
        self.isl.queue.clear()
        self.isl.handle_bubble_click()
        self.assertEqual(kinds(self.isl), ["done"])
        self.assertEqual(self.isl.queue[0]["severity"], "good")
        self.assertIsNone(self.isl.action_notice)

    def test_click_blocked_plays_question_event(self):
        self.step(t3={"a": False}, claude={"c": True})
        self.isl.queue.clear()
        bubble = self.isl.bubble_state()
        self.assertEqual(bubble["kind"], "blocked")
        self.isl.handle_bubble_click()
        self.assertEqual(kinds(self.isl), ["question"])
        self.assertEqual(self.isl.queue[0]["provider"], "claude")

    def test_one_of_two_ends_keeps_green_notice(self):
        self.step(t3={"a": False, "b": False})
        self.step(t3={"a": False}, t3_states={"b": "completed"})
        self.assertEqual(self.isl.action_notice["kind"], "done")
        self.assertEqual(kinds(self.isl), [])
        self.assertEqual(self.isl.bubble_state()["kind"], "done")

    def test_final_end_plays_transient_done_and_clears_everything(self):
        self.step(t3={"a": False, "b": False})
        self.step(t3={"a": False}, t3_states={"b": "completed"})
        self.isl.queue.clear()
        self.step(t3={}, t3_states={"a": "completed"})
        self.assertIsNone(self.isl.action_notice)
        self.assertEqual(kinds(self.isl), ["done"])
        self.assertIsNone(self.isl.current_action())
        self.assertIsNone(self.isl.bubble_state())

    def test_error_beats_done(self):
        self.step(t3={"a": False, "b": False})
        self.step(t3={}, t3_states={"a": "completed", "b": "error"})
        self.assertEqual(self.isl.queue[0]["text"], "error")
        self.assertEqual(self.isl.queue[0]["severity"], "bad")

    def test_vanished_busy_claude_is_silent(self):
        self.step(claude={"c": False})
        self.step(claude={}, claude_states={"c": "busy"})
        self.assertEqual(kinds(self.isl), [])

    def test_claude_error_status(self):
        self.step(claude={"c": False})
        self.step(claude={}, claude_states={"c": "error"})
        self.assertEqual(self.isl.queue[0]["text"], "error")

    def test_sole_blocked_stays_in_main(self):
        self.step(t3={"a": False})
        self.step(t3={"a": True})
        action = self.isl.current_action()
        self.assertEqual(action["text"], "question")
        self.assertEqual(action["state"], "blocked")
        self.assertIsNone(self.isl.bubble_state())
        self.assertEqual(kinds(self.isl), [])

    def test_blocked_moves_to_bubble_when_other_works(self):
        self.step(t3={"a": False}, claude={"c": False})
        self.step(t3={"a": True})
        self.assertEqual(self.isl.current_action()["provider"], "claude")
        bubble = self.isl.bubble_state()
        self.assertEqual((bubble["provider"], bubble["kind"]), ("t3", "blocked"))

    def test_blocked_counts_only_blocked_sessions(self):
        self.isl.remote_t3_active = {"r": True, "s": False}
        self.step(t3={"a": False, "b": False})
        self.assertEqual(self.isl.current_action()["text"], "remote question")
        self.isl.remote_t3_active = {"r": True, "s": True}
        self.step(t3={"a": True, "b": False})
        self.assertEqual(self.isl.current_action()["text"], "3 questions · 2 remote")

    def test_mixed_and_remote_labels(self):
        self.isl.remote_t3_active = {"r": False}
        self.step(t3={"a": False})
        self.assertEqual(self.isl.current_action()["text"], "2 working · 1 remote")
        self.step(t3={})
        self.assertEqual(self.isl.current_action()["text"], "remote working")
        self.isl.remote_t3_active = {"r": False, "s": False}
        self.step(t3={})
        self.assertEqual(self.isl.current_action()["text"], "2 remote working")

    def test_remote_stale_clears_without_completion(self):
        island.REMOTE_ACTIONS_AT = 0.0
        self.isl.remote_t3_active = {"r": False}
        self.isl.remote_actions_version = -1
        self.isl.remote_action_producer(island.REMOTE_STALE + 1)
        self.assertIsNone(self.isl.remote_t3_active)
        self.assertEqual(kinds(self.isl), [])
        island.REMOTE_ACTIONS = {
            "t3": [{"sessionId": "r", "status": "running", "state": "running"}],
            "claude": [],
            "codex": [],
        }
        island.REMOTE_ACTIONS_AT = island.REMOTE_STALE + 2
        self.isl.remote_action_producer(island.REMOTE_STALE + 3)
        self.assertEqual(self.isl.remote_t3_active, {"r": False})
        self.assertEqual(kinds(self.isl), [])

    def test_bench_makes_completion_transient(self):
        with open(f"{ROOT}/tasks/b.json", "w") as task:
            json.dump({"icon": "x", "text": "bench"}, task)
        self.step(t3={"a": False}, claude={"c": False})
        self.step(t3={}, t3_states={"a": "completed"})
        self.assertIsNone(self.isl.action_notice)
        self.assertEqual(kinds(self.isl), ["done"])
        self.assertEqual(self.isl.bubble_state()["provider"], "claude")

    def test_queued_telegram_gets_full_hold_when_shown(self):
        cfg = {"sound": False, "seconds": 3.0, "history_ignore": ["telegram"]}
        island.TELEGRAM_MESSAGES.put("Alice")
        self.isl.push({"id": "ram", "icon": "x", "text": "ram 92%", "severity": "bad"})
        self.isl.telegram_producer(100.0)
        self.isl.alert_pop(cfg, 100.0)
        self.assertEqual(self.isl.current["id"], "ram")
        self.isl.current = None
        self.isl.alert_pop(cfg, 102.6)
        self.assertEqual(self.isl.current["id"], "telegram-live")
        self.assertGreaterEqual(self.isl.current["live_until"], 102.6 + island.TELEGRAM_HOLD)

    def test_click_swaps_primary_without_flow(self):
        self.step(t3={"a": False}, claude={"c": False})
        self.assertEqual(self.isl.current_action()["provider"], "t3")
        self.isl.handle_bubble_click()
        self.assertEqual(self.isl.current_action()["provider"], "claude")
        self.assertEqual(kinds(self.isl), [])
        self.assertEqual(self.isl.bubble_state()["provider"], "t3")

    def test_click_green_dismisses_notice(self):
        self.step(t3={"a": False, "b": False})
        self.step(t3={"a": False}, t3_states={"b": "completed"})
        self.isl.queue.clear()
        self.assertEqual(self.isl.bubble_state()["kind"], "done")
        self.isl.handle_bubble_click()
        self.assertIsNone(self.isl.action_notice)
        self.assertIsNone(self.isl.bubble_state())

    def test_click_error_notice_clears_it(self):
        self.step(t3={"a": False, "b": False})
        self.step(t3={"a": False}, t3_states={"b": "error"})
        self.assertEqual(self.isl.action_notice["text"], "error")
        bubble = self.isl.bubble_state()
        self.assertEqual(bubble["kind"], "blocked")
        self.isl.queue.clear()
        self.isl.handle_bubble_click()
        self.assertIsNone(self.isl.action_notice)
        self.assertEqual(kinds(self.isl), ["question"])
        self.assertEqual(self.isl.queue[0]["text"], "error")

    def test_bench_bubble_shows_blocked_provider(self):
        with open(f"{ROOT}/tasks/b.json", "w") as task:
            json.dump({"icon": "x", "text": "bench"}, task)
        self.step(t3={"a": False}, claude={"c": False})
        self.step(t3={"a": True})
        bubble = self.isl.bubble_state()
        self.assertEqual((bubble["provider"], bubble["kind"]), ("t3", "blocked"))
        self.step(t3={"a": False})
        self.assertEqual(self.isl.bubble_state()["kind"], "working")


if __name__ == "__main__":
    unittest.main()


class BoundedRun(unittest.TestCase):
    def children(self):
        out = island.run(["ps", "-o", "pid=,comm=", "--ppid", str(os.getpid())], 5)
        return [line.split()[1] for line in out.splitlines() if line.split()]

    def test_output_cap_kills_group(self):
        result = island.bounded_run(["sh", "-c", "yes | cat"], 4096, 5)
        self.assertTrue(result.clipped)
        self.assertLessEqual(len(result.stdout), 4096 + (1 << 16))
        self.assertNotIn("yes", self.children())
        self.assertNotIn("cat", self.children())

    def test_deadline_kills_group(self):
        started = island.time.monotonic()
        result = island.bounded_run(["sh", "-c", "sleep 30; echo late"], 4096, 0.5)
        self.assertTrue(result.clipped)
        self.assertLess(island.time.monotonic() - started, 5)
        self.assertNotIn("sleep", self.children())

    def test_ok_result(self):
        result = island.bounded_run(["printf", "ab\\ncd"], 64, 5)
        self.assertTrue(result.ok)
        self.assertEqual(result.text, "ab\ncd")
        self.assertEqual(island.run(["false"]), "")

    def test_bounded_lines_skips_long_lines(self):
        proc = island.spawn(["sh", "-c", "printf 'one\\n'; head -c 200000 /dev/zero | tr '\\0' x; printf '\\ntwo\\n'"])
        lines = list(island.bounded_lines(proc.stdout, 1 << 16))
        proc.wait(5)
        self.assertEqual(lines, ["one", "two"])
