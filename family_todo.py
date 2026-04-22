import json
import re
import urllib.error
import urllib.parse
import urllib.request
import uuid
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from difflib import SequenceMatcher
from pathlib import Path

from audio import listen_speech
from config import SETTINGS
from sync_runtime import get_sync_runtime
from todo_actions import apply_move
from todo_logger import log_event, log_exception
from todo_ops import (
    WORKFLOW_SET,
    compute_interval,
    ensure_workflow_status,
    intervals_overlap,
    move_task,
    parse_iso_datetime,
    transition_task,
)
from todo_parsing import has_all_parts, token_overlap_score
from todo_reminders import seconds_until
from todo_router import resolve_action
import todo_storage as st
from tts import speak

try:
    import winsound
except Exception:  # pragma: no cover
    winsound = None


BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "family_data"
FAMILY_TASKS_PATH = DATA_DIR / "family_tasks.json"
# Backward-compatible runtime overrides used in tests/manual runs.
BACKEND_URL = ""
BACKEND_API_KEY = ""
BACKEND_SOURCE = ""
_BACKEND_LAST_ERROR: dict[str, str] = {}


def _set_backend_last_error(kind: str, message: str) -> None:
    _BACKEND_LAST_ERROR["kind"] = str(kind or "").strip()
    _BACKEND_LAST_ERROR["message"] = str(message or "").strip()


def _clear_backend_last_error() -> None:
    _BACKEND_LAST_ERROR.clear()


@dataclass(frozen=True)
class Person:
    key: str
    display_name: str
    aliases: tuple[str, ...]
    has_schedule: bool = False


PEOPLE: tuple[Person, ...] = (
    Person("nik", "Ник", ("ник", "я", "никита"), has_schedule=True),
    Person("misha", "Миша", ("миша", "сын", "михаил"), has_schedule=True),
    Person("nastya", "Настя", ("настя", "жена", "анастасия"), has_schedule=True),
    Person("arisha", "Ариша", ("ариша", "арина", "дочь"), has_schedule=True),
)

STOP_PHRASES = ("стоп", "выход", "хватит", "заверши", "закончи", "пока")
SWITCH_PERSON_PHRASES = (
    "сменить человека",
    "другой человек",
    "другой пользователь",
    "выбрать другого",
)
NO_TIME_PHRASES = ("без времени", "время не нужно", "не нужно время", "без часа")

DAY_ALIASES = {
    "понедельник": ("понедельник", "понедельника", "пн"),
    "вторник": ("вторник", "вторника", "вт"),
    "среда": ("среда", "среду", "среды", "ср"),
    "четверг": ("четверг", "четверга", "чт"),
    "пятница": ("пятница", "пятницу", "пятницы", "пт"),
    "суббота": ("суббота", "субботу", "субботы", "сб"),
    "воскресенье": ("воскресенье", "воскресенья", "воскресенью", "вс"),
}
DAY_ORDER = ("понедельник", "вторник", "среда", "четверг", "пятница", "суббота", "воскресенье")
WORKFLOW_STATUSES = WORKFLOW_SET
ADD_PREFIXES = ("добавь", "добавить", "запиши", "создай", "новое дело")
PRIORITY_ALIASES = {
    "high": ("важно", "срочно", "приоритет высокий", "высокий приоритет"),
    "medium": ("обычно", "средний приоритет", "не срочно"),
    "low": ("потом", "низкий приоритет", "неважно"),
}
RECURRING_ALIASES = {
    "daily": ("каждый день", "ежедневно"),
    "weekdays": ("каждый будний день", "по будням", "будни"),
}
DEFAULT_REMINDER_OFFSETS = [60, 30, 10]
QUIET_CONFIRMATIONS = True
RECURRENCE_HORIZON_DAYS = 30
TAG_ALIASES = {
    "дом": ("дом", "домашнее", "быт"),
    "работа": ("работа", "рабочее"),
    "школа": ("школа", "уроки", "учеба"),
    "здоровье": ("здоровье", "врач", "лекарства", "спорт"),
}

SCHEDULE_DEFAULT = {
    "понедельник": ["Математика", "Русский язык", "Литература", "Английский", "Окружающий мир", "Физкультура"],
    "вторник": ["Русский язык", "Математика", "Информатика", "История", "Музыка", "Английский"],
    "среда": ["Математика", "Русский язык", "Биология", "Литература", "Технология", "Физкультура"],
    "четверг": ["Английский", "Математика", "География", "Русский язык", "Обществознание", "ИЗО"],
    "пятница": ["Русский язык", "Математика", "Литература", "Информатика", "Биология", "Физкультура"],
    "суббота": ["Английский", "Русский язык", "Математика", "История", "Проект", "Музыка"],
    "воскресенье": ["Чтение", "Логика", "Творчество", "Английский", "Окружающий мир", "Спорт"],
}

NUM_WORDS = {
    "ноль": 0,
    "один": 1,
    "одна": 1,
    "первый": 1,
    "первая": 1,
    "первое": 1,
    "два": 2,
    "две": 2,
    "второй": 2,
    "вторая": 2,
    "второе": 2,
    "три": 3,
    "третий": 3,
    "третья": 3,
    "третье": 3,
    "четыре": 4,
    "четвертый": 4,
    "четвертая": 4,
    "четвертое": 4,
    "пять": 5,
    "пятый": 5,
    "пятая": 5,
    "пятое": 5,
    "шесть": 6,
    "седьмой": 7,
    "семь": 7,
    "седьмое": 7,
    "восемь": 8,
    "восьмое": 8,
    "девять": 9,
    "девятое": 9,
    "десять": 10,
    "десятое": 10,
    "одиннадцать": 11,
    "двенадцать": 12,
    "тринадцать": 13,
    "четырнадцать": 14,
    "пятнадцать": 15,
    "шестнадцать": 16,
    "семнадцать": 17,
    "восемнадцать": 18,
    "девятнадцать": 19,
    "двадцать": 20,
    "тридцать": 30,
    "сорок": 40,
    "пятьдесят": 50,
}

HALF_NEXT_HOUR = {
    "первого": 1,
    "второго": 2,
    "третьего": 3,
    "четвертого": 4,
    "пятого": 5,
    "шестого": 6,
    "седьмого": 7,
    "восьмого": 8,
    "девятого": 9,
    "десятого": 10,
    "одиннадцатого": 11,
    "двенадцатого": 12,
}


def normalize_text(text: str) -> str:
    cleaned = re.sub(r"[^а-яё0-9:\s-]", " ", text.lower())
    cleaned = cleaned.replace("ё", "е")
    return " ".join(cleaned.split())


def confirm(message: str = "Готово.") -> None:
    speak("Готово." if QUIET_CONFIRMATIONS else message)


def similarity(a: str, b: str) -> float:
    return SequenceMatcher(None, a, b).ratio()


def contains_phrase(text: str, phrase: str) -> bool:
    norm_text = normalize_text(text)
    norm_phrase = normalize_text(phrase)
    if not norm_text or not norm_phrase:
        return False

    if norm_phrase == norm_text:
        return True

    text_words = norm_text.split()
    phrase_words = norm_phrase.split()

    if len(phrase_words) == 1:
        target = phrase_words[0]
        for word in text_words:
            if word == target or similarity(word, target) >= 0.8:
                return True
        return False

    # For phrases, allow small ASR deviations: each phrase word should match some text word.
    for pword in phrase_words:
        matched = False
        for word in text_words:
            if word == pword or similarity(word, pword) >= 0.78:
                matched = True
                break
        if not matched:
            return False
    return True


def detect_stop(text: str | None) -> bool:
    if not text:
        return False
    return any(contains_phrase(text, phrase) for phrase in STOP_PHRASES)


def detect_switch_person(text: str | None) -> bool:
    if not text:
        return False
    return any(contains_phrase(text, phrase) for phrase in SWITCH_PERSON_PHRASES)


def read_json(path: Path, default: object) -> object:
    return st.read_json(path, default)


def write_json(path: Path, data: object) -> None:
    st.write_json(path, data)


def person_dir(person: Person) -> Path:
    return st.person_dir(DATA_DIR, person.key)


def todos_path(person: Person) -> Path:
    return st.todos_path(DATA_DIR, person.key)


def schedule_path(person: Person) -> Path:
    return st.schedule_path(DATA_DIR, person.key)


def history_path(person: Person) -> Path:
    return st.history_path(DATA_DIR, person.key)


def ui_settings_path(person: Person) -> Path:
    return person_dir(person) / "ui_settings.json"


def load_ui_settings(person: Person) -> dict:
    raw = read_json(ui_settings_path(person), {})
    return raw if isinstance(raw, dict) else {}


def save_ui_settings(person: Person, settings: dict) -> None:
    write_json(ui_settings_path(person), settings)


def bootstrap_data() -> None:
    DATA_DIR.mkdir(exist_ok=True)
    for person in PEOPLE:
        st.bootstrap_person_data(
            data_dir=DATA_DIR,
            person_key=person.key,
            has_schedule=person.has_schedule,
            schedule_default=SCHEDULE_DEFAULT,
        )


def person_by_key(person_key: str) -> Person | None:
    for person in PEOPLE:
        if person.key == person_key:
            return person
    return None


def _backend_enabled() -> bool:
    runtime = _backend_runtime()
    return bool(runtime["backend_url"])


def _backend_runtime(default_source: str = "desktop") -> dict:
    runtime = get_sync_runtime(default_source=default_source)
    backend_url = str(BACKEND_URL or runtime["backend_url"]).strip().rstrip("/")
    backend_api_key = str(BACKEND_API_KEY or runtime["backend_api_key"]).strip()
    backend_source = str(BACKEND_SOURCE or runtime["backend_source"]).strip() or default_source
    return {
        "backend_url": backend_url,
        "backend_api_key": backend_api_key,
        "backend_source": backend_source,
    }


