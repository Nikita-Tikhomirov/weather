import json
import base64
import tempfile
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
    _parse_tunnel,
    _resolve_codewhale_cmd,
    _tunnel_registration_message,
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
