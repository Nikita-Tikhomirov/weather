import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path

import family_todo as ft


def _silent(*_args, **_kwargs) -> None:
    return None


class FamilyTodoTests(unittest.TestCase):
    def setUp(self) -> None:
        self._orig_data_dir = ft.DATA_DIR
        self._orig_speak = ft.speak
        self.tmp = tempfile.TemporaryDirectory()
        ft.DATA_DIR = Path(self.tmp.name) / "family_data_test"
        ft.speak = _silent
        ft.bootstrap_data()
        self.person = ft.PEOPLE[0]

    def tearDown(self) -> None:
        ft.DATA_DIR = self._orig_data_dir
        ft.speak = self._orig_speak
        self.tmp.cleanup()

    def test_parse_day_and_time(self) -> None:
        self.assertEqual(ft.parse_day("список на вторник"), "вторник")
        self.assertEqual(ft.parse_time("19 30"), "19:30")
        self.assertEqual(ft.extract_time_from_inline("перенеси на среду в 21 10"), "21:10")

    def test_parse_explicit_index(self) -> None:
        self.assertEqual(ft.parse_explicit_index("перенеси номер 2 на среду в 19 30"), 2)
        self.assertIsNone(ft.parse_explicit_index("перенеси вторник кормить крыс на среду в 19 30"))

    def test_add_recurring_single_record(self) -> None:
        ft.add_todo(self.person, "добавь каждый день в 19 30 кормить крыс")
        todos = ft.load_todos(self.person)
        recurring = [t for t in todos if (t.get("recurrence_rule") or t.get("recurring")) == "daily"]
        self.assertGreaterEqual(len(recurring), 1)
        series_ids = {t.get("series_id") for t in recurring}
        self.assertEqual(len(series_ids), 1)

    def test_move_by_title_without_index(self) -> None:
        ft.add_todo(self.person, "добавь во вторник в 19 30 кормить крыс")
        ft.move_todo(self.person, "перенеси вторник кормить крыс на среду в 20 15")
        todos = ft.load_todos(self.person)
        self.assertTrue(any(t.get("day") == "среда" and t.get("time") == "20:15" for t in todos))

    def test_delete_done_undo(self) -> None:
        ft.add_todo(self.person, "добавь во вторник в 19 30 кормить крыс")
        ft.delete_todo(self.person, "удали вторник кормить крыс")
        self.assertEqual(len(ft.load_todos(self.person)), 0)
        ft.undo_last_action(self.person)
        self.assertEqual(len(ft.load_todos(self.person)), 1)
        ft.mark_done(self.person, "отметь вторник номер 1")
        self.assertTrue(ft.load_todos(self.person)[0].get("done"))

    def test_family_conflict_window_blocks_assignee_one_hour_before_and_during(self) -> None:
        start_dt = (datetime.now() + timedelta(days=1)).replace(hour=19, minute=0, second=0, microsecond=0)
        ok, error, _created = ft.create_family_task(
            title="Family slot",
            details="",
            start_at=start_dt.isoformat(timespec="minutes"),
            duration_minutes=90,
            assignees=["nik"],
        )
        self.assertTrue(ok, error)

        same_day = start_dt.date().isoformat()
        one_hour_before_conflicts = ft.family_conflicts_for_person("nik", same_day, "18:20")
        during_conflicts = ft.family_conflicts_for_person("nik", same_day, "19:45")
        before_window_conflicts = ft.family_conflicts_for_person("nik", same_day, "17:30")
        other_person_conflicts = ft.family_conflicts_for_person("arisha", same_day, "19:45")

        self.assertTrue(one_hour_before_conflicts)
        self.assertTrue(during_conflicts)
        self.assertFalse(before_window_conflicts)
        self.assertFalse(other_person_conflicts)


if __name__ == "__main__":
    unittest.main()
