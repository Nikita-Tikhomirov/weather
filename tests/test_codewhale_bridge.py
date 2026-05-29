import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from codewhale_bridge import (
    CodeWhaleBridge,
    CodeWhaleWorkerManager,
    SessionRegistry,
    WorkspaceRegistry,
    _parse_tunnel,
)


class _FakeProcess:
    _next_pid = 1000

    def __init__(self) -> None:
        type(self)._next_pid += 1
        self.pid = type(self)._next_pid
        self.terminated = False
        self.killed = False
        self.returncode = None

    def poll(self) -> int | None:
        return self.returncode

    def terminate(self) -> None:
        self.terminated = True
        self.returncode = 0

    def kill(self) -> None:
        self.killed = True
        self.returncode = -9

    def wait(self, timeout: float | None = None) -> int:
        if self.returncode is None:
            raise TimeoutError("still running")
        return self.returncode


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


class CodeWhaleWorkerManagerTests(unittest.TestCase):
    def test_start_worker_marks_session_running(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "Desktop" / "Weather"
            workspace.mkdir(parents=True)
            registry = SessionRegistry(root / "state")
            session = registry.create_session("weather", "Worker")
            process = _FakeProcess()

            with patch("codewhale_bridge.subprocess.Popen", return_value=process) as popen:
                manager = CodeWhaleWorkerManager(registry, root / "state")
                started = manager.start_worker(
                    "weather",
                    session["id"],
                    workspace,
                    port=43101,
                )

            self.assertEqual(started["status"], "running")
            self.assertEqual(started["worker_pid"], process.pid)
            self.assertEqual(started["worker_port"], 43101)
            self.assertEqual(popen.call_args.kwargs["cwd"], str(workspace))
            self.assertIn("serve", popen.call_args.args[0])

    def test_kill_worker_only_kills_target_process(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "Desktop" / "Weather"
            workspace.mkdir(parents=True)
            registry = SessionRegistry(root / "state")
            first = registry.create_session("weather", "First")
            second = registry.create_session("weather", "Second")
            processes = [_FakeProcess(), _FakeProcess()]

            with (
                patch("codewhale_bridge.subprocess.Popen", side_effect=processes),
                patch("codewhale_bridge.subprocess.run"),
            ):
                manager = CodeWhaleWorkerManager(registry, root / "state")
                manager.start_worker("weather", first["id"], workspace, port=43101)
                manager.start_worker("weather", second["id"], workspace, port=43102)
                killed = manager.kill_worker("weather", first["id"])

            self.assertEqual(killed["status"], "killed")
            self.assertTrue(processes[0].killed)
            self.assertFalse(processes[1].killed)
            still_running = registry.get_session("weather", second["id"])
            self.assertEqual(still_running["status"], "running")


class CodeWhaleBridgeTests(unittest.TestCase):
    def test_handle_workspace_create_returns_workspace(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bridge = CodeWhaleBridge(root / "Desktop", root / "state")

            reply = bridge.handle_message({"type": "workspace_create", "name": "Demo"})

            self.assertEqual(reply["type"], "workspace")
            self.assertEqual(reply["workspace"]["name"], "Demo")
            self.assertTrue(Path(reply["workspace"]["path"]).exists())

    def test_handle_session_create_and_list(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bridge = CodeWhaleBridge(root / "Desktop", root / "state")
            workspace = bridge.handle_message(
                {"type": "workspace_create", "name": "Demo"}
            )["workspace"]

            created = bridge.handle_message(
                {
                    "type": "session_create",
                    "workspace_id": workspace["id"],
                    "title": "Чат",
                }
            )
            listed = bridge.handle_message(
                {"type": "session_list", "workspace_id": workspace["id"]}
            )

            self.assertEqual(created["type"], "session")
            self.assertEqual(created["session"]["title"], "Чат")
            self.assertEqual(len(listed["sessions"]), 1)

    def test_handle_session_send_appends_user_event(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bridge = CodeWhaleBridge(root / "Desktop", root / "state")
            workspace = bridge.handle_message(
                {"type": "workspace_create", "name": "Demo"}
            )["workspace"]
            session = bridge.handle_message(
                {
                    "type": "session_create",
                    "workspace_id": workspace["id"],
                    "title": "Чат",
                }
            )["session"]

            reply = bridge.handle_message(
                {
                    "type": "session_send",
                    "workspace_id": workspace["id"],
                    "session_id": session["id"],
                    "text": "Привет",
                }
            )
            opened = bridge.handle_message(
                {
                    "type": "session_open",
                    "workspace_id": workspace["id"],
                    "session_id": session["id"],
                }
            )

            self.assertEqual(reply["type"], "session_event")
            self.assertEqual(reply["event"]["type"], "user_message")
            self.assertEqual(opened["events"][-1]["text"], "Привет")

    def test_handle_unknown_message_returns_error(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            bridge = CodeWhaleBridge(Path(tmp) / "Desktop", Path(tmp) / "state")

            reply = bridge.handle_message({"type": "missing"})

            self.assertEqual(reply["type"], "error")
            self.assertIn("unsupported", reply["error"])


class CodeWhaleBridgeCliTests(unittest.TestCase):
    def test_parse_tunnel(self) -> None:
        self.assertEqual(_parse_tunnel("31.129.97.211:9877"), ("31.129.97.211", 9877))

    def test_parse_tunnel_rejects_invalid_value(self) -> None:
        with self.assertRaises(ValueError):
            _parse_tunnel("31.129.97.211")


if __name__ == "__main__":
    unittest.main()
