import json
import time
from datetime import datetime
from pathlib import Path

import requests

import family_todo as ft
from notifier import event_actor, telegram_api
from todo_logger import log_event
from tts import muted_tts


BASE_DIR = Path(__file__).resolve().parent
STATE_PATH = BASE_DIR / "family_data" / "telegram_state.json"

ADULTS = {"nik", "nastya"}
CHILDREN = {"misha", "arisha"}

DAY_LABELS = list(ft.DAY_ORDER)
TIME_LABELS = [
    f"{hour:02d}:{minute:02d}"
    for hour in range(7, 23)
    for minute in (0, 15, 30, 45)
]
HOUR_LABELS = [f"{hour:02d}" for hour in range(0, 24)]
MINUTE_LABELS = ["00", "05", "10", "15", "20", "25", "30", "35", "40", "45", "50", "55"]


def read_state() -> dict:
    default = {
        "offset": 0,
        "chat_identity": {},
        "chat_person": {},
        "flow": {},
    }
    if not STATE_PATH.exists():
        return default
    try:
        data = json.loads(STATE_PATH.read_text(encoding="utf-8"))
        for key, value in default.items():
            data.setdefault(key, value)
        return data
    except Exception:
        return default


def write_state(state: dict) -> None:
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")


def send_message(chat_id: int, text: str, keyboard: dict | None = None) -> None:
    payload: dict[str, object] = {"chat_id": chat_id, "text": text}
    if keyboard:
        payload["reply_markup"] = keyboard
    try:
        requests.post(telegram_api("sendMessage"), json=payload, timeout=12)
    except Exception:
        pass


def person_by_key(key: str | None):
    if not key:
        return None
    for person in ft.PEOPLE:
        if person.key == key:
            return person
    return None


def person_by_display(display_name: str):
    for person in ft.PEOPLE:
        if person.display_name == display_name:
            return person
    return None


def identity_key(state: dict, chat_id: int) -> str | None:
    raw = state.get("chat_identity", {}).get(str(chat_id))
    return raw if isinstance(raw, str) and raw else None


def target_key(state: dict, chat_id: int) -> str | None:
    raw = state.get("chat_person", {}).get(str(chat_id))
    if isinstance(raw, str) and raw:
        return raw
    return identity_key(state, chat_id)


def set_identity(state: dict, chat_id: int, person_key: str) -> None:
    state.setdefault("chat_identity", {})[str(chat_id)] = person_key
    state.setdefault("chat_person", {})[str(chat_id)] = person_key


def set_target(state: dict, chat_id: int, person_key: str) -> None:
    state.setdefault("chat_person", {})[str(chat_id)] = person_key


def clear_flow(state: dict, chat_id: int) -> None:
    state.setdefault("flow", {}).pop(str(chat_id), None)


def set_flow(state: dict, chat_id: int, payload: dict) -> None:
    state.setdefault("flow", {})[str(chat_id)] = payload


def get_flow(state: dict, chat_id: int) -> dict | None:
    raw = state.get("flow", {}).get(str(chat_id))
    return raw if isinstance(raw, dict) else None


def can_view(actor_key: str, owner_key: str) -> bool:
    if actor_key in ADULTS:
        return owner_key == actor_key or owner_key in CHILDREN
    return owner_key == actor_key


def can_edit(actor_key: str, owner_key: str) -> bool:
    if actor_key in ADULTS:
        return owner_key == actor_key or owner_key in CHILDREN
    return owner_key == actor_key


def owner_restriction_text() -> str:
    return (
        "Недостаточно прав для этого профиля. "
        "Взрослые могут менять только себя и детей. "
        "Дети могут менять только свои данные."
    )


