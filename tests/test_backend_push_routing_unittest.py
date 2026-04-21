import json
import shutil
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
AUTH_PATH = (ROOT / "backend_api" / "src" / "auth.php").as_posix()


def _php_json(script: str) -> list[str]:
    completed = subprocess.run(
        ["php", "-r", script],
        cwd=str(ROOT),
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr or completed.stdout or "php failed")
    payload = json.loads(completed.stdout.strip() or "[]")
    return [str(item) for item in payload]


class BackendPushRoutingTests(unittest.TestCase):
    @unittest.skipIf(shutil.which("php") is None, "php is not installed in test environment")
    def test_personal_update_includes_actor_device(self) -> None:
        recipients = _php_json(
            f"require '{AUTH_PATH}'; echo json_encode(recipients_for_push('nik', 'task', 'upsert', ['owner_key' => 'nik', 'is_family' => false]));"
        )
        self.assertEqual(set(recipients), {"nik"})

    @unittest.skipIf(shutil.which("php") is None, "php is not installed in test environment")
    def test_child_update_keeps_visibility_and_actor(self) -> None:
        recipients = _php_json(
            f"require '{AUTH_PATH}'; echo json_encode(recipients_for_push('nik', 'task', 'upsert', ['owner_key' => 'misha', 'is_family' => false]));"
        )
        self.assertEqual(set(recipients), {"nik", "misha", "nastya"})

    @unittest.skipIf(shutil.which("php") is None, "php is not installed in test environment")
    def test_family_update_targets_both_adults(self) -> None:
        recipients = _php_json(
            f"require '{AUTH_PATH}'; echo json_encode(recipients_for_push('nastya', 'family_task', 'upsert', []));"
        )
        self.assertEqual(set(recipients), {"nik", "nastya"})


if __name__ == "__main__":
    unittest.main()
