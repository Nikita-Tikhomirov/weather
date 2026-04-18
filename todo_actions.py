from datetime import datetime


def apply_move(todo: dict, target_day: str, target_time: str) -> dict:
    todo["day"] = target_day
    todo["time"] = target_time
    todo["recurrence_rule"] = None
    todo["status"] = "active"
    todo["done"] = False
    todo["done_at"] = None
    todo["updated_at"] = datetime.now().isoformat(timespec="seconds")
    return todo
