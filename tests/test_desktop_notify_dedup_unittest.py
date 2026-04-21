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

        with patch("notifier.desktop_notify", return_value=None):
            DesktopTodoApp._flush_sync_notify_events(self.app)

        self.assertEqual(len(self.app.logged_messages), 1)
        message = self.app.logged_messages[0]
        self.assertIn("nik: добавлена «про» (x2)", message)
        self.assertIn("nik: удалена «старое»", message)
        self.assertEqual(self.app._sync_notify_flush_after_id, None)
        self.assertEqual(self.app._pending_sync_notify_events, [])


if __name__ == "__main__":
    unittest.main()
