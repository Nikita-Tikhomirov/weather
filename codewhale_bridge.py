from __future__ import annotations

import argparse
import asyncio
import json
import os
import re
import signal
import subprocess
import sys
import time
import urllib.request
import uuid
from pathlib import Path
from typing import Any


RECONNECT_DELAY_SECONDS = 5


def _now_ms() -> int:
    return int(time.time() * 1000)


def _safe_id(name: str) -> str:
    base = re.sub(r"[^a-z0-9]+", "-", name.strip().lower())
    base = base.strip("-")
    return base or f"workspace-{_now_ms()}"


def _safe_folder_name(name: str) -> str:
    cleaned = re.sub(r'[<>:"/\\|?*\x00-\x1f]', " ", name.strip())
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    if not cleaned:
        raise ValueError("workspace name is required")
    return cleaned


class WorkspaceRegistry:
    def __init__(self, desktop_root: Path, state_dir: Path) -> None:
        self.desktop_root = desktop_root.resolve()
        self.state_dir = state_dir.resolve()
        self.path = self.state_dir / "workspaces.json"
        self.desktop_root.mkdir(parents=True, exist_ok=True)
        self.state_dir.mkdir(parents=True, exist_ok=True)

    def list_workspaces(self) -> list[dict[str, Any]]:
        return [dict(item) for item in self._load()]

    def create_workspace(self, name: str) -> dict[str, Any]:
        folder_name = _safe_folder_name(name)
        folder = self._unique_folder(self.desktop_root / folder_name)
        folder.mkdir(parents=True, exist_ok=False)
        workspace = self._new_workspace(name=folder_name, folder=folder)
        items = self._load()
        items.append(workspace)
        self._save(items)
        return dict(workspace)

    def attach_workspace(self, name: str, folder: Path) -> dict[str, Any]:
        target = folder.resolve()
        if not target.exists() or not target.is_dir():
            raise ValueError("workspace folder does not exist")
        self._assert_under_desktop(target)

        display_name = _safe_folder_name(name)
        workspace = self._new_workspace(name=display_name, folder=target)
        items = self._load()
        items.append(workspace)
        self._save(items)
        return dict(workspace)

    def _new_workspace(self, name: str, folder: Path) -> dict[str, Any]:
        created_at = _now_ms()
        return {
            "id": self._unique_id(name),
            "name": name,
            "path": str(folder.resolve()),
            "status": "available",
            "created_at": created_at,
            "updated_at": created_at,
        }

    def _unique_folder(self, base: Path) -> Path:
        if not base.exists():
            return base
        for index in range(2, 10_000):
            candidate = base.with_name(f"{base.name} {index}")
            if not candidate.exists():
                return candidate
        raise RuntimeError("could not allocate workspace folder")

    def _unique_id(self, name: str) -> str:
        existing = {item["id"] for item in self._load()}
        base = _safe_id(name)
        if base not in existing:
            return base
        for index in range(2, 10_000):
            candidate = f"{base}-{index}"
            if candidate not in existing:
                return candidate
        return f"{base}-{uuid.uuid4().hex[:8]}"

    def _assert_under_desktop(self, folder: Path) -> None:
        try:
            folder.relative_to(self.desktop_root)
        except ValueError as exc:
            raise ValueError("workspace folder must be under desktop") from exc

    def _load(self) -> list[dict[str, Any]]:
        if not self.path.exists():
            return []
        with self.path.open("r", encoding="utf-8") as file:
            data = json.load(file)
        if not isinstance(data, list):
            raise ValueError("workspace registry must contain a JSON list")
        return [dict(item) for item in data]

    def _save(self, items: list[dict[str, Any]]) -> None:
        tmp = self.path.with_suffix(".json.tmp")
        with tmp.open("w", encoding="utf-8") as file:
            json.dump(items, file, ensure_ascii=False, indent=2)
            file.write("\n")
        tmp.replace(self.path)


