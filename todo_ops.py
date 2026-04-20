from __future__ import annotations

from datetime import datetime, timedelta


WORKFLOW_ORDER = ("todo", "in_progress", "in_review", "done")
WORKFLOW_SET = set(WORKFLOW_ORDER)


def ensure_workflow_status(todo: dict) -> str:
    status = str(todo.get("workflow_status") or "").strip()
    if status in WORKFLOW_SET:
        return status
    legacy_status = str(todo.get("status") or "")
    done_flag = bool(todo.get("done"))
    derived = "done" if legacy_status == "done" or done_flag else "todo"
    todo["workflow_status"] = derived
    return derived


def sync_legacy_fields(todo: dict, *, now_iso: str | None = None) -> None:
    workflow_status = ensure_workflow_status(todo)
    is_done = workflow_status == "done"
    todo["status"] = "done" if is_done else "active"
    todo["done"] = is_done
    if is_done:
        todo["done_at"] = todo.get("done_at") or now_iso or datetime.now().isoformat(timespec="seconds")
    else:
        todo["done_at"] = None


def transition_task(todo: dict, target_status: str, *, now_iso: str | None = None) -> None:
    if target_status not in WORKFLOW_SET:
        raise ValueError(f"Unsupported workflow status: {target_status}")
    todo["workflow_status"] = target_status
    sync_legacy_fields(todo, now_iso=now_iso)
    todo["updated_at"] = now_iso or datetime.now().isoformat(timespec="seconds")


def _ordered_items(todos: list[dict], status: str) -> list[dict]:
    return sorted(
        [t for t in todos if ensure_workflow_status(t) == status],
        key=lambda t: (int(t.get("sort_order") or 0), int(t.get("id") or 0)),
    )


def resequence_status(todos: list[dict], status: str) -> None:
    for idx, item in enumerate(_ordered_items(todos, status), start=1):
        item["sort_order"] = idx


def resequence_all(todos: list[dict]) -> None:
    for status in WORKFLOW_ORDER:
        resequence_status(todos, status)


def find_task_index_by_id(todos: list[dict], task_id: int) -> int | None:
    for idx, item in enumerate(todos):
        if int(item.get("id") or 0) == task_id:
            return idx
    return None


def delete_task_by_id(todos: list[dict], task_id: int) -> dict | None:
    idx = find_task_index_by_id(todos, task_id)
    if idx is None:
        return None
    removed = todos.pop(idx)
    resequence_all(todos)
    return removed


def move_task(
    todos: list[dict],
    task_id: int,
    target_status: str,
    *,
    target_index: int | None = None,
    now_iso: str | None = None,
) -> bool:
    if target_status not in WORKFLOW_SET:
        return False

    source_idx = find_task_index_by_id(todos, task_id)
    if source_idx is None:
        return False

    moving = todos[source_idx]
    current_status = ensure_workflow_status(moving)

    # Build target bucket without moved item.
    target_items = [t for t in _ordered_items(todos, target_status) if int(t.get("id") or 0) != task_id]
    insert_at = len(target_items) if target_index is None else max(0, min(target_index, len(target_items)))
    target_items.insert(insert_at, moving)

    transition_task(moving, target_status, now_iso=now_iso)

    # Reassign orders in target bucket.
    for idx, item in enumerate(target_items, start=1):
        item["sort_order"] = idx

    # Keep source bucket contiguous when moving across columns.
    if current_status != target_status:
        resequence_status(todos, current_status)
    else:
        for idx, item in enumerate(target_items, start=1):
            item["sort_order"] = idx

    return True


def parse_iso_datetime(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value))
    except ValueError:
        return None


def compute_interval(start_at: str | None, duration_minutes: int | None) -> tuple[datetime, datetime] | None:
    start = parse_iso_datetime(start_at)
    if start is None:
        return None
    duration = max(0, int(duration_minutes or 0))
    return start, start + timedelta(minutes=duration)


def intervals_overlap(left: tuple[datetime, datetime], right: tuple[datetime, datetime]) -> bool:
    return left[0] < right[1] and right[0] < left[1]

