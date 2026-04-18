
import copy
import os
import subprocess
import sys
import threading
import traceback
import uuid
from datetime import date, datetime, timedelta
from pathlib import Path

import customtkinter as ctk
from tkinter import messagebox

import family_todo as ft
from audio import listen_command
from commands import execute_command, match_command
from notifier import event_actor, register_message_listener, unregister_message_listener
from todo_logger import log_event
from tts import muted_tts


ctk.set_appearance_mode("dark")
ctk.set_default_color_theme("blue")

PRIORITY_RU_TO_KEY = {
    "Высокий": "high",
    "Обычный": "medium",
    "Низкий": "low",
}
PRIORITY_KEY_TO_RU = {v: k for k, v in PRIORITY_RU_TO_KEY.items()}

RECURRING_RU_TO_KEY = {
    "Нет": "",
    "Каждый день": "daily",
    "По будням": "weekdays",
}
RECURRING_KEY_TO_RU = {v: k for k, v in RECURRING_RU_TO_KEY.items()}


class VoiceWorker(threading.Thread):
    def __init__(self, on_log, on_state):
        super().__init__(daemon=True)
        self._stop_event = threading.Event()
        self._on_log = on_log
        self._on_state = on_state

    def stop(self) -> None:
        self._stop_event.set()

    def run(self) -> None:
        self._on_state(True)
        self._on_log("Голосовой режим включен")
        try:
            while not self._stop_event.is_set():
                ft.process_global_reminders()
                command_text = listen_command()
                if self._stop_event.is_set():
                    break
                if not command_text:
                    continue

                matched = match_command(command_text)
                if not matched:
                    self._on_log(f"Команда не распознана: {command_text}")
                    continue

                keep_running = execute_command(matched)
                if not keep_running:
                    self._on_log("Получена команда выхода, голосовой режим остановлен")
                    break
        except Exception:
            self._on_log("Ошибка голосового режима:\n" + traceback.format_exc())
        finally:
            self._on_state(False)
            self._on_log("Голосовой режим выключен")


class BotProcessHost:
    def __init__(self, on_log):
        self._on_log = on_log
        self._process: subprocess.Popen | None = None

    def is_running(self) -> bool:
        return self._process is not None and self._process.poll() is None

    def start(self) -> bool:
        if self.is_running():
            return True

        if getattr(sys, "frozen", False):
            cmd = [sys.executable, "--bot-only"]
        else:
            cmd = [sys.executable, str(Path(__file__).resolve()), "--bot-only"]

        try:
            self._process = subprocess.Popen(cmd, cwd=str(Path(__file__).resolve().parent))
            self._on_log("Встроенный Telegram-бот запущен")
            return True
        except Exception as exc:
            self._on_log(f"Не удалось запустить Telegram-бота: {exc}")
            self._process = None
            return False

    def stop(self) -> None:
        if not self.is_running():
            self._process = None
            return

        try:
            self._process.terminate()
            self._process.wait(timeout=5)
        except Exception:
            try:
                self._process.kill()
            except Exception:
                pass
        finally:
            self._process = None
            self._on_log("Встроенный Telegram-бот остановлен")


