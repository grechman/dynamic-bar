import importlib.util
import json
import os
import tempfile
import time
import unittest
from unittest import mock

ROOT = tempfile.mkdtemp(prefix="island-usage-")
os.environ["ISLAND_DIR"] = ROOT
os.environ["ISLAND_CONFIG"] = f"{ROOT}/island.json"
os.environ["XDG_STATE_HOME"] = f"{ROOT}/state"
SPEC = importlib.util.spec_from_file_location(
    "usage",
    os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "usage.py"
    ),
)
usage = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(usage)


def fake_http(responses):
    def call(url, data=None, headers=None, method=None, timeout=15):
        for needle, payload in responses:
            if needle in url:
                if isinstance(payload, Exception):
                    raise payload
                return payload
        raise AssertionError(f"unexpected url {url}")

    return call


class Parsers(unittest.TestCase):
    def test_claude_windows_and_plan(self):
        creds = {
            "claudeAiOauth": {
                "accessToken": "t",
                "expiresAt": (time.time() + 3600) * 1000,
                "rateLimitTier": "default_claude_max_20x",
            }
        }
        payload = {
            "five_hour": {"utilization": 31.0, "resets_at": "2026-08-28T20:00:00Z"},
            "seven_day": {"utilization": 73.0, "resets_at": "2026-08-31T10:00:00Z"},
            "limits": [
                {
                    "kind": "weekly_scoped",
                    "percent": 70,
                    "resets_at": "2026-08-31T10:00:00Z",
                    "scope": {"model": {"display_name": "Fable"}},
                }
            ],
        }
        with (
            mock.patch.object(usage, "read_json", return_value=creds),
            mock.patch.object(
                usage, "http_json", fake_http([("oauth/usage", payload)])
            ),
        ):
            out = usage.fetch_claude({})
        self.assertEqual(out["plan"], "Max 20x")
        self.assertEqual(
            [(w["tag"], w["pct"]) for w in out["windows"]],
            [("5h", 31), ("wk", 73), ("fb", 70)],
        )
        self.assertAlmostEqual(out["windows"][0]["reset"], 1787947200, delta=1)

    def claude_fixture(self, oauth):
        home = tempfile.mkdtemp(prefix="claude-cfg-")
        with open(f"{home}/.credentials.json", "w") as handle:
            json.dump({"claudeAiOauth": oauth, "keep": True}, handle)
        return home

    def expired_oauth(self):
        return {
            "accessToken": "old",
            "refreshToken": "r1",
            "expiresAt": (time.time() - 10) * 1000,
            "subscriptionType": "max",
        }

    def test_claude_running_cli_blocks_refresh(self):
        home = self.claude_fixture(self.expired_oauth())
        with (
            mock.patch.object(usage, "CLAUDE_DIR", home),
            mock.patch.object(usage, "claude_cli_running", return_value=True),
            mock.patch.object(
                usage, "http_json", side_effect=AssertionError("no network")
            ),
        ):
            with self.assertRaises(usage.Skip):
                usage.fetch_claude({})

    def test_claude_refresh_persists_rotated_tokens(self):
        home = self.claude_fixture(self.expired_oauth())
        grant = {"access_token": "new", "refresh_token": "r2", "expires_in": 3600}
        payload = {
            "five_hour": {"utilization": 10.0, "resets_at": "2026-08-31T10:00:00Z"}
        }
        entry = {}
        with (
            mock.patch.object(usage, "CLAUDE_DIR", home),
            mock.patch.object(usage, "claude_cli_running", return_value=False),
            mock.patch.object(
                usage,
                "http_json",
                fake_http([("oauth/token", grant), ("oauth/usage", payload)]),
            ),
        ):
            out = usage.fetch_claude(entry)
        path = f"{home}/.credentials.json"
        with open(path) as handle:
            saved = json.load(handle)
        self.assertEqual(saved["claudeAiOauth"]["accessToken"], "new")
        self.assertEqual(saved["claudeAiOauth"]["refreshToken"], "r2")
        self.assertTrue(saved["keep"])
        self.assertGreater(saved["claudeAiOauth"]["expiresAt"], time.time() * 1000)
        self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)
        self.assertEqual(out["plan"], "Max")
        self.assertEqual(out["windows"][0]["pct"], 10)
        self.assertNotIn("auth_stamp", entry)

    def refresh_attempt(self, home, grant, entry=None):
        with (
            mock.patch.object(usage, "CLAUDE_DIR", home),
            mock.patch.object(usage, "claude_cli_running", return_value=False),
            mock.patch.object(usage, "http_json", fake_http([("oauth/token", grant)])),
        ):
            usage.fetch_claude({} if entry is None else entry)

    def saved_oauth(self, home):
        with open(f"{home}/.credentials.json") as handle:
            return json.load(handle)["claudeAiOauth"]

    def test_claude_refresh_aborts_when_file_changes(self):
        home = self.claude_fixture(self.expired_oauth())
        path = f"{home}/.credentials.json"

        def rewrite(url, data=None, headers=None, method=None, timeout=15):
            fresh = dict(self.expired_oauth(), accessToken="cli", refreshToken="r9")
            with open(path, "w") as handle:
                json.dump({"claudeAiOauth": fresh}, handle)
            return {"access_token": "new", "refresh_token": "r2", "expires_in": 3600}

        with (
            mock.patch.object(usage, "CLAUDE_DIR", home),
            mock.patch.object(usage, "claude_cli_running", return_value=False),
            mock.patch.object(usage, "http_json", rewrite),
        ):
            with self.assertRaises(usage.Skip):
                usage.fetch_claude({})
        self.assertEqual(self.saved_oauth(home)["accessToken"], "cli")
        self.assertEqual(self.saved_oauth(home)["refreshToken"], "r9")
        self.assertEqual(
            [f for f in os.listdir(home) if f.endswith(".tmp")], []
        )

    def test_claude_refresh_rejects_bad_expiry(self):
        for bad in (float("inf"), float("nan"), -5, 0, 10**12, "3600", True, None):
            home = self.claude_fixture(self.expired_oauth())
            grant = {"access_token": "new", "refresh_token": "r2", "expires_in": bad}
            with self.assertRaises(usage.Skip):
                self.refresh_attempt(home, grant)
            self.assertEqual(self.saved_oauth(home)["accessToken"], "old")

    def test_claude_refresh_rejects_bad_tokens(self):
        for bad in ("x" * 5000, "a b", "a\n", "", 7, "\x00"):
            home = self.claude_fixture(self.expired_oauth())
            grant = {"access_token": bad, "refresh_token": "r2", "expires_in": 3600}
            with self.assertRaises(usage.Skip):
                self.refresh_attempt(home, grant)
            self.assertEqual(self.saved_oauth(home)["accessToken"], "old")
        home = self.claude_fixture(self.expired_oauth())
        grant = {"access_token": "new", "refresh_token": "r 2", "expires_in": 3600}
        with self.assertRaises(usage.Skip):
            self.refresh_attempt(home, grant)
        self.assertEqual(self.saved_oauth(home)["refreshToken"], "r1")

    def test_claude_dead_refresh_latches_offline(self):
        home = self.claude_fixture(self.expired_oauth())
        entry = {}
        with (
            mock.patch.object(usage, "CLAUDE_DIR", home),
            mock.patch.object(usage, "claude_cli_running", return_value=False),
            mock.patch.object(
                usage, "http_json", fake_http([("oauth/token", usage.HttpError(400))])
            ),
        ):
            with self.assertRaises(usage.Skip):
                usage.fetch_claude(entry)
        self.assertIn("auth_stamp", entry)
        with (
            mock.patch.object(usage, "CLAUDE_DIR", home),
            mock.patch.object(
                usage, "http_json", side_effect=AssertionError("no network")
            ),
        ):
            with self.assertRaises(usage.Skip):
                usage.fetch_claude(entry)

    def test_claude_refresh_ratelimit_backs_off(self):
        home = self.claude_fixture(self.expired_oauth())
        entry = {}
        with (
            mock.patch.object(usage, "CLAUDE_DIR", home),
            mock.patch.object(usage, "claude_cli_running", return_value=False),
            mock.patch.object(
                usage,
                "http_json",
                fake_http([("oauth/token", usage.HttpError(429, 60))]),
            ),
        ):
            with self.assertRaises(usage.HttpError):
                usage.fetch_claude(entry)
        self.assertNotIn("auth_stamp", entry)

    def test_gemini_groups_buckets(self):
        payload = {
            "buckets": [
                {
                    "modelId": "gemini-2.5-pro",
                    "remainingFraction": 0.4,
                    "resetTime": "2026-08-29T00:00:00Z",
                },
                {
                    "modelId": "gemini-2.5-pro-preview",
                    "remainingFraction": 0.9,
                    "resetTime": "2026-08-29T00:00:00Z",
                },
                {
                    "modelId": "gemini-2.5-flash",
                    "remainingFraction": 0.75,
                    "resetTime": "2026-08-29T00:00:00Z",
                },
            ]
        }
        with (
            mock.patch.object(usage, "gemini_token", return_value="tok"),
            mock.patch.object(
                usage,
                "http_json",
                fake_http(
                    [
                        (
                            "loadCodeAssist",
                            {
                                "cloudaicompanionProject": "p",
                                "currentTier": {"id": "standard-tier"},
                            },
                        ),
                        ("retrieveUserQuota", payload),
                    ]
                ),
            ),
        ):
            out = usage.fetch_gemini()
        self.assertEqual(
            [(w["tag"], w["pct"]) for w in out["windows"]], [("pro", 60), ("fl", 25)]
        )
        self.assertEqual(out["plan"], "standard-tier")

    def test_kimi_windows(self):
        payload = {
            "usage": {
                "limit": "1000",
                "used": "250",
                "resetTime": "2026-09-01T00:00:00Z",
            },
            "limits": [
                {
                    "window": {"duration": 5, "timeUnit": "TIME_UNIT_HOUR"},
                    "detail": {
                        "limit": "200",
                        "remaining": "50",
                        "resetTime": "2026-08-28T22:00:00Z",
                    },
                }
            ],
        }
        with (
            mock.patch.object(usage, "kimi_token", return_value="tok"),
            mock.patch.object(usage, "http_json", fake_http([("usages", payload)])),
        ):
            out = usage.fetch_kimi()
        self.assertEqual(
            [(w["tag"], w["pct"]) for w in out["windows"]], [("5h", 75), ("wk", 25)]
        )

    def test_zai_limits(self):
        payload = {
            "data": {
                "planName": "Pro",
                "limits": [
                    {
                        "type": "TOKENS_LIMIT",
                        "unit": "HOUR",
                        "number": 5,
                        "percentage": 42,
                        "nextResetTime": 1788300000000,
                    },
                    {
                        "type": "TOKENS_LIMIT",
                        "unit": "DAY",
                        "number": 7,
                        "usage": 300,
                        "total": 1000,
                        "nextResetTime": 1788600000000,
                    },
                    {"type": "TIME_LIMIT", "percentage": 5},
                ],
            }
        }
        with (
            mock.patch.object(
                usage, "zai_credential", return_value=("k", usage.ZAI_GLOBAL)
            ),
            mock.patch.object(
                usage, "http_json", fake_http([("quota/limit", payload)])
            ),
        ):
            out = usage.fetch_zai()
        self.assertEqual(out["plan"], "Pro")
        self.assertEqual(
            [(w["tag"], w["pct"]) for w in out["windows"]],
            [("5h", 42), ("wk", 30), ("mcp", 5)],
        )
        self.assertEqual(out["windows"][0]["reset"], 1788300000)

    def test_grok_percent_or_ratio(self):
        payload = {
            "config": {
                "onDemandCap": {"val": 200},
                "onDemandUsed": {"val": 50},
                "currentPeriod": {"end": "2026-09-05T00:00:00Z"},
                "subscriptionTier": "SUPER_GROK",
            }
        }
        with (
            mock.patch.object(usage, "grok_credential", return_value="tok"),
            mock.patch.object(
                usage,
                "http_json",
                fake_http(
                    [
                        ("billing", payload),
                        ("settings", {"subscription_tier_display": "SuperGrok"}),
                    ]
                ),
            ),
        ):
            out = usage.fetch_grok()
        self.assertEqual(out["windows"][0]["pct"], 25)
        self.assertEqual(out["plan"], "SuperGrok")

    def test_copilot_quota(self):
        payload = {
            "copilot_plan": "individual",
            "quota_reset_date": "2026-09-01",
            "quota_snapshots": {
                "premium_interactions": {"percent_remaining": 12.5, "unlimited": False},
                "chat": {"unlimited": True},
            },
        }
        with (
            mock.patch.object(usage, "copilot_token", return_value="tok"),
            mock.patch.object(
                usage, "http_json", fake_http([("copilot_internal", payload)])
            ),
        ):
            out = usage.fetch_copilot()
        self.assertEqual([(w["tag"], w["pct"]) for w in out["windows"]], [("pr", 88)])
        self.assertEqual(out["plan"], "individual")

    def test_minimax_remains_anywhere(self):
        payload = {
            "data": {
                "model_remains": [
                    {
                        "model_name": "M2",
                        "current_interval_remaining_percent": 80.0,
                        "end_time": 1788300000000,
                        "current_weekly_remaining_percent": 55.5,
                        "weekly_end_time": 1788600000000,
                    }
                ]
            }
        }
        with (
            mock.patch.dict(os.environ, {"MINIMAX_API_KEY": "k"}),
            mock.patch.object(usage, "http_json", fake_http([("remains", payload)])),
        ):
            out = usage.fetch_minimax()
        self.assertEqual(
            [(w["tag"], w["pct"]) for w in out["windows"]], [("5h", 20), ("wk", 44)]
        )

    def test_omarchy_records_are_ingested(self):
        directory = f"{ROOT}/state/omarchy/agents/usage"
        os.makedirs(directory, exist_ok=True)
        record = {
            "id": "fireworks",
            "name": "Fireworks",
            "tierLabel": "Prepaid",
            "updatedAt": "2026-08-28T10:00:00+00:00",
            "limits": [
                {
                    "label": "Weekly (7-day)",
                    "percent": 0.4,
                    "resetsAt": "2026-09-01T00:00:00+00:00",
                }
            ],
        }
        with open(f"{directory}/fireworks.json", "w") as handle:
            json.dump(record, handle)
        out = usage.omarchy_records({"claude"})
        self.assertEqual(out[0]["id"], "fireworks")
        self.assertEqual(
            [(w["tag"], w["pct"]) for w in out[0]["windows"]], [("wk", 40)]
        )
        self.assertEqual(usage.omarchy_records({"fireworks"}), [])


