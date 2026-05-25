import json
import html
import subprocess
import threading
from contextlib import contextmanager
from pathlib import Path
from typing import Callable


BASE_DIR = Path(__file__).resolve().parent
NIRCMD_PATH = BASE_DIR / "nircmd.exe"
_MESSAGE_LISTENERS: list[Callable[[str], None]] = []
_CTX = threading.local()

_TRACKED_EVENTS = {
    "todo_add",
    "todo_delete",
    "todo_clear_all",
    "todo_clear_day",
    "todo_delete_keyword",
    "todo_move",
    "todo_done",
    "todo_update",
    "todo_undo",
    "schedule_add",
    "schedule_remove",
}

_EVENT_LABELS = {
    "todo_add": "Добавлена задача",
    "todo_delete": "Удалена задача",
    "todo_clear_all": "Очищены все задачи",
    "todo_clear_day": "Очищены задачи на день",
    "todo_delete_keyword": "Удалены задачи по фильтру",
    "todo_move": "Задача перенесена",
    "todo_done": "Задача отмечена выполненной",
    "todo_update": "Задача изменена",
    "todo_undo": "Выполнен откат последнего изменения",
    "schedule_add": "В расписание добавлен пункт",
    "schedule_remove": "Из расписания удален пункт",
}

_FIELD_LABELS = {
    "person": "Профиль",
    "actor": "Кто изменил",
    "day": "День",
    "time": "Время",
    "title": "Задача",
    "notes": "Детали",
    "count": "Количество",
    "recurrence": "Повтор",
    "mode": "Режим",
    "id": "ID",
    "index": "Номер",
    "source_day": "Откуда",
    "target_day": "Куда",
    "target_time": "Новое время",
    "removed": "Удалено",
    "keyword": "Ключевое слово",
    "action": "Действие",
    "restored": "Восстановлено",
}


def _format_field_value(value: object) -> str:
    if isinstance(value, bool):
        return "да" if value else "нет"
    if value is None:
        return ""
    if isinstance(value, (dict, list, tuple)):
        try:
            return json.dumps(value, ensure_ascii=False)
        except Exception:
            return str(value)
    return str(value)


def _field_label(key: str) -> str:
    return _FIELD_LABELS.get(key, key.replace("_", " ").capitalize())


def _priority_for_field(key: str) -> int:
    order = {
        "title": 0,
        "time": 1,
        "day": 2,
        "person": 3,
        "actor": 4,
        "target_day": 5,
        "target_time": 6,
        "source_day": 7,
        "notes": 8,
    }
    return order.get(key, 100)


def _split_lines_for_toast(lines: list[str], max_lines: int = 4) -> list[list[str]]:
    if not lines:
        return []
    chunks: list[list[str]] = []
    for idx in range(0, len(lines), max_lines):
        chunks.append(lines[idx : idx + max_lines])
    return chunks


@contextmanager
def event_actor(actor_key: str | None):
    previous = getattr(_CTX, "actor", None)
    _CTX.actor = actor_key
    try:
        yield
    finally:
        _CTX.actor = previous


def current_actor() -> str | None:
    actor = getattr(_CTX, "actor", None)
    if isinstance(actor, str) and actor:
        return actor
    return None


def register_message_listener(listener: Callable[[str], None]) -> None:
    if listener not in _MESSAGE_LISTENERS:
        _MESSAGE_LISTENERS.append(listener)


def unregister_message_listener(listener: Callable[[str], None]) -> None:
    if listener in _MESSAGE_LISTENERS:
        _MESSAGE_LISTENERS.remove(listener)


def _notify_listeners(text: str) -> None:
    for listener in list(_MESSAGE_LISTENERS):
        try:
            listener(text)
        except Exception:
            continue


def _windows_toast(title: str, message: str) -> bool:
    escaped_title = html.escape(title)
    escaped_message = html.escape(message)
    script = f"""
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] > $null
$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
$xml.LoadXml("<toast><visual><binding template='ToastGeneric'><text>{escaped_title}</text><text>{escaped_message}</text></binding></visual></toast>")
$toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Microsoft.Windows.Explorer').Show($toast)
""".strip()
    try:
        completed = subprocess.run(
            ["powershell", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", script],
            capture_output=True,
            text=True,
            timeout=6,
            check=False,
        )
        return completed.returncode == 0 and "Exception" not in (completed.stderr or "")
    except Exception:
        return False


def _nircmd_balloon(title: str, message: str) -> bool:
    if not NIRCMD_PATH.exists():
        return False
    try:
        completed = subprocess.run(
            [str(NIRCMD_PATH), "trayballoon", title, message, "2500"],
            capture_output=True,
            timeout=4,
            check=False,
        )
        return completed.returncode == 0
    except Exception:
        return False


def desktop_notify(message: str, title: str = "Семейный ассистент") -> None:
    body = (message or "").strip()
    if not body:
        return
    # Передаем максимально полный текст в Windows toast.
    if _windows_toast(title, body):
        return
    _nircmd_balloon(title, body)


def emit_assistant_message(text: str) -> None:
    clipped = (text or "").strip()
    if not clipped:
        return
    _notify_listeners(clipped)
    desktop_notify(clipped)


def notify_event(event: str, **fields: object) -> None:
    if event not in _TRACKED_EVENTS:
        return

    event_label = _EVENT_LABELS.get(event, event)
    owner = str(fields.get("person") or "")
    actor = str(fields.get("actor") or current_actor() or owner or "система")

    normalized_fields = dict(fields)
    normalized_fields["person"] = owner or normalized_fields.get("person") or "неизвестно"
    normalized_fields["actor"] = actor

    rendered_items: list[tuple[str, str]] = []
    for key, value in normalized_fields.items():
        rendered = _format_field_value(value).strip()
        if not rendered:
            continue
        rendered_items.append((key, f"{_field_label(key)}: {rendered}"))

    rendered_items.sort(key=lambda kv: (_priority_for_field(kv[0]), kv[0]))
    detail_lines = [text for _, text in rendered_items]
    all_lines = [f"Изменение расписания: {event_label}", *detail_lines]
    toast_chunks = _split_lines_for_toast(all_lines, max_lines=4)

    if toast_chunks:
        desktop_notify("\n".join(toast_chunks[0]), title="Семейное расписание")
        if len(toast_chunks) > 1:
            desktop_notify("\n".join(toast_chunks[1]), title="Семейное расписание (подробно)")
    else:
        desktop_notify(f"Изменение расписания: {event_label}", title="Семейное расписание")

    # Telegram delivery has been removed. Push notifications are handled
    # by the backend (FCM) and desktop toasts only.
