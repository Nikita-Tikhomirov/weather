"""
PC-side launcher for project_bridge.py.

Keep this process running on the Windows PC. The mobile app can then ask the
VPS tunnel to start project_bridge.py when a project chat is opened.

Usage: python bridge_launcher.py --tunnel 31.129.97.211:9877
"""
import argparse
import asyncio
import json
import subprocess
import sys
from pathlib import Path

if sys.platform == "win32":
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

RECONNECT_DELAY_SECONDS = 5


class BridgeLauncher:
    def __init__(self, tunnel_host: str, tunnel_port: int, project_root: Path):
        self.tunnel_host = tunnel_host
        self.tunnel_port = tunnel_port
        self.project_root = project_root
        self._bridge_process: subprocess.Popen | None = None

    async def run_forever(self) -> None:
        while True:
            try:
                await self._run_once()
            except Exception as exc:
                print(f"[launcher] error: {exc}", flush=True)
            await asyncio.sleep(RECONNECT_DELAY_SECONDS)

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
                    started = self.start_bridge()
                    status = "started" if started else "already running"
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
        finally:
            writer.close()
            await writer.wait_closed()
            print("[launcher] disconnected", flush=True)

    def start_bridge(self) -> bool:
        if self._bridge_process and self._bridge_process.poll() is None:
            return False
        if self._external_bridge_running():
            return False

        state_dir = self.project_root / ".deepseek" / "state"
        state_dir.mkdir(parents=True, exist_ok=True)
        log_path = state_dir / "bridge_launcher_project_bridge.log"
        log_file = log_path.open("a", encoding="utf-8")
        script = self.project_root / "project_bridge.py"
        tunnel = f"{self.tunnel_host}:{self.tunnel_port}"
        self._bridge_process = subprocess.Popen(
            [sys.executable, str(script), "--tunnel", tunnel],
            cwd=str(self.project_root),
            stdout=log_file,
            stderr=subprocess.STDOUT,
            text=True,
        )
        print(
            f"[launcher] started project_bridge.py pid={self._bridge_process.pid}",
            flush=True,
        )
        return True

    def _external_bridge_running(self) -> bool:
        tunnel = f"{self.tunnel_host}:{self.tunnel_port}"
        if sys.platform == "win32":
            command = (
                "Get-CimInstance Win32_Process | "
                "Where-Object { $_.ProcessName -like 'python*' "
                "-and $_.CommandLine -like '*project_bridge.py*' "
                f"-and $_.CommandLine -like '*{tunnel}*' }} | "
                "Select-Object -First 1 -ExpandProperty ProcessId"
            )
            result = subprocess.run(
                ["powershell", "-NoProfile", "-Command", command],
                capture_output=True,
                text=True,
                timeout=5,
                check=False,
            )
            return bool(result.stdout.strip())

        result = subprocess.run(
            ["ps", "-eo", "pid,args"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
        return any(
            "project_bridge.py" in line and tunnel in line
            for line in result.stdout.splitlines()
        )


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