class Collect(unittest.TestCase):
    def setUp(self):
        for name in ("usage.json", "usage.log"):
            try:
                os.remove(f"{ROOT}/{name}")
            except OSError:
                pass

    def test_rate_limit_honours_retry_after_and_keeps_windows(self):
        first = {
            "plan": "Max",
            "windows": [
                usage.window("claude:5h", "5h", "claude 5h", 40, time.time() + 3600)
            ],
        }
        calls = []

        def fetch(entry):
            calls.append(1)
            if len(calls) == 1:
                return first
            raise usage.HttpError(429, retry_after=900, body="slow down")

        fake = [("claude", "Claude", lambda: True, fetch)]
        with mock.patch.object(usage, "PROVIDERS", fake):
            usage.collect()
            usage.collect(force=True)
            payload = usage.collect()
        provider = payload["providers"][0]
        self.assertEqual(provider["windows"][0]["pct"], 40)
        self.assertIn("HTTP 429", provider["error"])
        self.assertIn("retry in 15 min", provider["error"])
        self.assertEqual(len(calls), 2)

    def test_expired_windows_are_dropped(self):
        old = {
            "plan": "",
            "windows": [
                usage.window("codex:5h", "5h", "codex 5h", 90, time.time() - 600),
                usage.window("codex:wk", "wk", "codex weekly", 10, time.time() + 600),
            ],
        }
        fake = [("codex", "Codex", lambda: True, lambda entry: old)]
        with mock.patch.object(usage, "PROVIDERS", fake):
            payload = usage.collect()
        self.assertEqual([w["tag"] for w in payload["providers"][0]["windows"]], ["wk"])

    def test_reset_event_posted_when_window_rolls(self):
        stamps = [time.time() + 100, time.time() + 90000]
        results = [
            {
                "plan": "",
                "windows": [
                    usage.window("claude:5h", "5h", "claude 5h", 60, stamps[0])
                ],
            },
            {
                "plan": "",
                "windows": [usage.window("claude:5h", "5h", "claude 5h", 2, stamps[1])],
            },
        ]
        fake = [("claude", "Claude", lambda: True, lambda entry: results.pop(0))]
        with mock.patch.object(usage, "PROVIDERS", fake):
            usage.collect()
            usage.collect(force=True)
        events = os.listdir(f"{ROOT}/events")
        self.assertEqual(events, ["reset-claude-5h.json"])


if __name__ == "__main__":
    unittest.main()