def _backend_request(
    method: str,
    path: str,
    payload: dict | None = None,
    *,
    raise_on_error: bool = False,
) -> dict | None:
    if not _backend_enabled():
        return None
    _clear_backend_last_error()
    runtime = _backend_runtime(default_source="desktop")
    base_url = runtime["backend_url"]
    api_key = runtime["backend_api_key"]
    url = f"{base_url}{path}"
    body = None
    headers = {"Content-Type": "application/json; charset=utf-8"}
    if api_key:
        headers["X-Api-Key"] = api_key
    if payload is not None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(url, data=body, method=method.upper(), headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            raw = resp.read().decode("utf-8")
            parsed = json.loads(raw) if raw else {}
            _clear_backend_last_error()
            return parsed if isinstance(parsed, dict) else None
    except urllib.error.HTTPError as exc:
        response_body = ""
        try:
            response_body = exc.read().decode("utf-8", errors="replace")[:400]
        except Exception:
            response_body = "<unavailable>"
        log_exception(
            "backend_http_error",
            exc,
            method=method.upper(),
            url=url,
            status=getattr(exc, "code", None),
            response=response_body,
        )
        status_code = int(getattr(exc, "code", 0) or 0)
        response_lc = response_body.lower()
        if status_code == 500 and "sqlstate[hy000] [1045]" in response_lc:
            _set_backend_last_error("sync_backend_db_error", response_body)
        else:
            _set_backend_last_error("backend_http_error", response_body or str(exc))
        if raise_on_error:
            raise
        return None
    except (urllib.error.URLError, TimeoutError, ValueError) as exc:
        log_exception(
            "backend_request_failed",
            exc if isinstance(exc, Exception) else Exception(str(exc)),
            method=method.upper(),
            url=url,
        )
        if isinstance(exc, TimeoutError):
            _set_backend_last_error("backend_timeout", str(exc))
        else:
            _set_backend_last_error("backend_request_failed", str(exc))
        if raise_on_error:
            raise
        return None


def _backend_pull_snapshot(
    *,
    since: str = "1970-01-01T00:00:00",
    cursor: str | None = None,
) -> dict | None:
    query_payload = {"since": since}
    if cursor:
        query_payload["cursor"] = cursor
        query_payload["mode"] = "changes"
    query = urllib.parse.urlencode(query_payload)
    paths = [f"/sync_pull.php?{query}", f"/sync/pull?{query}"]
    if cursor:
        paths = [f"/sync_changes.php?{query}", f"/sync/changes?{query}", *paths]
    preferred_error: dict[str, str] | None = None
    for path in paths:
        response = _backend_request("GET", path)
        if isinstance(response, dict):
            return response
        if str(_BACKEND_LAST_ERROR.get("kind") or "") == "sync_backend_db_error":
            preferred_error = {
                "kind": "sync_backend_db_error",
                "message": str(_BACKEND_LAST_ERROR.get("message") or ""),
            }
    if preferred_error is not None:
        _BACKEND_LAST_ERROR.clear()
        _BACKEND_LAST_ERROR.update(preferred_error)
    return None


def _canonical_person_task(item: dict) -> dict:
    return {
        "id": str(item.get("id") or ""),
        "owner_key": str(item.get("owner_key") or ""),
        "is_family": False,
        "title": str(item.get("title") or item.get("text") or ""),
        "details": str(item.get("details") or ""),
        "due_date": str(item.get("due_date") or ""),
        "time": str(item.get("time") or ""),
        "workflow_status": str(item.get("workflow_status") or "todo"),
        "priority": str(item.get("priority") or "medium"),
        "tags": sorted([str(tag) for tag in item.get("tags", []) if isinstance(tag, (str, int, float))]),
        "participants": sorted([str(p) for p in item.get("participants", []) if isinstance(p, (str, int, float))]),
        "duration_minutes": int(item.get("duration_minutes") or 0),
        "updated_at": str(item.get("updated_at") or ""),
        "version": int(item.get("version") or 1),
    }


def _canonical_family_task(item: dict) -> dict:
    due_date = str(item.get("due_date") or "")
    time_value = str(item.get("time") or "")
    start_at = str(item.get("start_at") or "")
    if not start_at and due_date:
        start_at = f"{due_date}T{time_value or '19:00'}"
    raw_assignees = item.get("assignees") if isinstance(item.get("assignees"), list) else item.get("participants", [])
    assignees = sorted(
        {
            str(p)
            for p in raw_assignees
            if isinstance(p, (str, int, float)) and person_by_key(str(p))
        }
    )
    return {
        "id": str(item.get("id") or ""),
        "owner_key": str(item.get("owner_key") or "family"),
        "is_family": True,
        "title": str(item.get("title") or item.get("text") or ""),
        "text": str(item.get("title") or item.get("text") or ""),
        "details": str(item.get("details") or ""),
        "due_date": due_date,
        "time": time_value,
        "start_at": start_at,
        "workflow_status": str(item.get("workflow_status") or "todo"),
        "assignees": assignees,
        "participants": assignees,
        "duration_minutes": int(item.get("duration_minutes") or 0),
        "updated_at": str(item.get("updated_at") or ""),
        "version": int(item.get("version") or 1),
    }


def _item_diff_fingerprint(item: dict, *, is_family: bool) -> str:
    canonical = _canonical_family_task(item) if is_family else _canonical_person_task(item)
    canonical.pop("updated_at", None)
    canonical.pop("version", None)
    return json.dumps(canonical, sort_keys=True, ensure_ascii=False)


def _pick_latest_metadata(prev_item: dict | None, cur_item: dict, *, now_iso: str) -> tuple[str, int]:
    prev_updated = str(prev_item.get("updated_at") or "") if isinstance(prev_item, dict) else ""
    cur_updated = str(cur_item.get("updated_at") or "").strip()
    updated_at = cur_updated or prev_updated or now_iso

    prev_version_raw = prev_item.get("version") if isinstance(prev_item, dict) else 1
    cur_version_raw = cur_item.get("version")
    try:
        prev_version = int(prev_version_raw or 1)
    except (TypeError, ValueError):
        prev_version = 1
    try:
        cur_version = int(cur_version_raw or 1)
    except (TypeError, ValueError):
        cur_version = 1
    prev_version = max(1, prev_version)
    cur_version = max(1, cur_version)

    if prev_item is None:
        return updated_at, cur_version

    changed = _item_diff_fingerprint(prev_item, is_family=bool(prev_item.get("is_family"))) != _item_diff_fingerprint(
        cur_item,
        is_family=bool(cur_item.get("is_family")),
    )
    if changed:
        if cur_version <= prev_version:
            cur_version = prev_version + 1
        if updated_at <= prev_updated:
            updated_at = now_iso
    else:
        cur_version = max(cur_version, prev_version)
        if not cur_updated:
            updated_at = prev_updated or now_iso
    return updated_at, cur_version


def _merge_remote_changes(
    current_items: list[dict],
    incoming_items: list[dict],
    *,
    is_family: bool,
) -> tuple[list[dict], bool]:
    current = _stable_items(current_items, is_family=is_family)
    incoming = _stable_items(incoming_items, is_family=is_family)
    merged_by_id = {str(item.get("id") or ""): item for item in current if str(item.get("id") or "")}
    changed = False

    for remote_item in incoming:
        item_id = str(remote_item.get("id") or "")
        if not item_id:
            continue
        local_item = merged_by_id.get(item_id)
        if local_item is None:
            merged_by_id[item_id] = remote_item
            changed = True
            continue

        local_version = int(local_item.get("version") or 1)
        remote_version = int(remote_item.get("version") or 1)
        local_updated = str(local_item.get("updated_at") or "")
        remote_updated = str(remote_item.get("updated_at") or "")
        should_apply = remote_version > local_version or (remote_version == local_version and remote_updated > local_updated)
        if should_apply and local_item != remote_item:
            merged_by_id[item_id] = remote_item
            changed = True

    merged = list(merged_by_id.values())
    merged = _stable_items(merged, is_family=is_family)
    return merged, changed


def _stable_items(items: list[dict], *, is_family: bool) -> list[dict]:
    canonical_items: list[dict] = []
    for item in items:
        if not isinstance(item, dict):
            continue
        canonical = _canonical_family_task(item) if is_family else _canonical_person_task(item)
        if not str(canonical.get("id") or ""):
            continue
        canonical_items.append(canonical)
    canonical_items.sort(
        key=lambda item: (
            str(item.get("owner_key") or ""),
            str(item.get("id") or ""),
            str(item.get("due_date") or ""),
            str(item.get("time") or ""),
            str(item.get("updated_at") or ""),
            int(item.get("version") or 1),
        )
    )
    return canonical_items


def _diff_events(before: list[dict], after: list[dict], *, owner_key: str, is_family: bool) -> list[dict]:
    before_by_id = {str(item.get("id") or ""): item for item in before if str(item.get("id") or "")}
    after_by_id = {str(item.get("id") or ""): item for item in after if str(item.get("id") or "")}
    events: list[dict] = []

    added_ids = sorted(set(after_by_id.keys()) - set(before_by_id.keys()))
    removed_ids = sorted(set(before_by_id.keys()) - set(after_by_id.keys()))
    common_ids = sorted(set(before_by_id.keys()) & set(after_by_id.keys()))

    for item_id in added_ids:
        item = after_by_id[item_id]
        events.append(
            {
                "event_id": f"{owner_key}:{'family' if is_family else 'person'}:add:{item_id}",
                "kind": "add",
                "owner_key": owner_key,
                "is_family": is_family,
                "id": item_id,
                "title": str(item.get("title") or item.get("text") or "без названия"),
            }
        )
    for item_id in removed_ids:
        item = before_by_id[item_id]
        events.append(
            {
                "event_id": f"{owner_key}:{'family' if is_family else 'person'}:delete:{item_id}",
                "kind": "delete",
                "owner_key": owner_key,
                "is_family": is_family,
                "id": item_id,
                "title": str(item.get("title") or item.get("text") or "без названия"),
            }
        )
    for item_id in common_ids:
        prev = before_by_id[item_id]
        cur = after_by_id[item_id]
        if prev == cur:
            continue
        events.append(
            {
                "event_id": f"{owner_key}:{'family' if is_family else 'person'}:update:{item_id}",
                "kind": "update",
                "owner_key": owner_key,
                "is_family": is_family,
                "id": item_id,
                "title": str(cur.get("title") or cur.get("text") or "без названия"),
            }
        )
    return events


def pull_backend_snapshot_to_local() -> dict[str, object]:
    """Sync full backend snapshot into local files for all profiles."""
    if not _backend_enabled():
        return {"ok": False, "reason": "backend_disabled"}
    remote = _backend_pull_snapshot(since="1970-01-01T00:00:00")
    if not isinstance(remote, dict):
        return {
            "ok": False,
            "reason": "pull_failed",
            "error_kind": str(_BACKEND_LAST_ERROR.get("kind") or ""),
            "error_message": str(_BACKEND_LAST_ERROR.get("message") or ""),
        }

    raw_tasks = remote.get("tasks")
    tasks = _stable_items(raw_tasks if isinstance(raw_tasks, list) else [], is_family=False)
    by_owner: dict[str, list[dict]] = {person.key: [] for person in PEOPLE}
    for item in tasks:
        if not isinstance(item, dict):
            continue
        owner = str(item.get("owner_key") or "").strip()
        if owner in by_owner and not bool(item.get("is_family")):
            by_owner[owner].append(item)

    changed_profiles: list[str] = []
    change_events: list[dict] = []
    for person in PEOPLE:
        target_path = todos_path(person)
        snapshot = _stable_items(by_owner.get(person.key, []), is_family=False)
        current = read_json(target_path, [])
        current_items = _stable_items(current if isinstance(current, list) else [], is_family=False)
        if current_items != snapshot:
            write_json(target_path, snapshot)
            changed_profiles.append(person.key)
            change_events.extend(
                _diff_events(
                    current_items,
                    snapshot,
                    owner_key=person.key,
                    is_family=False,
                )
            )

    raw_family = remote.get("family_tasks")
    family_items = _stable_items(raw_family if isinstance(raw_family, list) else [], is_family=True)
    current_family = read_json(FAMILY_TASKS_PATH, [])
    current_family_items = _stable_items(current_family if isinstance(current_family, list) else [], is_family=True)
    family_changed = current_family_items != family_items
    if family_changed:
        write_json(FAMILY_TASKS_PATH, family_items)
        change_events.extend(
            _diff_events(
                current_family_items,
                family_items,
                owner_key="family",
                is_family=True,
            )
        )

    return {
        "ok": True,
        "changed_profiles": changed_profiles,
        "family_changed": family_changed,
        "changed": bool(changed_profiles or family_changed),
        "events": change_events,
        "mode": "full",
        "next_cursor": str(remote.get("next_cursor") or remote.get("server_time") or ""),
    }


def pull_backend_changes_since_cursor(cursor: str) -> dict[str, object]:
    """Apply incremental backend changes since cursor (add/update only, deletions come from full sync)."""
    if not _backend_enabled():
        return {"ok": False, "reason": "backend_disabled"}
    cursor_value = (cursor or "").strip() or "1970-01-01T00:00:00"
    remote = _backend_pull_snapshot(since=cursor_value, cursor=cursor_value)
    if not isinstance(remote, dict):
        return {
            "ok": False,
            "reason": "pull_failed",
            "cursor": cursor_value,
            "error_kind": str(_BACKEND_LAST_ERROR.get("kind") or ""),
            "error_message": str(_BACKEND_LAST_ERROR.get("message") or ""),
        }

    raw_tasks = remote.get("tasks")
    tasks = _stable_items(raw_tasks if isinstance(raw_tasks, list) else [], is_family=False)
    by_owner: dict[str, list[dict]] = {person.key: [] for person in PEOPLE}
    for item in tasks:
        owner = str(item.get("owner_key") or "").strip()
        if owner in by_owner:
            by_owner[owner].append(item)

    changed_profiles: list[str] = []
    change_events: list[dict] = []
    for person in PEOPLE:
        incoming = _stable_items(by_owner.get(person.key, []), is_family=False)
        if not incoming:
            continue
        target_path = todos_path(person)
        current = read_json(target_path, [])
        current_items = _stable_items(current if isinstance(current, list) else [], is_family=False)
        merged_items, changed = _merge_remote_changes(current_items, incoming, is_family=False)
        if not changed:
            continue
        write_json(target_path, merged_items)
        changed_profiles.append(person.key)
        change_events.extend(
            _diff_events(
                current_items,
                merged_items,
                owner_key=person.key,
                is_family=False,
            )
        )

    family_changed = False
    raw_family = remote.get("family_tasks")
    incoming_family = _stable_items(raw_family if isinstance(raw_family, list) else [], is_family=True)
    if incoming_family:
        current_family = read_json(FAMILY_TASKS_PATH, [])
        current_family_items = _stable_items(current_family if isinstance(current_family, list) else [], is_family=True)
        merged_family, family_changed = _merge_remote_changes(current_family_items, incoming_family, is_family=True)
        if family_changed:
            write_json(FAMILY_TASKS_PATH, merged_family)
            change_events.extend(
                _diff_events(
                    current_family_items,
                    merged_family,
                    owner_key="family",
                    is_family=True,
                )
            )

    next_cursor = str(remote.get("next_cursor") or remote.get("server_time") or cursor_value)
    return {
        "ok": True,
        "changed_profiles": changed_profiles,
        "family_changed": family_changed,
        "changed": bool(changed_profiles or family_changed),
        "events": change_events,
        "mode": "delta",
        "cursor": cursor_value,
        "next_cursor": next_cursor,
    }


def pull_backend_family_snapshot_to_local() -> dict[str, object]:
    """Sync only family tasks from backend and apply pointwise diff by id/version/updated_at."""
    if not _backend_enabled():
        return {"ok": False, "reason": "backend_disabled"}
    remote = _backend_pull_snapshot()
    if not isinstance(remote, dict):
        return {
            "ok": False,
            "reason": "pull_failed",
            "error_kind": str(_BACKEND_LAST_ERROR.get("kind") or ""),
            "error_message": str(_BACKEND_LAST_ERROR.get("message") or ""),
        }

    raw_family = remote.get("family_tasks")
    remote_items = _stable_items(raw_family if isinstance(raw_family, list) else [], is_family=True)
    current_family = read_json(FAMILY_TASKS_PATH, [])
    current_items = _stable_items(current_family if isinstance(current_family, list) else [], is_family=True)

    remote_by_id = {str(item.get("id") or ""): item for item in remote_items if str(item.get("id") or "")}
    local_by_id = {str(item.get("id") or ""): item for item in current_items if str(item.get("id") or "")}

    merged: dict[str, dict] = dict(local_by_id)
    changed = False
    for item_id, remote_item in remote_by_id.items():
        local_item = local_by_id.get(item_id)
        if local_item is None:
            merged[item_id] = remote_item
            changed = True
            continue
        local_version = int(local_item.get("version") or 1)
        remote_version = int(remote_item.get("version") or 1)
        local_updated = str(local_item.get("updated_at") or "")
        remote_updated = str(remote_item.get("updated_at") or "")
        if remote_version > local_version or (remote_version == local_version and remote_updated >= local_updated):
            if local_item != remote_item:
                merged[item_id] = remote_item
                changed = True

    remote_ids = set(remote_by_id.keys())
    for item_id in list(merged.keys()):
        if item_id not in remote_ids:
            merged.pop(item_id, None)
            changed = True

    if not changed:
        return {"ok": True, "family_changed": False, "changed": False, "events": []}

    merged_items = list(merged.values())
    merged_items.sort(key=lambda x: (str(x.get("start_at") or ""), str(x.get("id") or "")))
    write_json(FAMILY_TASKS_PATH, merged_items)
    events = _diff_events(current_items, _stable_items(merged_items, is_family=True), owner_key="family", is_family=True)
    return {"ok": True, "family_changed": True, "changed": True, "events": events}


def _push_snapshot_event(actor_profile: str, event: dict) -> bool:
    if not _backend_enabled():
        return False
    runtime = _backend_runtime(default_source="desktop")
    payload = {
        "actor_profile": actor_profile,
        "source": runtime["backend_source"],
        "events": [event],
    }
    for path in ("/sync_push.php", "/sync/push"):
        if isinstance(_backend_request("POST", path, payload=payload), dict):
            return True
    log_event(
        "backend_push_failed",
        actor_profile=actor_profile,
        entity=str(event.get("entity") or ""),
        action=str(event.get("action") or ""),
    )
    return False


def load_family_tasks(*, pull_remote: bool = False) -> list[dict]:
    if pull_remote and _backend_enabled():
        pull_backend_snapshot_to_local()
    raw = read_json(FAMILY_TASKS_PATH, [])
    source = raw if isinstance(raw, list) else []
    normalized: list[dict] = []
    changed = False
    max_id = 0
    for item in source:
        if not isinstance(item, dict):
            changed = True
            continue
        raw_id = item.get("id")
        if isinstance(raw_id, int):
            item_id = str(raw_id)
            max_id = max(max_id, raw_id)
        elif isinstance(raw_id, str) and raw_id.strip():
            item_id = raw_id.strip()
            if item_id.isdigit():
                max_id = max(max_id, int(item_id))
        else:
            item_id = str(max_id + 1)
            max_id += 1
            changed = True
        assignees_raw = item.get("assignees") if isinstance(item.get("assignees"), list) else item.get("participants")
        assignees = [str(p) for p in assignees_raw] if isinstance(assignees_raw, list) else []
        assignees = sorted({p for p in assignees if person_by_key(p)})
        if not assignees:
            changed = True
            continue
        workflow = str(item.get("workflow_status") or "todo")
        if workflow not in WORKFLOW_STATUSES:
            workflow = "todo"
            changed = True
        duration_raw = item.get("duration_minutes")
        duration = int(duration_raw) if isinstance(duration_raw, int) and duration_raw >= 0 else 60
        if duration != duration_raw:
            changed = True
        start_at = str(item.get("start_at") or "")
        if not parse_iso_datetime(start_at):
            changed = True
            continue
        owner_key = str(item.get("owner_key") or "family").strip() or "family"
        if owner_key != "family":
            owner_key = "family"
            changed = True
        raw_updated = str(item.get("updated_at") or "").strip()
        if not raw_updated:
            raw_updated = datetime.now().isoformat(timespec="seconds")
            changed = True
        version_raw = item.get("version")
        try:
            version = int(version_raw or 1)
        except (TypeError, ValueError):
            version = 1
            changed = True
        if version < 1:
            version = 1
            changed = True
        due = start_at[:10]
        time_value = start_at[11:16]
        normalized.append(
            {
                "id": item_id,
                "owner_key": owner_key,
                "title": str(item.get("title") or item.get("text") or "семейное дело").strip(),
                "text": str(item.get("title") or item.get("text") or "семейное дело").strip(),
                "details": str(item.get("details") or "").strip(),
                "due_date": due,
                "time": time_value,
                "start_at": start_at,
                "duration_minutes": duration,
                "assignees": assignees,
                "participants": assignees,
                "is_family": True,
                "workflow_status": workflow,
                "status": "done" if workflow == "done" else "active",
                "done": workflow == "done",
                "done_at": item.get("done_at"),
                "reminder_offsets": item.get("reminder_offsets") if isinstance(item.get("reminder_offsets"), list) else list(DEFAULT_REMINDER_OFFSETS),
                "sort_order": int(item.get("sort_order") or (int(item_id) if item_id.isdigit() else max_id + 1)),
                "updated_at": raw_updated,
                "version": version,
                "created_at": str(item.get("created_at") or datetime.now().isoformat(timespec="seconds")),
                "last_reminder_key": item.get("last_reminder_key"),
            }
        )
    normalized.sort(key=lambda x: (str(x.get("start_at") or ""), str(x.get("id") or "")))
    if changed:
        save_family_tasks(normalized, push_remote=False)
    return normalized


def _normalize_family_tasks_for_storage(items: list[dict]) -> list[dict]:
    now_iso = datetime.now().isoformat(timespec="seconds")
    previous_raw = read_json(FAMILY_TASKS_PATH, [])
    previous_items = _stable_items(previous_raw if isinstance(previous_raw, list) else [], is_family=True)
    previous_by_id = {str(item.get("id") or ""): item for item in previous_items if str(item.get("id") or "")}
    normalized: list[dict] = []
    for raw_item in items:
        if not isinstance(raw_item, dict):
            continue
        prepared = dict(raw_item)
        prepared["owner_key"] = "family"
        prepared["is_family"] = True
        canonical = _canonical_family_task(prepared)
        item_id = str(canonical.get("id") or "")
        if not item_id:
            continue
        previous = previous_by_id.get(item_id)
        updated_at, version = _pick_latest_metadata(previous, canonical, now_iso=now_iso)
        status_key = str(canonical.get("workflow_status") or "todo")
        assignees = list(canonical.get("assignees") or [])
        normalized.append(
            {
                **prepared,
                "owner_key": "family",
                "is_family": True,
                "title": str(canonical.get("title") or "семейное дело"),
                "text": str(canonical.get("title") or "семейное дело"),
                "details": str(canonical.get("details") or ""),
                "due_date": str(canonical.get("due_date") or ""),
                "time": str(canonical.get("time") or ""),
                "start_at": str(canonical.get("start_at") or ""),
                "workflow_status": status_key,
                "status": "done" if status_key == "done" else "active",
                "done": status_key == "done",
                "assignees": assignees,
                "participants": assignees,
                "duration_minutes": int(canonical.get("duration_minutes") or 0),
                "updated_at": updated_at,
                "version": version,
            }
        )
    normalized.sort(key=lambda x: (str(x.get("start_at") or ""), str(x.get("id") or "")))
    return normalized


def save_family_tasks(items: list[dict], *, push_remote: bool = True) -> None:
    normalized = _normalize_family_tasks_for_storage(items)
    write_json(FAMILY_TASKS_PATH, normalized)
    if push_remote and _backend_enabled():
        _push_snapshot_event(
            actor_profile="nik",
            event={
                "event_id": f"desktop-family-snapshot-{uuid.uuid4()}",
                "entity": "family_task",
                "action": "replace_family_tasks",
                "payload": {"items": normalized},
                "happened_at": datetime.now().isoformat(timespec="seconds"),
            },
        )


def create_family_task(
    *,
    title: str,
    details: str,
    start_at: str,
    duration_minutes: int,
    assignees: list[str] | None = None,
    participants: list[str] | None = None,
) -> tuple[bool, str, dict | None]:
    raw_assignees = assignees if assignees is not None else participants or []
    cleaned_assignees = sorted({p for p in raw_assignees if person_by_key(p)})
    if not cleaned_assignees:
        return False, "Не выбраны участники семейного дела.", None
    start_dt = parse_iso_datetime(start_at)
    if start_dt is None:
        return False, "Некорректная дата/время семейного дела.", None
    tasks = load_family_tasks()
    next_id = max([int(str(t.get("id") or "0")) for t in tasks if str(t.get("id") or "").isdigit()], default=0) + 1
    now_iso = datetime.now().isoformat(timespec="seconds")
    item = {
        "id": str(next_id),
        "owner_key": "family",
        "title": title.strip() or "семейное дело",
        "text": title.strip() or "семейное дело",
        "details": details.strip(),
        "due_date": start_dt.date().isoformat(),
        "time": start_dt.strftime("%H:%M"),
        "start_at": start_dt.isoformat(timespec="minutes"),
        "duration_minutes": max(0, int(duration_minutes or 0)),
        "assignees": cleaned_assignees,
        "participants": cleaned_assignees,
        "is_family": True,
        "workflow_status": "todo",
        "status": "active",
        "done": False,
        "done_at": None,
        "reminder_offsets": list(DEFAULT_REMINDER_OFFSETS),
        "sort_order": next_id,
        "created_at": now_iso,
        "updated_at": now_iso,
        "version": 1,
    }
    tasks.append(item)
    save_family_tasks(tasks)
    return True, "", item


def update_family_task(task_id: str | int, payload: dict) -> tuple[bool, str, dict | None]:
    tasks = load_family_tasks()
    task_id_value = str(task_id)
    for item in tasks:
        if str(item.get("id") or "") != task_id_value:
            continue
        current_version = int(item.get("version") or 1)
        item.update(payload)
        ensure_workflow_status(item)
        transition_task(item, str(item.get("workflow_status") or "todo"))
        item["owner_key"] = "family"
        item["is_family"] = True
        if isinstance(payload.get("assignees"), list):
            raw_assignees = payload.get("assignees")
        elif isinstance(payload.get("participants"), list):
            raw_assignees = payload.get("participants")
        else:
            raw_assignees = item.get("assignees") if isinstance(item.get("assignees"), list) else item.get("participants", [])
        item["assignees"] = sorted({str(p) for p in raw_assignees if person_by_key(str(p))})
        item["participants"] = list(item["assignees"])
        if not item["assignees"]:
            return False, "Семейное дело должно иметь хотя бы одного участника.", None
        if not parse_iso_datetime(str(item.get("start_at") or "")):
            return False, "Некорректная дата/время семейного дела.", None
        start_dt = parse_iso_datetime(str(item.get("start_at") or ""))
        item["due_date"] = start_dt.date().isoformat() if start_dt else item.get("due_date")
        item["time"] = start_dt.strftime("%H:%M") if start_dt else item.get("time")
        item["duration_minutes"] = max(0, int(item.get("duration_minutes") or 0))
        next_version_raw = item.get("version")
        try:
            next_version = int(next_version_raw or 1)
        except (TypeError, ValueError):
            next_version = 1
        item["version"] = max(current_version + 1, next_version)
        save_family_tasks(tasks)
        return True, "", item
    return False, "Семейное дело не найдено.", None


def delete_family_task(task_id: str | int) -> dict | None:
    tasks = load_family_tasks()
    task_id_value = str(task_id)
    for idx, item in enumerate(tasks):
        if str(item.get("id") or "") == task_id_value:
            removed = tasks.pop(idx)
            save_family_tasks(tasks)
            return removed
    return None


def family_conflicts_for_person(person_key: str, due_date: str, time_value: str) -> list[dict]:
    try:
        candidate_start = datetime.fromisoformat(f"{due_date}T{time_value}")
    except ValueError:
        return []
    candidate = (candidate_start, candidate_start + timedelta(minutes=1))
    conflicts: list[dict] = []
    for family_item in load_family_tasks():
        assignees = family_item.get("assignees") if isinstance(family_item.get("assignees"), list) else family_item.get("participants", [])
        if person_key not in assignees:
            continue
        if str(family_item.get("workflow_status") or "todo") == "done":
            continue
        family_interval = compute_interval(
            str(family_item.get("start_at") or ""),
            int(family_item.get("duration_minutes") or 0),
        )
        if family_interval is None:
            continue
        blocked = (family_interval[0] - timedelta(minutes=60), family_interval[1])
        if intervals_overlap(candidate, blocked):
            conflicts.append(family_item)
    return conflicts


def listen_once(prompt: str, retries: int = 1, phrase_time_limit: int | None = None) -> str | None:
    for attempt in range(retries + 1):
        if prompt:
            speak(prompt)
        text = listen_speech(
            timeout=SETTINGS.audio.default_timeout + 3,
            phrase_time_limit=phrase_time_limit or SETTINGS.audio.default_phrase_time_limit,
            ambient_duration=SETTINGS.audio.default_ambient_duration,
            language=SETTINGS.audio.language,
            retries=1,
            with_cue=True,
        )
        if text:
            print(f"Распознано: {text}")
            return text
        if attempt < retries:
            speak("Повтори коротко.")
    return None


def find_person(text: str | None) -> Person | None:
    if not text:
        return None
    for person in PEOPLE:
        if any(contains_phrase(text, alias) for alias in person.aliases):
            return person
    return None


def load_todos(person: Person, *, pull_remote: bool = False) -> list[dict]:
    if pull_remote and _backend_enabled():
        pull_backend_snapshot_to_local()
    data = read_json(todos_path(person), [])
    source = data if isinstance(data, list) else []
    changed = False

    normalized: list[dict] = []
    used_ids: set[int] = set()
    max_id = 0
    today = datetime.now().date()

    def reserve_id(preferred: int | None = None) -> int:
        nonlocal max_id
        if preferred is not None and preferred > 0 and preferred not in used_ids:
            used_ids.add(preferred)
            max_id = max(max_id, preferred)
            return preferred
        max_id = max(max_id + 1, 1)
        while max_id in used_ids:
            max_id += 1
        used_ids.add(max_id)
        return max_id

    for todo in source:
        if not isinstance(todo, dict):
            changed = True
            continue

        text_blob = " ".join(
            [
                str(todo.get("title") or ""),
                str(todo.get("text") or ""),
                str(todo.get("details") or ""),
            ]
        ).strip()

        inferred_time = str(todo.get("time") or "").strip()
        if not inferred_time:
            inferred_time = extract_time_from_inline(text_blob) or ""
            if inferred_time:
                changed = True

        due_date = todo_due_date(todo, base_date=today)
        if due_date is None:
            day_value = parse_day(text_blob) or weekday_ru(today)
            due_date = nearest_date_for_weekday(day_value, base_date=today).isoformat()
            changed = True

        status = str(todo.get("status") or "")
        done_flag = bool(todo.get("done"))
        if status not in {"active", "done"}:
            status = "done" if done_flag else "active"
            changed = True

        workflow_status = str(todo.get("workflow_status") or "").strip()
        if workflow_status not in WORKFLOW_STATUSES:
            workflow_status = "done" if status == "done" else "todo"
            changed = True
        status = "done" if workflow_status == "done" else "active"

        recurrence_rule = str(todo.get("recurrence_rule") or todo.get("recurring") or "").strip()
        if recurrence_rule not in {"daily", "weekdays"}:
            recurrence_rule = ""

        raw_id = todo.get("id")
        candidate_id = int(raw_id) if isinstance(raw_id, int) else None
        item_id = reserve_id(candidate_id)
        if candidate_id != item_id:
            changed = True

        sort_order_raw = todo.get("sort_order")
        sort_order = sort_order_raw if isinstance(sort_order_raw, int) else item_id
        if not isinstance(sort_order_raw, int):
            changed = True

        title = str(todo.get("title") or todo.get("text") or "").strip() or "без названия"
        if not todo.get("title"):
            changed = True

        offsets = todo.get("reminder_offsets")
        if not isinstance(offsets, list) or not offsets:
            offsets = list(DEFAULT_REMINDER_OFFSETS)
            changed = True

        tags = todo.get("tags")
        if not isinstance(tags, list):
            tags = []
            changed = True

        participants_raw = todo.get("participants")
        participants = [str(v) for v in participants_raw] if isinstance(participants_raw, list) else []
        participants = sorted({p for p in participants if person_by_key(p)})
        if participants:
            changed = True
        is_family = False
        if bool(todo.get("is_family")):
            changed = True
        start_at = str(todo.get("start_at") or "").strip() or None
        duration_raw = todo.get("duration_minutes")
        duration_minutes = int(duration_raw) if isinstance(duration_raw, int) and duration_raw >= 0 else None
        if is_family and not start_at:
            fallback_time = inferred_time or "19:00"
            start_at = f"{due_date}T{fallback_time}"
            changed = True
        if is_family and duration_minutes is None:
            duration_minutes = 60
            changed = True

        series_id = todo.get("series_id")
        if recurrence_rule and not series_id:
            series_id = f"series-{uuid.uuid4().hex[:12]}"
            changed = True

        owner_key = str(todo.get("owner_key") or person.key).strip()
        if owner_key != person.key:
            changed = True
            owner_key = person.key

        raw_updated = str(todo.get("updated_at") or "").strip()
        if not raw_updated:
            raw_updated = datetime.now().isoformat(timespec="seconds")
            changed = True

        version_raw = todo.get("version")
        try:
            version = int(version_raw or 1)
        except (TypeError, ValueError):
            version = 1
            changed = True
        if version < 1:
            version = 1
            changed = True

        normalized.append(
            {
                "id": item_id,
                "owner_key": owner_key,
                "title": title,
                "text": title,
                "details": str(todo.get("details") or "").strip(),
                "due_date": due_date,
                "day": weekday_ru(datetime.fromisoformat(due_date).date()),
                "time": inferred_time or None,
                "priority": str(todo.get("priority") or "medium"),
                "tags": tags,
                "status": status,
                "done": status == "done",
                "workflow_status": workflow_status,
                "sort_order": sort_order,
                "done_at": todo.get("done_at"),
                "is_family": is_family,
                "participants": participants,
                "start_at": start_at,
                "duration_minutes": duration_minutes,
                "created_at": str(todo.get("created_at") or datetime.now().isoformat(timespec="seconds")),
                "updated_at": raw_updated,
                "version": version,
                "reminder_offsets": offsets,
                "series_id": series_id,
                "recurrence_rule": recurrence_rule or None,
                "generated_from_rule": bool(todo.get("generated_from_rule") or recurrence_rule),
                "legacy_day": todo.get("day"),
            }
        )

    # Ensure recurrence horizon has concrete instances for the next N days.
    horizon_end = today + timedelta(days=RECURRENCE_HORIZON_DAYS - 1)
    by_series: dict[str, list[dict]] = {}
    for todo in normalized:
        sid = str(todo.get("series_id") or "")
        rule = str(todo.get("recurrence_rule") or "")
        if sid and rule:
            by_series.setdefault(sid, []).append(todo)

    for sid, items in by_series.items():
        rule = str(items[0].get("recurrence_rule") or "")
        existing_dates = {str(item.get("due_date")) for item in items}
        template = min(items, key=lambda x: str(x.get("due_date") or ""))
        cursor = datetime.fromisoformat(str(template.get("due_date"))).date()
        while cursor <= horizon_end:
            cursor_iso = cursor.isoformat()
            matches = rule == "daily" or (rule == "weekdays" and cursor.weekday() <= 4)
            if matches and cursor_iso not in existing_dates:
                new_id = reserve_id(None)
                normalized.append(
                    {
                        **template,
                        "id": new_id,
                        "owner_key": person.key,
                        "due_date": cursor_iso,
                        "day": weekday_ru(cursor),
                        "status": "active",
                        "done": False,
                        "workflow_status": "todo",
                        "sort_order": new_id,
                        "done_at": None,
                        "updated_at": datetime.now().isoformat(timespec="seconds"),
                        "version": int(template.get("version") or 1),
                        "generated_from_rule": True,
                    }
                )
                existing_dates.add(cursor_iso)
                changed = True
            cursor += timedelta(days=1)

    normalized.sort(
        key=lambda item: (
            str(item.get("due_date") or ""),
            str(item.get("workflow_status") or "todo"),
            int(item.get("sort_order") or 0),
            str(item.get("time") or ""),
            int(item.get("id") or 0),
        )
    )

    if changed:
        save_todos(person, normalized, push_remote=False)
    return normalized


def _normalize_person_todos_for_storage(person: Person, todos: list[dict]) -> list[dict]:
    now_iso = datetime.now().isoformat(timespec="seconds")
    previous_raw = read_json(todos_path(person), [])
    previous_items = _stable_items(previous_raw if isinstance(previous_raw, list) else [], is_family=False)
    previous_by_id = {str(item.get("id") or ""): item for item in previous_items if str(item.get("id") or "")}
    normalized: list[dict] = []
    for raw_todo in todos:
        if not isinstance(raw_todo, dict):
            continue
        prepared = dict(raw_todo)
        prepared["owner_key"] = person.key
        prepared["is_family"] = False
        canonical = _canonical_person_task(prepared)
        item_id = str(canonical.get("id") or "")
        if not item_id:
            continue
        previous = previous_by_id.get(item_id)
        updated_at, version = _pick_latest_metadata(previous, canonical, now_iso=now_iso)
        title = str(canonical.get("title") or "без названия")
        normalized.append(
            {
                **prepared,
                "owner_key": person.key,
                "is_family": False,
                "title": title,
                "text": title,
                "tags": list(canonical.get("tags") or []),
                "participants": [],
                "updated_at": updated_at,
                "version": version,
            }
        )
    return normalized


def save_todos(person: Person, todos: list[dict], *, push_remote: bool = True) -> None:
    normalized = _normalize_person_todos_for_storage(person, todos)
    write_json(todos_path(person), normalized)
    if push_remote and _backend_enabled():
        _push_snapshot_event(
            actor_profile=person.key,
            event={
                "event_id": f"desktop-person-snapshot-{person.key}-{uuid.uuid4()}",
                "entity": "task",
                "action": "replace_person_tasks",
                "payload": {"owner_key": person.key, "tasks": normalized},
                "happened_at": datetime.now().isoformat(timespec="seconds"),
            },
        )


def cleanup_legacy_todos(person: Person) -> dict:
    """Удаляет только legacy-записи, которые нельзя привести к текущей схеме."""
    path = todos_path(person)
    raw = read_json(path, [])
    source = raw if isinstance(raw, list) else []
    removed = 0
    kept: list[dict] = []
    reasons: list[str] = []

    for item in source:
        if not isinstance(item, dict):
            removed += 1
            reasons.append("не словарь")
            continue
        raw_id = item.get("id")
        if not isinstance(raw_id, int) or raw_id <= 0:
            removed += 1
            reasons.append("невалидный id")
            continue
        due = todo_due_date(item)
        if due is None:
            removed += 1
            reasons.append("битая дата")
            continue
        kept.append(item)

    backup_path = ""
    if removed > 0:
        stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_path = str(path.with_name(f"todos.backup_{stamp}.json"))
        try:
            Path(backup_path).write_text(Path(path).read_text(encoding="utf-8"), encoding="utf-8")
        except Exception:
            backup_path = ""
        write_json(path, kept)

    return {"removed": removed, "backup_path": backup_path, "reasons": reasons}


def cleanup_legacy_misha_todos() -> dict:
    target = next((p for p in PEOPLE if p.key == "misha"), None)
    if target is None:
        return {"removed": 0, "backup_path": "", "reasons": ["профиль не найден"]}
    report = cleanup_legacy_todos(target)
    if report.get("removed", 0) > 0:
        log_event("todo_cleanup_legacy", person=target.key, removed=report["removed"])
    return report


def cleanup_legacy_todos_all_profiles() -> dict:
    report = {"profiles": {}, "total_removed": 0}
    for person in PEOPLE:
        person_report = cleanup_legacy_todos(person)
        report["profiles"][person.key] = person_report
        report["total_removed"] += int(person_report.get("removed", 0))
        if int(person_report.get("removed", 0)) > 0:
            log_event("todo_cleanup_legacy", person=person.key, removed=person_report["removed"])
    return report


def cleanup_misha_todos_from_date(min_due_date: str = "2026-04-20") -> dict:
    target = next((p for p in PEOPLE if p.key == "misha"), None)
    if target is None:
        return {"removed": 0, "backup_path": "", "threshold": min_due_date, "error": "профиль не найден"}
    path = todos_path(target)
    raw = read_json(path, [])
    source = raw if isinstance(raw, list) else []
    kept: list[dict] = []
    removed = 0
    for item in source:
        if not isinstance(item, dict):
            kept.append(item)
            continue
        due = str(item.get("due_date") or "")
        if due and due >= min_due_date:
            removed += 1
            continue
        kept.append(item)
    backup_path = ""
    if removed > 0 and path.exists():
        stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup = path.with_name(f"todos.backup_cleanup_{stamp}.json")
        backup.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")
        backup_path = str(backup)
        write_json(path, kept)
    log_event(
        "todo_cleanup_misha_due_date",
        person="misha",
        threshold=min_due_date,
        removed=removed,
        backup_path=backup_path,
    )
    return {"removed": removed, "backup_path": backup_path, "threshold": min_due_date}


def load_history(person: Person) -> list[dict]:
    return st.load_history(DATA_DIR, person.key)


def save_history(person: Person, history: list[dict]) -> None:
    st.save_history(DATA_DIR, person.key, history)


def push_history(person: Person, action: str, payload: dict) -> None:
    st.push_history(DATA_DIR, person.key, action, payload)


def parse_day(text: str | None) -> str | None:
    if not text:
        return None
    for canonical, aliases in DAY_ALIASES.items():
        if any(contains_phrase(text, alias) for alias in aliases):
            return canonical
    return None


def day_from_relative_word(text: str | None) -> str | None:
    if not text:
        return None
    normalized = normalize_text(text)
    today_idx = datetime.now().weekday()
    if any(contains_phrase(normalized, phrase) for phrase in ("сегодня", "на сегодня")):
        return DAY_ORDER[today_idx]
    if any(contains_phrase(normalized, phrase) for phrase in ("завтра", "на завтра")):
        return DAY_ORDER[(today_idx + 1) % 7]
    return None


def parse_day_or_relative(text: str | None) -> str | None:
    return parse_day(text) or day_from_relative_word(text)


def weekday_ru(dt: date) -> str:
    return DAY_ORDER[dt.weekday()]


def nearest_date_for_weekday(day_ru: str, *, base_date: date | None = None, include_today: bool = True) -> date:
    base = base_date or datetime.now().date()
    target_idx = DAY_ORDER.index(day_ru)
    delta = (target_idx - base.weekday()) % 7
    if delta == 0 and not include_today:
        delta = 7
    return base + timedelta(days=delta)


def parse_due_date_input(text: str | None, *, base_date: date | None = None) -> str | None:
    if not text:
        return None
    source = (text or "").strip()
    normalized = normalize_text(source)
    today = base_date or datetime.now().date()

    if any(contains_phrase(normalized, phrase) for phrase in ("сегодня", "на сегодня")):
        return today.isoformat()
    if any(contains_phrase(normalized, phrase) for phrase in ("завтра", "на завтра")):
        return (today + timedelta(days=1)).isoformat()

    iso_match = re.search(r"\b(20\d{2})-(\d{1,2})-(\d{1,2})\b", source)
    if iso_match:
        y, m, d = map(int, iso_match.groups())
        try:
            return date(y, m, d).isoformat()
        except ValueError:
            return None

    full_match = re.search(r"\b(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})\b", source)
    if full_match:
        d, m, y = full_match.groups()
        year = int(y)
        if year < 100:
            year += 2000
        try:
            return date(year, int(m), int(d)).isoformat()
        except ValueError:
            return None

    short_match = re.search(r"\b(\d{1,2})[./-](\d{1,2})\b", source)
    if short_match:
        d, m = map(int, short_match.groups())
        for candidate_year in (today.year, today.year + 1):
            try:
                dt = date(candidate_year, m, d)
            except ValueError:
                continue
            if dt >= today:
                return dt.isoformat()
        return None

    month_map = {
        "января": 1,
        "февраля": 2,
        "марта": 3,
        "апреля": 4,
        "мая": 5,
        "июня": 6,
        "июля": 7,
        "августа": 8,
        "сентября": 9,
        "октября": 10,
        "ноября": 11,
        "декабря": 12,
    }
    text_month_match = re.search(
        r"\b(\d{1,2})\s+(января|февраля|марта|апреля|мая|июня|июля|августа|сентября|октября|ноября|декабря)(?:\s+(\d{4}))?\b",
        normalized,
    )
    if text_month_match:
        day_num = int(text_month_match.group(1))
        month_num = month_map.get(text_month_match.group(2), 0)
        year_num = int(text_month_match.group(3)) if text_month_match.group(3) else today.year
        try:
            dt = date(year_num, month_num, day_num)
        except ValueError:
            return None
        if not text_month_match.group(3) and dt < today:
            try:
                dt = date(today.year + 1, month_num, day_num)
            except ValueError:
                return None
        return dt.isoformat()

    parsed_day = parse_day(normalized)
    if parsed_day:
        return nearest_date_for_weekday(parsed_day, base_date=today).isoformat()

    return None


def todo_due_date(todo: dict, *, base_date: date | None = None) -> str | None:
    raw = str(todo.get("due_date") or "").strip()
    if re.match(r"^\d{4}-\d{2}-\d{2}$", raw):
        return raw
    migrated = parse_due_date_input(str(todo.get("date") or "") or str(todo.get("day") or ""), base_date=base_date)
    return migrated


def parse_day_or_date(text: str | None) -> tuple[str | None, str | None]:
    due_date = parse_due_date_input(text)
    if due_date:
        return due_date, None
    return None, parse_day_or_relative(text)


def week_bounds(anchor: date | None = None) -> tuple[date, date]:
    base = anchor or datetime.now().date()
    start = base - timedelta(days=base.weekday())
    end = start + timedelta(days=6)
    return start, end


def month_bounds(anchor: date | None = None) -> tuple[date, date]:
    base = anchor or datetime.now().date()
    start = date(base.year, base.month, 1)
    if base.month == 12:
        next_month = date(base.year + 1, 1, 1)
    else:
        next_month = date(base.year, base.month + 1, 1)
    end = next_month - timedelta(days=1)
    return start, end


def parse_period_request(text: str | None, *, base_date: date | None = None) -> tuple[str | None, str | None, str]:
    source = text or ""
    normalized = normalize_text(source)
    today = base_date or datetime.now().date()

    if any(contains_phrase(normalized, phrase) for phrase in ("прошлая неделя", "на прошлой неделе")):
        start, end = week_bounds(today - timedelta(days=7))
        return start.isoformat(), end.isoformat(), "прошлая неделя"
    if any(contains_phrase(normalized, phrase) for phrase in ("следующая неделя", "на следующей неделе")):
        start, end = week_bounds(today + timedelta(days=7))
        return start.isoformat(), end.isoformat(), "следующая неделя"
    if any(contains_phrase(normalized, phrase) for phrase in ("эта неделя", "текущая неделя", "на неделе", "за неделю")):
        start, end = week_bounds(today)
        return start.isoformat(), end.isoformat(), "текущая неделя"

    if any(contains_phrase(normalized, phrase) for phrase in ("прошлый месяц", "за прошлый месяц")):
        prev_month_anchor = date(today.year - 1, 12, 15) if today.month == 1 else date(today.year, today.month - 1, 15)
        start, end = month_bounds(prev_month_anchor)
        return start.isoformat(), end.isoformat(), "прошлый месяц"
    if any(contains_phrase(normalized, phrase) for phrase in ("следующий месяц",)):
        next_month_anchor = date(today.year + 1, 1, 15) if today.month == 12 else date(today.year, today.month + 1, 15)
        start, end = month_bounds(next_month_anchor)
        return start.isoformat(), end.isoformat(), "следующий месяц"
    if any(contains_phrase(normalized, phrase) for phrase in ("этот месяц", "текущий месяц", "за месяц")):
        start, end = month_bounds(today)
        return start.isoformat(), end.isoformat(), "текущий месяц"

    range_match = re.search(
        r"\b(?:с|от)\s+(\d{1,2}[./-]\d{1,2}(?:[./-]\d{2,4})?)\s+(?:по|до)\s+(\d{1,2}[./-]\d{1,2}(?:[./-]\d{2,4})?)\b",
        source,
        flags=re.IGNORECASE,
    )
    if range_match:
        left = parse_due_date_input(range_match.group(1), base_date=today)
        right = parse_due_date_input(range_match.group(2), base_date=today)
        if left and right:
            start, end = sorted((left, right))
            return start, end, f"{start}..{end}"

    due_date = parse_due_date_input(source, base_date=today)
    if due_date:
        return due_date, due_date, due_date

    day = parse_day_or_relative(source)
    if day:
        due = nearest_date_for_weekday(day, base_date=today).isoformat()
        return due, due, due

    start, end = week_bounds(today)
    return start.isoformat(), end.isoformat(), "текущая неделя"


def parse_priority(text: str | None) -> str:
    normalized = normalize_text(text or "")
    for priority, aliases in PRIORITY_ALIASES.items():
        if any(contains_phrase(normalized, alias) for alias in aliases):
            return priority
    return "medium"


def priority_label(value: str | None) -> str:
    if value == "high":
        return "высокий приоритет"
    if value == "low":
        return "низкий приоритет"
    return "средний приоритет"


def parse_recurrence(text: str | None) -> str | None:
    normalized = normalize_text(text or "")
    for recurrence, aliases in RECURRING_ALIASES.items():
        if any(contains_phrase(normalized, alias) for alias in aliases):
            return recurrence
    return None


def parse_tags(text: str | None) -> list[str]:
    normalized = normalize_text(text or "")
    tags: list[str] = []
    for tag, aliases in TAG_ALIASES.items():
        if any(contains_phrase(normalized, alias) for alias in aliases):
            tags.append(tag)
    return tags


def extract_tag_filter(text: str | None) -> str | None:
    normalized = normalize_text(text or "")
    for tag, aliases in TAG_ALIASES.items():
        if any(contains_phrase(normalized, alias) for alias in aliases):
            return tag
    return None


def recurrence_matches_today(todo: dict, current_day: str, current_date: datetime) -> bool:
    due = str(todo.get("due_date") or "")
    if due:
        return due == current_date.date().isoformat()
    return str(todo.get("day") or "") == current_day


def is_recurring_done_for_today(todo: dict, current_date: datetime) -> bool:
    return str(todo.get("status") or "active") == "done"


def extract_numbers(text: str | None) -> list[int]:
    if not text:
        return []
    normalized = normalize_text(text)
    out: list[int] = []

    # Digits first
    for token in normalized.split():
        if token.isdigit():
            out.append(int(token))

    tokens = normalized.split()
    i = 0
    while i < len(tokens):
        token = tokens[i]
        if token in NUM_WORDS:
            val = NUM_WORDS[token]
            # combine tens + units, like "двадцать три"
            if val in (20, 30, 40, 50) and i + 1 < len(tokens):
                nxt = tokens[i + 1]
                nxt_val = NUM_WORDS.get(nxt)
                if nxt_val is not None and 1 <= nxt_val <= 9:
                    out.append(val + nxt_val)
                    i += 2
                    continue
            out.append(val)
        i += 1

    return out


def parse_time(text: str | None) -> str | None:
    if not text:
        return None

    normalized = normalize_text(text)
    is_evening = any(word in normalized for word in ("вечера", "дня", "днем", "пополудни"))
    is_morning = any(word in normalized for word in ("утра", "утром", "ночи"))

    # Conversational style: "пол восьмого" -> 07:30
    half_match = re.search(r"\bпол\s+([а-я]+)\b", normalized)
    if half_match:
        nxt_hour = HALF_NEXT_HOUR.get(half_match.group(1))
        if nxt_hour:
            hour = nxt_hour - 1
            if hour == 0:
                hour = 12
            if is_evening and 1 <= hour <= 11:
                hour += 12
            return f"{hour:02d}:30"

    # "19:05", "7 30", "7:5", "7-30", "19.05"
    match = re.search(r"\b([01]?\d|2[0-3])\s*[:.\- ]\s*([0-5]?\d)\b", normalized)
    if match:
        hh = int(match.group(1))
        mm = int(match.group(2))
        if mm <= 59:
            if is_evening and 1 <= hh <= 11:
                hh += 12
            elif is_morning and hh == 12:
                hh = 0
            return f"{hh:02d}:{mm:02d}"

    # "730", "0730", "1905"
    compact_match = re.search(r"\b(\d{3,4})\b", normalized)
    if compact_match:
        raw = compact_match.group(1)
        hh = int(raw[:-2])
        mm = int(raw[-2:])
        if 0 <= hh <= 23 and 0 <= mm <= 59:
            if is_evening and 1 <= hh <= 11:
                hh += 12
            elif is_morning and hh == 12:
                hh = 0
            return f"{hh:02d}:{mm:02d}"

    nums = extract_numbers(normalized)
    if len(nums) >= 2:
        hh, mm = nums[0], nums[1]
        if 0 <= hh <= 23 and 0 <= mm <= 59:
            if is_evening and 1 <= hh <= 11:
                hh += 12
            elif is_morning and hh == 12:
                hh = 0
            return f"{hh:02d}:{mm:02d}"
    elif len(nums) == 1 and 0 <= nums[0] <= 23:
        hh = nums[0]
        if is_evening and 1 <= hh <= 11:
            hh += 12
        elif is_morning and hh == 12:
            hh = 0
        return f"{hh:02d}:00"

    return None


def capture_time_value() -> tuple[bool, str | None]:
    """Ask for time and retry if parsing failed.

    Returns (cancelled, time_value).
    """
    for attempt in range(3):
        prompt = (
            "Время, например 18 30, или без времени."
            if attempt == 0
            else "Не понял время. Скажи еще раз, например 19 45, или без времени."
        )
        time_text = listen_once(prompt, retries=1, phrase_time_limit=6)
        if detect_stop(time_text):
            return True, None
        if not time_text:
            continue
        if any(contains_phrase(time_text, phrase) for phrase in NO_TIME_PHRASES):
            return False, None

        parsed = parse_time(time_text)
        if parsed:
            speak(f"Записал время {parsed}.")
            return False, parsed

    speak("Время не распознал, сохраню без времени.")
    return False, None


def parse_index(text: str | None) -> int | None:
    nums = extract_numbers(text)
    if not nums:
        return None
    value = nums[0]
    return value if value > 0 else None


def parse_explicit_index(text: str | None) -> int | None:
    normalized = normalize_text(text or "")
    if not normalized:
        return None
    if "номер" in normalized:
        match = re.search(r"\bномер\s+(\d+)\b", normalized)
        if match:
            value = int(match.group(1))
            return value if value > 0 else None
    return None


def format_todo_line(index: int, todo: dict) -> str:
    done_value = str(todo.get("status") or ("done" if todo.get("done") else "active")) == "done"
    status = "сделано" if done_value else "не сделано"
    due_date = str(todo.get("due_date") or "")
    day = todo.get("day") or "без дня"
    if due_date:
        try:
            dt = datetime.fromisoformat(due_date).date()
            day = f"{dt.strftime('%d.%m.%Y')} ({weekday_ru(dt)})"
        except ValueError:
            day = due_date
    time_value = todo.get("time") or "без времени"
    priority = priority_label(todo.get("priority"))
    tags = todo.get("tags") if isinstance(todo.get("tags"), list) else []
    tags_text = f" теги: {', '.join(tags)}." if tags else ""
    text = (todo.get("title") or todo.get("text") or "").strip()
    details = (todo.get("details") or "").strip()
    if details:
        return f"{index}. {text}. {details}. {day}, {time_value}. {priority}. {status}.{tags_text}"
    return f"{index}. {text}. {day}, {time_value}. {priority}. {status}.{tags_text}"


def filter_todos_by_day(todos: list[dict], day: str | None) -> list[tuple[int, dict]]:
    items: list[tuple[int, dict]] = []
    for idx, todo in enumerate(todos):
        if day is None:
            items.append((idx, todo))
            continue
        due_date = str(todo.get("due_date") or "")
        due_day = str(todo.get("day") or "")
        if due_date:
            try:
                due_day = weekday_ru(datetime.fromisoformat(due_date).date())
            except ValueError:
                pass
        if due_day == day:
            items.append((idx, todo))
    return items


def filter_todos_by_date(todos: list[dict], due_date: str | None) -> list[tuple[int, dict]]:
    if not due_date:
        return list(enumerate(todos))
    items: list[tuple[int, dict]] = []
    for idx, todo in enumerate(todos):
        if str(todo.get("due_date") or "") == due_date:
            items.append((idx, todo))
    return items


def filter_todos_by_range(
    todos: list[dict],
    start_date: str | None,
    end_date: str | None,
) -> list[tuple[int, dict]]:
    if not start_date or not end_date:
        return list(enumerate(todos))
    items: list[tuple[int, dict]] = []
    for idx, todo in enumerate(todos):
        due = str(todo.get("due_date") or "")
        if start_date <= due <= end_date:
            items.append((idx, todo))
    return items


def filter_todos_by_tag(items: list[tuple[int, dict]], tag: str | None) -> list[tuple[int, dict]]:
    if not tag:
        return items
    out: list[tuple[int, dict]] = []
    for idx, todo in items:
        tags = todo.get("tags") if isinstance(todo.get("tags"), list) else []
        if tag in tags:
            out.append((idx, todo))
    return out


def todo_items_for_period(
    person: Person,
    *,
    start_date: str | None = None,
    end_date: str | None = None,
    tag: str | None = None,
) -> list[tuple[int, dict]]:
    todos = load_todos(person)
    items = filter_todos_by_range(todos, start_date, end_date)
    return filter_todos_by_tag(items, tag)


def resolve_day_value(text: str | None, prompt: str = "Скажи день недели.") -> str | None:
    day = parse_day(text)
    if day:
        return day
    answer = listen_once(prompt, retries=1, phrase_time_limit=3)
    if detect_stop(answer):
        return None
    return parse_day(answer)


def parse_days_in_text(text: str | None) -> list[str]:
    if not text:
        return []
    normalized = normalize_text(text)
    hits: list[tuple[int, str]] = []
    for canonical, aliases in DAY_ALIASES.items():
        for alias in (canonical, *aliases):
            match = re.search(rf"\b{re.escape(alias)}\b", normalized)
            if match:
                hits.append((match.start(), canonical))
                break
    hits.sort(key=lambda x: x[0])
    out: list[str] = []
    for _pos, day in hits:
        if not out or out[-1] != day:
            out.append(day)
    rel_day = day_from_relative_word(normalized)
    if rel_day and rel_day not in out:
        out.append(rel_day)
    return out


def _day_alias_set() -> set[str]:
    out: set[str] = set()
    for canonical, aliases in DAY_ALIASES.items():
        out.add(canonical)
        out.update(aliases)
    return out


def _tokens_for_move_match(text: str | None) -> set[str]:
    if not text:
        return set()
    normalized = normalize_text(text)
    normalized = re.sub(r"\b\d{1,2}\s*[:.\- ]\s*\d{1,2}\b", " ", normalized)
    normalized = re.sub(r"\b\d{3,4}\b", " ", normalized)
    normalized = re.sub(r"\b\d+\b", " ", normalized)
    normalized = re.sub(r"\bпол\s+[а-я]+\b", " ", normalized)

    stop_words = {
        "перенеси",
        "перенести",
        "перенес",
        "сдвинь",
        "задачу",
        "дело",
        "таск",
        "на",
        "в",
        "к",
        "с",
        "со",
        "из",
        "во",
        "и",
        "или",
        "пожалуйста",
    }
    stop_words.update(_day_alias_set())
    stop_words.update({"утра", "вечера", "дня", "ночи"})

    tokens = {tok for tok in normalized.split() if tok and tok not in stop_words and len(tok) > 1}
    return tokens


def _move_from_single_phrase(person: Person, text: str) -> bool:
    """Try direct move: 'перенеси вторник тренировка на среду 19:30'."""
    days = parse_days_in_text(text)
    if len(days) < 2:
        return False

    source_day = days[0]
    target_day = days[-1]
    target_time = extract_time_from_inline(text)
    if target_time is None:
        return False

    query_tokens = _tokens_for_move_match(text)
    if not query_tokens:
        return False

    todos = load_todos(person)
    candidates: list[tuple[float, int, dict]] = []
    for idx, todo in enumerate(todos):
        due = str(todo.get("due_date") or "")
        todo_day = str(todo.get("day") or "")
        if due:
            try:
                todo_day = weekday_ru(datetime.fromisoformat(due).date())
            except ValueError:
                pass
        if todo_day != source_day:
            continue
        title = (todo.get("title") or todo.get("text") or "").strip()
        details = (todo.get("details") or "").strip()
        todo_tokens = _tokens_for_move_match(f"{title} {details}")
        if not todo_tokens:
            continue
        overlap = len(query_tokens & todo_tokens)
        if overlap <= 0:
            continue
        score = overlap / max(1, len(query_tokens))
        candidates.append((score, idx, todo))

    if not candidates:
        return False

    candidates.sort(key=lambda item: item[0], reverse=True)
    best_score, best_idx, best_todo = candidates[0]
    if best_score < 0.2:
        return False

    previous_state = dict(todos[best_idx])
    apply_move(todos[best_idx], target_day, target_time)
    target_due = nearest_date_for_weekday(target_day, include_today=False)
    todos[best_idx]["due_date"] = target_due.isoformat()
    todos[best_idx]["day"] = target_day
    transition_task(todos[best_idx], "todo")
    save_todos(person, todos)
    push_history(person, "update_item", {"id": previous_state.get("id"), "before": previous_state})

    title = (best_todo.get("title") or best_todo.get("text") or "задача").strip()
    confirm(f"Перенес: {title}. На {target_due.strftime('%d.%m.%Y')} в {target_time}.")
    return True


def speak_todos(person: Person, day: str | None = None, tag: str | None = None) -> list[tuple[int, dict]]:
    todos = load_todos(person)
    if not todos:
        speak("Список пуст.")
        return []

    filtered = filter_todos_by_day(todos, day)
    filtered = filter_todos_by_tag(filtered, tag)
    if day and not filtered:
        speak(f"На {day} дел нет.")
        return []
    if tag and not filtered:
        speak(f"По тегу {tag} дел нет.")
        return []

    if day:
        speak(f"На {day} дел: {len(filtered)}")
    else:
        speak(f"Дел: {len(filtered)}")

    for local_idx, (_global_idx, todo) in enumerate(filtered, start=1):
        line = format_todo_line(local_idx, todo)
        print(line)
        speak(line)
    return filtered


def strip_add_prefix(text: str) -> str:
    cleaned = text.strip()
    for prefix in ADD_PREFIXES:
        if contains_phrase(cleaned, prefix):
            pattern = r"^\s*" + re.escape(prefix) + r"\b[:,\s-]*"
            cleaned = re.sub(pattern, "", cleaned, flags=re.IGNORECASE)
            break
    return " ".join(cleaned.split())


def extract_time_from_inline(text: str) -> str | None:
    normalized = normalize_text(text)
    patterns = (
        r"\b([01]?\d|2[0-3])\s*[:.\-]\s*([0-5]?\d)\b",
        r"\b([01]?\d|2[0-3])\s+([0-5]?\d)\b",
        r"\b(\d{3,4})\b",
        r"\b(?:в|к)\s+([01]?\d|2[0-3])\s*[:.\- ]\s*([0-5]?\d)\b",
        r"\b(?:в|к)\s+(\d{3,4})\b",
        r"\b(?:в|к)\s+([01]?\d|2[0-3])\b(?:\s+(утра|вечера|дня|ночи))?",
        r"\b([01]?\d|2[0-3])\b(?:\s+(утра|вечера|дня|ночи))",
        r"\bпол\s+[а-я]+\b(?:\s+(утра|вечера|дня|ночи))?",
    )
    for pat in patterns:
        match = re.search(pat, normalized)
        if not match:
            continue
        start, end = match.span()
        parsed = parse_time(normalized[start:end])
        if parsed:
            return parsed
    return None


def extract_task_parts(raw_text: str) -> tuple[str, str | None, str | None, str | None]:
    """Returns (title, details, day, time)."""
    cleaned = strip_add_prefix(raw_text)
    day = parse_day(cleaned)
    time_value = extract_time_from_inline(cleaned)

    # Optional details marker
    details = None
    for marker in (" описание ", " подробно ", " чтобы "):
        if marker in f" {cleaned.lower()} ":
            parts = cleaned.split(marker.strip(), 1)
            if len(parts) == 2:
                cleaned = parts[0].strip()
                details = parts[1].strip()
            break

    # Remove day mentions from title text
    for canonical, aliases in DAY_ALIASES.items():
        all_aliases = (canonical, *aliases)
        for alias in all_aliases:
            cleaned = re.sub(
                rf"\b(?:на|в|по)?\s*{re.escape(alias)}\b",
                " ",
                cleaned,
                flags=re.IGNORECASE,
            )

    # Remove time phrases from title text
    cleaned = re.sub(r"\b(?:в|к)\s+\d{1,2}\s*[:.\- ]\s*\d{1,2}\b", " ", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\b(?:в|к)\s+\d{3,4}\b", " ", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\b\d{1,2}\s*[:.\- ]\s*\d{1,2}\b", " ", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\b\d{3,4}\b", " ", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\b(?:в|к)\s+\d{1,2}\b(?:\s+(утра|вечера|дня|ночи))?", " ", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\b\d{1,2}\b(?:\s+(утра|вечера|дня|ночи))", " ", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\bпол\s+[а-я]+\b(?:\s+(утра|вечера|дня|ночи))?", " ", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\bкаждый\s+день\b", " ", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\bкаждый\s+будний\s+день\b", " ", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\bпо\s+будням\b", " ", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\b(важно|срочно|обычно|не\s+срочно|низкий\s+приоритет|высокий\s+приоритет)\b", " ", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\bза\s+\d{1,3}\s*(минут|мин|м)\b", " ", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\b(задачу|дело|таск)\b", " ", cleaned, flags=re.IGNORECASE)
    cleaned = cleaned.strip(" ,.-:")
    cleaned = " ".join(cleaned.split())
    if not cleaned:
        cleaned = raw_text.strip()

    return cleaned, details, day, time_value


def extract_delete_query(text: str | None) -> str:
    if not text:
        return ""
    cleaned = normalize_text(text)
    cleaned = re.sub(r"\b(удали|удалить|удаляем|убери|убрать|стереть|стери|очисти|очистить)\b", " ", cleaned)
    cleaned = re.sub(r"\b(дела|дело|задачу|задача|задачи|расписание|список|на)\b", " ", cleaned)
    for canonical, aliases in DAY_ALIASES.items():
        for alias in (canonical, *aliases):
            cleaned = re.sub(rf"\b{re.escape(alias)}\b", " ", cleaned)
    cleaned = re.sub(r"\bвсе\b", " ", cleaned)
    cleaned = re.sub(r"\b\d+\b", " ", cleaned)
    return " ".join(cleaned.split())


def is_clear_all_request(text: str | None) -> bool:
    if not text:
        return False
    normalized = normalize_text(text)
    has_clear = any(
        contains_phrase(normalized, phrase)
        for phrase in ("очисти", "очистить", "удали все", "удалить все")
    )
    has_scope = any(
        contains_phrase(normalized, phrase)
        for phrase in ("все расписание", "все дела", "полностью", "целиком", "полный список")
    )
    has_day = parse_day(normalized) is not None
    return has_clear and has_scope and not has_day


def find_best_todo_match(candidates: list[tuple[int, dict]], query: str) -> tuple[int, dict] | None:
    if not candidates or not query:
        return None

    q = normalize_text(query)
    best: tuple[int, dict] | None = None
    best_score = 0.0
    for idx, todo in candidates:
        haystack = normalize_text(
            " ".join(
                [
                    str(todo.get("title") or ""),
                    str(todo.get("text") or ""),
                    str(todo.get("details") or ""),
                ]
            )
        )
        if not haystack:
            continue
        score = similarity(q, haystack)
        overlap = token_overlap_score(q, haystack)
        score = max(score, overlap)
        if q in haystack:
            score = max(score, 0.95)
        elif has_all_parts(q.split(), haystack):
            score = max(score, 0.8)
        if score > best_score:
            best_score = score
            best = (idx, todo)

    return best if best and best_score >= 0.3 else None


def parse_reminder_offsets(text: str | None) -> list[int]:
    normalized = normalize_text(text or "")
    offsets: list[int] = []
    for match in re.finditer(r"\bза\s+(\d{1,3})\s*(?:минут|мин|м)\b", normalized):
        value = int(match.group(1))
        if 1 <= value <= 180 and value not in offsets:
            offsets.append(value)
    return offsets or list(DEFAULT_REMINDER_OFFSETS)


def expand_recurrence_days(recurrence: str | None, parsed_day: str | None) -> list[str]:
    # Recurring task is represented by a single record (no duplication by weekdays).
    if recurrence in ("daily", "weekdays"):
        anchor = parsed_day or DAY_ORDER[datetime.now().weekday()]
        return [anchor]
    return [parsed_day] if parsed_day else []


def extract_bulk_delete_keyword(text: str | None) -> str:
    normalized = normalize_text(text or "")
    match = re.search(r"\b(?:где|с)\s+(?:есть|словом|текстом)?\s*([а-я0-9\s-]{2,})", normalized)
    if not match:
        return ""
    keyword = " ".join(match.group(1).split())
    for filler in ("на", "вторник", "среда", "среду", "понедельник", "четверг", "пятница", "суббота", "воскресенье"):
        keyword = re.sub(rf"\b{re.escape(filler)}\b", " ", keyword)
    return " ".join(keyword.split())


def _now_weekday_ru() -> str:
    return DAY_ORDER[datetime.now().weekday()]


def _play_reminder_cue() -> None:
    if not winsound:
        return
    try:
        winsound.PlaySound("SystemNotification", winsound.SND_ALIAS | winsound.SND_ASYNC)
    except Exception:
        try:
            winsound.MessageBeep(winsound.MB_ICONASTERISK)
        except Exception:
            pass


def _todo_due_in_offset(todo: dict, now: datetime, weekday: str) -> tuple[str, int] | None:
    if str(todo.get("workflow_status") or "") == "done" or str(todo.get("status") or "") == "done" or bool(todo.get("done")):
        return None
    due_date = str(todo.get("due_date") or "")
    if due_date and due_date != now.date().isoformat():
        return None
    if not due_date and not recurrence_matches_today(todo, weekday, now):
        return None

    time_value = todo.get("time")
    if not time_value or not re.match(r"^\d{2}:\d{2}$", str(time_value)):
        return None

    seconds_left = seconds_until(str(time_value), now)
    if seconds_left is None:
        return None
    if seconds_left < 0:
        return None
    offsets = todo.get("reminder_offsets")
    if not isinstance(offsets, list) or not offsets:
        offsets = list(DEFAULT_REMINDER_OFFSETS)
    for offset in sorted([int(v) for v in offsets if isinstance(v, int) or str(v).isdigit()], reverse=True):
        lower_bound = offset * 60
        upper_bound = lower_bound + 59
        if lower_bound <= seconds_left <= upper_bound:
            return time_value, offset
    return None


def check_due_reminders(person: Person) -> None:
    todos = load_todos(person)
    if not todos:
        return

    now = datetime.now()
    weekday = _now_weekday_ru()
    changed = False

    for todo in todos:
        due = _todo_due_in_offset(todo, now, weekday)
        if not due:
            continue
        time_value, offset = due
        reminder_key = f"{now.date().isoformat()}:{time_value}:{offset}"
        if todo.get("last_reminder_key") == reminder_key:
            continue

        title = (todo.get("title") or todo.get("text") or "дело").strip()
        speak(f"Напоминание: через {offset} минут дело {title}. Время {time_value}.")
        _play_reminder_cue()
        todo["last_reminder_key"] = reminder_key
        changed = True

    if changed:
        save_todos(person, todos)


def _apply_reminder_reply(person: Person, todo: dict, reply: str | None) -> bool:
    if not reply:
        return False

    normalized = normalize_text(reply)
    if any(contains_phrase(normalized, phrase) for phrase in ("сделано", "отметь сделано", "выполнено", "готово")):
        transition_task(todo, "done")
        speak(f"{person.display_name}: отметил сделанным.")
        return True

    if any(contains_phrase(normalized, phrase) for phrase in ("перенеси", "перенести", "сдвинь", "потом")):
        target_due_date = parse_due_date_input(normalized)
        if target_due_date is None:
            days = parse_days_in_text(normalized)
            target_day = days[-1] if days else parse_day_or_relative(normalized)
            if target_day:
                target_due_date = nearest_date_for_weekday(target_day, base_date=datetime.now().date(), include_today=False).isoformat()
        target_time = extract_time_from_inline(normalized)

        if target_due_date is None and target_time is None:
            speak(f"{person.display_name}: не понял перенос.")
            return False

        if target_due_date is not None:
            todo["due_date"] = target_due_date
            todo["day"] = weekday_ru(datetime.fromisoformat(target_due_date).date())
        if target_time is not None:
            todo["time"] = target_time
        transition_task(todo, "todo")
        todo.pop("last_reminder_key", None)
        speak(
            f"{person.display_name}: перенес. "
            f"{todo.get('due_date') or todo.get('day') or 'без дня'}, {todo.get('time') or 'без времени'}."
        )
        return True

    return False


def process_global_reminders() -> None:
    """Run reminders for all family members from the main assistant loop."""
    bootstrap_data()
    now = datetime.now()
    weekday = DAY_ORDER[now.weekday()]

    family_items = load_family_tasks()
    family_changed = False
    for item in family_items:
        if str(item.get("workflow_status") or "todo") == "done":
            continue
        start_at = str(item.get("start_at") or "")
        start_dt = parse_iso_datetime(start_at)
        if start_dt is None:
            continue
        time_value = start_dt.strftime("%H:%M")
        seconds_left = seconds_until(time_value, now)
        if seconds_left is None or seconds_left < 0:
            continue
        offsets = item.get("reminder_offsets")
        if not isinstance(offsets, list) or not offsets:
            offsets = list(DEFAULT_REMINDER_OFFSETS)
        matched_offset = None
        for offset in sorted([int(v) for v in offsets if isinstance(v, int) or str(v).isdigit()], reverse=True):
            lower_bound = offset * 60
            upper_bound = lower_bound + 59
            if lower_bound <= seconds_left <= upper_bound:
                matched_offset = offset
                break
        if matched_offset is None:
            continue
        reminder_key = f"{now.date().isoformat()}:{time_value}:{matched_offset}"
        if item.get("last_reminder_key") == reminder_key:
            continue

        assignees = [str(p) for p in item.get("assignees") if person_by_key(str(p))]
        participant_names = ", ".join([person_by_key(p).display_name for p in assignees if person_by_key(p)])
        title = (item.get("title") or item.get("text") or "семейное дело").strip()
        details = str(item.get("details") or "").strip()
        text = (
            f"Семейное дело: {title}. "
            f"Старт {start_dt.strftime('%d.%m.%Y %H:%M')}, через {matched_offset} минут. "
            f"Участники: {participant_names or 'не указаны'}."
        )
        if details:
            text += f" Детали: {details}"

        from notifier import desktop_notify, push_by_visibility

        desktop_notify(text, title="Семейное напоминание")
        for participant in assignees:
            push_by_visibility(participant, text)
        speak(text)
        item["last_reminder_key"] = reminder_key
        item["updated_at"] = datetime.now().isoformat(timespec="seconds")
        family_changed = True
        break

    if family_changed:
        save_family_tasks(family_items)

    for person in PEOPLE:
        todos = load_todos(person)
        if not todos:
            continue

        for todo in todos:
            due = _todo_due_in_offset(todo, now, weekday)
            if not due:
                continue
            time_value, offset = due
            reminder_key = f"{now.date().isoformat()}:{time_value}:{offset}"
            if todo.get("last_reminder_key") == reminder_key:
                continue

            title = (todo.get("title") or todo.get("text") or "дело").strip()
            speak(
                f"{person.display_name}, напоминание: {title}. "
                f"Время {time_value}, через {offset} минут. Скажи: сделано, или перенеси на день и время."
            )
            _play_reminder_cue()
            reply = listen_once("", retries=0, phrase_time_limit=4)
            _apply_reminder_reply(person, todo, reply)
            todo["last_reminder_key"] = reminder_key
            save_todos(person, todos)
            return


def add_todo(person: Person, initial_text: str | None = None) -> None:
    task_text = initial_text if initial_text and len(initial_text.split()) > 1 else None
    if not task_text:
        log_event("todo_add_failed", person=person.key, reason="empty_text")
        speak("Скажи команду одной фразой: день, время и задачу.")
        return
    if detect_stop(task_text):
        log_event("todo_add_failed", person=person.key, reason="cancelled")
        speak("Отменено.")
        return
    if not task_text:
        log_event("todo_add_failed", person=person.key, reason="not_understood")
        speak("Не понял текст дела.")
        return

    title, details, day_value, time_value = extract_task_parts(task_text)
    due_date_value = parse_due_date_input(task_text)
    if due_date_value is None and day_value:
        due_date_value = nearest_date_for_weekday(day_value).isoformat()
    recurrence = parse_recurrence(task_text)
    priority = parse_priority(task_text)
    tags = parse_tags(task_text)
    reminder_offsets = parse_reminder_offsets(task_text)
    if (not due_date_value and not recurrence) or not time_value:
        log_event(
            "todo_add_failed",
            person=person.key,
            reason="missing_date_or_time",
            parsed_due=due_date_value or "",
            parsed_time=time_value or "",
            text=task_text,
        )
        speak("Для добавления скажи дату/день и время. Например: добавь 25.04 в 19 30 кормить крыс.")
        return

    todos = load_todos(person)
    current_id = max([item.get("id", 0) for item in todos], default=0)
    created_ids: list[int] = []
    series_id = f"series-{uuid.uuid4().hex[:12]}" if recurrence else None

    dates_to_create: list[date] = []
    if recurrence:
        start_dt = datetime.fromisoformat(due_date_value or datetime.now().date().isoformat()).date()
        end_dt = start_dt + timedelta(days=RECURRENCE_HORIZON_DAYS - 1)
        cursor = start_dt
        while cursor <= end_dt:
            if recurrence == "daily" or (recurrence == "weekdays" and cursor.weekday() <= 4):
                dates_to_create.append(cursor)
            cursor += timedelta(days=1)
    elif due_date_value:
        dates_to_create = [datetime.fromisoformat(due_date_value).date()]

    for due_dt in dates_to_create:
        due_iso = due_dt.isoformat()
        conflicts = family_conflicts_for_person(person.key, due_iso, time_value)
        if conflicts:
            conflict = conflicts[0]
            title = str(conflict.get("title") or conflict.get("text") or "семейное дело")
            start_at = str(conflict.get("start_at") or "")
            log_event(
                "todo_add_blocked_family_conflict",
                person=person.key,
                due_date=due_iso,
                time=time_value,
                family_task_id=int(conflict.get("id") or 0),
            )
            speak(
                f"Нельзя создать личную задачу: конфликт с семейным делом '{title}' ({start_at})."
            )
            return

        current_id += 1
        created_ids.append(current_id)
        todos.append(
            {
                "id": current_id,
                "owner_key": person.key,
                "title": title.strip(),
                "text": title.strip(),  # backward compatibility
                "details": (details or "").strip(),
                "due_date": due_iso,
                "day": weekday_ru(due_dt),
                "time": time_value,
                "priority": priority,
                "tags": tags,
                "status": "active",
                "done": False,
                "workflow_status": "todo",
                "sort_order": current_id,
                "is_family": False,
                "participants": [],
                "start_at": None,
                "duration_minutes": None,
                "recurrence_rule": recurrence,
                "series_id": series_id,
                "generated_from_rule": bool(recurrence),
                "reminder_offsets": reminder_offsets,
                "created_at": datetime.now().isoformat(timespec="seconds"),
                "updated_at": datetime.now().isoformat(timespec="seconds"),
                "version": 1,
            }
        )
    save_todos(person, todos)
    push_history(person, "add", {"created_ids": created_ids})
    log_event(
        "todo_add",
        person=person.key,
        count=len(created_ids),
        recurrence=recurrence or "",
        time=time_value,
        day=day_value or "",
        due_date=due_date_value or "",
        title=title.strip(),
    )
    if recurrence:
        confirm(f"Добавил повторяемую задачу. {priority_label(priority)}.")
    else:
        confirm(f"Добавил. {priority_label(priority)}.")


def delete_todo(person: Person, initial_text: str | None = None) -> None:
    todos = load_todos(person)
    if not todos:
        speak("Список пуст.")
        return

    if is_clear_all_request(initial_text):
        push_history(person, "replace_all", {"todos_before": todos})
        save_todos(person, [])
        log_event("todo_clear_all", person=person.key)
        confirm("Очистил все дела полностью.")
        return

    due_date, day = parse_day_or_date(initial_text)
    if not day and not due_date:
        speak("Скажи дату или день в этой же фразе. Например: удали 25.04 номер 1.")
        return

    filtered = filter_todos_by_date(todos, due_date) if due_date else filter_todos_by_day(todos, day)
    if not filtered:
        label = due_date or day or "выбранную дату"
        speak(f"На {label} дел нет.")
        return

    normalized_text = normalize_text(initial_text or "")
    remove_all_for_day = any(
        contains_phrase(normalized_text, phrase)
        for phrase in ("все дела", "очисти расписание", "очистить расписание", "очисти день", "очистить день")
    )
    if remove_all_for_day:
        if due_date:
            removed_items = [todo for todo in todos if str(todo.get("due_date") or "") == due_date]
            todos = [todo for todo in todos if str(todo.get("due_date") or "") != due_date]
        else:
            removed_items = [todo for todo in todos if todo.get("day") == day]
            todos = [todo for todo in todos if todo.get("day") != day]
        save_todos(person, todos)
        push_history(person, "restore_items", {"items": removed_items})
        log_event("todo_clear_day", person=person.key, day=day or "", due_date=due_date or "", removed=len(removed_items))
        confirm(f"Очистил {due_date or day} полностью.")
        return

    bulk_keyword = extract_bulk_delete_keyword(initial_text)
    if bulk_keyword:
        removed_items = []
        kept_items = []
        for todo in todos:
            if due_date and str(todo.get("due_date") or "") != due_date:
                kept_items.append(todo)
                continue
            if not due_date and todo.get("day") != day:
                kept_items.append(todo)
                continue
            haystack = normalize_text(
                " ".join(
                    [
                        str(todo.get("title") or ""),
                        str(todo.get("text") or ""),
                        str(todo.get("details") or ""),
                    ]
                )
            )
            if bulk_keyword in haystack:
                removed_items.append(todo)
            else:
                kept_items.append(todo)
        if not removed_items:
            speak("По этому слову ничего не нашел.")
            return
        save_todos(person, kept_items)
        push_history(person, "restore_items", {"items": removed_items})
        log_event(
            "todo_delete_keyword",
            person=person.key,
            day=day or "",
            due_date=due_date or "",
            keyword=bulk_keyword,
            removed=len(removed_items),
        )
        confirm(f"Удалил по слову '{bulk_keyword}': {len(removed_items)}.")
        return

    index = parse_index(initial_text)
    if index:
        if index > len(filtered):
            speak("Номер вне списка.")
            return
        global_idx, removed = filtered[index - 1]
        todos.pop(global_idx)
        save_todos(person, todos)
        push_history(person, "restore_items", {"items": [removed]})
        log_event(
            "todo_delete",
            person=person.key,
            day=day or "",
            due_date=due_date or "",
            mode="index",
            title=removed.get("title") or removed.get("text", "дело"),
        )
        confirm(f"Удалил: {removed.get('title') or removed.get('text', 'дело')}.")
        return

    query = extract_delete_query(initial_text)
    if not query:
        speak("После дня недели добавь текст задачи или скажи 'все дела'.")
        return

    best = find_best_todo_match(filtered, query)
    if not best:
        speak("Точную задачу не нашел.")
        return

    global_idx, removed = best
    todos.pop(global_idx)
    save_todos(person, todos)
    push_history(person, "restore_items", {"items": [removed]})
    log_event(
        "todo_delete",
        person=person.key,
        day=day or "",
        due_date=due_date or "",
        mode="query",
        title=removed.get("title") or removed.get("text", "дело"),
    )
    confirm(f"Удалил: {removed.get('title') or removed.get('text', 'дело')}.")


def mark_done(person: Person, initial_text: str | None = None) -> None:
    todos = load_todos(person)
    if not todos:
        speak("Список пуст.")
        return

    due_date, day = parse_day_or_date(initial_text)
    if not day and not due_date:
        speak("Скажи дату/день и номер задачи в одной фразе.")
        return
    filtered = filter_todos_by_date(todos, due_date) if due_date else filter_todos_by_day(todos, day)
    if not filtered:
        speak(f"На {due_date or day} дел нет.")
        return

    index = parse_index(initial_text)
    if not index or index > len(filtered):
        speak("Номер не понял.")
        return

    global_idx, _todo = filtered[index - 1]
    previous_state = dict(todos[global_idx])
    transition_task(todos[global_idx], "done")
    save_todos(person, todos)
    push_history(person, "update_item", {"id": previous_state.get("id"), "before": previous_state})
    log_event(
        "todo_done",
        person=person.key,
        day=day or "",
        due_date=due_date or "",
        id=previous_state.get("id"),
        title=previous_state.get("title") or previous_state.get("text", "дело"),
    )
    confirm("Отметил.")


def move_todo(person: Person, initial_text: str | None = None) -> None:
    if initial_text and _move_from_single_phrase(person, initial_text):
        return

    todos = load_todos(person)
    if not todos:
        speak("Список пуст.")
        return

    source_due_date = parse_due_date_input(initial_text)
    days_in_text = parse_days_in_text(initial_text)
    source_day = days_in_text[0] if days_in_text else parse_day_or_relative(initial_text)
    if not source_day and not source_due_date:
        speak("Скажи исходную дату/день и название задачи в одной фразе.")
        return
    filtered = filter_todos_by_date(todos, source_due_date) if source_due_date else filter_todos_by_day(todos, source_day)
    if not filtered:
        speak(f"На {source_due_date or source_day} дел нет.")
        return

    target_due_date = parse_due_date_input(normalize_text(initial_text or "").replace(str(source_due_date or ""), "")) or None
    target_day = days_in_text[-1] if len(days_in_text) >= 2 else None
    if not target_due_date and target_day:
        target_due_date = nearest_date_for_weekday(target_day, include_today=False).isoformat()
    if not target_due_date:
        speak("Скажи целевую дату или день недели одной фразой.")
        return

    target_time = extract_time_from_inline(initial_text or "")
    if target_time is None:
        speak("Скажи время переноса в этой же фразе.")
        return

    global_idx: int | None = None
    explicit_index = parse_explicit_index(initial_text)
    if explicit_index is not None:
        if explicit_index <= 0 or explicit_index > len(filtered):
            speak("Номер вне списка.")
            return
        global_idx = filtered[explicit_index - 1][0]
    else:
        query_tokens = _tokens_for_move_match(initial_text)
        best_match: tuple[float, int] | None = None
        for idx, todo in filtered:
            title = (todo.get("title") or todo.get("text") or "").strip()
            details = (todo.get("details") or "").strip()
            todo_tokens = _tokens_for_move_match(f"{title} {details}")
            if not todo_tokens:
                continue
            overlap = len(query_tokens & todo_tokens)
            if overlap <= 0:
                continue
            score = overlap / max(1, len(query_tokens))
            if best_match is None or score > best_match[0]:
                best_match = (score, idx)

        if best_match is None or best_match[0] < 0.2:
            speak("Не нашел задачу по названию на этот день.")
            return
        global_idx = best_match[1]

    if global_idx is None:
        speak("Не удалось определить задачу для переноса.")
        return

    previous_state = dict(todos[global_idx])
    todos[global_idx]["due_date"] = target_due_date
    todos[global_idx]["day"] = weekday_ru(datetime.fromisoformat(target_due_date).date())
    todos[global_idx]["time"] = target_time
    transition_task(todos[global_idx], "todo")
    save_todos(person, todos)
    push_history(person, "update_item", {"id": previous_state.get("id"), "before": previous_state})
    log_event(
        "todo_move",
        person=person.key,
        id=previous_state.get("id"),
        source_day=previous_state.get("day") or "",
        source_due_date=previous_state.get("due_date") or "",
        target_day=todos[global_idx].get("day") or "",
        target_due_date=target_due_date,
        target_time=target_time,
        title=previous_state.get("title") or previous_state.get("text", "дело"),
    )
    confirm(f"Перенес на {target_due_date}, {target_time or 'без времени'}.")


def list_todos_for_requested_day(person: Person, initial_text: str | None = None) -> None:
    tag = extract_tag_filter(initial_text)
    start_date, end_date, label = parse_period_request(initial_text)
    todos = load_todos(person)
    filtered = filter_todos_by_range(todos, start_date, end_date)
    filtered = filter_todos_by_tag(filtered, tag)
    if not filtered:
        speak(f"За период {label} дел нет.")
        return

    if start_date == end_date:
        speak(f"На {label} дел: {len(filtered)}")
    else:
        speak(f"За период {label} дел: {len(filtered)}")
    for local_idx, (_global_idx, todo) in enumerate(filtered, start=1):
        line = format_todo_line(local_idx, todo)
        print(line)
        speak(line)


def get_schedule_for_day(person: Person, initial_text: str | None = None) -> None:
    if not person.has_schedule:
        speak("Для этого пользователя расписания нет.")
        return

    day = parse_day_or_relative(initial_text)
    if not day:
        speak("Скажи день недели в этой же фразе. Например: расписание на среду.")
        return

    schedule = read_json(schedule_path(person), SCHEDULE_DEFAULT)
    lessons = schedule.get(day, []) if isinstance(schedule, dict) else []
    if not lessons:
        speak("На этот день уроков нет.")
        return

    speak(f"{day}.")
    for idx, lesson in enumerate(lessons, start=1):
        line = f"{idx}. {lesson}"
        print(line)
        speak(line)


def weekly_review(person: Person) -> None:
    todos = load_todos(person)
    history = load_history(person)
    today = datetime.now().date()
    week_start, week_end = week_bounds(today)
    month_start, month_end = month_bounds(today)

    not_done = [
        t
        for t in todos
        if str(t.get("status") or ("done" if t.get("done") else "active")) != "done"
    ]
    week_items = filter_todos_by_range(todos, week_start.isoformat(), week_end.isoformat())
    month_items = filter_todos_by_range(todos, month_start.isoformat(), month_end.isoformat())

    by_day: dict[str, int] = {day: 0 for day in DAY_ORDER}
    for _idx, todo in week_items:
        day = str(todo.get("day") or "")
        due = str(todo.get("due_date") or "")
        if due:
            try:
                day = weekday_ru(datetime.fromisoformat(due).date())
            except ValueError:
                pass
        if day in by_day:
            by_day[day] += 1

    moved_count: dict[int, int] = {}
    for entry in history:
        if entry.get("action") != "update_item":
            continue
        payload = entry.get("payload")
        if not isinstance(payload, dict):
            continue
        todo_id = payload.get("id")
        if isinstance(todo_id, int):
            moved_count[todo_id] = moved_count.get(todo_id, 0) + 1

    top_moved = sorted(moved_count.items(), key=lambda x: x[1], reverse=True)[:3]
    speak(
        "Обзор. "
        f"Невыполненных всего: {len(not_done)}. "
        f"На текущую неделю: {len(week_items)}. "
        f"На текущий месяц: {len(month_items)}."
    )
    for day, count in by_day.items():
        if count > 0:
            speak(f"{day}: {count}.")
    if top_moved:
        speak("Чаще переносились:")
        by_id = {int(t.get('id') or 0): t for t in todos}
        for todo_id, cnt in top_moved:
            title = (by_id.get(todo_id, {}).get("title") or "задача")
            speak(f"{title}: {cnt} переносов.")


def undo_last_action(person: Person) -> None:
    history = load_history(person)
    if not history:
        speak("История пуста.")
        return

    entry = history.pop()
    todos = load_todos(person)
    action = entry.get("action")
    payload = entry.get("payload") if isinstance(entry.get("payload"), dict) else {}

    if action == "add":
        created_ids = set(payload.get("created_ids", []))
        todos = [todo for todo in todos if todo.get("id") not in created_ids]
        save_todos(person, todos)
        save_history(person, history)
        log_event("todo_undo", person=person.key, action="add")
        confirm("Отменил последнее добавление.")
        return

    if action == "replace_all":
        old = payload.get("todos_before")
        if isinstance(old, list):
            save_todos(person, old)
            save_history(person, history)
            log_event("todo_undo", person=person.key, action="replace_all")
            confirm("Вернул полный список.")
            return

    if action == "restore_items":
        items = payload.get("items")
        if isinstance(items, list) and items:
            existing_ids = {todo.get("id") for todo in todos}
            for item in items:
                if isinstance(item, dict) and item.get("id") not in existing_ids:
                    todos.append(item)
            todos.sort(key=lambda item: int(item.get("id") or 0))
            save_todos(person, todos)
            save_history(person, history)
            log_event("todo_undo", person=person.key, action="restore_items", restored=len(items))
            confirm("Вернул удаленные задачи.")
            return

    if action == "update_item":
        target_id = payload.get("id")
        old_state = payload.get("before")
        if target_id is not None and isinstance(old_state, dict):
            for idx, todo in enumerate(todos):
                if todo.get("id") == target_id:
                    todos[idx] = old_state
                    save_todos(person, todos)
                    save_history(person, history)
                    log_event("todo_undo", person=person.key, action="update_item", id=target_id)
                    confirm("Откатил последнее изменение.")
                    return

    speak("Не получилось откатить последнее действие.")


def parse_action(person: Person, text: str | None) -> str | None:
    return resolve_action(
        text=text,
        person_has_schedule=person.has_schedule,
        contains_phrase=contains_phrase,
        detect_stop=detect_stop,
        detect_switch_person=detect_switch_person,
    )


def choose_person() -> Person | None:
    speak("Кто это?")
    while True:
        text = listen_once("", retries=1, phrase_time_limit=3)
        if detect_stop(text):
            return None
        person = find_person(text)
        if person:
            speak(person.display_name)
            return person
        speak("Имя не понял.")


def run_for_person(person: Person) -> str:
    speak("Слушаю.")

    while True:
        check_due_reminders(person)
        text = listen_once("Команда?", retries=1, phrase_time_limit=8)
        action = parse_action(person, text)
        if action == "stop":
            return "stop"
        if action == "switch_person":
            return "switch_person"
        if action == "add":
            add_todo(person, initial_text=text)
        elif action == "delete":
            delete_todo(person, initial_text=text)
        elif action == "clear":
            delete_todo(person, initial_text=text)
        elif action == "done":
            mark_done(person, initial_text=text)
        elif action == "move":
            move_todo(person, initial_text=text)
        elif action == "list":
            list_todos_for_requested_day(person, initial_text=text)
        elif action == "schedule":
            get_schedule_for_day(person, initial_text=text)
        elif action == "undo":
            undo_last_action(person)
        elif action == "review":
            weekly_review(person)
        else:
            speak("Не понял команду.")


def main() -> None:
    bootstrap_data()
    speak("Семейная тудушка.")
    while True:
        person = choose_person()
        if person is None:
            speak("Пока.")
            return
        result = run_for_person(person)
        if result == "stop":
            speak("Готово. Пока.")
            return


if __name__ == "__main__":
    main()