def main_keyboard(state: dict, chat_id: int) -> dict:
    actor = person_by_key(identity_key(state, chat_id))
    target = person_by_key(target_key(state, chat_id))
    actor_text = actor.display_name if actor else "не выбран"
    target_text = target.display_name if target else "не выбран"
    return {
        "keyboard": [
            [{"text": "🪪 Кто я"}, {"text": "👤 Профиль"}],
            [{"text": "➕ Задача"}, {"text": "🗑 Удалить"}, {"text": "✅ Сделано"}],
            [{"text": "🔁 Перенести"}, {"text": "📋 Список"}, {"text": "📅 Сегодня"}],
            [{"text": "🗓 Расписание"}, {"text": "➕ Урок"}, {"text": "🗑 Урок"}],
            [{"text": "❌ Отмена"}, {"text": "❓ Помощь"}],
            [{"text": f"ℹ️ Я: {actor_text}"}, {"text": f"ℹ️ Профиль: {target_text}"}],
        ],
        "resize_keyboard": True,
        "one_time_keyboard": False,
    }


def identity_keyboard() -> dict:
    return {
        "keyboard": [
            [{"text": "🪪 Я Ник"}, {"text": "🪪 Я Настя"}],
            [{"text": "🪪 Я Миша"}, {"text": "🪪 Я Ариша"}],
            [{"text": "⬅ Назад"}],
        ],
        "resize_keyboard": True,
        "one_time_keyboard": True,
    }


def profile_keyboard(actor_key: str | None) -> dict:
    actor = person_by_key(actor_key)
    options: list[dict[str, str]] = []
    if actor:
        for person in ft.PEOPLE:
            if can_view(actor.key, person.key):
                options.append({"text": f"👤 Профиль {person.display_name}"})
    rows = [options[i : i + 2] for i in range(0, len(options), 2)] if options else []
    rows.append([{"text": "⬅ Назад"}])
    return {"keyboard": rows, "resize_keyboard": True, "one_time_keyboard": True}


def day_keyboard() -> dict:
    rows = [
        [{"text": "понедельник"}, {"text": "вторник"}, {"text": "среда"}],
        [{"text": "четверг"}, {"text": "пятница"}, {"text": "суббота"}],
        [{"text": "воскресенье"}],
        [{"text": "сегодня"}, {"text": "завтра"}],
        [{"text": "❌ Отмена"}],
    ]
    return {"keyboard": rows, "resize_keyboard": True, "one_time_keyboard": True}


def time_keyboard() -> dict:
    rows: list[list[dict[str, str]]] = []
    for i in range(0, len(TIME_LABELS), 4):
        rows.append([{"text": val} for val in TIME_LABELS[i : i + 4]])
    rows.append([{"text": "⌨ Ввести время"}])
    rows.append([{"text": "❌ Отмена"}])
    return {"keyboard": rows, "resize_keyboard": True, "one_time_keyboard": True}


def hour_keyboard() -> dict:
    rows: list[list[dict[str, str]]] = []
    for i in range(0, len(HOUR_LABELS), 6):
        rows.append([{"text": val} for val in HOUR_LABELS[i : i + 6]])
    rows.append([{"text": "⌨ Ввести время"}])
    rows.append([{"text": "❌ Отмена"}])
    return {"keyboard": rows, "resize_keyboard": True, "one_time_keyboard": True}


def minute_keyboard() -> dict:
    rows: list[list[dict[str, str]]] = []
    for i in range(0, len(MINUTE_LABELS), 6):
        rows.append([{"text": val} for val in MINUTE_LABELS[i : i + 6]])
    rows.append([{"text": "⬅ Час"}, {"text": "⌨ Ввести время"}])
    rows.append([{"text": "❌ Отмена"}])
    return {"keyboard": rows, "resize_keyboard": True, "one_time_keyboard": True}


def parse_day_choice(text: str) -> str | None:
    normalized = (text or "").strip().lower()
    if normalized == "сегодня":
        return ft.DAY_ORDER[datetime.now().weekday()]
    if normalized == "завтра":
        return ft.DAY_ORDER[(datetime.now().weekday() + 1) % 7]
    return normalized if normalized in DAY_LABELS else None


