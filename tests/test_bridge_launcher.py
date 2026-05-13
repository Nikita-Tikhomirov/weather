import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from bridge_launcher import BridgeLauncher


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


if __name__ == "__main__":
    unittest.main()
