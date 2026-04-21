import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

import family_todo as ft


def main() -> int:
    ft.bootstrap_data()
    if not ft._backend_enabled():
        print("Backend sync disabled: configure sync_runtime.local.json or TODO_BACKEND_URL")
        return 1

    report = {"profiles": {}, "family_tasks": 0}
    for person in ft.PEOPLE:
        todos = ft.load_todos(person)
        ft.save_todos(person, todos, push_remote=True)
        report["profiles"][person.key] = len(todos)

    family_tasks = ft.load_family_tasks()
    ft.save_family_tasks(family_tasks, push_remote=True)
    report["family_tasks"] = len(family_tasks)

    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