def parse_time_choice(text: str) -> str | None:
    normalized = (text or "").strip().lower()
    if normalized in {"⌨ ввести время", "ввести время", "время"}:
        return None
    return ft.parse_time(normalized)


def parse_hour_choice(text: str) -> str | None:
    normalized = (text or "").strip()
    if normalized.isdigit():
        value = int(normalized)
        if 0 <= value <= 23:
            return f"{value:02d}"
    return None


def parse_minute_choice(text: str) -> str | None:
    normalized = (text or "").strip()
    if normalized.isdigit():
        value = int(normalized)
        if 0 <= value <= 59:
            return f"{value:02d}"
    return None


def todo_items_for_day(person, day: str) -> list[tuple[int, dict]]:
    return ft.filter_todos_by_day(ft.load_todos(person), day)


def make_pick_keyboard(items: list[tuple[int, dict]], prefix: str) -> tuple[dict, dict[str, int]]:
    mapping: dict[str, int] = {}
    rows: list[list[dict[str, str]]] = []
    for index, (_global_idx, todo) in enumerate(items, start=1):
        label = f"{prefix}{index}"
        mapping[label] = index
        rows.append([{"text": label}])
    rows.append([{"text": "❌ Отмена"}])
    return {"keyboard": rows, "resize_keyboard": True, "one_time_keyboard": True}, mapping


def execute_todo_command(target, text: str, actor_key: str) -> list[str]:
    captured: list[str] = []

    def capture(message: str) -> None:
        captured.append(message)

    from notifier import register_message_listener, unregister_message_listener

    register_message_listener(capture)
    try:
        with muted_tts(), event_actor(actor_key):
            action = ft.parse_action(target, text)
            if action in {None, "stop", "switch_person"}:
                ft.speak("Не понял команду.")
            elif action == "add":
                ft.add_todo(target, initial_text=text)
            elif action in {"delete", "clear"}:
                ft.delete_todo(target, initial_text=text)
            elif action == "done":
                ft.mark_done(target, initial_text=text)
            elif action == "move":
                ft.move_todo(target, initial_text=text)
            elif action == "list":
                ft.list_todos_for_requested_day(target, initial_text=text)
            elif action == "schedule":
                ft.get_schedule_for_day(target, initial_text=text)
            elif action == "undo":
                ft.undo_last_action(target)
            elif action == "review":
                ft.weekly_review(target)
            else:
                ft.speak("Не понял команду.")
    finally:
        unregister_message_listener(capture)

    return captured or ["Готово."]


def ensure_schedule_dict(person) -> dict[str, list[str]]:
    path = ft.schedule_path(person)
    data = ft.read_json(path, ft.SCHEDULE_DEFAULT)
    if not isinstance(data, dict):
        data = dict(ft.SCHEDULE_DEFAULT)
    changed = False
    for day in ft.DAY_ORDER:
        if day not in data or not isinstance(data.get(day), list):
            data[day] = []
            changed = True
    if changed or not path.exists():
        ft.write_json(path, data)
    return data


def add_lesson(person, day: str, lesson_text: str, actor_key: str) -> str:
    schedule = ensure_schedule_dict(person)
    lessons = schedule.setdefault(day, [])
    lessons.append(lesson_text)
    ft.write_json(ft.schedule_path(person), schedule)
    log_event("schedule_add", person=person.key, actor=actor_key, day=day, title=lesson_text)
    return f"Добавил в расписание {person.display_name} на {day}: {lesson_text}."


def remove_lesson(person, day: str, index: int, actor_key: str) -> str:
    schedule = ensure_schedule_dict(person)
    lessons = schedule.get(day, [])
    if not isinstance(lessons, list) or index < 1 or index > len(lessons):
        return "Не нашел пункт для удаления."
    removed = str(lessons.pop(index - 1))
    schedule[day] = lessons
    ft.write_json(ft.schedule_path(person), schedule)
    log_event("schedule_remove", person=person.key, actor=actor_key, day=day, title=removed)
    return f"Удалил из расписания {person.display_name} на {day}: {removed}."


