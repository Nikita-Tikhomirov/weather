import tempfile
import unittest
from pathlib import Path

import family_todo as ft


class BackendBridgeTests(unittest.TestCase):
    def setUp(self) -> None:
        self._orig_data_dir = ft.DATA_DIR
        self._orig_backend_url = ft.BACKEND_URL
        self._orig_backend_source = ft.BACKEND_SOURCE
        self._orig_backend_request = ft._backend_request
        self.tmp = tempfile.TemporaryDirectory()
        ft.DATA_DIR = Path(self.tmp.name) / "family_data_test"
        ft.BACKEND_URL = "https://example.test"
        ft.BACKEND_SOURCE = "telegram"
        ft.bootstrap_data()
        self.person = ft.PEOPLE[0]

    def tearDown(self) -> None:
        ft.DATA_DIR = self._orig_data_dir
        ft.BACKEND_URL = self._orig_backend_url
        ft.BACKEND_SOURCE = self._orig_backend_source
        ft._backend_request = self._orig_backend_request
        self.tmp.cleanup()

    def test_save_todos_pushes_snapshot_event(self) -> None:
        captured: list[tuple[str, str, dict | None]] = []

        def fake_request(method: str, path: str, payload: dict | None = None) -> dict:
            captured.append((method, path, payload))
            return {"ok": True}

        ft._backend_request = fake_request

        ft.save_todos(self.person, [{"id": 1, "title": "task", "text": "task"}])

        self.assertEqual(len(captured), 1)
        method, path, payload = captured[0]
        self.assertEqual(method, "POST")
        self.assertEqual(path, "/sync_push.php")
        self.assertEqual(payload["source"], "telegram")
        self.assertEqual(payload["actor_profile"], self.person.key)
        self.assertEqual(payload["events"][0]["action"], "replace_person_tasks")


if __name__ == "__main__":
    unittest.main()