class TaskCard(ctk.CTkFrame):
    def __init__(self, parent, app, local_index: int, todo: dict, selected: bool):
        super().__init__(parent, corner_radius=12, border_width=1)
        self.app = app
        self.local_index = local_index
        self.todo = todo

        if selected:
            self.configure(border_color="#2FA4FF", fg_color=("#263042", "#263042"))
        else:
            self.configure(border_color=("#555", "#444"), fg_color=("#1F2937", "#1F2937"))

        self.grid_columnconfigure(1, weight=1)

        done_value = str(todo.get("status") or ("done" if todo.get("done") else "active")) == "done"
        done_text = "готово" if done_value else "в работе"

        badge_color = "#2ECC71" if done_value else "#F39C12"
        ctk.CTkLabel(self, text=done_text, width=70, fg_color=badge_color, corner_radius=8).grid(
            row=0,
            column=0,
            rowspan=3,
            padx=(10, 12),
            pady=10,
            sticky="n",
        )

        title = str(todo.get("title") or todo.get("text") or "Без названия")
        title_label = ctk.CTkLabel(self, text=f"{local_index}. {title}", font=ctk.CTkFont(size=15, weight="bold"), anchor="w")
        title_label.grid(row=0, column=1, sticky="we", pady=(10, 2))

        day = todo.get("due_date") or todo.get("day") or "без даты"
        if todo.get("due_date"):
            try:
                dt = datetime.fromisoformat(str(todo.get("due_date"))).date()
                day = f"{dt.strftime('%d.%m.%Y')} ({ft.weekday_ru(dt)})"
            except ValueError:
                day = str(todo.get("due_date"))
        recurrence = str(todo.get("recurrence_rule") or todo.get("recurring") or "")
        if recurrence == "daily":
            day = f"{day} | каждый день"
        elif recurrence == "weekdays":
            day = f"{day} | по будням"
        time_text = todo.get("time") or "без времени"
        priority = ft.priority_label(todo.get("priority"))
        tags = todo.get("tags") if isinstance(todo.get("tags"), list) else []
        tags_line = f" | теги: {', '.join(tags)}" if tags else ""
        meta = f"{day} | {time_text} | {priority}{tags_line}"
        meta_label = ctk.CTkLabel(self, text=meta, anchor="w", text_color=("#D6E3F0", "#A8B3C2"))
        meta_label.grid(row=1, column=1, sticky="we", pady=(0, 3))

        details = str(todo.get("details") or "").strip()
        if details:
            if len(details) > 140:
                details = details[:137] + "..."
            details_line = f"Описание: {details}"
        else:
            details_line = "Описание: —"
        details_label = ctk.CTkLabel(self, text=details_line, anchor="w", text_color=("#CBD5E1", "#94A3B8"), wraplength=380)
        details_label.grid(row=2, column=1, sticky="we", pady=(0, 10))

        buttons = ctk.CTkFrame(self, fg_color="transparent")
        buttons.grid(row=0, column=2, rowspan=3, padx=(8, 10), pady=8)
        ctk.CTkButton(buttons, text="Выбрать", width=80, command=self._select).pack(pady=2)
        ctk.CTkButton(buttons, text="Готово", width=80, fg_color="#16A34A", hover_color="#15803D", command=self._done).pack(pady=2)
        ctk.CTkButton(buttons, text="Удалить", width=80, fg_color="#DC2626", hover_color="#B91C1C", command=self._delete).pack(pady=2)

        self.bind("<Button-1>", lambda _e: self._select())
        title_label.bind("<Button-1>", lambda _e: self._select())
        meta_label.bind("<Button-1>", lambda _e: self._select())
        details_label.bind("<Button-1>", lambda _e: self._select())

    def _select(self) -> None:
        self.app.select_task(self.local_index - 1)

    def _done(self) -> None:
        self.app.mark_done_by_local_index(self.local_index - 1)

    def _delete(self) -> None:
        self.app.delete_by_local_index(self.local_index - 1)

