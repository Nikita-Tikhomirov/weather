import json
import shutil
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
AUTH_PATH = (ROOT / "backend_api" / "src" / "auth.php").as_posix()
PUSH_OUTBOX_PATH = (ROOT / "backend_api" / "src" / "push_outbox.php").as_posix()


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


def _php_text(script: str) -> str:
    completed = subprocess.run(
        ["php", "-r", script],
        cwd=str(ROOT),
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr or completed.stdout or "php failed")
    return completed.stdout.strip()


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
        self.assertEqual(set(recipients), {"nik", "nastya", "misha"})

    @unittest.skipIf(shutil.which("php") is None, "php is not installed in test environment")
    def test_family_update_targets_both_adults(self) -> None:
        recipients = _php_json(
            f"require '{AUTH_PATH}'; echo json_encode(recipients_for_push('nastya', 'family_task', 'upsert', ['assignees' => ['nastya', 'misha']]));"
        )
        self.assertEqual(set(recipients), {"nastya", "misha"})

    @unittest.skipIf(shutil.which("php") is None, "php is not installed in test environment")
    def test_push_dedup_signature_ignores_volatile_fields(self) -> None:
        signature_a = _php_text(
            f"require '{PUSH_OUTBOX_PATH}';"
            "echo build_push_dedup_signature('nik', 'task', 'upsert', "
            "['id' => '1', 'title' => 'Корм', 'updated_at' => '2026-04-21T10:00:00', 'version' => 3], 'nik');"
        )
        signature_b = _php_text(
            f"require '{PUSH_OUTBOX_PATH}';"
            "echo build_push_dedup_signature('nik', 'task', 'upsert', "
            "['id' => '1', 'title' => 'Корм', 'updated_at' => '2026-04-21T10:02:00', 'version' => 7], 'nik');"
        )
        self.assertEqual(signature_a, signature_b)

    @unittest.skipIf(shutil.which("php") is None, "php is not installed in test environment")
    def test_push_dedup_signature_changes_for_meaningful_payload(self) -> None:
        signature_a = _php_text(
            f"require '{PUSH_OUTBOX_PATH}';"
            "echo build_push_dedup_signature('nik', 'task', 'upsert', ['id' => '1', 'title' => 'Корм'], 'nik');"
        )
        signature_b = _php_text(
            f"require '{PUSH_OUTBOX_PATH}';"
            "echo build_push_dedup_signature('nik', 'task', 'upsert', ['id' => '1', 'title' => 'Математика'], 'nik');"
        )
        self.assertNotEqual(signature_a, signature_b)


if __name__ == "__main__":
    unittest.main()