class SessionRegistry:
    def __init__(self, state_dir: Path) -> None:
        self.state_dir = state_dir.resolve()
        self.sessions_root = self.state_dir / "sessions"
        self.sessions_root.mkdir(parents=True, exist_ok=True)

    def create_session(self, workspace_id: str, title: str) -> dict[str, Any]:
        workspace_key = self._require_key(workspace_id, "workspace_id")
        display_title = title.strip() or "Новая сессия"
        created_at = _now_ms()
        session = {
            "id": self._unique_session_id(workspace_key),
            "workspace_id": workspace_key,
            "title": display_title,
            "status": "idle",
            "worker_pid": None,
            "worker_port": None,
            "created_at": created_at,
            "updated_at": created_at,
            "last_event_seq": 0,
        }
        self._save_session(session)
        self._events_path(workspace_key, session["id"]).touch(exist_ok=True)
        return dict(session)

    def list_sessions(self, workspace_id: str) -> list[dict[str, Any]]:
        workspace_key = self._require_key(workspace_id, "workspace_id")
        folder = self._workspace_sessions_dir(workspace_key)
        if not folder.exists():
            return []
        sessions = [
            self._load_session_file(path)
            for path in folder.glob("*.json")
            if path.name != "workspaces.json"
        ]
        return sorted(sessions, key=lambda item: (item["updated_at"], item["id"]), reverse=True)

    def get_session(self, workspace_id: str, session_id: str) -> dict[str, Any]:
        workspace_key = self._require_key(workspace_id, "workspace_id")
        session_key = self._require_key(session_id, "session_id")
        path = self._session_path(workspace_key, session_key)
        if not path.exists():
            raise KeyError(f"session not found: {session_key}")
        return self._load_session_file(path)

    def update_session(
        self,
        workspace_id: str,
        session_id: str,
        **patch: Any,
    ) -> dict[str, Any]:
        session = self.get_session(workspace_id, session_id)
        allowed = {"title", "status", "worker_pid", "worker_port", "last_event_seq"}
        for key, value in patch.items():
            if key not in allowed:
                raise ValueError(f"unsupported session field: {key}")
            session[key] = value
        session["updated_at"] = _now_ms()
        self._save_session(session)
        return dict(session)

    def append_event(
        self,
        workspace_id: str,
        session_id: str,
        event: dict[str, Any],
    ) -> dict[str, Any]:
        session = self.get_session(workspace_id, session_id)
        seq = int(session.get("last_event_seq") or 0) + 1
        record = {
            "seq": seq,
            "ts": _now_ms(),
            **event,
        }
        events_path = self._events_path(session["workspace_id"], session["id"])
        events_path.parent.mkdir(parents=True, exist_ok=True)
        with events_path.open("a", encoding="utf-8") as file:
            file.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")))
            file.write("\n")
        self.update_session(
            session["workspace_id"],
            session["id"],
            last_event_seq=seq,
        )
        return dict(record)

    def load_events(
        self,
        workspace_id: str,
        session_id: str,
        limit: int = 300,
    ) -> list[dict[str, Any]]:
        workspace_key = self._require_key(workspace_id, "workspace_id")
        session_key = self._require_key(session_id, "session_id")
        path = self._events_path(workspace_key, session_key)
        if not path.exists():
            return []
        with path.open("r", encoding="utf-8") as file:
            events = [json.loads(line) for line in file if line.strip()]
        if limit <= 0:
            return events
        return events[-limit:]

    def _unique_session_id(self, workspace_id: str) -> str:
        existing = {item["id"] for item in self.list_sessions(workspace_id)}
        while True:
            candidate = f"session-{_now_ms()}-{uuid.uuid4().hex[:6]}"
            if candidate not in existing:
                return candidate

    def _workspace_sessions_dir(self, workspace_id: str) -> Path:
        return self.sessions_root / workspace_id

    def _session_path(self, workspace_id: str, session_id: str) -> Path:
        return self._workspace_sessions_dir(workspace_id) / f"{session_id}.json"

    def _events_path(self, workspace_id: str, session_id: str) -> Path:
        return self._workspace_sessions_dir(workspace_id) / f"{session_id}.jsonl"

    def _save_session(self, session: dict[str, Any]) -> None:
        path = self._session_path(session["workspace_id"], session["id"])
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".json.tmp")
        with tmp.open("w", encoding="utf-8") as file:
            json.dump(session, file, ensure_ascii=False, indent=2)
            file.write("\n")
        tmp.replace(path)

    def _load_session_file(self, path: Path) -> dict[str, Any]:
        with path.open("r", encoding="utf-8") as file:
            data = json.load(file)
        if not isinstance(data, dict):
            raise ValueError(f"session metadata must be a JSON object: {path}")
        return dict(data)

    def _require_key(self, value: str, field_name: str) -> str:
        key = value.strip()
        if not key:
            raise ValueError(f"{field_name} is required")
        if not re.fullmatch(r"[A-Za-z0-9_.-]+", key):
            raise ValueError(f"{field_name} contains unsupported characters")
        return key


