import json
import shutil
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
AUTH_PATH = (ROOT / "backend_api" / "src" / "auth.php").as_posix()
REPO_PATH = (ROOT / "backend_api" / "src" / "repository.php").as_posix()
SYNC_STORE_FILE = ROOT / "backend_api" / "public" / "sync_store.php"


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
    def test_file_store_source_is_utf8_and_keeps_collaboration_contract(self) -> None:
        raw = SYNC_STORE_FILE.read_bytes()
        self.assertFalse(raw.startswith(b"\xff\xfe"))
        source = raw.decode("utf-8")
        self.assertIn("function sync_normalize_collaboration_payload", source)
        self.assertEqual(
            source.count("'collaboration' => sync_normalize_collaboration_payload"),
            2,
        )

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
        self.assertEqual(payload.get("owner_key"), "family")
        self.assertEqual(payload.get("is_family"), True)

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
        self.assertEqual(payload.get("owner_key"), "family")
        self.assertEqual(payload.get("is_family"), True)

    @unittest.skipIf(shutil.which("php") is None, "php is not installed in test environment")
    def test_file_store_family_task_preserves_collaboration(self) -> None:
        sync_store_path = SYNC_STORE_FILE.as_posix()
        payload = _php_json(
            f"require '{sync_store_path}'; "
            "echo json_encode(sync_normalize_family_task(["
            "'id' => 'f-collab',"
            "'title' => 'With work log',"
            "'assignees' => ['nik'],"
            "'collaboration' => ["
            "  'comments' => [['id' => 'c-1', 'text' => 'Сделал']],"
            "  'attachments' => [['id' => 'a-1', 'filename' => 'photo.jpg']],"
            "  'checklists' => [['id' => 'cl-1', 'title' => 'QA']],"
            "  'activity' => [['id' => 'act-1', 'type' => 'comment_added']]"
            "]"
            "]));"
        )

        collaboration = payload.get("collaboration", {})
        self.assertEqual(collaboration.get("comments", [{}])[0].get("text"), "Сделал")
        self.assertEqual(collaboration.get("attachments", [{}])[0].get("filename"), "photo.jpg")
        self.assertEqual(collaboration.get("checklists", [{}])[0].get("title"), "QA")
        self.assertEqual(collaboration.get("activity", [{}])[0].get("type"), "comment_added")


if __name__ == "__main__":
    unittest.main()
