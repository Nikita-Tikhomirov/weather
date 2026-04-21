import unittest
import urllib.error
from pathlib import Path

import family_todo as ft


class SyncStabilityTests(unittest.TestCase):
    def test_desktop_startup_has_no_dangerous_misha_cleanup(self) -> None:
        source = Path("desktop_app.py").read_text(encoding="utf-8")
        self.assertNotIn('cleanup_misha_todos_from_date("2026-04-20")', source)

    def test_backend_pull_snapshot_uses_php_and_rewrite_fallback(self) -> None:
        original_backend_request = ft._backend_request
        calls: list[str] = []

        def fake_backend_request(method: str, path: str, payload=None, **_kwargs):
            calls.append(path)
            if "sync_pull.php" in path:
                return None
            return {"ok": True, "tasks": [], "family_tasks": []}

        ft._backend_request = fake_backend_request
        try:
            result = ft._backend_pull_snapshot()
        finally:
            ft._backend_request = original_backend_request

        self.assertEqual(calls[0].startswith("/sync_pull.php?"), True)
        self.assertEqual(calls[1].startswith("/sync/pull?"), True)
        self.assertIsInstance(result, dict)

    def test_backend_request_logs_url_errors(self) -> None:
        original_urlopen = ft.urllib.request.urlopen
        original_get_runtime = ft.get_sync_runtime
        original_log_exception = ft.log_exception
        captured: list[tuple[str, dict]] = []

        def fake_urlopen(*_args, **_kwargs):
            raise urllib.error.URLError("network down")

        def fake_get_runtime(default_source: str = "desktop"):
            return {
                "backend_url": "https://example.test",
                "backend_api_key": "",
                "backend_source": default_source,
            }

        def fake_log_exception(event: str, exc: Exception, **fields):
            captured.append((event, fields))

        ft.urllib.request.urlopen = fake_urlopen
        ft.get_sync_runtime = fake_get_runtime
        ft.log_exception = fake_log_exception
        try:
            result = ft._backend_request("GET", "/sync_pull.php")
        finally:
            ft.urllib.request.urlopen = original_urlopen
            ft.get_sync_runtime = original_get_runtime
            ft.log_exception = original_log_exception

        self.assertIsNone(result)
        self.assertTrue(captured)
        self.assertEqual(captured[0][0], "backend_request_failed")
        self.assertIn("https://example.test/sync_pull.php", captured[0][1].get("url", ""))

    def test_desktop_app_has_background_sync_poll(self) -> None:
        source = Path("desktop_app.py").read_text(encoding="utf-8")
        self.assertIn("_schedule_sync_poll(initial=True)", source)
        self.assertIn("ft.pull_backend_snapshot_to_local()", source)
        self.assertIn("self.refresh_all_views()", source)

    def test_sync_pull_uses_actor_filter_for_mobile(self) -> None:
        source = Path("backend_api/public/index.php").read_text(encoding="utf-8")
        self.assertIn("require_api_key($config);", source)
        self.assertIn("actor_profile", source)
        self.assertIn("changed_tasks_since_for_actor", source)


if __name__ == "__main__":
    unittest.main()