class DesktopTodoApp(ctk.CTk):
    def __init__(self) -> None:
        super().__init__()
        self.title("Family Todo Control Center")
        self.geometry("1380x860")
        self.minsize(1180, 760)

        ft.bootstrap_data()

        self.person_by_name = {p.display_name: p for p in ft.PEOPLE}
        self.display_names = [p.display_name for p in ft.PEOPLE]

        self.person_var = ctk.StringVar(value=self.display_names[0])
        self.filter_var = ctk.StringVar(value="Текущая неделя")
        self.search_var = ctk.StringVar(value="")

        self.title_var = ctk.StringVar(value="")
        self.details_var = ctk.StringVar(value="")
        self.due_date_var = ctk.StringVar(value=datetime.now().date().isoformat())
        self.time_var = ctk.StringVar(value="19:00")
        self.time_hour_var = ctk.StringVar(value="19")
        self.time_min_var = ctk.StringVar(value="00")
        self.priority_var = ctk.StringVar(value="Обычный")
        self.tags_var = ctk.StringVar(value="")
        self.recurring_var = ctk.StringVar(value="Нет")
        self.reminders_var = ctk.StringVar(value="60,30,10")

        self.voice_var = ctk.BooleanVar(value=False)
        self.bot_var = ctk.BooleanVar(value=False)
        self.voice_worker: VoiceWorker | None = None
        self.bot_host = BotProcessHost(on_log=self._threadsafe_log)

        self.period_anchor: date = datetime.now().date()
        self.search_after_id: str | None = None
        self._cache_person_key: str | None = None
        self._cache_todos: list[dict] = []
        self._cards: list[TaskCard] = []

        self.current_items: list[tuple[int, dict]] = []
        self.selected_local_index: int | None = None

        self._build_layout()
        self._bind_shortcuts()
        self.refresh_tasks()
        self.protocol("WM_DELETE_WINDOW", self.on_close)

        if os.getenv("TELEGRAM_BOT_TOKEN", "").strip():
            self.bot_var.set(True)
            self.toggle_bot()
        else:
            self._append_log("TELEGRAM_BOT_TOKEN не задан в окружении этого процесса")

    def _build_layout(self) -> None:
        self.grid_columnconfigure(1, weight=1)
        self.grid_rowconfigure(0, weight=1)

        sidebar = ctk.CTkFrame(self, corner_radius=0, fg_color=("#0B1220", "#0B1220"))
        sidebar.grid(row=0, column=0, sticky="nsew")
        sidebar.grid_rowconfigure(9, weight=1)

        ctk.CTkLabel(sidebar, text="Control Center", font=ctk.CTkFont(size=24, weight="bold"), text_color="#C7D2FE").grid(
            row=0,
            column=0,
            padx=20,
            pady=(20, 8),
            sticky="w",
        )

        ctk.CTkLabel(sidebar, text="Профиль", anchor="w").grid(row=1, column=0, padx=20, sticky="w")
        ctk.CTkOptionMenu(sidebar, variable=self.person_var, values=self.display_names, command=lambda _v: self.on_person_changed()).grid(
            row=2,
            column=0,
            padx=20,
            pady=(6, 12),
            sticky="ew",
        )

        ctk.CTkLabel(sidebar, text="Режим просмотра", anchor="w").grid(row=3, column=0, padx=20, sticky="w")
        ctk.CTkOptionMenu(
            sidebar,
            variable=self.filter_var,
            values=["Текущая неделя", "Текущий месяц", "Сегодня", "Завтра", "Все"],
            command=lambda _v: self.on_filter_changed(),
        ).grid(row=4, column=0, padx=20, pady=(6, 12), sticky="ew")

        self.voice_switch = ctk.CTkSwitch(sidebar, text="Голосовой режим", variable=self.voice_var, command=self.toggle_voice)
        self.voice_switch.grid(row=5, column=0, padx=20, pady=(8, 2), sticky="w")

        self.bot_switch = ctk.CTkSwitch(sidebar, text="Встроенный Telegram-бот", variable=self.bot_var, command=self.toggle_bot)
        self.bot_switch.grid(row=6, column=0, padx=20, pady=(8, 2), sticky="w")

        self.voice_status = ctk.CTkLabel(sidebar, text="Голос: OFF", text_color="#94A3B8")
        self.voice_status.grid(row=7, column=0, padx=20, sticky="w")

        self.bot_status = ctk.CTkLabel(sidebar, text="Бот: OFF", text_color="#94A3B8")
        self.bot_status.grid(row=8, column=0, padx=20, sticky="w")

        actions = ctk.CTkFrame(sidebar, fg_color="transparent")
        actions.grid(row=10, column=0, padx=16, pady=16, sticky="ew")
        ctk.CTkButton(actions, text="Откат", command=self.undo_action).pack(fill="x", pady=4)
        ctk.CTkButton(actions, text="Недельный обзор", command=self.run_weekly_review).pack(fill="x", pady=4)
        ctk.CTkButton(actions, text="Обновить", command=self.refresh_tasks).pack(fill="x", pady=4)

        main = ctk.CTkFrame(self, fg_color=("#111827", "#111827"))
        main.grid(row=0, column=1, sticky="nsew")
        main.grid_columnconfigure(0, weight=7)
        main.grid_columnconfigure(1, weight=5)
        main.grid_rowconfigure(1, weight=1)

        header = ctk.CTkFrame(main, fg_color="transparent")
        header.grid(row=0, column=0, columnspan=2, sticky="ew", padx=18, pady=(14, 8))
        header.grid_columnconfigure(0, weight=1)

        ctk.CTkLabel(header, text="Семейная тудушка", font=ctk.CTkFont(size=30, weight="bold"), text_color="#E2E8F0").grid(
            row=0,
            column=0,
            sticky="w",
        )

        nav = ctk.CTkFrame(header, fg_color="transparent")
        nav.grid(row=0, column=1, sticky="w", padx=(12, 8))
        ctk.CTkButton(nav, text="←", width=36, command=lambda: self.shift_period(-1)).pack(side="left", padx=(0, 4))
        ctk.CTkButton(nav, text="→", width=36, command=lambda: self.shift_period(1)).pack(side="left")
        self.period_label = ctk.CTkLabel(nav, text="", text_color="#94A3B8")
        self.period_label.pack(side="left", padx=(8, 0))

        self.search_entry = ctk.CTkEntry(header, textvariable=self.search_var, placeholder_text="Поиск по задачам")
        self.search_entry.grid(row=0, column=2, padx=(8, 8), sticky="ew")
        self.search_entry.bind("<KeyRelease>", lambda _e: self._debounced_refresh())

        ctk.CTkButton(header, text="+ Быстро добавить", width=140, command=self.quick_add_today).grid(row=0, column=3, sticky="e")

        self.list_area = ctk.CTkScrollableFrame(main, corner_radius=14, fg_color=("#1E293B", "#1E293B"))
        self.list_area.grid(row=1, column=0, sticky="nsew", padx=(18, 10), pady=(0, 16))
        self.list_area.grid_columnconfigure(0, weight=1)

        right = ctk.CTkFrame(main, corner_radius=14, fg_color=("#0F172A", "#0F172A"))
        right.grid(row=1, column=1, sticky="nsew", padx=(10, 18), pady=(0, 16))
        right.grid_rowconfigure(4, weight=1)
        right.grid_columnconfigure(0, weight=1)

        ctk.CTkLabel(right, text="Редактор", font=ctk.CTkFont(size=20, weight="bold")).grid(row=0, column=0, sticky="w", padx=14, pady=(12, 8))

        form = ctk.CTkFrame(right, fg_color="transparent")
        form.grid(row=1, column=0, sticky="ew", padx=14)
        form.grid_columnconfigure(1, weight=1)

        self._form_row(form, 0, "Название", ctk.CTkEntry(form, textvariable=self.title_var, placeholder_text="Что сделать"))
        self._form_row(form, 1, "Детали", ctk.CTkEntry(form, textvariable=self.details_var, placeholder_text="Дополнительные детали"))
        self._form_row(form, 2, "Дата", ctk.CTkEntry(form, textvariable=self.due_date_var, placeholder_text="2026-04-18 или 18.04"))

        time_frame = ctk.CTkFrame(form, fg_color="transparent")
        ctk.CTkOptionMenu(time_frame, variable=self.time_hour_var, values=[f"{h:02d}" for h in range(0, 24)], width=86, command=lambda _v: self._sync_time_from_dropdowns()).pack(side="left")
        ctk.CTkLabel(time_frame, text=":", width=16).pack(side="left", padx=4)
        ctk.CTkOptionMenu(time_frame, variable=self.time_min_var, values=["00", "05", "10", "15", "20", "25", "30", "35", "40", "45", "50", "55"], width=86, command=lambda _v: self._sync_time_from_dropdowns()).pack(side="left")
        ctk.CTkEntry(time_frame, textvariable=self.time_var, width=110, placeholder_text="20:15 / 20-15").pack(side="left", padx=(8, 0))
        self._form_row(form, 3, "Время", time_frame)

        self._form_row(form, 4, "Приоритет", ctk.CTkOptionMenu(form, variable=self.priority_var, values=list(PRIORITY_RU_TO_KEY.keys())))
        self._form_row(form, 5, "Теги", ctk.CTkEntry(form, textvariable=self.tags_var, placeholder_text="дом, школа"))
        self._form_row(form, 6, "Повтор", ctk.CTkOptionMenu(form, variable=self.recurring_var, values=list(RECURRING_RU_TO_KEY.keys())))
        self._form_row(form, 7, "Напоминания", ctk.CTkEntry(form, textvariable=self.reminders_var, placeholder_text="60,30,10"))

        editor_buttons = ctk.CTkFrame(right, fg_color="transparent")
        editor_buttons.grid(row=2, column=0, sticky="new", padx=14, pady=(6, 8))
        ctk.CTkButton(editor_buttons, text="Добавить", command=self.add_task, fg_color="#2563EB").pack(side="left", padx=(0, 8))
        ctk.CTkButton(editor_buttons, text="Сохранить", command=self.update_selected_task, fg_color="#0891B2").pack(side="left", padx=8)
        ctk.CTkButton(editor_buttons, text="Очистить форму", command=self.clear_form, fg_color="#334155").pack(side="left", padx=8)

        command_panel = ctk.CTkFrame(right, corner_radius=12, fg_color=("#1E293B", "#1E293B"))
        command_panel.grid(row=3, column=0, sticky="ew", padx=14, pady=(0, 8))
        command_panel.grid_columnconfigure(0, weight=1)
        ctk.CTkLabel(command_panel, text="Текстовые команды (как голосом)").grid(row=0, column=0, sticky="w", padx=10, pady=(8, 4))
        self.command_entry = ctk.CTkEntry(command_panel, placeholder_text="Например: добавь во вторник в 20-15 кормить крыс")
        self.command_entry.grid(row=1, column=0, sticky="ew", padx=10, pady=(0, 8))
        ctk.CTkButton(command_panel, text="Выполнить", width=120, command=self.execute_text_command).grid(row=1, column=1, padx=(0, 10), pady=(0, 8))

        log_panel = ctk.CTkFrame(right, corner_radius=12, fg_color=("#1E293B", "#1E293B"))
        log_panel.grid(row=4, column=0, sticky="nsew", padx=14, pady=(0, 12))
        log_panel.grid_columnconfigure(0, weight=1)
        log_panel.grid_rowconfigure(1, weight=1)
        ctk.CTkLabel(log_panel, text="Журнал").grid(row=0, column=0, sticky="w", padx=10, pady=(8, 4))
        self.log_box = ctk.CTkTextbox(log_panel, height=200)
        self.log_box.grid(row=1, column=0, sticky="nsew", padx=10, pady=(0, 10))
        self.log_box.configure(state="disabled")

    def _form_row(self, parent, row: int, label: str, widget) -> None:
        ctk.CTkLabel(parent, text=label, width=90, anchor="w").grid(row=row, column=0, sticky="w", pady=5, padx=(0, 8))
        widget.grid(row=row, column=1, sticky="ew", pady=5)

    def _bind_shortcuts(self) -> None:
        self.bind("<Control-n>", lambda _e: self.add_task())
        self.bind("<Control-s>", lambda _e: self.update_selected_task())
        self.bind("<Control-f>", lambda _e: self.search_entry.focus_set())
        self.bind("<Control-Return>", lambda _e: self.execute_text_command())

    def _priority_to_key(self, label: str) -> str:
        return PRIORITY_RU_TO_KEY.get(label.strip(), "medium")

    def _priority_to_ru(self, key: str | None) -> str:
        return PRIORITY_KEY_TO_RU.get((key or "medium").strip(), "Обычный")

    def _recurrence_to_key(self, label: str) -> str:
        return RECURRING_RU_TO_KEY.get(label.strip(), "")

    def _recurrence_to_ru(self, key: str | None) -> str:
        return RECURRING_KEY_TO_RU.get((key or "").strip(), "Нет")

    def _sync_time_from_dropdowns(self) -> None:
        self.time_var.set(f"{self.time_hour_var.get()}:{self.time_min_var.get()}")

    def _sync_dropdowns_from_time(self, value: str) -> None:
        parsed = ft.parse_time(value)
        if not parsed:
            return
        hh, mm = parsed.split(":", 1)
        self.time_hour_var.set(hh)
        self.time_min_var.set(mm)
        self.time_var.set(parsed)

    def _selected_time_value(self) -> str | None:
        candidate = self.time_var.get().strip()
        if not candidate:
            self._sync_time_from_dropdowns()
            candidate = self.time_var.get().strip()
        parsed = ft.parse_time(candidate)
        if parsed:
            self._sync_dropdowns_from_time(parsed)
        return parsed

    def get_person(self) -> ft.Person:
        return self.person_by_name[self.person_var.get()]

    def on_person_changed(self) -> None:
        self._cache_person_key = None
        self.selected_local_index = None
        self.refresh_tasks()

    def on_filter_changed(self) -> None:
        self.selected_local_index = None
        self.refresh_tasks()

    def _debounced_refresh(self) -> None:
        if self.search_after_id is not None:
            self.after_cancel(self.search_after_id)
        self.search_after_id = self.after(280, self.refresh_tasks)

    def _load_cached_todos(self, person: ft.Person) -> list[dict]:
        if self._cache_person_key != person.key:
            self._cache_person_key = person.key
            self._cache_todos = ft.load_todos(person)
        return self._cache_todos

    def _invalidate_cache(self) -> None:
        self._cache_person_key = None
        self._cache_todos = []

    def _resolve_filter_range(self) -> tuple[str | None, str | None, str]:
        value = self.filter_var.get().strip().lower()
        today = datetime.now().date()

        if value == "сегодня":
            iso = today.isoformat()
            return iso, iso, today.strftime("%d.%m.%Y")
        if value == "завтра":
            tomorrow = today + timedelta(days=1)
            iso = tomorrow.isoformat()
            return iso, iso, tomorrow.strftime("%d.%m.%Y")
        if value == "все":
            return None, None, "все"
        if value == "текущий месяц":
            start, end = ft.month_bounds(self.period_anchor)
            return start.isoformat(), end.isoformat(), f"{start.strftime('%m.%Y')}"

        start, end = ft.week_bounds(self.period_anchor)
        return start.isoformat(), end.isoformat(), f"{start.strftime('%d.%m')} - {end.strftime('%d.%m')}"

    def shift_period(self, delta: int) -> None:
        mode = self.filter_var.get().strip().lower()
        if mode == "текущий месяц":
            base = self.period_anchor
            month = base.month + delta
            year = base.year
            while month < 1:
                month += 12
                year -= 1
            while month > 12:
                month -= 12
                year += 1
            self.period_anchor = date(year, month, min(base.day, 28))
        else:
            self.period_anchor = self.period_anchor + timedelta(days=7 * delta)
        self.refresh_tasks()

    def _matches_search(self, todo: dict) -> bool:
        needle = self.search_var.get().strip().lower()
        if not needle:
            return True
        hay = " ".join(
            [
                str(todo.get("title") or "").lower(),
                str(todo.get("text") or "").lower(),
                str(todo.get("details") or "").lower(),
                str(todo.get("day") or "").lower(),
                str(todo.get("due_date") or "").lower(),
                str(todo.get("time") or "").lower(),
            ]
        )
        return needle in hay

    def refresh_tasks(self) -> None:
        person = self.get_person()
        todos = self._load_cached_todos(person)
        start_date, end_date, label = self._resolve_filter_range()
        self.period_label.configure(text=label)

        ordered = ft.filter_todos_by_range(todos, start_date, end_date)
        self.current_items = [(idx, todo) for idx, todo in ordered if self._matches_search(todo)]

        for child in self.list_area.winfo_children():
            child.destroy()
        self._cards = []

        if not self.current_items:
            ctk.CTkLabel(self.list_area, text="По этому фильтру задач нет", text_color="#94A3B8").grid(row=0, column=0, sticky="w", padx=10, pady=10)
            self.selected_local_index = None
            return

        for local_idx, (_global_idx, todo) in enumerate(self.current_items, start=1):
            card = TaskCard(self.list_area, self, local_index=local_idx, todo=todo, selected=(self.selected_local_index == local_idx - 1))
            card.grid(row=local_idx, column=0, sticky="ew", padx=10, pady=6)
            self._cards.append(card)

        if self.selected_local_index is not None and self.selected_local_index >= len(self.current_items):
            self.selected_local_index = None
        self._apply_card_selection()

    def _apply_card_selection(self) -> None:
        for idx, card in enumerate(self._cards):
            selected = self.selected_local_index == idx
            if selected:
                card.configure(border_color="#2FA4FF", fg_color=("#263042", "#263042"))
            else:
                card.configure(border_color=("#555", "#444"), fg_color=("#1F2937", "#1F2937"))

    def select_task(self, local_index: int) -> None:
        if local_index < 0 or local_index >= len(self.current_items):
            return

        self.selected_local_index = local_index
        _, todo = self.current_items[local_index]
        self.title_var.set(str(todo.get("title") or todo.get("text") or ""))
        self.details_var.set(str(todo.get("details") or ""))
        self.due_date_var.set(str(todo.get("due_date") or datetime.now().date().isoformat()))
        time_value = str(todo.get("time") or "")
        self.time_var.set(time_value)
        self._sync_dropdowns_from_time(time_value)
        self.priority_var.set(self._priority_to_ru(str(todo.get("priority") or "medium")))
        tags = todo.get("tags") if isinstance(todo.get("tags"), list) else []
        self.tags_var.set(", ".join(tags))
        self.recurring_var.set(self._recurrence_to_ru(str(todo.get("recurrence_rule") or todo.get("recurring") or "")))
        offsets = todo.get("reminder_offsets") if isinstance(todo.get("reminder_offsets"), list) else [60, 30, 10]
        self.reminders_var.set(",".join(str(x) for x in offsets))
        self._apply_card_selection()

    def clear_form(self) -> None:
        self.title_var.set("")
        self.details_var.set("")
        self.due_date_var.set(datetime.now().date().isoformat())
        self.time_hour_var.set("19")
        self.time_min_var.set("00")
        self._sync_time_from_dropdowns()
        self.priority_var.set("Обычный")
        self.tags_var.set("")
        self.recurring_var.set("Нет")
        self.reminders_var.set("60,30,10")

    def _parse_tags(self) -> list[str]:
        raw = self.tags_var.get().strip()
        if not raw:
            return []
        return [part.strip().lower() for part in raw.split(",") if part.strip()]

    def _parse_offsets(self) -> list[int]:
        raw = self.reminders_var.get().strip()
        if not raw:
            return [60, 30, 10]
        out: list[int] = []
        for piece in raw.split(","):
            p = piece.strip()
            if p.isdigit() and int(p) > 0:
                out.append(int(p))
        return out or [60, 30, 10]

    def _append_log(self, message: str) -> None:
        stamp = datetime.now().strftime("%H:%M:%S")
        line = f"[{stamp}] {message}\n"
        self.log_box.configure(state="normal")
        self.log_box.insert("end", line)
        self.log_box.see("end")
        self.log_box.configure(state="disabled")

    def _threadsafe_log(self, message: str) -> None:
        self.after(0, lambda: self._append_log(message))

    def _collect_messages(self, fn) -> list[str]:
        captured: list[str] = []

        def listener(message: str) -> None:
            captured.append(message)

        register_message_listener(listener)
        try:
            with muted_tts(), event_actor("desktop"):
                fn()
        finally:
            unregister_message_listener(listener)
        return captured

    def _set_voice_state(self, enabled: bool) -> None:
        def apply_state() -> None:
            self.voice_var.set(enabled)
            self.voice_status.configure(text=f"Голос: {'ON' if enabled else 'OFF'}", text_color="#2ECC71" if enabled else "#94A3B8")

        self.after(0, apply_state)

    def _set_bot_state(self, enabled: bool) -> None:
        self.bot_var.set(enabled)
        self.bot_status.configure(text=f"Бот: {'ON' if enabled else 'OFF'}", text_color="#2ECC71" if enabled else "#94A3B8")

    def _selected_entry(self) -> tuple[int, dict] | None:
        if self.selected_local_index is None:
            return None
        if self.selected_local_index < 0 or self.selected_local_index >= len(self.current_items):
            return None
        return self.current_items[self.selected_local_index]

    def add_task(self) -> None:
        person = self.get_person()
        title = self.title_var.get().strip()
        if not title:
            messagebox.showwarning("Добавление", "Укажи название задачи")
            return

        parsed_time = self._selected_time_value()
        if not parsed_time:
            messagebox.showwarning("Добавление", "Время должно быть в формате ЧЧ:ММ")
            return

        recurring = self._recurrence_to_key(self.recurring_var.get()) or None
        due_date = ft.parse_due_date_input(self.due_date_var.get().strip())
        if not due_date:
            messagebox.showwarning("Добавление", "Укажи корректную дату (например 2026-04-18 или 18.04)")
            return

        todos = self._load_cached_todos(person)
        next_id = max([item.get("id", 0) for item in todos], default=0) + 1

        todo = {
            "id": next_id,
            "title": title,
            "text": title,
            "details": self.details_var.get().strip(),
            "due_date": due_date,
            "day": ft.weekday_ru(datetime.fromisoformat(due_date).date()),
            "time": parsed_time,
            "priority": self._priority_to_key(self.priority_var.get()),
            "tags": self._parse_tags(),
            "recurrence_rule": recurring,
            "series_id": str(uuid.uuid4()) if recurring else None,
            "generated_from_rule": bool(recurring),
            "reminder_offsets": self._parse_offsets(),
            "status": "active",
            "done": False,
            "done_at": None,
            "created_at": datetime.now().isoformat(timespec="seconds"),
        }

        ft.save_todos(person, [*todos, todo])
        ft.push_history(person, "add", {"created_ids": [next_id]})
        log_event("todo_add", person=person.key, actor="desktop", count=1, day=todo["day"], due_date=due_date, time=parsed_time, title=title, recurrence=recurring or "")
        self._invalidate_cache()
        self._append_log(f"Добавил задачу: {title}")
        self.clear_form()
        self.refresh_tasks()

    def update_selected_task(self) -> None:
        selected = self._selected_entry()
        if not selected:
            messagebox.showinfo("Редактирование", "Сначала выбери задачу")
            return

        person = self.get_person()
        global_idx, _todo = selected
        todos = self._load_cached_todos(person)
        if global_idx >= len(todos):
            self.refresh_tasks()
            return

        title = self.title_var.get().strip()
        if not title:
            messagebox.showwarning("Редактирование", "Название не может быть пустым")
            return

        due_date = ft.parse_due_date_input(self.due_date_var.get().strip())
        recurring = self._recurrence_to_key(self.recurring_var.get()) or None
        if not due_date:
            messagebox.showwarning("Редактирование", "Укажи корректную дату (например 2026-04-18 или 18.04)")
            return

        parsed_time = self._selected_time_value()
        if not parsed_time:
            messagebox.showwarning("Редактирование", "Время должно быть в формате ЧЧ:ММ")
            return

        old_state = copy.deepcopy(todos[global_idx])
        todos[global_idx]["title"] = title
        todos[global_idx]["text"] = title
        todos[global_idx]["details"] = self.details_var.get().strip()
        todos[global_idx]["due_date"] = due_date
        todos[global_idx]["day"] = ft.weekday_ru(datetime.fromisoformat(due_date).date())
        todos[global_idx]["time"] = parsed_time
        todos[global_idx]["priority"] = self._priority_to_key(self.priority_var.get())
        todos[global_idx]["tags"] = self._parse_tags()
        todos[global_idx]["recurrence_rule"] = recurring
        todos[global_idx]["generated_from_rule"] = bool(recurring)
        if recurring and not todos[global_idx].get("series_id"):
            todos[global_idx]["series_id"] = str(uuid.uuid4())
        todos[global_idx]["reminder_offsets"] = self._parse_offsets()
        todos[global_idx]["status"] = "active" if str(todos[global_idx].get("status") or "") not in {"done"} else "done"
        todos[global_idx]["updated_at"] = datetime.now().isoformat(timespec="seconds")

        ft.save_todos(person, todos)
        ft.push_history(person, "update_item", {"id": old_state.get("id"), "before": old_state})
        log_event("todo_update", person=person.key, actor="desktop", day=todos[global_idx].get("day") or "", due_date=due_date, time=parsed_time, title=title)
        self._invalidate_cache()
        self._append_log(f"Сохранил изменения: {title}")
        self.refresh_tasks()

    def delete_by_local_index(self, local_index: int) -> None:
        if local_index < 0 or local_index >= len(self.current_items):
            return

        person = self.get_person()
        global_idx, todo = self.current_items[local_index]
        todos = self._load_cached_todos(person)
        if global_idx >= len(todos):
            self.refresh_tasks()
            return

        removed = todos.pop(global_idx)
        ft.save_todos(person, todos)
        ft.push_history(person, "restore_items", {"items": [removed]})
        title = todo.get("title") or todo.get("text") or "задача"
        log_event("todo_delete", person=person.key, actor="desktop", day=removed.get("day") or "", due_date=removed.get("due_date") or "", mode="ui", title=title)
        self._invalidate_cache()
        self._append_log(f"Удалил: {title}")

        if self.selected_local_index == local_index:
            self.selected_local_index = None
        self.refresh_tasks()

    def mark_done_by_local_index(self, local_index: int) -> None:
        if local_index < 0 or local_index >= len(self.current_items):
            return

        person = self.get_person()
        global_idx, todo = self.current_items[local_index]
        todos = self._load_cached_todos(person)
        if global_idx >= len(todos):
            self.refresh_tasks()
            return

        old_state = copy.deepcopy(todos[global_idx])
        now_iso = datetime.now().isoformat(timespec="seconds")

        todos[global_idx]["done"] = True
        todos[global_idx]["status"] = "done"
        todos[global_idx]["done_at"] = now_iso

        ft.save_todos(person, todos)
        ft.push_history(person, "update_item", {"id": old_state.get("id"), "before": old_state})
        title = todo.get("title") or todo.get("text") or "задача"
        log_event("todo_done", person=person.key, actor="desktop", day=todos[global_idx].get("day") or "", due_date=todos[global_idx].get("due_date") or "", id=old_state.get("id"), title=title)
        self._invalidate_cache()
        self._append_log(f"Отметил готово: {title}")
        self.refresh_tasks()

    def quick_add_today(self) -> None:
        self.due_date_var.set(datetime.now().date().isoformat())
        self.time_hour_var.set("19")
        self.time_min_var.set("00")
        self._sync_time_from_dropdowns()
        self.title_var.set("")
        self._append_log("Форма готова для быстрого добавления на сегодня")

    def _resolve_text_action(self, person: ft.Person, text: str) -> str | None:
        action = ft.parse_action(person, text)
        if action:
            return action
        normalized = ft.normalize_text(text)
        action = ft.parse_action(person, normalized)
        if action:
            return action

        if not normalized:
            return None

        if ft.parse_day_or_relative(normalized) and ft.extract_time_from_inline(normalized):
            return "add"
        if ft.parse_due_date_input(normalized) and ft.extract_time_from_inline(normalized):
            return "add"
        if normalized.startswith(("список", "покажи", "что на")):
            return "list"
        if normalized.startswith("расписание"):
            return "schedule"
        if normalized.startswith(("отмени", "откат")):
            return "undo"
        return None

    def execute_text_command(self) -> None:
        person = self.get_person()
        text = self.command_entry.get().strip()
        if not text:
            return

        self._append_log(f"Команда: {text}")

        def runner() -> None:
            action = self._resolve_text_action(person, text)
            if action in {None, "stop", "switch_person"}:
                matched_global = match_command(text) or match_command(text.lower()) or match_command(ft.normalize_text(text))
                if matched_global:
                    execute_command(matched_global)
                    ft.speak("Команда выполнена.")
                    return
                ft.speak("Не понял команду")
                return
            if action == "add":
                ft.add_todo(person, initial_text=text)
            elif action in {"delete", "clear"}:
                ft.delete_todo(person, initial_text=text)
            elif action == "done":
                ft.mark_done(person, initial_text=text)
            elif action == "move":
                ft.move_todo(person, initial_text=text)
            elif action == "list":
                ft.list_todos_for_requested_day(person, initial_text=text)
            elif action == "schedule":
                ft.get_schedule_for_day(person, initial_text=text)
            elif action == "undo":
                ft.undo_last_action(person)
            elif action == "review":
                ft.weekly_review(person)
            else:
                ft.speak("Не понял команду")

        messages = self._collect_messages(runner)
        for msg in messages or ["Команда выполнена"]:
            self._append_log(msg)

        self.command_entry.delete(0, "end")
        self._invalidate_cache()
        self.refresh_tasks()

    def run_weekly_review(self) -> None:
        person = self.get_person()
        messages = self._collect_messages(lambda: ft.weekly_review(person))
        for msg in messages or ["Недельный обзор выполнен"]:
            self._append_log(msg)

    def undo_action(self) -> None:
        person = self.get_person()
        messages = self._collect_messages(lambda: ft.undo_last_action(person))
        for msg in messages or ["Откат выполнен"]:
            self._append_log(msg)
        self._invalidate_cache()
        self.refresh_tasks()

    def toggle_voice(self) -> None:
        if self.voice_var.get():
            if self.voice_worker and self.voice_worker.is_alive():
                return
            self.voice_worker = VoiceWorker(on_log=self._threadsafe_log, on_state=self._set_voice_state)
            self.voice_worker.start()
            return

        if self.voice_worker:
            self.voice_worker.stop()
        self._set_voice_state(False)

    def toggle_bot(self) -> None:
        if self.bot_var.get():
            if not os.getenv("TELEGRAM_BOT_TOKEN", "").strip():
                self._append_log("Нельзя включить бота: TELEGRAM_BOT_TOKEN не задан")
                self._set_bot_state(False)
                return
            started = self.bot_host.start()
            self._set_bot_state(started)
            return

        self.bot_host.stop()
        self._set_bot_state(False)

    def on_close(self) -> None:
        if self.voice_worker:
            self.voice_worker.stop()
        self.bot_host.stop()
        self.destroy()


def run_bot_only() -> None:
    import telegram_bot

    telegram_bot.main()


def main() -> None:
    if "--bot-only" in sys.argv:
        run_bot_only()
        return

    app = DesktopTodoApp()
    app.mainloop()


if __name__ == "__main__":
    main()
