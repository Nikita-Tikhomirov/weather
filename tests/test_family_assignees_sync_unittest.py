import tempfile
import unittest
from pathlib import Path

import family_todo as ft


class FamilyAssigneesSyncTests(unittest.TestCase):
    def setUp(self) -> None:
        self._orig_data_dir = ft.DATA_DIR
        self._orig_family_tasks_path = ft.FAMILY_TASKS_PATH
        self._orig_backend_url = ft.BACKEND_URL
        self._orig_backend_pull_snapshot = ft._backend_pull_snapshot
        self.tmp = tempfile.TemporaryDirectory()
        ft.DATA_DIR = Path(self.tmp.name) / "family_data_test"
        ft.FAMILY_TASKS_PATH = ft.DATA_DIR / "family_tasks.json"
        ft.BACKEND_URL = "https://example.test"
        ft.bootstrap_data()

    def tearDown(self) -> None:
        ft.DATA_DIR = self._orig_data_dir
        ft.FAMILY_TASKS_PATH = self._orig_family_tasks_path
        ft.BACKEND_URL = self._orig_backend_url
        ft._backend_pull_snapshot = self._orig_backend_pull_snapshot
        self.tmp.cleanup()

    def test_create_family_task_persists_assignees_and_legacy_participants(self) -> None:
        ok, error, created = ft.create_family_task(
            title="Семейная",
            details="детали",
            start_at="2026-04-21T19:00",
            duration_minutes=30,
            assignees=["nik", "misha"],
        )
        self.assertTrue(ok, error)
        self.assertIsNotNone(created)
        self.assertEqual(created.get("assignees"), ["misha", "nik"])
        self.assertEqual(created.get("participants"), ["misha", "nik"])

    def test_update_family_task_accepts_legacy_participants_payload(self) -> None:
        ok, error, created = ft.create_family_task(
            title="Семейная",
            details="детали",
            start_at="2026-04-21T19:00",
            duration_minutes=30,
            assignees=["nik"],
        )
        self.assertTrue(ok, error)
        updated_ok, updated_error, updated = ft.update_family_task(
            str(created.get("id") or ""),
            {"participants": ["nastya", "misha"], "start_at": "2026-04-21T20:00"},
        )
        self.assertTrue(updated_ok, updated_error)
        self.assertEqual(updated.get("assignees"), ["misha", "nastya"])
        self.assertEqual(updated.get("participants"), ["misha", "nastya"])

    def test_family_pull_applies_diff_and_removes_deleted_ids(self) -> None:
        ft.save_family_tasks(
            [
                {
                    "id": 1,
                    "title": "Локальная",
                    "text": "Локальная",
                    "details": "",
                    "due_date": "2026-04-21",
                    "time": "18:00",
                    "start_at": "2026-04-21T18:00",
                    "duration_minutes": 30,
                    "assignees": ["nik"],
                    "participants": ["nik"],
                    "is_family": True,
                    "workflow_status": "todo",
                    "updated_at": "2026-04-21T10:00:00",
                    "version": 1,
                }
            ],
            push_remote=False,
        )

        ft._backend_pull_snapshot = lambda: {
            "tasks": [],
            "family_tasks": [
                {
                    "id": "2",
                    "title": "Удаленная",
                    "due_date": "2026-04-21",
                    "time": "20:00",
                    "workflow_status": "todo",
                    "assignees": ["nastya"],
                    "updated_at": "2026-04-21T12:00:00",
                    "version": 2,
                }
            ],
        }

        result = ft.pull_backend_family_snapshot_to_local()
        self.assertTrue(result.get("ok"))
        self.assertTrue(result.get("changed"))
        self.assertTrue(result.get("family_changed"))
        items = ft.load_family_tasks(pull_remote=False)
        self.assertEqual(len(items), 1)
        self.assertEqual(str(items[0].get("id")), "2")
        self.assertEqual(items[0].get("assignees"), ["nastya"])


if __name__ == "__main__":
    unittest.main()
