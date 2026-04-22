import shutil
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PUSH_OUTBOX_PATH = (ROOT / "backend_api" / "src" / "push_outbox.php").as_posix()
TELEGRAM_OUTBOX_PATH = (ROOT / "backend_api" / "src" / "telegram_outbox.php").as_posix()


def _php(script: str) -> str:
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


def _php_has_sqlite() -> bool:
    if shutil.which("php") is None:
        return False
    completed = subprocess.run(
        ["php", "-m"],
        cwd=str(ROOT),
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        return False
    modules = {line.strip().lower() for line in completed.stdout.splitlines()}
    return "pdo_sqlite" in modules and "sqlite3" in modules


class BackendDedupWindowTests(unittest.TestCase):
    @unittest.skipIf(shutil.which("php") is None, "php is not installed in test environment")
    @unittest.skipUnless(_php_has_sqlite(), "php sqlite extensions are not installed")
    def test_push_dedup_detects_recent_duplicate(self) -> None:
        result = _php(
            f"require '{PUSH_OUTBOX_PATH}';"
            "$db = new PDO('sqlite::memory:');"
            "$db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);"
            "$db->exec(\"CREATE TABLE push_outbox (id INTEGER PRIMARY KEY AUTOINCREMENT, profile_key TEXT, token TEXT, data_json TEXT, status TEXT, created_at TEXT)\");"
            "$signature = 'sig-123';"
            "$payload = json_encode(['dedup_signature' => $signature]);"
            "$stmt = $db->prepare('INSERT INTO push_outbox (profile_key, token, data_json, status, created_at) VALUES (?, ?, ?, ?, ?)');"
            "$stmt->execute(['nik', 'tok', $payload, 'sent', '2026-04-22T10:00:00']);"
            "$ok = has_recent_push_signature($db, 'nik', 'tok', $signature, '2026-04-22T09:59:00', null, true);"
            "echo $ok ? '1' : '0';"
        )
        self.assertEqual(result, "1")

    @unittest.skipIf(shutil.which("php") is None, "php is not installed in test environment")
    @unittest.skipUnless(_php_has_sqlite(), "php sqlite extensions are not installed")
    def test_telegram_dedup_detects_recent_duplicate(self) -> None:
        result = _php(
            f"require '{TELEGRAM_OUTBOX_PATH}';"
            "$db = new PDO('sqlite::memory:');"
            "$db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);"
            "$db->exec(\"CREATE TABLE telegram_outbox (id INTEGER PRIMARY KEY AUTOINCREMENT, payload_json TEXT, status TEXT, created_at TEXT)\");"
            "$signature = 'tg-sig-123';"
            "$payload = json_encode(['dedup_signature' => $signature]);"
            "$stmt = $db->prepare('INSERT INTO telegram_outbox (payload_json, status, created_at) VALUES (?, ?, ?)');"
            "$stmt->execute([$payload, 'sent', '2026-04-22T10:00:00']);"
            "$ok = has_recent_telegram_signature($db, $signature, '2026-04-22T09:59:00', null, true);"
            "echo $ok ? '1' : '0';"
        )
        self.assertEqual(result, "1")


if __name__ == "__main__":
    unittest.main()
