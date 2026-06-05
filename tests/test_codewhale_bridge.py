import asyncio
import json
import base64
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest.mock import patch

from codewhale_bridge import (
    CodeWhaleBridge,
    CodeWhaleExecClient,
    CodeWhaleRuntimeClient,
    CodeWhaleWorkerManager,
    SessionRegistry,
    WorkspaceRegistry,
    _background_creation_flags,
    _is_tunnel_control_message,
    _run_tunnel_once,
    _parse_tunnel,
    _resolve_codewhale_cmd,
    _tunnel_registration_message,
)
from agent_policy import build_agent_run_policy, build_user_access, sign_policy_ticket


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


class CodeWhaleCommandTests(unittest.TestCase):
    def test_resolve_codewhale_cmd_preserves_explicit_path(self) -> None:
        self.assertEqual(
            _resolve_codewhale_cmd(r"C:\Tools\codewhale.cmd"),
            r"C:\Tools\codewhale.cmd",
        )


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

    def test_update_session_settings_survives_restart(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp) / "state"
            registry = SessionRegistry(state)
            session = registry.create_session("weather", "Modes")

            registry.update_session(
                "weather",
                session["id"],
                provider="deepseek",
                model="deepseek-v4-flash",
                approval_policy="never",
                sandbox_mode="workspace-write",
                auto_mode=True,
            )

            loaded = SessionRegistry(state).get_session("weather", session["id"])
            self.assertEqual(loaded["provider"], "deepseek")
            self.assertEqual(loaded["model"], "deepseek-v4-flash")
            self.assertEqual(loaded["approval_policy"], "never")
            self.assertEqual(loaded["sandbox_mode"], "workspace-write")
            self.assertTrue(loaded["auto_mode"])

    def test_create_session_persists_task_card_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp) / "state"
            registry = SessionRegistry(state)

            session = registry.create_session(
                "weather",
                "Агент",
                task_card={
                    "task_id": "task-1",
                    "agent_session_id": "agent-session-1",
                    "actor_profile": "Nikita",
                    "actor_phone": "+79679812438",
                    "api_url": "https://api.example.test",
                    "policy_ticket": "ticket-1",
                    "task_type": "feature",
                    "mode": "executor",
                },
            )

            loaded = SessionRegistry(state).get_session("weather", session["id"])
            self.assertEqual(loaded["task_card"]["task_id"], "task-1")
            self.assertEqual(loaded["task_card"]["policy_ticket"], "ticket-1")


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
            command = popen.call_args.args[0]
            self.assertIn("serve", command)
            self.assertIn("--http", command)
            self.assertIn("--host", command)
            self.assertIn("127.0.0.1", command)
            self.assertIn("--port", command)
            self.assertIn("43101", command)
            self.assertIn("--insecure", command)
            self.assertEqual(
                popen.call_args.kwargs["creationflags"],
                _background_creation_flags(),
            )

    def test_start_worker_injects_task_card_cli_environment(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace = root / "Desktop" / "Weather"
            workspace.mkdir(parents=True)
            registry = SessionRegistry(root / "state")
            session = registry.create_session(
                "weather",
                "Worker",
                task_card={
                    "task_id": "task-1",
                    "agent_session_id": "agent-session-1",
                    "actor_profile": "Nikita",
                    "actor_phone": "+79679812438",
                    "api_url": "https://api.example.test",
                    "policy_ticket": "ticket-1",
                    "task_type": "feature",
                    "mode": "executor",
                },
            )
            process = _FakeProcess()

            with patch("codewhale_bridge.subprocess.Popen", return_value=process) as popen:
                manager = CodeWhaleWorkerManager(registry, root / "state")
                manager.start_worker("weather", session["id"], workspace, port=43101)

            env = popen.call_args.kwargs["env"]
            self.assertEqual(env["FAMILY_TASK_CARD_TASK_ID"], "task-1")
            self.assertEqual(env["FAMILY_TASK_CARD_TICKET"], "ticket-1")
            self.assertEqual(env["FAMILY_TASK_CARD_WORKSPACE_PATH"], str(workspace))
            self.assertIn(str(workspace / ".family-task-card"), env["PATH"])
            self.assertTrue((workspace / ".family-task-card" / "family-task-card.cmd").exists())

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

    def test_kill_worker_after_restart_kills_persisted_pid_and_port_matches(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            registry = SessionRegistry(root / "state")
            session = registry.create_session("weather", "Worker")
            registry.update_session(
                "weather",
                session["id"],
                status="running",
                worker_pid=12345,
                worker_port=43116,
            )
            manager = CodeWhaleWorkerManager(registry, root / "state")

            with (
                patch.object(manager, "_kill_pid_tree") as kill_pid_tree,
                patch.object(
                    manager,
                    "_find_codewhale_process_ids",
                    return_value=[22222, 33333],
                ) as find_processes,
            ):
                killed = manager.kill_worker("weather", session["id"])

            find_processes.assert_called_once_with(["serve", "--port", "43116"])
            killed_pids = [call.args[0] for call in kill_pid_tree.call_args_list]
            self.assertEqual(killed_pids, [12345, 22222, 33333])
            self.assertEqual(killed["status"], "killed")
            self.assertIsNone(killed["worker_pid"])


class CodeWhaleBridgeTests(unittest.TestCase):
    def test_handle_workspace_create_returns_workspace(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bridge = CodeWhaleBridge(root / "Desktop", root / "state")

            reply = bridge.handle_message({"type": "workspace_create", "name": "Demo"})

            self.assertEqual(reply["type"], "workspace")
            self.assertEqual(reply["workspace"]["name"], "Demo")
            self.assertTrue(Path(reply["workspace"]["path"]).exists())

    def test_secure_bridge_requires_policy_ticket_for_workspace_commands(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bridge = CodeWhaleBridge(
                root / "Desktop",
                root / "state",
                require_policy_ticket=True,
                policy_ticket_secret="secret",
            )

            reply = bridge.handle_message({"type": "workspace_list"})

            self.assertEqual(reply["type"], "error")
            self.assertIn("Нет прав", reply["error"])

    def test_secure_bridge_accepts_signed_ticket_for_allowed_workspace_command(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bridge = CodeWhaleBridge(
                root / "Desktop",
                root / "state",
                require_policy_ticket=True,
                policy_ticket_secret="secret",
            )
            access = build_user_access(
                "+7 967 981-24-38",
                profile_key="nikita",
            )
            policy = build_agent_run_policy(
                access,
                task_type="feature",
                requested_mode="executor",
                workspace_id="weather",
                task_id="task-1",
            )
            ticket = sign_policy_ticket(policy, secret="secret")

            reply = bridge.handle_message(
                {"type": "workspace_list", "policy_ticket": ticket}
            )

            self.assertEqual(reply["type"], "workspace_list")

    def test_secure_bridge_rejects_command_not_allowed_by_ticket(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bridge = CodeWhaleBridge(
                root / "Desktop",
                root / "state",
                require_policy_ticket=True,
                policy_ticket_secret="secret",
            )
            access = build_user_access(
                "+7 900 000-00-00",
                profile_key="observer",
                roles=["workspace_user"],
                capabilities=["messenger.use", "workspaces.view"],
            )
            policy = {
                **build_agent_run_policy(
                    access,
                    task_type="feature",
                    requested_mode="commentator",
                    workspace_id="weather",
                    task_id="task-1",
                ),
                "allowed": True,
                "allowed_commands": ["workspace_list"],
            }
            ticket = sign_policy_ticket(policy, secret="secret")

            reply = bridge.handle_message(
                {"type": "session_create", "workspace_id": "weather", "policy_ticket": ticket}
            )

            self.assertEqual(reply["type"], "error")
            self.assertIn("Нет прав", reply["error"])

    def test_handle_codewhale_command_list_includes_skills(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bridge = CodeWhaleBridge(root / "Desktop", root / "state")

            reply = bridge.handle_message({"type": "codewhale_command_list"})

            self.assertEqual(reply["type"], "codewhale_command_list")
            values = {item["value"] for item in reply["commands"]}
            self.assertIn("/help", values)
            self.assertIn("/skill", values)
            self.assertIn("/lang ru", values)
            self.assertIn("/model", values)
            self.assertIn("/mode agent", values)
            self.assertIn("/mode plan", values)
            self.assertIn("/mode yolo", values)
            self.assertIn("/skill delegate", values)
            self.assertIn("/skill v4-best-practices", values)
            self.assertIn("/skill documents", values)
            self.assertIn("/skill presentations", values)
            self.assertIn("/skill spreadsheets", values)

    def test_handle_workspace_folder_list_browses_desktop_folders(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            desktop = root / "Desktop"
            (desktop / "Weather").mkdir(parents=True)
            (desktop / "Notes.txt").write_text("skip", encoding="utf-8")
            bridge = CodeWhaleBridge(desktop, root / "state")

            reply = bridge.handle_message({"type": "workspace_folder_list"})

            self.assertEqual(reply["type"], "workspace_folder_list")
            self.assertEqual(reply["path"], str(desktop.resolve()))
            self.assertEqual(len(reply["folders"]), 1)
            self.assertEqual(reply["folders"][0]["name"], "Weather")
            self.assertEqual(
                reply["folders"][0]["path"],
                str((desktop / "Weather").resolve()),
            )

    def test_handle_workspace_folder_list_rejects_outside_desktop(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            desktop = root / "Desktop"
            outside = root / "Outside"
            outside.mkdir(parents=True)
            bridge = CodeWhaleBridge(desktop, root / "state")

            reply = bridge.handle_message(
                {"type": "workspace_folder_list", "path": str(outside)}
            )

            self.assertEqual(reply["type"], "error")
            self.assertIn("under desktop", reply["error"])

    def test_workspace_file_list_and_read_stay_inside_workspace(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bridge = CodeWhaleBridge(root / "Desktop", root / "state")
            workspace = bridge.handle_message(
                {"type": "workspace_create", "name": "Demo"}
            )["workspace"]
            file_path = Path(workspace["path"]) / "README.md"
            file_path.write_text("hello", encoding="utf-8")

            listed = bridge.handle_message(
                {"type": "workspace_file_list", "workspace_id": workspace["id"]}
            )
            content = bridge.handle_message(
                {
                    "type": "workspace_file_read",
                    "workspace_id": workspace["id"],
                    "path": "README.md",
                }
            )

            self.assertEqual(listed["type"], "workspace_file_list")
            self.assertEqual(listed["files"][0]["name"], "README.md")
            self.assertEqual(content["type"], "workspace_file_content")
            self.assertEqual(content["text"], "hello")
            self.assertEqual(content["data_base64"], base64.b64encode(b"hello").decode("ascii"))
            self.assertEqual(content["mime_type"], "text/markdown")

    def test_session_upload_file_saves_attachment_event(self) -> None:
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
                    "type": "session_upload_file",
                    "workspace_id": workspace["id"],
                    "session_id": session["id"],
                    "filename": "photo.png",
                    "mime_type": "image/png",
                    "data_base64": base64.b64encode(b"png").decode("ascii"),
                    "caption": "посмотри",
                }
            )

            self.assertEqual(reply["type"], "session_file_uploaded")
            self.assertTrue(reply["path"].startswith("vision/"))
            self.assertTrue((Path(workspace["path"]) / reply["path"]).exists())
            events = bridge.sessions.load_events(workspace["id"], session["id"])
            self.assertEqual(events[-1]["type"], "file_attachment")
            self.assertIn("посмотри", events[-1]["text"])

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

    def test_handle_session_create_accepts_task_card_metadata(self) -> None:
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
                    "title": "Агент по задаче",
                    "task_card": {
                        "task_id": "task-1",
                        "agent_session_id": "agent-session-1",
                        "policy_ticket": "ticket-1",
                        "actor_profile": "Nikita",
                        "task_type": "feature",
                        "mode": "executor",
                    },
                }
            )

            self.assertEqual(created["type"], "session")
            task_card = created["session"]["task_card"]
            self.assertEqual(task_card["task_id"], "task-1")
            self.assertEqual(task_card["agent_session_id"], "agent-session-1")
            self.assertEqual(task_card["workspace_id"], workspace["id"])

    def test_session_create_rejects_unknown_workspace(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bridge = CodeWhaleBridge(root / "Desktop", root / "state")

            reply = bridge.handle_message(
                {
                    "type": "session_create",
                    "workspace_id": "project-1",
                    "title": "Wrong workspace",
                }
            )

            self.assertEqual(reply["type"], "error")
            self.assertIn("workspace not found", reply["error"])
            self.assertEqual(bridge.sessions.list_sessions("project-1"), [])

    def test_handle_session_send_starts_runtime_task(self) -> None:
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
            bridge.sessions.update_session(
                workspace["id"],
                session["id"],
                status="running",
                worker_port=43101,
            )

            with patch.object(
                bridge.runtime,
                "create_task",
                return_value={"id": "task-1", "status": "queued"},
            ) as create_task:
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

            self.assertEqual(reply["type"], "session_task")
            self.assertEqual(reply["task_id"], "task-1")
            create_task.assert_called_once_with(43101, "Привет")
            self.assertEqual(opened["events"][0]["type"], "user_message")
            self.assertEqual(opened["events"][1]["type"], "runtime_task")

    def test_handle_session_send_starts_worker_when_needed(self) -> None:
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

            with (
                patch.object(
                    bridge.workers,
                    "start_worker",
                    return_value={
                        **session,
                        "status": "running",
                        "worker_port": 43101,
                    },
                ) as start_worker,
                patch.object(
                    bridge.runtime,
                    "create_task",
                    return_value={"id": "task-1", "status": "queued"},
                ),
            ):
                reply = bridge.handle_message(
                    {
                        "type": "session_send",
                        "workspace_id": workspace["id"],
                        "session_id": session["id"],
                        "text": "Привет",
                    }
                )

            self.assertEqual(reply["type"], "session_task")
            start_worker.assert_called_once()

    def test_handle_session_task_poll_appends_completed_result(self) -> None:
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
            bridge.sessions.update_session(
                workspace["id"],
                session["id"],
                status="running",
                worker_port=43101,
            )

            with patch.object(
                bridge.runtime,
                "get_task",
                return_value={
                    "id": "task-1",
                    "status": "completed",
                    "result_summary": "Готово",
                },
            ):
                reply = bridge.handle_message(
                    {
                        "type": "session_task_poll",
                        "workspace_id": workspace["id"],
                        "session_id": session["id"],
                        "task_id": "task-1",
                    }
                )

            self.assertEqual(reply["type"], "session_task")
            self.assertEqual(reply["status"], "completed")
            events = bridge.sessions.load_events(workspace["id"], session["id"])
            self.assertEqual(events[-1]["type"], "assistant_delta")
            self.assertEqual(events[-1]["text"], "Готово")

    def test_stream_session_message_persists_codewhale_session(self) -> None:
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

            with patch.object(
                bridge.exec_client,
                "stream_prompt",
                return_value=iter(
                    [
                        {"type": "content", "content": "При"},
                        {"type": "content", "content": "вет"},
                        {"type": "session_capture", "content": "cw-session-1"},
                        {
                            "type": "metadata",
                            "meta": {
                                "session_id": "cw-session-1",
                                "status": "completed",
                            },
                        },
                        {"type": "done"},
                    ]
                ),
            ) as stream_prompt:
                replies = list(
                    bridge.stream_session_message(
                        {
                            "type": "session_send",
                            "workspace_id": workspace["id"],
                            "session_id": session["id"],
                            "text": "Привет",
                        }
                    )
                )

            stream_prompt.assert_called_once_with(
                Path(workspace["path"]),
                "Привет",
                session_id=None,
                provider="",
                model="",
                approval_policy="",
                sandbox_mode="",
                auto_mode=False,
                on_process_start=bridge._remember_exec_process,
                on_process_end=bridge._forget_exec_process,
                process_key=(workspace["id"], session["id"]),
            )
            self.assertEqual(
                [reply["type"] for reply in replies],
                [
                    "session_stream_started",
                    "assistant_delta",
                    "assistant_delta",
                    "session_process_event",
                    "session_stream_done",
                ],
            )
            self.assertEqual(replies[1]["text"], "При")
            self.assertEqual(replies[2]["text"], "вет")
            self.assertIn("status=completed", replies[3]["text"])

            updated = bridge.sessions.get_session(workspace["id"], session["id"])
            self.assertEqual(updated["runtime_session_id"], "cw-session-1")
            events = bridge.sessions.load_events(workspace["id"], session["id"])
            self.assertEqual(
                [event["type"] for event in events],
                ["user_message", "session_process_event", "assistant_delta"],
            )
            self.assertEqual(events[-1]["text"], "Привет")
            self.assertTrue(events[-1]["final"])

    def test_stream_session_message_reuses_codewhale_session(self) -> None:
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
            bridge.sessions.update_session(
                workspace["id"],
                session["id"],
                runtime_session_id="cw-session-1",
            )

            with patch.object(
                bridge.exec_client,
                "stream_prompt",
                return_value=iter([{"type": "content", "content": "OK"}, {"type": "done"}]),
            ) as stream_prompt:
                list(
                    bridge.stream_session_message(
                        {
                            "type": "session_send",
                            "workspace_id": workspace["id"],
                            "session_id": session["id"],
                            "text": "Продолжи",
                        }
                    )
                )

            self.assertEqual(stream_prompt.call_args.kwargs["session_id"], "cw-session-1")

    def test_stream_session_message_serializes_concurrent_sends_to_reuse_runtime_session(
        self,
    ) -> None:
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
            first_started = threading.Event()
            release_first = threading.Event()
            calls: list[tuple[str, str | None]] = []
            calls_lock = threading.Lock()
            errors: list[BaseException] = []

            def stream_prompt(path, prompt, **kwargs):
                del path
                with calls_lock:
                    calls.append((prompt, kwargs["session_id"]))
                if prompt == "/skill delegate":
                    first_started.set()
                    if not release_first.wait(timeout=5):
                        raise TimeoutError("first stream was not released")
                    yield {"type": "session_capture", "content": "cw-session-1"}
                    yield {
                        "type": "metadata",
                        "meta": {
                            "session_id": "cw-session-1",
                            "status": "completed",
                        },
                    }
                    yield {"type": "done"}
                    return
                yield {"type": "content", "content": "second"}
                yield {"type": "done"}

            def collect(text: str) -> None:
                try:
                    list(
                        bridge.stream_session_message(
                            {
                                "type": "session_send",
                                "workspace_id": workspace["id"],
                                "session_id": session["id"],
                                "text": text,
                            }
                        )
                    )
                except BaseException as exc:
                    errors.append(exc)

            with patch.object(bridge.exec_client, "stream_prompt", stream_prompt):
                first = threading.Thread(target=collect, args=("/skill delegate",))
                second = threading.Thread(
                    target=collect,
                    args=("/skill v4-best-practices",),
                )
                first.start()
                self.assertTrue(first_started.wait(timeout=5))
                second.start()
                time.sleep(0.1)
                release_first.set()
                first.join(timeout=5)
                second.join(timeout=5)

            self.assertFalse(first.is_alive())
            self.assertFalse(second.is_alive())
            self.assertEqual(errors, [])
            self.assertEqual(
                calls,
                [
                    ("/skill delegate", None),
                    ("/skill v4-best-practices", "cw-session-1"),
                ],
            )

    def test_stream_session_message_passes_saved_exec_settings(self) -> None:
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
            bridge.handle_message(
                {
                    "type": "session_update_settings",
                    "workspace_id": workspace["id"],
                    "session_id": session["id"],
                    "provider": "deepseek",
                    "model": "deepseek-v4-flash",
                    "approval_policy": "never",
                    "sandbox_mode": "workspace-write",
                    "auto_mode": True,
                }
            )

            with patch.object(
                bridge.exec_client,
                "stream_prompt",
                return_value=iter([{"type": "content", "content": "OK"}, {"type": "done"}]),
            ) as stream_prompt:
                list(
                    bridge.stream_session_message(
                        {
                            "type": "session_send",
                            "workspace_id": workspace["id"],
                            "session_id": session["id"],
                            "text": "Продолжи",
                        }
                    )
                )

            self.assertEqual(stream_prompt.call_args.kwargs["provider"], "deepseek")
            self.assertEqual(stream_prompt.call_args.kwargs["model"], "deepseek-v4-flash")
            self.assertEqual(stream_prompt.call_args.kwargs["approval_policy"], "never")
            self.assertEqual(stream_prompt.call_args.kwargs["sandbox_mode"], "workspace-write")
            self.assertTrue(stream_prompt.call_args.kwargs["auto_mode"])

    def test_stream_session_message_marks_session_idle_after_exec_error(self) -> None:
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

            def broken_stream(*args, **kwargs):
                kwargs["on_process_start"](kwargs["process_key"], _FakeProcess())
                yield {"type": "content", "content": "partial"}
                raise RuntimeError("exec failed")

            with patch.object(bridge.exec_client, "stream_prompt", broken_stream):
                stream = bridge.stream_session_message(
                    {
                        "type": "session_send",
                        "workspace_id": workspace["id"],
                        "session_id": session["id"],
                        "text": "Привет",
                    }
                )
                self.assertEqual(next(stream)["type"], "session_stream_started")
                self.assertEqual(next(stream)["type"], "assistant_delta")
                with self.assertRaises(RuntimeError):
                    next(stream)

            updated = bridge.sessions.get_session(workspace["id"], session["id"])
            self.assertEqual(updated["status"], "idle")
            self.assertIsNone(updated["active_pid"])

    def test_session_kill_clears_persisted_active_pid_after_bridge_restart(self) -> None:
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
            bridge.sessions.update_session(
                workspace["id"],
                session["id"],
                status="running",
                active_pid=12345,
            )

            with patch.object(bridge, "_kill_pid_tree") as kill_pid_tree:
                reply = bridge.handle_message(
                    {
                        "type": "session_kill",
                        "workspace_id": workspace["id"],
                        "session_id": session["id"],
                    }
                )

            kill_pid_tree.assert_called_once_with(12345, force=True)
            self.assertEqual(reply["session"]["status"], "killed")
            self.assertIsNone(reply["session"]["active_pid"])

    def test_session_kill_after_restart_kills_execs_by_runtime_session_id(self) -> None:
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
            bridge.sessions.update_session(
                workspace["id"],
                session["id"],
                status="running",
                runtime_session_id="cw-session-1",
                active_pid=None,
            )

            with (
                patch.object(bridge, "_kill_pid_tree") as kill_pid_tree,
                patch.object(
                    bridge,
                    "_find_codewhale_process_ids",
                    return_value=[44444, 55555],
                ) as find_processes,
            ):
                reply = bridge.handle_message(
                    {
                        "type": "session_kill",
                        "workspace_id": workspace["id"],
                        "session_id": session["id"],
                    }
                )

            find_processes.assert_called_once_with(["exec", "cw-session-1"])
            killed_pids = [call.args[0] for call in kill_pid_tree.call_args_list]
            self.assertEqual(killed_pids, [44444, 55555])
            self.assertEqual(reply["session"]["status"], "killed")
            self.assertIsNone(reply["session"]["runtime_session_id"])

    def test_stream_session_message_rejects_killed_session_until_started(self) -> None:
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
            bridge.sessions.update_session(
                workspace["id"],
                session["id"],
                status="killed",
                runtime_session_id="cw-session-1",
            )

            with self.assertRaisesRegex(ValueError, "start a new run"):
                list(
                    bridge.stream_session_message(
                        {
                            "type": "session_send",
                            "workspace_id": workspace["id"],
                            "session_id": session["id"],
                            "text": "ау",
                        }
                    )
                )

    def test_allocate_port_skips_ports_recorded_by_existing_sessions(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bridge = CodeWhaleBridge(root / "Desktop", root / "state")
            workspace = bridge.handle_message(
                {"type": "workspace_create", "name": "Demo"}
            )["workspace"]
            first = bridge.handle_message(
                {
                    "type": "session_create",
                    "workspace_id": workspace["id"],
                    "title": "First",
                }
            )["session"]
            second = bridge.handle_message(
                {
                    "type": "session_create",
                    "workspace_id": workspace["id"],
                    "title": "Second",
                }
            )["session"]
            bridge.sessions.update_session(
                workspace["id"],
                first["id"],
                worker_port=43101,
            )
            bridge.sessions.update_session(
                workspace["id"],
                second["id"],
                worker_port=43102,
            )

            with patch.object(bridge, "_is_port_available", return_value=True):
                self.assertEqual(bridge._allocate_port(), 43103)

    def test_handle_unknown_message_returns_error(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            bridge = CodeWhaleBridge(Path(tmp) / "Desktop", Path(tmp) / "state")

            reply = bridge.handle_message({"type": "missing"})

            self.assertEqual(reply["type"], "error")
            self.assertIn("unsupported", reply["error"])


class CodeWhaleBridgeCliTests(unittest.TestCase):
    def test_tunnel_registration_message_supports_new_and_legacy_channels(self) -> None:
        self.assertEqual(
            _tunnel_registration_message("codewhale", legacy=False),
            {"type": "codewhale_register", "project_id": "codewhale"},
        )
        self.assertEqual(
            _tunnel_registration_message("codewhale", legacy=True),
            {"type": "register", "project_id": "codewhale"},
        )

    def test_tunnel_control_messages_include_legacy_mobile_attach(self) -> None:
        self.assertTrue(_is_tunnel_control_message({"type": "codewhale_mobile_attached"}))
        self.assertTrue(_is_tunnel_control_message({"type": "mobile_attached"}))
        self.assertFalse(_is_tunnel_control_message({"type": "workspace_list"}))

    def test_parse_tunnel(self) -> None:
        self.assertEqual(_parse_tunnel("31.129.97.211:9877"), ("31.129.97.211", 9877))

    def test_parse_tunnel_rejects_invalid_value(self) -> None:
        with self.assertRaises(ValueError):
            _parse_tunnel("31.129.97.211")


class CodeWhaleBridgeTunnelClientTests(unittest.IsolatedAsyncioTestCase):
    async def test_tunnel_client_processes_large_session_upload_line(self) -> None:
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

            data = b"x" * (96 * 1024)
            payload = {
                "type": "session_upload_file",
                "workspace_id": workspace["id"],
                "session_id": session["id"],
                "filename": "large-photo.jpg",
                "mime_type": "image/jpeg",
                "data_base64": base64.b64encode(data).decode("ascii"),
                "caption": "проверь",
            }
            replies: list[dict[str, object]] = []

            async def handle_client(
                reader: asyncio.StreamReader,
                writer: asyncio.StreamWriter,
            ) -> None:
                await reader.readline()
                writer.write(json.dumps(payload).encode("utf-8") + b"\n")
                await writer.drain()
                reply_line = await asyncio.wait_for(reader.readline(), timeout=5)
                replies.append(json.loads(reply_line.decode("utf-8")))
                writer.close()
                await writer.wait_closed()

            server = await asyncio.start_server(
                handle_client,
                "127.0.0.1",
                0,
                limit=32 * 1024 * 1024,
            )
            port = server.sockets[0].getsockname()[1]
            try:
                await _run_tunnel_once(
                    bridge,
                    "127.0.0.1",
                    port,
                    "codewhale",
                    legacy=False,
                )
            finally:
                server.close()
                await server.wait_closed()

            self.assertEqual(replies[0]["type"], "session_file_uploaded")
            uploaded_path = str(replies[0]["path"])
            self.assertTrue(uploaded_path.startswith("vision/"))
            self.assertEqual((Path(workspace["path"]) / uploaded_path).read_bytes(), data)
            events = bridge.sessions.load_events(workspace["id"], session["id"])
            self.assertEqual(events[-1]["type"], "file_attachment")
            self.assertIn("проверь", events[-1]["text"])


class CodeWhaleRuntimeClientTests(unittest.TestCase):
    def test_create_task_posts_prompt_to_runtime_api(self) -> None:
        captured = {}

        def fake_urlopen(request, timeout=0):
            captured["url"] = request.full_url
            captured["method"] = request.get_method()
            captured["body"] = json.loads(request.data.decode("utf-8"))
            return _FakeHttpResponse(201, {"id": "task-1", "status": "queued"})

        client = CodeWhaleRuntimeClient(urlopen=fake_urlopen)

        task = client.create_task(43101, "Привет")

        self.assertEqual(task["id"], "task-1")
        self.assertEqual(captured["url"], "http://127.0.0.1:43101/v1/tasks")
        self.assertEqual(captured["method"], "POST")
        self.assertEqual(captured["body"]["prompt"], "Привет")

    def test_get_task_reads_runtime_task(self) -> None:
        def fake_urlopen(request, timeout=0):
            return _FakeHttpResponse(
                200,
                {"id": "task-1", "status": "completed", "result_summary": "OK"},
            )

        client = CodeWhaleRuntimeClient(urlopen=fake_urlopen)

        task = client.get_task(43101, "task-1")

        self.assertEqual(task["status"], "completed")
        self.assertEqual(task["result_summary"], "OK")


class CodeWhaleExecClientTests(unittest.TestCase):
    def test_parse_stream_json_lines_ignores_terminal_control_prefix(self) -> None:
        lines = [
            '\x1b]0;🐳 DeepSeek TUI\x07{"type":"content","content":"OK"}\n',
            '{"type":"session_capture","content":"session-1"}\n',
        ]

        parsed = list(CodeWhaleExecClient._parse_stream_json_lines(lines))

        self.assertEqual(parsed[0], {"type": "content", "content": "OK"})
        self.assertEqual(parsed[1]["content"], "session-1")

    def test_stream_prompt_starts_without_visible_console_window(self) -> None:
        process = _FakeProcess()
        process.stdout = iter(['{"type":"done"}\n'])
        process.returncode = 0
        captured = {}

        def fake_popen(command, **kwargs):
            captured["kwargs"] = kwargs
            return process

        client = CodeWhaleExecClient(codewhale_cmd="codewhale", popen=fake_popen)

        list(client.stream_prompt(Path("C:/work"), "Привет"))

        self.assertEqual(captured["kwargs"]["creationflags"], _background_creation_flags())

    def test_stream_prompt_adds_codewhale_mode_flags(self) -> None:
        process = _FakeProcess()
        process.stdout = iter(['{"type":"done"}\n'])
        process.returncode = 0
        captured = {}

        def fake_popen(command, **kwargs):
            captured["command"] = command
            return process

        client = CodeWhaleExecClient(codewhale_cmd="codewhale", popen=fake_popen)

        list(
            client.stream_prompt(
                Path("C:/work"),
                "Привет",
                provider="deepseek",
                model="deepseek-v4-flash",
                approval_policy="never",
                sandbox_mode="workspace-write",
                auto_mode=True,
            )
        )

        self.assertEqual(
            captured["command"],
            [
                "codewhale",
                "--provider",
                "deepseek",
                "--model",
                "deepseek-v4-flash",
                "--approval-policy",
                "never",
                "--sandbox-mode",
                "workspace-write",
                "exec",
                "--output-format",
                "stream-json",
                "--auto",
                "Привет",
            ],
        )


class _FakeHttpResponse:
    def __init__(self, status: int, payload: dict) -> None:
        self.status = status
        self._payload = payload

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        return None

    def read(self) -> bytes:
        return json.dumps(self._payload).encode("utf-8")


if __name__ == "__main__":
    unittest.main()