class CodeWhaleWorkerManager:
    def __init__(
        self,
        sessions: SessionRegistry,
        state_dir: Path,
        codewhale_cmd: str = "codewhale",
    ) -> None:
        self.sessions = sessions
        self.state_dir = state_dir.resolve()
        self.codewhale_cmd = codewhale_cmd
        self._workers: dict[tuple[str, str], subprocess.Popen] = {}

    def start_worker(
        self,
        workspace_id: str,
        session_id: str,
        workspace_path: Path,
        port: int,
    ) -> dict[str, Any]:
        workspace = workspace_path.resolve()
        if not workspace.exists() or not workspace.is_dir():
            raise ValueError("workspace path does not exist")

        key = self._key(workspace_id, session_id)
        existing = self._workers.get(key)
        if existing is not None and existing.poll() is None:
            return self.sessions.update_session(
                workspace_id,
                session_id,
                status="running",
                worker_pid=existing.pid,
                worker_port=port,
            )

        env = os.environ.copy()
        env.setdefault("PYTHONIOENCODING", "utf-8:backslashreplace")
        command = [
            self.codewhale_cmd,
            "serve",
            "--http",
            "--host",
            "127.0.0.1",
            "--port",
            str(port),
            "--insecure",
        ]
        logs = self._open_worker_logs(workspace_id, session_id)
        try:
            process = subprocess.Popen(
                command,
                cwd=str(workspace),
                stdout=logs,
                stderr=subprocess.STDOUT,
                text=True,
                env=env,
                creationflags=self._creation_flags(),
            )
        finally:
            logs.close()
        self._workers[key] = process
        session = self.sessions.update_session(
            workspace_id,
            session_id,
            status="running",
            worker_pid=process.pid,
            worker_port=port,
        )
        self.sessions.append_event(
            workspace_id,
            session_id,
            {
                "type": "worker_status",
                "status": "running",
                "pid": process.pid,
                "port": port,
            },
        )
        return session

    def stop_worker(
        self,
        workspace_id: str,
        session_id: str,
        timeout_seconds: float = 5,
    ) -> dict[str, Any]:
        key = self._key(workspace_id, session_id)
        process = self._workers.get(key)
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=timeout_seconds)
            except Exception:
                return self.kill_worker(workspace_id, session_id)
        self._workers.pop(key, None)
        self.sessions.append_event(
            workspace_id,
            session_id,
            {"type": "worker_status", "status": "stopped"},
        )
        return self.sessions.update_session(
            workspace_id,
            session_id,
            status="stopped",
            worker_pid=None,
            worker_port=None,
        )

    def kill_worker(self, workspace_id: str, session_id: str) -> dict[str, Any]:
        key = self._key(workspace_id, session_id)
        process = self._workers.pop(key, None)
        if process is not None and process.poll() is None:
            self._kill_process_tree(process)
        self.sessions.append_event(
            workspace_id,
            session_id,
            {"type": "worker_status", "status": "killed"},
        )
        return self.sessions.update_session(
            workspace_id,
            session_id,
            status="killed",
            worker_pid=None,
            worker_port=None,
        )

    def health(self, workspace_id: str, session_id: str) -> dict[str, Any]:
        key = self._key(workspace_id, session_id)
        process = self._workers.get(key)
        session = self.sessions.get_session(workspace_id, session_id)
        if process is None:
            return {**session, "worker_alive": False}
        return {**session, "worker_alive": process.poll() is None}

    def _open_worker_logs(self, workspace_id: str, session_id: str):
        logs_dir = self.state_dir / "sessions" / workspace_id
        logs_dir.mkdir(parents=True, exist_ok=True)
        return (logs_dir / f"{session_id}.worker.log").open("a", encoding="utf-8")

    def _kill_process_tree(self, process: subprocess.Popen) -> None:
        if sys.platform == "win32":
            subprocess.run(
                ["taskkill", "/T", "/F", "/PID", str(process.pid)],
                capture_output=True,
                timeout=10,
                check=False,
            )
        else:
            try:
                os.killpg(os.getpgid(process.pid), signal.SIGKILL)
            except Exception:
                process.kill()
        if process.poll() is None:
            process.kill()
            try:
                process.wait(timeout=5)
            except Exception:
                pass

    def _creation_flags(self) -> int:
        if sys.platform != "win32":
            return 0
        return getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)

    def _key(self, workspace_id: str, session_id: str) -> tuple[str, str]:
        return (
            self.sessions._require_key(workspace_id, "workspace_id"),
            self.sessions._require_key(session_id, "session_id"),
        )


