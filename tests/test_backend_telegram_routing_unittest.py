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


if __name__ == "__main__":
    unittest.main()
