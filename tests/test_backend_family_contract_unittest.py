import json
import shutil
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
AUTH_PATH = (ROOT / "backend_api" / "src" / "auth.php").as_posix()
REPO_PATH = (ROOT / "backend_api" / "src" / "repository.php").as_posix()


def _php_json(script: str) -> dict:
    completed = subprocess.run(
        ["php", "-r", script],
        cwd=str(ROOT),
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr or completed.stdout or "php failed")
    return json.loads(completed.stdout.strip() or "{}")


class BackendFamilyContractTests(unittest.TestCase):
    @unittest.skipIf(shutil.which("php") is None, "php is not installed in test environment")
    def test_assignees_are_filtered_by_allowed_profiles(self) -> None:
        payload = _php_json(
            f"require '{AUTH_PATH}'; require '{REPO_PATH}'; "
            "echo json_encode(normalize_family_task(["
            "'id' => 'f-1',"
            "'title' => 'Test',"
            "'assignees' => ['nik', 'nik', 'unknown', 'misha']"
            "]));"
        )
        self.assertEqual(payload.get("assignees"), ["nik", "misha"])
        self.assertEqual(payload.get("participants"), ["nik", "misha"])

    @unittest.skipIf(shutil.which("php") is None, "php is not installed in test environment")
    def test_participants_payload_is_mapped_to_assignees(self) -> None:
        payload = _php_json(
            f"require '{AUTH_PATH}'; require '{REPO_PATH}'; "
            "echo json_encode(normalize_family_task(["
            "'id' => 'f-2',"
            "'title' => 'Legacy',"
            "'participants' => ['nastya', 'arisha']"
            "]));"
        )
        self.assertEqual(payload.get("assignees"), ["nastya", "arisha"])
        self.assertEqual(payload.get("participants"), ["nastya", "arisha"])


if __name__ == "__main__":
    unittest.main()
