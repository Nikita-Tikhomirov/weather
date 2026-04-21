import json
import shutil
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TELEGRAM_OUTBOX_PATH = (ROOT / "backend_api" / "src" / "telegram_outbox.php").as_posix()


def _php_json(script: str) -> list[int]:
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
    return [int(item) for item in payload]


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


class BackendTelegramRoutingTests(unittest.TestCase):
    @unittest.skipIf(shutil.which("php") is None, "php is not installed in test environment")
    def test_recipient_profiles_use_chat_ids_by_profile(self) -> None:
        chat_ids = _php_json(
            f"require '{TELEGRAM_OUTBOX_PATH}';"
            "echo json_encode(resolve_telegram_chat_ids("
            "['recipient_profiles' => ['nastya', 'misha']],"
            "[-1001],"
            "['nik' => [-101], 'nastya' => [-102], 'misha' => [-103, -104]]"
            "));"
        )
        self.assertEqual(set(chat_ids), {-102, -103, -104})

    @unittest.skipIf(shutil.which("php") is None, "php is not installed in test environment")
    def test_fallback_to_default_chat_ids_when_mapping_absent(self) -> None:
        chat_ids = _php_json(
            f"require '{TELEGRAM_OUTBOX_PATH}';"
            "echo json_encode(resolve_telegram_chat_ids("
            "['entity' => 'task'],"
            "[-1001, '-1002'],"
            "[]"
            "));"
        )
        self.assertEqual(set(chat_ids), {-1001, -1002})

    @unittest.skipIf(shutil.which("php") is None, "php is not installed in test environment")
    def test_telegram_dedup_signature_ignores_event_id(self) -> None:
        signature_a = _php_text(
            f"require '{TELEGRAM_OUTBOX_PATH}';"
            "echo build_telegram_dedup_signature(["
            "'event_id' => 'event-1',"
            "'entity' => 'task',"
            "'action' => 'upsert',"
            "'payload' => ['id' => '1', 'title' => 'Корм']"
            "]);"
        )
        signature_b = _php_text(
            f"require '{TELEGRAM_OUTBOX_PATH}';"
            "echo build_telegram_dedup_signature(["
            "'event_id' => 'event-2',"
            "'entity' => 'task',"
            "'action' => 'upsert',"
            "'payload' => ['id' => '1', 'title' => 'Корм']"
            "]);"
        )
        self.assertEqual(signature_a, signature_b)

    @unittest.skipIf(shutil.which("php") is None, "php is not installed in test environment")
    def test_telegram_dedup_signature_changes_on_payload(self) -> None:
        signature_a = _php_text(
            f"require '{TELEGRAM_OUTBOX_PATH}';"
            "echo build_telegram_dedup_signature(['entity' => 'task', 'action' => 'upsert', 'payload' => ['id' => '1', 'title' => 'Корм']]);"
        )
        signature_b = _php_text(
            f"require '{TELEGRAM_OUTBOX_PATH}';"
            "echo build_telegram_dedup_signature(['entity' => 'task', 'action' => 'upsert', 'payload' => ['id' => '1', 'title' => 'Чтение']]);"
        )
        self.assertNotEqual(signature_a, signature_b)


if __name__ == "__main__":
    unittest.main()