class CodeWhaleRuntimeClient:
    def __init__(self, urlopen=urllib.request.urlopen, timeout_seconds: float = 10) -> None:
        self.urlopen = urlopen
        self.timeout_seconds = timeout_seconds

    def create_task(self, port: int, prompt: str) -> dict[str, Any]:
        return self._json_request(
            port,
            "POST",
            "/v1/tasks",
            {
                "prompt": prompt,
                "mode": "agent",
            },
        )

    def get_task(self, port: int, task_id: str) -> dict[str, Any]:
        return self._json_request(port, "GET", f"/v1/tasks/{task_id}")

    def _json_request(
        self,
        port: int,
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        data = None
        headers = {}
        if payload is not None:
            data = json.dumps(payload).encode("utf-8")
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(
            f"http://127.0.0.1:{port}{path}",
            data=data,
            headers=headers,
            method=method,
        )
        with self.urlopen(request, timeout=self.timeout_seconds) as response:
            body = response.read().decode("utf-8", "replace")
        decoded = json.loads(body)
        if not isinstance(decoded, dict):
            raise ValueError("runtime API returned non-object JSON")
        return decoded


class CodeWhaleBridge:
    def __init__(
        self,
        desktop_root: Path,
        state_dir: Path,
        codewhale_cmd: str = "codewhale",
    ) -> None:
        self.workspaces = WorkspaceRegistry(desktop_root, state_dir)
        self.sessions = SessionRegistry(state_dir)
        self.workers = CodeWhaleWorkerManager(
            self.sessions,
            state_dir,
            codewhale_cmd=codewhale_cmd,
        )
        self.runtime = CodeWhaleRuntimeClient()
        self._next_port = 43100

    def handle_message(self, message: dict[str, Any]) -> dict[str, Any]:
        request_id = message.get("request_id")
        try:
            reply = self._handle_message(message)
        except Exception as exc:
            reply = {"type": "error", "error": str(exc)}
        if request_id is not None:
            reply["request_id"] = request_id
        return reply

    def _handle_message(self, message: dict[str, Any]) -> dict[str, Any]:
        msg_type = str(message.get("type") or "").strip()
        if msg_type == "workspace_list":
            return {
                "type": "workspace_list",
                "workspaces": self.workspaces.list_workspaces(),
            }
        if msg_type == "workspace_create":
            workspace = self.workspaces.create_workspace(str(message.get("name") or ""))
            return {"type": "workspace", "workspace": workspace}
        if msg_type == "workspace_attach":
            workspace = self.workspaces.attach_workspace(
                str(message.get("name") or ""),
                Path(str(message.get("path") or "")),
            )
            return {"type": "workspace", "workspace": workspace}
        if msg_type == "session_list":
            return {
                "type": "session_list",
                "workspace_id": self._workspace_id(message),
                "sessions": self.sessions.list_sessions(self._workspace_id(message)),
            }
        if msg_type == "session_create":
            session = self.sessions.create_session(
                self._workspace_id(message),
                str(message.get("title") or ""),
            )
            return {"type": "session", "session": session}
        if msg_type == "session_open":
            session = self.sessions.get_session(
                self._workspace_id(message),
                self._session_id(message),
            )
            events = self.sessions.load_events(session["workspace_id"], session["id"])
            return {"type": "session_open", "session": session, "events": events}
        if msg_type == "session_send":
            text = str(message.get("text") or "").strip()
            if not text:
                raise ValueError("message text is required")
            workspace_id = self._workspace_id(message)
            session_id = self._session_id(message)
            session = self.sessions.get_session(workspace_id, session_id)
            self.sessions.append_event(
                workspace_id,
                session_id,
                {"type": "user_message", "text": text},
            )
            port = session.get("worker_port")
            if not port:
                workspace = self._find_workspace(workspace_id)
                port = self._allocate_port()
                session = self.workers.start_worker(
                    workspace_id,
                    session_id,
                    Path(workspace["path"]),
                    port=int(port),
                )
                port = session.get("worker_port")
            if not port:
                raise ValueError("session worker failed to start")
            task = self.runtime.create_task(int(port), text)
            event = self.sessions.append_event(
                workspace_id,
                session_id,
                {
                    "type": "runtime_task",
                    "task_id": str(task.get("id") or ""),
                    "status": str(task.get("status") or "queued"),
                },
            )
            return {
                "type": "session_task",
                "workspace_id": workspace_id,
                "session_id": session_id,
                "task_id": event["task_id"],
                "status": event["status"],
                "event": event,
            }
        if msg_type == "session_task_poll":
            workspace_id = self._workspace_id(message)
            session_id = self._session_id(message)
            task_id = str(message.get("task_id") or "").strip()
            if not task_id:
                raise ValueError("task_id is required")
            session = self.sessions.get_session(workspace_id, session_id)
            port = session.get("worker_port")
            if not port:
                raise ValueError("session worker is not running")
            task = self.runtime.get_task(int(port), task_id)
            status = str(task.get("status") or "")
            event = self.sessions.append_event(
                workspace_id,
                session_id,
                {
                    "type": "runtime_task",
                    "task_id": task_id,
                    "status": status,
                },
            )
            result_summary = str(task.get("result_summary") or "").strip()
            if status == "completed" and result_summary:
                self.sessions.append_event(
                    workspace_id,
                    session_id,
                    {
                        "type": "assistant_delta",
                        "task_id": task_id,
                        "text": result_summary,
                        "final": True,
                    },
                )
            return {
                "type": "session_task",
                "workspace_id": workspace_id,
                "session_id": session_id,
                "task_id": task_id,
                "status": status,
                "task": task,
                "event": event,
            }
        if msg_type == "session_health":
            session = self.workers.health(self._workspace_id(message), self._session_id(message))
            return {"type": "session_health", "session": session}
        if msg_type == "session_stop":
            session = self.workers.stop_worker(
                self._workspace_id(message),
                self._session_id(message),
            )
            return {"type": "session", "session": session}
        if msg_type == "session_kill":
            session = self.workers.kill_worker(
                self._workspace_id(message),
                self._session_id(message),
            )
            return {"type": "session", "session": session}
        if msg_type == "session_start":
            workspace = self._find_workspace(self._workspace_id(message))
            session = self.workers.start_worker(
                workspace["id"],
                self._session_id(message),
                Path(workspace["path"]),
                port=self._allocate_port(),
            )
            return {"type": "session", "session": session}
        raise ValueError(f"unsupported message type: {msg_type}")

    def _find_workspace(self, workspace_id: str) -> dict[str, Any]:
        for workspace in self.workspaces.list_workspaces():
            if workspace["id"] == workspace_id:
                return workspace
        raise KeyError(f"workspace not found: {workspace_id}")

    def _allocate_port(self) -> int:
        self._next_port += 1
        return self._next_port

    def _workspace_id(self, message: dict[str, Any]) -> str:
        return str(message.get("workspace_id") or "").strip()

    def _session_id(self, message: dict[str, Any]) -> str:
        return str(message.get("session_id") or "").strip()


def _parse_tunnel(value: str) -> tuple[str, int]:
    host, sep, port_text = value.rpartition(":")
    if not sep or not host or not port_text.isdigit():
        raise ValueError("tunnel must be in host:port format")
    return host, int(port_text)


async def run_tunnel_client(
    bridge: CodeWhaleBridge,
    tunnel_host: str,
    tunnel_port: int,
    project_id: str = "codewhale",
) -> None:
    while True:
        try:
            await _run_tunnel_once(bridge, tunnel_host, tunnel_port, project_id)
        except Exception as exc:
            print(f"[codewhale_bridge] tunnel error: {exc}", flush=True)
        await asyncio.sleep(RECONNECT_DELAY_SECONDS)


async def _run_tunnel_once(
    bridge: CodeWhaleBridge,
    tunnel_host: str,
    tunnel_port: int,
    project_id: str,
) -> None:
    reader, writer = await asyncio.open_connection(tunnel_host, tunnel_port)
    writer.write(
        json.dumps(
            {"type": "codewhale_register", "project_id": project_id},
            ensure_ascii=False,
        ).encode("utf-8")
        + b"\n"
    )
    await writer.drain()
    print(
        f"[codewhale_bridge] connected to {tunnel_host}:{tunnel_port}",
        flush=True,
    )
    try:
        while True:
            line = await reader.readline()
            if not line:
                break
            try:
                message = json.loads(line.decode("utf-8", "replace").strip())
            except json.JSONDecodeError:
                continue
            if message.get("type") == "codewhale_mobile_attached":
                continue
            reply = bridge.handle_message(message)
            writer.write(json.dumps(reply, ensure_ascii=False).encode("utf-8") + b"\n")
            await writer.drain()
    finally:
        writer.close()
        await writer.wait_closed()


def main() -> None:
    parser = argparse.ArgumentParser(description="CodeWhale workspace bridge")
    parser.add_argument("--tunnel", default="31.129.97.211:9877")
    parser.add_argument("--desktop", default=str(Path.home() / "Desktop"))
    parser.add_argument("--state-dir", default=".codewhale_bridge")
    parser.add_argument("--project-id", default="codewhale")
    args = parser.parse_args()

    tunnel_host, tunnel_port = _parse_tunnel(args.tunnel)
    bridge = CodeWhaleBridge(Path(args.desktop), Path(args.state_dir))
    asyncio.run(
        run_tunnel_client(
            bridge,
            tunnel_host,
            tunnel_port,
            project_id=args.project_id,
        )
    )


if __name__ == "__main__":
    main()
