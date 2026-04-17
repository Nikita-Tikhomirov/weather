import json
from datetime import datetime
from pathlib import Path
from typing import Any

from todo_logger import log_exception


def read_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        log_exception("json_read_failed", exc, path=str(path))
        return default


def write_json(path: Path, data: Any) -> None:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    except Exception as exc:
        log_exception("json_write_failed", exc, path=str(path))


def person_dir(data_dir: Path, person_key: str) -> Path:
    return data_dir / person_key


def todos_path(data_dir: Path, person_key: str) -> Path:
    return person_dir(data_dir, person_key) / "todos.json"


def schedule_path(data_dir: Path, person_key: str) -> Path:
    return person_dir(data_dir, person_key) / "schedule.json"


def history_path(data_dir: Path, person_key: str) -> Path:
    return person_dir(data_dir, person_key) / "history.json"


def bootstrap_person_data(
    data_dir: Path,
    person_key: str,
    has_schedule: bool,
    schedule_default: dict[str, list[str]],
) -> None:
    pdir = person_dir(data_dir, person_key)
    pdir.mkdir(parents=True, exist_ok=True)
    tp = todos_path(data_dir, person_key)
    hp = history_path(data_dir, person_key)
    if not tp.exists():
        write_json(tp, [])
    if has_schedule:
        sp = schedule_path(data_dir, person_key)
        if not sp.exists():
            write_json(sp, schedule_default)
    if not hp.exists():
        write_json(hp, [])


def load_history(data_dir: Path, person_key: str) -> list[dict]:
    data = read_json(history_path(data_dir, person_key), [])
    return data if isinstance(data, list) else []


def save_history(data_dir: Path, person_key: str, history: list[dict]) -> None:
    write_json(history_path(data_dir, person_key), history[-30:])


def push_history(data_dir: Path, person_key: str, action: str, payload: dict) -> None:
    history = load_history(data_dir, person_key)
    history.append(
        {
            "action": action,
            "payload": payload,
            "created_at": datetime.now().isoformat(timespec="seconds"),
        }
    )
    save_history(data_dir, person_key, history)
