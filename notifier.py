import json
import html
import os
import subprocess
import threading
from contextlib import contextmanager
from pathlib import Path
from typing import Callable

import requests


BASE_DIR = Path(__file__).resolve().parent
NIRCMD_PATH = BASE_DIR / "nircmd.exe"
TELEGRAM_STATE_PATH = BASE_DIR / "family_data" / "telegram_state.json"

ADULTS = {"nik", "nastya"}
CHILDREN = {"misha", "arisha"}

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


def _telegram_token() -> str:
    return os.getenv("TELEGRAM_BOT_TOKEN", "").strip()


def family_chat_ids() -> list[int]:
    raw = os.getenv("TELEGRAM_FAMILY_CHAT_IDS", "").strip()
    if not raw:
        return []
    out: list[int] = []
    for part in raw.split(","):
        part = part.strip()
        if not part:
            continue
        try:
            out.append(int(part))
        except ValueError:
            continue
    return out


def _load_state() -> dict:
    if not TELEGRAM_STATE_PATH.exists():
        return {}
    try:
        return json.loads(TELEGRAM_STATE_PATH.read_text(encoding="utf-8"))
    except Exception:
        return {}


def _identity_chat_map() -> dict[str, list[int]]:
    state = _load_state()
    raw = state.get("chat_identity", {})
    result: dict[str, list[int]] = {}
    if not isinstance(raw, dict):
        return result
    for chat_id_raw, identity in raw.items():
        if not isinstance(identity, str) or not identity:
            continue
        chat_id: int | None = None
        if isinstance(chat_id_raw, int):
            chat_id = chat_id_raw
        elif isinstance(chat_id_raw, str) and chat_id_raw.strip().lstrip("-").isdigit():
            chat_id = int(chat_id_raw.strip())
        if chat_id is None:
            continue
        result.setdefault(identity, []).append(chat_id)
    return result


def _recipients_for_owner(owner: str) -> set[str]:
    if owner in ADULTS or owner in CHILDREN:
        return {owner}
    return set()


def telegram_api(method: str) -> str:
    token = _telegram_token()
    if not token:
        raise RuntimeError("TELEGRAM_BOT_TOKEN не задан")
    return f"https://api.telegram.org/bot{token}/{method}"


def send_telegram_message(
    chat_id: int,
    text: str,
    *,
    disable_notification: bool = False,
    reply_markup: dict | None = None,
) -> bool:
    token = _telegram_token()
    if not token:
        return False
    payload: dict[str, object] = {
        "chat_id": chat_id,
        "text": text,
        "disable_notification": disable_notification,
    }
    if reply_markup:
        payload["reply_markup"] = reply_markup
    try:
        requests.post(telegram_api("sendMessage"), json=payload, timeout=12)
        return True
    except Exception:
        return False


def push_to_family(text: str, *, disable_notification: bool = False) -> None:
    for chat_id in family_chat_ids():
        send_telegram_message(chat_id, text, disable_notification=disable_notification)


def push_by_visibility(owner: str, text: str, *, disable_notification: bool = False) -> None:
    mapping = _identity_chat_map()
    identities = _recipients_for_owner(owner)
    if not identities:
        return

    chat_ids: set[int] = set()
    for identity in identities:
        for cid in mapping.get(identity, []):
            chat_ids.add(cid)

    if not chat_ids:
        # fallback for first setup if identity mapping is not configured yet
        chat_ids.update(family_chat_ids())

    for chat_id in sorted(chat_ids):
        send_telegram_message(chat_id, text, disable_notification=disable_notification)


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

    message = "\n".join(all_lines)
    if owner:
        push_by_visibility(owner, message)
    else:
        push_to_family(message)
