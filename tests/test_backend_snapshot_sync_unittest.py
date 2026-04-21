import tempfile
import unittest
from pathlib import Path

import family_todo as ft


class BackendSnapshotSyncTests(unittest.TestCase):
    def setUp(self) -> None:
        self._orig_data_dir = ft.DATA_DIR
        self._orig_backend_url = ft.BACKEND_URL
        self._orig_backend_pull_snapshot = ft._backend_pull_snapshot
        self.tmp = tempfile.TemporaryDirectory()
        ft.DATA_DIR = Path(self.tmp.name) / "family_data_test"
        ft.BACKEND_URL = "https://example.test"
        ft.bootstrap_data()

    def tearDown(self) -> None:
        ft.DATA_DIR = self._orig_data_dir
        ft.BACKEND_URL = self._orig_backend_url
        ft._backend_pull_snapshot = self._orig_backend_pull_snapshot
        self.tmp.cleanup()

    def test_pull_backend_snapshot_updates_profiles_and_family(self) -> None:
        ft._backend_pull_snapshot = lambda: {
            "tasks": [
                {"id": "1", "owner_key": "nik", "title": "Nik task", "updated_at": "2026-04-21T10:00:00"},
                {"id": "2", "owner_key": "misha", "title": "Misha task", "updated_at": "2026-04-21T10:00:00"},
            ],
            "family_tasks": [
                {"id": "f-1", "title": "Family", "updated_at": "2026-04-21T10:00:00"},
            ],
        }

        result = ft.pull_backend_snapshot_to_local()

        self.assertTrue(result["ok"])
        self.assertTrue(result["changed"])
        self.assertIn("nik", result["changed_profiles"])
        self.assertIn("misha", result["changed_profiles"])
        self.assertTrue(result["family_changed"])
        self.assertTrue(isinstance(result.get("events"), list))
        self.assertGreaterEqual(len(result.get("events", [])), 3)

        nik = next(p for p in ft.PEOPLE if p.key == "nik")
        misha = next(p for p in ft.PEOPLE if p.key == "misha")
        self.assertEqual(len(ft.read_json(ft.todos_path(nik), [])), 1)
        self.assertEqual(len(ft.read_json(ft.todos_path(misha), [])), 1)
        self.assertEqual(len(ft.read_json(ft.FAMILY_TASKS_PATH, [])), 1)


if __name__ == "__main__":
    unittest.main()
