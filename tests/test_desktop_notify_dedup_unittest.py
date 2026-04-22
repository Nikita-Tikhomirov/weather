import unittest
from datetime import datetime
from unittest.mock import patch

from desktop_app import DesktopTodoApp


class _DummyDesktop:
    def __init__(self) -> None:
        self._sync_notify_cooldown_seconds = 120
        self._sync_notify_history = {}
        self._pending_sync_notify_events = []
        self._sync_notify_flush_after_id = None
        self._sync_notify_flush_delay_ms = 1
        self.logged_messages: list[str] = []
        self._after_callback = None
        self.cache_invalidations = 0
        self.personal_refreshes = 0
        self.family_refreshes = 0
        self.notify_calls = 0

    def _append_log(self, message: str) -> None:
        self.logged_messages.append(message)

    def after(self, _delay: int, callback):
        self._after_callback = callback
        return "timer-token"

    def _sync_event_key(self, event):
        return DesktopTodoApp._sync_event_key(self, event)

    def _prune_sync_notify_history(self, now: datetime):
        return DesktopTodoApp._prune_sync_notify_history(self, now)

    def _schedule_sync_notify_flush(self):
        return DesktopTodoApp._schedule_sync_notify_flush(self)

    def _flush_sync_notify_events(self):
        return DesktopTodoApp._flush_sync_notify_events(self)

    def get_person(self):
        return type("Person", (), {"key": "nik"})()

    def _invalidate_cache(self):
        self.cache_invalidations += 1

    def _refresh_personal_views(self):
        self.personal_refreshes += 1

    def refresh_family_tasks(self):
        self.family_refreshes += 1

    def _notify_sync_changes(self, _sync_result):
        self.notify_calls += 1


class DesktopSyncNotifyDedupTests(unittest.TestCase):
    def setUp(self) -> None:
        self.app = _DummyDesktop()

    def test_repeated_event_is_deduped_in_cooldown(self) -> None:
        event = {
            "event_id": "sync:nik:add:1",
            "kind": "add",
            "owner_key": "nik",
            "id": "1",
            "title": "про",
            "is_family": False,
        }

        DesktopTodoApp._notify_sync_changes(self.app, {"events": [event]})
        DesktopTodoApp._notify_sync_changes(self.app, {"events": [event]})

        self.assertEqual(len(self.app._pending_sync_notify_events), 1)

    def test_flush_aggregates_duplicates_into_single_line(self) -> None:
        now = datetime.now()
        self.app._pending_sync_notify_events = [
            {"event_key": "a", "line": "nik: добавлена «про»"},
            {"event_key": "b", "line": "nik: добавлена «про»"},
            {"event_key": "c", "line": "nik: удалена «старое»"},
        ]

        with patch("notifier.desktop_notify", return_value=None), patch(
            "notifier.push_by_visibility", return_value=None
        ), patch("notifier.push_to_family", return_value=None):
            DesktopTodoApp._flush_sync_notify_events(self.app)

        self.assertEqual(len(self.app.logged_messages), 1)
        message = self.app.logged_messages[0]
        self.assertIn("nik: добавлена «про» (x2)", message)
        self.assertIn("nik: удалена «старое»", message)
        self.assertEqual(self.app._sync_notify_flush_after_id, None)
        self.assertEqual(self.app._pending_sync_notify_events, [])

    def test_sync_refresh_updates_only_current_person_views(self) -> None:
        DesktopTodoApp._apply_sync_refresh(
            self.app,
            {
                "changed_profiles": ["nik"],
                "family_changed": False,
                "events": [],
            },
        )
        self.assertEqual(self.app.cache_invalidations, 1)
        self.assertEqual(self.app.personal_refreshes, 1)
        self.assertEqual(self.app.family_refreshes, 0)
        self.assertEqual(self.app.notify_calls, 1)

    def test_sync_refresh_skips_unrelated_personal_updates(self) -> None:
        DesktopTodoApp._apply_sync_refresh(
            self.app,
            {
                "changed_profiles": ["misha"],
                "family_changed": False,
                "events": [],
            },
        )
        self.assertEqual(self.app.cache_invalidations, 0)
        self.assertEqual(self.app.personal_refreshes, 0)
        self.assertEqual(self.app.family_refreshes, 0)
        self.assertEqual(self.app.notify_calls, 0)


if __name__ == "__main__":
    unittest.main()
