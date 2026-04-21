import tempfile
import unittest
from pathlib import Path

import family_todo as ft


class TaskContractRoundTripTests(unittest.TestCase):
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

    def test_personal_round_trip_keeps_required_fields(self) -> None:
        nik = next(person for person in ft.PEOPLE if person.key == "nik")
        payload = [
            {
                "id": "101",
                "owner_key": "wrong-owner",
                "is_family": True,
                "title": "Personal item",
                "details": "Test",
                "due_date": "2026-04-22",
                "time": "10:00",
                "workflow_status": "todo",
                "updated_at": "2026-04-22T10:00:00",
                "version": 7,
            }
        ]

        ft.save_todos(nik, payload, push_remote=False)
        first = ft.read_json(ft.todos_path(nik), [])
        self.assertEqual(len(first), 1)
        self.assertEqual(first[0].get("owner_key"), "nik")
        self.assertEqual(bool(first[0].get("is_family")), False)
        self.assertEqual(first[0].get("updated_at"), "2026-04-22T10:00:00")
        self.assertEqual(int(first[0].get("version") or 0), 7)

        ft.save_todos(nik, first, push_remote=False)
        second = ft.read_json(ft.todos_path(nik), [])
        self.assertEqual(second[0].get("updated_at"), first[0].get("updated_at"))
        self.assertEqual(int(second[0].get("version") or 0), int(first[0].get("version") or 0))

    def test_family_round_trip_keeps_required_fields(self) -> None:
        payload = [
            {
                "id": "f-101",
                "owner_key": "nik",
                "is_family": False,
                "title": "Family item",
                "details": "Family details",
                "due_date": "2026-04-22",
                "time": "18:30",
                "start_at": "2026-04-22T18:30",
                "workflow_status": "in_progress",
                "assignees": ["nik", "misha"],
                "updated_at": "2026-04-22T18:30:00",
                "version": 5,
            }
        ]

        ft.save_family_tasks(payload, push_remote=False)
        first = ft.read_json(ft.FAMILY_TASKS_PATH, [])
        self.assertEqual(len(first), 1)
        self.assertEqual(first[0].get("owner_key"), "family")
        self.assertEqual(bool(first[0].get("is_family")), True)
        self.assertEqual(first[0].get("updated_at"), "2026-04-22T18:30:00")
        self.assertEqual(int(first[0].get("version") or 0), 5)

        ft.save_family_tasks(first, push_remote=False)
        second = ft.read_json(ft.FAMILY_TASKS_PATH, [])
        self.assertEqual(second[0].get("updated_at"), first[0].get("updated_at"))
        self.assertEqual(int(second[0].get("version") or 0), int(first[0].get("version") or 0))

    def test_delta_pull_same_payload_does_not_report_changed(self) -> None:
        base_payload = {
            "tasks": [
                {
                    "id": "12",
                    "owner_key": "nik",
                    "is_family": False,
                    "title": "Nik task",
                    "updated_at": "2026-04-22T08:00:00",
                    "version": 3,
                }
            ],
            "family_tasks": [
                {
                    "id": "f-12",
                    "owner_key": "family",
                    "is_family": True,
                    "title": "Family task",
                    "updated_at": "2026-04-22T09:00:00",
                    "version": 4,
                    "assignees": ["nik"],
                }
            ],
            "next_cursor": "2026-04-22T09:00:00",
        }
        ft._backend_pull_snapshot = lambda **_kwargs: base_payload
        first = ft.pull_backend_snapshot_to_local()
        second = ft.pull_backend_changes_since_cursor("2026-04-22T09:00:00")

        self.assertTrue(first.get("changed"))
        self.assertFalse(second.get("changed"))


if __name__ == "__main__":
    unittest.main()
