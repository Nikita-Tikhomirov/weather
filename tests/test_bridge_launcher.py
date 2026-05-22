import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from bridge_launcher import BridgeLauncher


class _ExitedProcess:
    def poll(self) -> int:
        return 1


class _RunningProcess:
    def poll(self) -> None:
        return None


class BridgeLauncherTests(unittest.TestCase):
    def test_find_bridge_pids_detects_project_bridge_process(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            launcher = BridgeLauncher("31.129.97.211", 9877, Path(tmp))
            tunnel = "31.129.97.211:9877"

            fake_result = subprocess.CompletedProcess(
                args=[],
                returncode=0,
                stdout="1234\n" if sys.platform == "win32" else (
                    "1234 python project_bridge.py --tunnel 31.129.97.211:9877\n"
                ),
                stderr="",
            )
            with patch("bridge_launcher.subprocess.run", return_value=fake_result):
                pids = launcher._find_bridge_pids(tunnel)
                self.assertGreater(len(pids), 0)
                self.assertIn(1234, pids)

    def test_ensure_bridge_running_spawns_when_missing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            launcher = BridgeLauncher("31.129.97.211", 9877, Path(tmp))

            with (
                patch.object(launcher, "_find_bridge_pids", return_value=[]),
                patch.object(launcher, "_spawn_bridge", return_value=True) as spawn_bridge,
            ):
                self.assertTrue(launcher.ensure_bridge_running())

            spawn_bridge.assert_called_once_with()

    def test_ensure_bridge_running_keeps_external_bridge(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            launcher = BridgeLauncher("31.129.97.211", 9877, Path(tmp))

            with (
                patch.object(launcher, "_find_bridge_pids", return_value=[1234]),
                patch.object(launcher, "_spawn_bridge", return_value=True) as spawn_bridge,
            ):
                self.assertTrue(launcher.ensure_bridge_running())

            spawn_bridge.assert_not_called()

    def test_ensure_bridge_running_keeps_tracked_bridge(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            launcher = BridgeLauncher("31.129.97.211", 9877, Path(tmp))
            launcher._bridge_process = _RunningProcess()

            with patch.object(launcher, "_spawn_bridge", return_value=True) as spawn_bridge:
                self.assertTrue(launcher.ensure_bridge_running())

            spawn_bridge.assert_not_called()

    def test_ensure_bridge_running_restarts_exited_tracked_bridge(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            launcher = BridgeLauncher("31.129.97.211", 9877, Path(tmp))
            launcher._bridge_process = _ExitedProcess()

            with (
                patch.object(launcher, "_find_bridge_pids", return_value=[]),
                patch.object(launcher, "_spawn_bridge", return_value=True) as spawn_bridge,
            ):
                self.assertTrue(launcher.ensure_bridge_running())

            spawn_bridge.assert_called_once_with()


if __name__ == "__main__":
    unittest.main()
