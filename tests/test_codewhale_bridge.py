import tempfile
import unittest
from pathlib import Path

from codewhale_bridge import SessionRegistry, WorkspaceRegistry


class WorkspaceRegistryTests(unittest.TestCase):
    def test_create_workspace_under_desktop(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            desktop = root / "Desktop"
            state = root / "state"
            registry = WorkspaceRegistry(desktop, state)

            workspace = registry.create_workspace("Мой проект")

            self.assertEqual(workspace["name"], "Мой проект")
            self.assertTrue(Path(workspace["path"]).exists())
            self.assertTrue(Path(workspace["path"]).is_dir())
            self.assertEqual(Path(workspace["path"]).parent, desktop)
            self.assertEqual(workspace["status"], "available")
            self.assertEqual(len(registry.list_workspaces()), 1)

    def test_attach_rejects_path_outside_desktop(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            desktop = root / "Desktop"
            outside = root / "Outside"
            outside.mkdir(parents=True)
            registry = WorkspaceRegistry(desktop, root / "state")

            with self.assertRaises(ValueError):
                registry.attach_workspace("Внешний", outside)

    def test_registry_persists_workspaces(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            desktop = root / "Desktop"
            state = root / "state"
            first = WorkspaceRegistry(desktop, state)
            created = first.create_workspace("Persisted")

            second = WorkspaceRegistry(desktop, state)
            loaded = second.list_workspaces()

            self.assertEqual(len(loaded), 1)
            self.assertEqual(loaded[0]["id"], created["id"])
            self.assertEqual(loaded[0]["name"], "Persisted")


class SessionRegistryTests(unittest.TestCase):
    def test_create_session_persists_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp) / "state"
            registry = SessionRegistry(state)

            session = registry.create_session("weather", "Первый чат")

            self.assertEqual(session["workspace_id"], "weather")
            self.assertEqual(session["title"], "Первый чат")
            self.assertEqual(session["status"], "idle")
            self.assertEqual(len(registry.list_sessions("weather")), 1)

            second = SessionRegistry(state)
            loaded = second.get_session("weather", session["id"])
            self.assertEqual(loaded["id"], session["id"])
            self.assertEqual(loaded["title"], "Первый чат")

    def test_session_events_are_replayed_in_order(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            registry = SessionRegistry(Path(tmp) / "state")
            session = registry.create_session("weather", "History")

            registry.append_event(
                "weather",
                session["id"],
                {"type": "user_message", "text": "Привет"},
            )
            registry.append_event(
                "weather",
                session["id"],
                {"type": "assistant_delta", "text": "Готов"},
            )

            events = registry.load_events("weather", session["id"])

            self.assertEqual([event["seq"] for event in events], [1, 2])
            self.assertEqual(events[0]["text"], "Привет")
            self.assertEqual(events[1]["text"], "Готов")

    def test_update_session_status_survives_restart(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp) / "state"
            registry = SessionRegistry(state)
            session = registry.create_session("weather", "Worker")

            registry.update_session(
                "weather",
                session["id"],
                status="running",
                worker_pid=1234,
            )

            loaded = SessionRegistry(state).get_session("weather", session["id"])
            self.assertEqual(loaded["status"], "running")
            self.assertEqual(loaded["worker_pid"], 1234)


if __name__ == "__main__":
    unittest.main()