def help_text() -> str:
    return (
        "Кнопочный режим:\n"
        "1) Нажми '🪪 Кто я' и выбери себя.\n"
        "2) Нажми '👤 Профиль' и выбери чей профиль редактировать.\n"
        "3) Используй кнопки действий: задача, удаление, перенос, расписание.\n"
        "Права: взрослые (Ник/Настя) редактируют себя и детей; дети только себя."
    )


def handle_flow(chat_id: int, state: dict, text: str) -> bool:
    flow = get_flow(state, chat_id)
    if not flow:
        return False

    if text == "❌ Отмена":
        clear_flow(state, chat_id)
        send_message(chat_id, "Действие отменено.", main_keyboard(state, chat_id))
        return True

    actor_key_value = identity_key(state, chat_id)
    target_key_value = target_key(state, chat_id)
    actor = person_by_key(actor_key_value)
    target = person_by_key(target_key_value)
    if not actor or not target:
        clear_flow(state, chat_id)
        send_message(chat_id, "Сначала выбери себя и профиль.", main_keyboard(state, chat_id))
        return True

    name = flow.get("name")
    if name == "add_day":
        day = parse_day_choice(text)
        if not day:
            send_message(chat_id, "Выбери день кнопкой.", day_keyboard())
            return True
        flow["day"] = day
        flow["name"] = "add_hour"
        set_flow(state, chat_id, flow)
        send_message(chat_id, f"Выбран день: {day}. Теперь выбери час или введи время вручную.", hour_keyboard())
        return True

    if name == "add_hour":
        if (text or "").strip().lower() in {"⌨ ввести время", "ввести время", "время"}:
            send_message(chat_id, "Напиши время текстом. Примеры: 20:15, 20-15, 2015.", main_keyboard(state, chat_id))
            return True
        time_value = parse_time_choice(text)
        if time_value:
            flow["time"] = time_value
            flow["name"] = "add_title"
            set_flow(state, chat_id, flow)
            send_message(chat_id, "Теперь напиши название задачи одним сообщением.", main_keyboard(state, chat_id))
            return True

        hour = parse_hour_choice(text)
        if hour is None:
            send_message(chat_id, "Выбери час кнопкой или напиши время вручную.", hour_keyboard())
            return True
        flow["hour"] = hour
        flow["name"] = "add_minute"
        set_flow(state, chat_id, flow)
        send_message(chat_id, f"Час {hour}. Теперь выбери минуты.", minute_keyboard())
        return True

    if name == "add_minute":
        if (text or "").strip().lower() == "⬅ час":
            flow["name"] = "add_hour"
            set_flow(state, chat_id, flow)
            send_message(chat_id, "Хорошо, выбери час.", hour_keyboard())
            return True
        if (text or "").strip().lower() in {"⌨ ввести время", "ввести время", "время"}:
            send_message(chat_id, "Напиши время текстом. Примеры: 20:15, 20-15, 2015.", main_keyboard(state, chat_id))
            return True

        time_value = parse_time_choice(text)
        if time_value:
            flow["time"] = time_value
            flow["name"] = "add_title"
            set_flow(state, chat_id, flow)
            send_message(chat_id, "Теперь напиши название задачи одним сообщением.", main_keyboard(state, chat_id))
            return True

        minute = parse_minute_choice(text)
        if minute is None:
            send_message(chat_id, "Выбери минуты кнопкой или напиши время вручную.", minute_keyboard())
            return True

        hour = str(flow.get("hour") or "19")
        flow["time"] = f"{hour}:{minute}"
        flow["name"] = "add_title"
        set_flow(state, chat_id, flow)
        send_message(chat_id, "Теперь напиши название задачи одним сообщением.", main_keyboard(state, chat_id))
        return True

    if name == "add_title":
        title = (text or "").strip()
        if not title or title.startswith("🪪") or title.startswith("👤"):
            send_message(chat_id, "Напиши текст задачи обычным сообщением.", main_keyboard(state, chat_id))
            return True
        day = str(flow.get("day"))
        time_value = str(flow.get("time"))
        command = f"добавь в {day} в {time_value.replace(':', ' ')} {title}"
        replies = execute_todo_command(target, command, actor.key)
        clear_flow(state, chat_id)
        for reply in replies:
            send_message(chat_id, reply, main_keyboard(state, chat_id))
        return True

    if name in {"delete_day", "done_day", "move_day", "schedule_remove_day", "schedule_add_day", "schedule_view_day", "list_view_day"}:
        day = parse_day_choice(text)
        if not day:
            send_message(chat_id, "Выбери день кнопкой.", day_keyboard())
            return True
        flow["day"] = day

        if name == "schedule_view_day":
            replies = execute_todo_command(target, f"расписание {day}", actor.key)
            clear_flow(state, chat_id)
            for reply in replies:
                send_message(chat_id, reply, main_keyboard(state, chat_id))
            return True

        if name == "list_view_day":
            replies = execute_todo_command(target, f"список на {day}", actor.key)
            clear_flow(state, chat_id)
            for reply in replies:
                send_message(chat_id, reply, main_keyboard(state, chat_id))
            return True

        if name == "schedule_add_day":
            flow["name"] = "schedule_add_title"
            set_flow(state, chat_id, flow)
            send_message(chat_id, f"Напиши урок/пункт расписания на {day}.", main_keyboard(state, chat_id))
            return True

        if name == "schedule_remove_day":
            schedule = ensure_schedule_dict(target)
            lessons = schedule.get(day, [])
            if not lessons:
                clear_flow(state, chat_id)
                send_message(chat_id, f"На {day} у {target.display_name} пусто.", main_keyboard(state, chat_id))
                return True
            text_lines = [f"{i}. {val}" for i, val in enumerate(lessons, start=1)]
            keys = {f"🗑 №{i}": i for i in range(1, len(lessons) + 1)}
            rows = [[{"text": key}] for key in keys.keys()]
            rows.append([{"text": "❌ Отмена"}])
            flow["name"] = "schedule_remove_pick"
            flow["keys"] = keys
            set_flow(state, chat_id, flow)
            send_message(chat_id, "Выбери пункт для удаления:\n" + "\n".join(text_lines), {"keyboard": rows, "resize_keyboard": True, "one_time_keyboard": True})
            return True

        items = todo_items_for_day(target, day)
        if not items:
            clear_flow(state, chat_id)
            send_message(chat_id, f"На {day} задач нет.", main_keyboard(state, chat_id))
            return True

        rows_text = [ft.format_todo_line(i, todo) for i, (_idx, todo) in enumerate(items, start=1)]
        prefix = "✅ №" if name == "done_day" else ("🗑 №" if name == "delete_day" else "🔁 №")
        keyboard_payload, mapping = make_pick_keyboard(items, prefix)
        flow["keys"] = mapping
        flow["name"] = {"done_day": "done_pick", "delete_day": "delete_pick", "move_day": "move_pick"}[name]
        set_flow(state, chat_id, flow)
        send_message(chat_id, "Выбери задачу:\n" + "\n".join(rows_text), keyboard_payload)
        return True

    if name == "done_pick":
        keys = flow.get("keys", {})
        if text not in keys:
            send_message(chat_id, "Выбери номер кнопкой.", None)
            return True
        day = str(flow.get("day"))
        index = int(keys[text])
        replies = execute_todo_command(target, f"отметь {day} номер {index}", actor.key)
        clear_flow(state, chat_id)
        for reply in replies:
            send_message(chat_id, reply, main_keyboard(state, chat_id))
        return True

    if name == "delete_pick":
        keys = flow.get("keys", {})
        if text not in keys:
            send_message(chat_id, "Выбери номер кнопкой.", None)
            return True
        day = str(flow.get("day"))
        index = int(keys[text])
        replies = execute_todo_command(target, f"удали {day} номер {index}", actor.key)
        clear_flow(state, chat_id)
        for reply in replies:
            send_message(chat_id, reply, main_keyboard(state, chat_id))
        return True

    if name == "move_pick":
        keys = flow.get("keys", {})
        if text not in keys:
            send_message(chat_id, "Выбери номер кнопкой.", None)
            return True
        flow["index"] = int(keys[text])
        flow["name"] = "move_target_day"
        set_flow(state, chat_id, flow)
        send_message(chat_id, "Выбери новый день.", day_keyboard())
        return True

    if name == "move_target_day":
        day = parse_day_choice(text)
        if not day:
            send_message(chat_id, "Выбери день кнопкой.", day_keyboard())
            return True
        flow["target_day"] = day
        flow["name"] = "move_target_hour"
        set_flow(state, chat_id, flow)
        send_message(chat_id, "Выбери новый час или введи время вручную.", hour_keyboard())
        return True

    if name == "move_target_hour":
        if (text or "").strip().lower() in {"⌨ ввести время", "ввести время", "время"}:
            send_message(chat_id, "Напиши новое время текстом. Примеры: 20:15, 20-15, 2015.", main_keyboard(state, chat_id))
            return True
        time_value = parse_time_choice(text)
        if time_value:
            source_day = str(flow.get("day"))
            index = int(flow.get("index") or 1)
            target_day = str(flow.get("target_day"))
            replies = execute_todo_command(
                target,
                f"перенеси {source_day} номер {index} на {target_day} в {time_value.replace(':', ' ')}",
                actor.key,
            )
            clear_flow(state, chat_id)
            for reply in replies:
                send_message(chat_id, reply, main_keyboard(state, chat_id))
            return True

        hour = parse_hour_choice(text)
        if hour is None:
            send_message(chat_id, "Выбери час кнопкой или напиши время вручную.", hour_keyboard())
            return True
        flow["target_hour"] = hour
        flow["name"] = "move_target_minute"
        set_flow(state, chat_id, flow)
        send_message(chat_id, f"Час {hour}. Теперь выбери минуты.", minute_keyboard())
        return True

    if name == "move_target_minute":
        if (text or "").strip().lower() == "⬅ час":
            flow["name"] = "move_target_hour"
            set_flow(state, chat_id, flow)
            send_message(chat_id, "Хорошо, выбери час.", hour_keyboard())
            return True
        if (text or "").strip().lower() in {"⌨ ввести время", "ввести время", "время"}:
            send_message(chat_id, "Напиши новое время текстом. Примеры: 20:15, 20-15, 2015.", main_keyboard(state, chat_id))
            return True

        time_value = parse_time_choice(text)
        if not time_value:
            minute = parse_minute_choice(text)
            if minute is None:
                send_message(chat_id, "Выбери минуты кнопкой или напиши время вручную.", minute_keyboard())
                return True
            target_hour = str(flow.get("target_hour") or "19")
            time_value = f"{target_hour}:{minute}"

        source_day = str(flow.get("day"))
        index = int(flow.get("index") or 1)
        target_day = str(flow.get("target_day"))
        replies = execute_todo_command(
            target,
            f"перенеси {source_day} номер {index} на {target_day} в {time_value.replace(':', ' ')}",
            actor.key,
        )
        clear_flow(state, chat_id)
        for reply in replies:
            send_message(chat_id, reply, main_keyboard(state, chat_id))
        return True

    if name == "schedule_add_title":
        lesson = (text or "").strip()
        if not lesson or lesson.startswith("🪪") or lesson.startswith("👤"):
            send_message(chat_id, "Напиши текст урока обычным сообщением.", main_keyboard(state, chat_id))
            return True
        day = str(flow.get("day"))
        reply = add_lesson(target, day, lesson, actor.key)
        clear_flow(state, chat_id)
        send_message(chat_id, reply, main_keyboard(state, chat_id))
        return True

    if name == "schedule_remove_pick":
        keys = flow.get("keys", {})
        if text not in keys:
            send_message(chat_id, "Выбери пункт кнопкой.", None)
            return True
        day = str(flow.get("day"))
        reply = remove_lesson(target, day, int(keys[text]), actor.key)
        clear_flow(state, chat_id)
        send_message(chat_id, reply, main_keyboard(state, chat_id))
        return True

    return False


