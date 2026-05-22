"""
PC-side launcher for project_bridge.py.

Keep this process running on the Windows PC. The mobile app can then ask the
VPS tunnel to start project_bridge.py when a project chat is opened.

Usage: python bridge_launcher.py --tunnel 31.129.97.211:9877
"""
import argparse
import asyncio
import json
import os
import signal
import subprocess
import sys
from pathlib import Path

if sys.platform == "win32":
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

RECONNECT_DELAY_SECONDS = 5
HEARTBEAT_SECONDS = 10


class BridgeLauncher:
    def __init__(self, tunnel_host: str, tunnel_port: int, project_root: Path):
        self.tunnel_host = tunnel_host
        self.tunnel_port = tunnel_port
        self.project_root = project_root
        self._bridge_process: subprocess.Popen | None = None

    async def run_forever(self) -> None:
        health_task = asyncio.create_task(self._health_check_loop())
        try:
            while True:
                try:
                    await self._run_once()
                except Exception as exc:
                    print(f"[launcher] error: {exc}", flush=True)
                await asyncio.sleep(RECONNECT_DELAY_SECONDS)
        finally:
            health_task.cancel()
            try:
                await health_task
            except asyncio.CancelledError:
                pass

    async def _run_once(self) -> None:
        reader, writer = await asyncio.open_connection(
            self.tunnel_host,
            self.tunnel_port,
        )
        writer.write(
            json.dumps(
                {"type": "launcher", "project_id": "launcher"},
                ensure_ascii=False,
            ).encode("utf-8")
            + b"\n"
        )
        await writer.drain()
        print(
            f"[launcher] connected to {self.tunnel_host}:{self.tunnel_port}",
            flush=True,
        )
        self.ensure_bridge_running()
        heartbeat_task = asyncio.create_task(self._heartbeat_loop(writer))

        try:
            while True:
                line = await reader.readline()
                if not line:
                    break
                try:
                    msg = json.loads(line.decode("utf-8", "replace").strip())
                except json.JSONDecodeError:
                    continue
                if msg.get("type") == "start_bridge":
                    project_id = str(msg.get("project_id", "")).strip()
                    try:
                        started = self.start_bridge()
                    except Exception as exc:
                        print(f"[launcher] start_bridge failed: {exc}", flush=True)
                        started = False
                    status = "started" if started else "failed"
                    writer.write(
                        json.dumps(
                            {
                                "type": "status",
                                "text": f"project_bridge {status} for {project_id}",
                            },
                            ensure_ascii=False,
                        ).encode("utf-8")
                        + b"\n"
                    )
                    await writer.drain()
                elif msg.get("type") == "ping":
                    writer.write(
                        json.dumps(
                            {"type": "pong", "text": "launcher pong"},
                            ensure_ascii=False,
                        ).encode("utf-8")
                        + b"\n"
                    )
                    await writer.drain()
        finally:
            heartbeat_task.cancel()
            try:
                await heartbeat_task
            except asyncio.CancelledError:
                pass
            writer.close()
            await writer.wait_closed()
            print("[launcher] disconnected", flush=True)

    async def _heartbeat_loop(self, writer: asyncio.StreamWriter) -> None:
        """Keep the tunnel socket active so broken connections are detected."""
        while True:
            await asyncio.sleep(HEARTBEAT_SECONDS)
            writer.write(
                json.dumps(
                    {"type": "heartbeat", "text": "heartbeat"},
                    ensure_ascii=False,
                ).encode("utf-8")
                + b"\n"
            )
            await writer.drain()

    def start_bridge(self) -> bool:
        """Kill any stale bridge process, then start a fresh one."""
        self._kill_stale_bridge()
        return self._spawn_bridge()

    def ensure_bridge_running(self) -> bool:
        """Start project_bridge.py if no healthy instance is available."""
        tunnel = f"{self.tunnel_host}:{self.tunnel_port}"

        if self._bridge_process is not None:
            rc = self._bridge_process.poll()
            if rc is None:
                return True
            print(
                f"[launcher] project_bridge.py exited with code {rc}, restarting...",
                flush=True,
            )
            self._bridge_process = None

        if self._find_bridge_pids(tunnel):
            return True

        print("[launcher] project_bridge.py is not running, starting...", flush=True)
        return self._spawn_bridge()

    def _spawn_bridge(self) -> bool:
        state_dir = self.project_root / ".deepseek" / "state"
        state_dir.mkdir(parents=True, exist_ok=True)
        log_path = state_dir / "bridge_launcher_project_bridge.log"
        log_file = log_path.open("a", encoding="utf-8")
        script = self.project_root / "project_bridge.py"
        tunnel = f"{self.tunnel_host}:{self.tunnel_port}"
        env = os.environ.copy()
        env.setdefault("PYTHONIOENCODING", "utf-8:backslashreplace")
        self._bridge_process = subprocess.Popen(
            [sys.executable, str(script), "--tunnel", tunnel],
            cwd=str(self.project_root),
            stdout=log_file,
            stderr=subprocess.STDOUT,
            text=True,
            env=env,
        )
        print(
            f"[launcher] started project_bridge.py pid={self._bridge_process.pid}",
            flush=True,
        )
        return True

    def _kill_stale_bridge(self) -> None:
        """Terminate any existing project_bridge.py process (ours or external)."""
        # Kill our tracked process if it exists (even if zombie)
        if self._bridge_process is not None:
            try:
                if self._bridge_process.poll() is None:
                    self._bridge_process.terminate()
                    try:
                        self._bridge_process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        self._bridge_process.kill()
                        self._bridge_process.wait(timeout=5)
                    print("[launcher] Terminated tracked bridge process", flush=True)
            except Exception as exc:
                print(f"[launcher] Error killing tracked bridge: {exc}", flush=True)
            finally:
                self._bridge_process = None

        # Find and kill any external bridge processes
        tunnel = f"{self.tunnel_host}:{self.tunnel_port}"
        pids = self._find_bridge_pids(tunnel)
        for pid in pids:
            try:
                if sys.platform == "win32":
                    subprocess.run(
                        ["taskkill", "/F", "/PID", str(pid)],
                        capture_output=True, timeout=10, check=False,
                    )
                else:
                    os.kill(int(pid), signal.SIGTERM)
                print(f"[launcher] Killed external bridge pid={pid}", flush=True)
            except Exception as exc:
                print(f"[launcher] Failed to kill pid={pid}: {exc}", flush=True)

    def _find_bridge_pids(self, tunnel: str) -> list[int]:
        """Return list of PIDs for project_bridge.py processes with given tunnel."""
        if sys.platform == "win32":
            command = (
                "Get-CimInstance Win32_Process | "
                "Where-Object { $_.ProcessName -like 'python*' "
                "-and $_.CommandLine -like '*project_bridge.py*' "
                f"-and $_.CommandLine -like '*{tunnel}*' }} | "
                "Select-Object -ExpandProperty ProcessId"
            )
            result = subprocess.run(
                ["powershell", "-NoProfile", "-Command", command],
                capture_output=True,
                text=True,
                timeout=10,
                check=False,
            )
            pids: list[int] = []
            for line in result.stdout.strip().splitlines():
                line = line.strip()
                if line.isdigit():
                    pids.append(int(line))
            return pids

        result = subprocess.run(
            ["ps", "-eo", "pid,args"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
        pids: list[int] = []
        for line in result.stdout.splitlines():
            if "project_bridge.py" in line and tunnel in line:
                parts = line.strip().split(None, 1)
                if parts and parts[0].isdigit():
                    pids.append(int(parts[0]))
        return pids

    async def _health_check_loop(self) -> None:
        """Periodically check if project_bridge.py is alive; restart if dead."""
        while True:
            await asyncio.sleep(15)  # Check every 15 seconds
            try:
                self.ensure_bridge_running()
            except Exception as exc:
                print(f"[launcher] health check failed: {exc}", flush=True)


async def main() -> None:
    parser = argparse.ArgumentParser(description="Project bridge launcher")
    parser.add_argument("--tunnel", default="31.129.97.211:9877")
    args = parser.parse_args()

    host, _, port = args.tunnel.partition(":")
    launcher = BridgeLauncher(
        host,
        int(port) if port else 9877,
        Path(__file__).resolve().parent,
    )
    await launcher.run_forever()


if __name__ == "__main__":
    asyncio.run(main())