def handle_text(chat_id: int, state: dict, text: str) -> None:
    text_clean = (text or "").strip()

    if text_clean in {"/start", "/help", "❓ Помощь"}:
        clear_flow(state, chat_id)
        send_message(chat_id, help_text(), main_keyboard(state, chat_id))
        return

    if text_clean == "❌ Отмена":
        clear_flow(state, chat_id)
        send_message(chat_id, "Отменено.", main_keyboard(state, chat_id))
        return

    if text_clean == "⬅ Назад":
        clear_flow(state, chat_id)
        send_message(chat_id, "Главное меню.", main_keyboard(state, chat_id))
        return

    if handle_flow(chat_id, state, text_clean):
        return

    if text_clean == "🪪 Кто я":
        send_message(chat_id, "Выбери себя.", identity_keyboard())
        return

    if text_clean.startswith("🪪 Я "):
        display = text_clean.replace("🪪 Я ", "", 1).strip()
        person = person_by_display(display)
        if not person:
            send_message(chat_id, "Не понял выбор.", identity_keyboard())
            return
        set_identity(state, chat_id, person.key)
        clear_flow(state, chat_id)
        send_message(chat_id, f"Личность сохранена: {person.display_name}.", main_keyboard(state, chat_id))
        return

    if text_clean == "👤 Профиль":
        actor_key_value = identity_key(state, chat_id)
        if not actor_key_value:
            send_message(chat_id, "Сначала выбери себя через '🪪 Кто я'.", identity_keyboard())
            return
        send_message(chat_id, "Выбери профиль для работы.", profile_keyboard(actor_key_value))
        return

    if text_clean.startswith("👤 Профиль "):
        actor_key_value = identity_key(state, chat_id)
        actor = person_by_key(actor_key_value)
        display = text_clean.replace("👤 Профиль ", "", 1).strip()
        target = person_by_display(display)
        if not actor or not target:
            send_message(chat_id, "Сначала выбери себя, затем профиль.", main_keyboard(state, chat_id))
            return
        if not can_view(actor.key, target.key):
            send_message(chat_id, owner_restriction_text(), main_keyboard(state, chat_id))
            return
        set_target(state, chat_id, target.key)
        clear_flow(state, chat_id)
        send_message(chat_id, f"Текущий профиль: {target.display_name}.", main_keyboard(state, chat_id))
        return

    actor_key_value = identity_key(state, chat_id)
    target_key_value = target_key(state, chat_id)
    actor = person_by_key(actor_key_value)
    target = person_by_key(target_key_value)
    if not actor or not target:
        send_message(chat_id, "Сначала выбери себя и профиль.", main_keyboard(state, chat_id))
        return

    if text_clean == "📅 Сегодня":
        if not can_view(actor.key, target.key):
            send_message(chat_id, owner_restriction_text(), main_keyboard(state, chat_id))
            return
        replies = execute_todo_command(target, "что на сегодня", actor.key)
        for reply in replies:
            send_message(chat_id, reply, main_keyboard(state, chat_id))
        return

    if text_clean == "📋 Список":
        if not can_view(actor.key, target.key):
            send_message(chat_id, owner_restriction_text(), main_keyboard(state, chat_id))
            return
        set_flow(state, chat_id, {"name": "list_view_day"})
        send_message(chat_id, "Выбери день для списка задач.", day_keyboard())
        return

    if text_clean == "🗓 Расписание":
        if not can_view(actor.key, target.key):
            send_message(chat_id, owner_restriction_text(), main_keyboard(state, chat_id))
            return
        set_flow(state, chat_id, {"name": "schedule_view_day"})
        send_message(chat_id, "Выбери день для просмотра расписания.", day_keyboard())
        return

    if text_clean == "➕ Задача":
        if not can_edit(actor.key, target.key):
            send_message(chat_id, owner_restriction_text(), main_keyboard(state, chat_id))
            return
        set_flow(state, chat_id, {"name": "add_day"})
        send_message(chat_id, "Выбери день новой задачи.", day_keyboard())
        return

    if text_clean == "🗑 Удалить":
        if not can_edit(actor.key, target.key):
            send_message(chat_id, owner_restriction_text(), main_keyboard(state, chat_id))
            return
        set_flow(state, chat_id, {"name": "delete_day"})
        send_message(chat_id, "Выбери день, откуда удалять задачу.", day_keyboard())
        return

    if text_clean == "✅ Сделано":
        if not can_edit(actor.key, target.key):
            send_message(chat_id, owner_restriction_text(), main_keyboard(state, chat_id))
            return
        set_flow(state, chat_id, {"name": "done_day"})
        send_message(chat_id, "Выбери день задачи для отметки.", day_keyboard())
        return

    if text_clean == "🔁 Перенести":
        if not can_edit(actor.key, target.key):
            send_message(chat_id, owner_restriction_text(), main_keyboard(state, chat_id))
            return
        set_flow(state, chat_id, {"name": "move_day"})
        send_message(chat_id, "Выбери день задачи для переноса.", day_keyboard())
        return

    if text_clean == "➕ Урок":
        if not can_edit(actor.key, target.key):
            send_message(chat_id, owner_restriction_text(), main_keyboard(state, chat_id))
            return
        set_flow(state, chat_id, {"name": "schedule_add_day"})
        send_message(chat_id, "Выбери день, куда добавить пункт расписания.", day_keyboard())
        return

    if text_clean == "🗑 Урок":
        if not can_edit(actor.key, target.key):
            send_message(chat_id, owner_restriction_text(), main_keyboard(state, chat_id))
            return
        set_flow(state, chat_id, {"name": "schedule_remove_day"})
        send_message(chat_id, "Выбери день, откуда удалить пункт расписания.", day_keyboard())
        return

    send_message(chat_id, "Используй кнопки меню. Для начала нажми '🪪 Кто я'.", main_keyboard(state, chat_id))


def handle_update(update: dict, state: dict) -> None:
    message = update.get("message") or {}
    chat = message.get("chat") or {}
    chat_id = chat.get("id")
    if not isinstance(chat_id, int):
        return

    if "text" in message:
        handle_text(chat_id, state, str(message.get("text") or ""))
        return

    send_message(chat_id, "Бот работает в кнопочно-текстовом режиме. Используй кнопки и текст там, где бот попросит.", main_keyboard(state, chat_id))


def main() -> None:
    token_ready = False
    try:
        telegram_api("getMe")
        token_ready = True
    except Exception:
        token_ready = False

    if not token_ready:
        print("TELEGRAM_BOT_TOKEN не задан или недоступен. Бот не запущен.")
        return

    ft.bootstrap_data()
    state = read_state()
    offset = int(state.get("offset") or 0)
    print("Telegram-бот запущен. Ожидаю сообщения...")

    while True:
        try:
            resp = requests.get(
                telegram_api("getUpdates"),
                params={"offset": offset, "timeout": 25, "allowed_updates": ["message"]},
                timeout=35,
            ).json()
            if not resp.get("ok"):
                time.sleep(2)
                continue

            results = resp.get("result") or []
            for update in results:
                update_id = int(update.get("update_id") or 0)
                if update_id >= offset:
                    offset = update_id + 1
                handle_update(update, state)

            state["offset"] = offset
            write_state(state)
        except KeyboardInterrupt:
            print("Остановка Telegram-бота.")
            break
        except Exception:
            time.sleep(2)


if __name__ == "__main__":
    main()
