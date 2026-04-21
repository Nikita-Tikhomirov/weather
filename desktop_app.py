import calendar
import copy
import os
import subprocess
import sys
import threading
import traceback
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Callable

import customtkinter as ctk
from tkinter import messagebox

import family_todo as ft
from audio import listen_command
from commands import execute_command, match_command
from todo_logger import log_event
from todo_ops import move_task, transition_task


ctk.set_appearance_mode("light")
ctk.set_default_color_theme("blue")

PRIORITY_RU_TO_KEY = {
    "Высокий": "high",
    "Обычный": "medium",
    "Низкий": "low",
}
PRIORITY_KEY_TO_RU = {v: k for k, v in PRIORITY_RU_TO_KEY.items()}

WORKFLOW_RU_TO_KEY = {
    "К выполнению": "todo",
    "В работе": "in_progress",
    "На проверке": "in_review",
    "Готово": "done",
}
WORKFLOW_KEY_TO_RU = {v: k for k, v in WORKFLOW_RU_TO_KEY.items()}
WORKFLOW_ORDER = ["todo", "in_progress", "in_review", "done"]

MONTH_NAMES_RU = (
    "Январь",
    "Февраль",
    "Март",
    "Апрель",
    "Май",
    "Июнь",
    "Июль",
    "Август",
    "Сентябрь",
    "Октябрь",
    "Ноябрь",
    "Декабрь",
)
WEEKDAY_SHORT_RU = ("Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс")

APPEARANCE_LABEL_TO_KEY = {
    "Светлая": "light",
    "Темная": "dark",
}
APPEARANCE_KEY_TO_LABEL = {value: key for key, value in APPEARANCE_LABEL_TO_KEY.items()}
THEME_DEFAULT_BY_MODE = {
    "light": "Ocean",
    "dark": "Midnight",
}
THEME_SCHEMES: dict[str, dict[str, dict[str, str]]] = {
    "light": {
        "Ocean": {
            "bg_app": "#F1F5F9",
            "bg_panel": "#FFFFFF",
            "bg_card": "#F8FAFC",
            "text_primary": "#0F172A",
            "text_muted": "#64748B",
            "border": "#E2E8F0",
            "accent": "#2563EB",
            "accent_hover": "#1D4ED8",
            "success": "#16A34A",
            "success_hover": "#15803D",
            "danger": "#DC2626",
            "danger_hover": "#B91C1C",
            "calendar_chip_bg": "#DBEAFE",
            "calendar_chip_text": "#1E3A8A",
            "selected_nav_bg": "#E2E8F0",
        },
        "Slate": {
            "bg_app": "#EEF2F7",
            "bg_panel": "#FFFFFF",
            "bg_card": "#F6F8FC",
            "text_primary": "#111827",
            "text_muted": "#6B7280",
            "border": "#DCE3EE",
            "accent": "#475569",
            "accent_hover": "#334155",
            "success": "#15803D",
            "success_hover": "#166534",
            "danger": "#DC2626",
            "danger_hover": "#B91C1C",
            "calendar_chip_bg": "#E2E8F0",
            "calendar_chip_text": "#1F2937",
            "selected_nav_bg": "#E2E8F0",
        },
        "Forest": {
            "bg_app": "#ECFDF3",
            "bg_panel": "#FFFFFF",
            "bg_card": "#F3FDF7",
            "text_primary": "#052E16",
            "text_muted": "#3F6A56",
            "border": "#CFE9DA",
            "accent": "#15803D",
            "accent_hover": "#166534",
            "success": "#16A34A",
            "success_hover": "#15803D",
            "danger": "#DC2626",
            "danger_hover": "#B91C1C",
            "calendar_chip_bg": "#DCFCE7",
            "calendar_chip_text": "#166534",
            "selected_nav_bg": "#D1FAE5",
        },
    },
    "dark": {
        "Midnight": {
            "bg_app": "#0B1220",
            "bg_panel": "#111827",
            "bg_card": "#1F2937",
            "text_primary": "#F8FAFC",
            "text_muted": "#94A3B8",
            "border": "#334155",
            "accent": "#3B82F6",
            "accent_hover": "#2563EB",
            "success": "#22C55E",
            "success_hover": "#16A34A",
            "danger": "#F87171",
            "danger_hover": "#EF4444",
            "calendar_chip_bg": "#1E3A8A",
            "calendar_chip_text": "#DBEAFE",
            "selected_nav_bg": "#1E293B",
        },
        "Graphite": {
            "bg_app": "#111111",
            "bg_panel": "#1A1A1A",
            "bg_card": "#242424",
            "text_primary": "#F3F4F6",
            "text_muted": "#A1A1AA",
            "border": "#3F3F46",
            "accent": "#7C8BA1",
            "accent_hover": "#64748B",
            "success": "#4ADE80",
            "success_hover": "#22C55E",
            "danger": "#F87171",
            "danger_hover": "#EF4444",
            "calendar_chip_bg": "#374151",
            "calendar_chip_text": "#E5E7EB",
            "selected_nav_bg": "#2A2A2A",
        },
        "Nord": {
            "bg_app": "#0F172A",
            "bg_panel": "#111827",
            "bg_card": "#1E293B",
            "text_primary": "#E2E8F0",
            "text_muted": "#93C5FD",
            "border": "#334155",
            "accent": "#38BDF8",
            "accent_hover": "#0EA5E9",
            "success": "#34D399",
            "success_hover": "#10B981",
            "danger": "#FB7185",
            "danger_hover": "#F43F5E",
            "calendar_chip_bg": "#0C4A6E",
            "calendar_chip_text": "#BAE6FD",
            "selected_nav_bg": "#172554",
        },
    },
}


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
                if matched:
                    execute_command(matched)
                    continue
                person = ft.PEOPLE[0]
                action = ft.parse_action(person, command_text)
                if action == "add":
                    ft.add_todo(person, initial_text=command_text)
                elif action in {"delete", "clear"}:
                    ft.delete_todo(person, initial_text=command_text)
                elif action == "done":
                    ft.mark_done(person, initial_text=command_text)
                elif action == "move":
                    ft.move_todo(person, initial_text=command_text)
                elif action == "list":
                    ft.list_todos_for_requested_day(person, initial_text=command_text)
                else:
                    self._on_log(f"Команда не распознана: {command_text}")
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
            env = os.environ.copy()
            env.setdefault("TODO_BACKEND_SOURCE", "telegram")
            self._process = subprocess.Popen(cmd, cwd=str(Path(__file__).resolve().parent), env=env)
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


class DatePickerPopup(ctk.CTkToplevel):
    def __init__(self, parent, initial_date: date, on_select):
        super().__init__(parent)
        self.on_select = on_select
        self.selected_date = initial_date
        self.view_year = initial_date.year
        self.view_month = initial_date.month
        self.title("Календарь")
        self.geometry("360x340")
        self.resizable(False, False)
        self.transient(parent)
        self.grab_set()
        self._build()
        self._render()

    def _build(self) -> None:
        root = ctk.CTkFrame(self)
        root.pack(fill="both", expand=True, padx=8, pady=8)
        head = ctk.CTkFrame(root, fg_color="transparent")
        head.pack(fill="x")
        ctk.CTkButton(head, text="<", width=36, command=lambda: self._shift(-1)).pack(side="left")
        self.title_label = ctk.CTkLabel(head, text="")
        self.title_label.pack(side="left", expand=True)
        ctk.CTkButton(head, text=">", width=36, command=lambda: self._shift(1)).pack(side="right")
        self.grid_frame = ctk.CTkFrame(root, fg_color="transparent")
        self.grid_frame.pack(fill="both", expand=True, pady=(8, 0))
        for r in range(7):
            self.grid_frame.grid_rowconfigure(r, weight=1)
        for c in range(7):
            self.grid_frame.grid_columnconfigure(c, weight=1)

    def _shift(self, months: int) -> None:
        idx = self.view_year * 12 + self.view_month - 1 + months
        self.view_year = idx // 12
        self.view_month = idx % 12 + 1
        self._render()

    def _render(self) -> None:
        for child in self.grid_frame.winfo_children():
            child.destroy()
        self.title_label.configure(text=f"{MONTH_NAMES_RU[self.view_month - 1]} {self.view_year}")
        for i, day in enumerate(WEEKDAY_SHORT_RU):
            ctk.CTkLabel(self.grid_frame, text=day, text_color="#64748B").grid(row=0, column=i, padx=2, pady=2)
        matrix = calendar.monthcalendar(self.view_year, self.view_month)
        while len(matrix) < 6:
            matrix.append([0] * 7)
        for r, week in enumerate(matrix, start=1):
            for c, d in enumerate(week):
                if d <= 0:
                    ctk.CTkLabel(self.grid_frame, text="").grid(row=r, column=c, padx=2, pady=2)
                    continue
                dt = date(self.view_year, self.view_month, d)
                active = dt == self.selected_date
                ctk.CTkButton(
                    self.grid_frame,
                    text=str(d),
                    fg_color="#2563EB" if active else "#E2E8F0",
                    text_color="#FFFFFF" if active else "#0F172A",
                    hover_color="#1D4ED8" if active else "#CBD5E1",
                    command=lambda pick=dt: self._pick(pick),
                ).grid(row=r, column=c, padx=2, pady=2, sticky="nsew")

    def _pick(self, dt: date) -> None:
        self.on_select(dt)
        self.destroy()


class TaskEditorPopup(ctk.CTkToplevel):
    def __init__(self, parent, todo: dict | None, on_save, on_delete=None, theme_tokens: dict[str, str] | None = None):
        super().__init__(parent)
        self.todo = copy.deepcopy(todo) if todo else None
        self.on_save = on_save
        self.on_delete = on_delete
        self.theme_tokens = theme_tokens or THEME_SCHEMES["light"]["Ocean"]
        self.title("Редактор задачи")
        self.geometry("520x500")
        self.resizable(False, False)
        self.transient(parent)
        self.grab_set()
        src = todo or {}
        self.title_var = ctk.StringVar(value=str(src.get("title") or src.get("text") or ""))
        self.details_var = ctk.StringVar(value=str(src.get("details") or ""))
        self.date_var = ctk.StringVar(value=str(src.get("due_date") or date.today().isoformat()))
        self.time_var = ctk.StringVar(value=str(src.get("time") or "19:00"))
        self.priority_var = ctk.StringVar(value=PRIORITY_KEY_TO_RU.get(str(src.get("priority") or "medium"), "Обычный"))
        self.status_var = ctk.StringVar(value=WORKFLOW_KEY_TO_RU.get(str(src.get("workflow_status") or "todo"), "К выполнению"))
        self.tags_var = ctk.StringVar(value=", ".join(src.get("tags") if isinstance(src.get("tags"), list) else []))
        self._build()

    def _c(self, token: str, fallback: str) -> str:
        return self.theme_tokens.get(token, fallback)

    def _build(self) -> None:
        root = ctk.CTkFrame(self)
        root.pack(fill="both", expand=True, padx=12, pady=12)
        root.grid_columnconfigure(1, weight=1)
        self._row(root, 0, "Название", ctk.CTkEntry(root, textvariable=self.title_var))
        self._row(root, 1, "Детали", ctk.CTkEntry(root, textvariable=self.details_var))
        date_row = ctk.CTkFrame(root, fg_color="transparent")
        date_row.grid_columnconfigure(0, weight=1)
        ctk.CTkEntry(date_row, textvariable=self.date_var).grid(row=0, column=0, sticky="ew")
        ctk.CTkButton(date_row, text="📅", width=40, command=self._pick_date).grid(row=0, column=1, padx=(8, 0))
        self._row(root, 2, "Дата", date_row)
        self._row(root, 3, "Время", ctk.CTkEntry(root, textvariable=self.time_var))
        self._row(root, 4, "Приоритет", ctk.CTkOptionMenu(root, variable=self.priority_var, values=list(PRIORITY_RU_TO_KEY.keys())))
        self._row(root, 5, "Статус", ctk.CTkOptionMenu(root, variable=self.status_var, values=list(WORKFLOW_RU_TO_KEY.keys())))
        self._row(root, 6, "Теги", ctk.CTkEntry(root, textvariable=self.tags_var))
        btns = ctk.CTkFrame(root, fg_color="transparent")
        btns.grid(row=7, column=0, columnspan=2, sticky="ew", pady=(14, 0))
        ctk.CTkButton(btns, text="Сохранить", fg_color=self._c("accent", "#2563EB"), hover_color=self._c("accent_hover", "#1D4ED8"), command=self._save).pack(side="left")
        if self.todo and self.on_delete:
            ctk.CTkButton(btns, text="Удалить", fg_color=self._c("danger", "#DC2626"), hover_color=self._c("danger_hover", "#B91C1C"), command=self._delete).pack(side="left", padx=(8, 0))
        ctk.CTkButton(btns, text="Закрыть", fg_color=self._c("selected_nav_bg", "#64748B"), text_color=self._c("text_primary", "#0F172A"), hover_color=self._c("accent_hover", "#1D4ED8"), command=self.destroy).pack(side="left", padx=(8, 0))

    def _row(self, parent, idx: int, label: str, widget) -> None:
        ctk.CTkLabel(parent, text=label, anchor="w").grid(row=idx, column=0, sticky="w", pady=6, padx=(0, 8))
        widget.grid(row=idx, column=1, sticky="ew", pady=6)

    def _pick_date(self) -> None:
        parsed = ft.parse_due_date_input(self.date_var.get())
        base = datetime.fromisoformat(parsed).date() if parsed else date.today()
        DatePickerPopup(self, base, lambda d: self.date_var.set(d.isoformat()))

    def _save(self) -> None:
        title = self.title_var.get().strip()
        if not title:
            messagebox.showwarning("Редактор", "Название не может быть пустым")
            return
        due = ft.parse_due_date_input(self.date_var.get().strip())
        if not due:
            messagebox.showwarning("Редактор", "Некорректная дата")
            return
        time_value = ft.parse_time(self.time_var.get().strip())
        if not time_value:
            messagebox.showwarning("Редактор", "Некорректное время")
            return
        wf = WORKFLOW_RU_TO_KEY.get(self.status_var.get(), "todo")
        payload = {
            "title": title,
            "text": title,
            "details": self.details_var.get().strip(),
            "due_date": due,
            "day": ft.weekday_ru(datetime.fromisoformat(due).date()),
            "time": time_value,
            "priority": PRIORITY_RU_TO_KEY.get(self.priority_var.get(), "medium"),
            "workflow_status": wf,
            "status": "done" if wf == "done" else "active",
            "done": wf == "done",
            "done_at": datetime.now().isoformat(timespec="seconds") if wf == "done" else None,
            "tags": [x.strip().lower() for x in self.tags_var.get().split(",") if x.strip()],
            "updated_at": datetime.now().isoformat(timespec="seconds"),
        }
        self.on_save(payload)
        self.destroy()

    def _delete(self) -> None:
        if self.on_delete and messagebox.askyesno("Удаление", "Удалить задачу?"):
            self.on_delete()
            self.destroy()


class FamilyTaskPopup(ctk.CTkToplevel):
    def __init__(self, parent, task: dict | None, on_save, on_delete=None, theme_tokens: dict[str, str] | None = None):
        super().__init__(parent)
        self.task = copy.deepcopy(task) if task else None
        self.on_save = on_save
        self.on_delete = on_delete
        self.theme_tokens = theme_tokens or THEME_SCHEMES["light"]["Ocean"]
        src = task or {}
        self.title("Семейное дело")
        self.geometry("620x560")
        self.resizable(False, False)
        self.transient(parent)
        self.grab_set()

        start_at = str(src.get("start_at") or "")
        start_dt = datetime.fromisoformat(start_at) if start_at else datetime.now().replace(minute=0, second=0, microsecond=0)
        self.title_var = ctk.StringVar(value=str(src.get("title") or src.get("text") or ""))
        self.details_var = ctk.StringVar(value=str(src.get("details") or ""))
        self.date_var = ctk.StringVar(value=start_dt.date().isoformat())
        self.time_var = ctk.StringVar(value=start_dt.strftime("%H:%M"))
        self.duration_var = ctk.StringVar(value=str(src.get("duration_minutes") or 60))
        self.status_var = ctk.StringVar(value=WORKFLOW_KEY_TO_RU.get(str(src.get("workflow_status") or "todo"), "К выполнению"))
        participants = src.get("participants") if isinstance(src.get("participants"), list) else []
        self.participant_vars: dict[str, ctk.BooleanVar] = {
            person.key: ctk.BooleanVar(value=person.key in participants) for person in ft.PEOPLE
        }
        self._build()

    def _c(self, token: str, fallback: str) -> str:
        return self.theme_tokens.get(token, fallback)

    def _build(self) -> None:
        root = ctk.CTkFrame(self)
        root.pack(fill="both", expand=True, padx=12, pady=12)
        root.grid_columnconfigure(1, weight=1)
        ctk.CTkLabel(root, text="Название").grid(row=0, column=0, sticky="w", pady=6, padx=(0, 8))
        ctk.CTkEntry(root, textvariable=self.title_var).grid(row=0, column=1, sticky="ew", pady=6)
        ctk.CTkLabel(root, text="Детали").grid(row=1, column=0, sticky="w", pady=6, padx=(0, 8))
        ctk.CTkEntry(root, textvariable=self.details_var).grid(row=1, column=1, sticky="ew", pady=6)
        date_row = ctk.CTkFrame(root, fg_color="transparent")
        date_row.grid_columnconfigure(0, weight=1)
        ctk.CTkEntry(date_row, textvariable=self.date_var).grid(row=0, column=0, sticky="ew")
        ctk.CTkButton(date_row, text="📅", width=40, command=self._pick_date).grid(row=0, column=1, padx=(8, 0))
        ctk.CTkLabel(root, text="Дата").grid(row=2, column=0, sticky="w", pady=6, padx=(0, 8))
        date_row.grid(row=2, column=1, sticky="ew", pady=6)
        ctk.CTkLabel(root, text="Время").grid(row=3, column=0, sticky="w", pady=6, padx=(0, 8))
        ctk.CTkEntry(root, textvariable=self.time_var).grid(row=3, column=1, sticky="ew", pady=6)
        ctk.CTkLabel(root, text="Длительность (мин)").grid(row=4, column=0, sticky="w", pady=6, padx=(0, 8))
        ctk.CTkEntry(root, textvariable=self.duration_var).grid(row=4, column=1, sticky="ew", pady=6)
        ctk.CTkLabel(root, text="Статус").grid(row=5, column=0, sticky="w", pady=6, padx=(0, 8))
        ctk.CTkOptionMenu(root, variable=self.status_var, values=list(WORKFLOW_RU_TO_KEY.keys())).grid(row=5, column=1, sticky="ew", pady=6)

        ctk.CTkLabel(root, text="Участники").grid(row=6, column=0, sticky="nw", pady=6, padx=(0, 8))
        users = ctk.CTkFrame(root, fg_color="transparent")
        users.grid(row=6, column=1, sticky="ew", pady=6)
        for idx, person in enumerate(ft.PEOPLE):
            ctk.CTkCheckBox(users, text=person.display_name, variable=self.participant_vars[person.key]).grid(row=idx // 2, column=idx % 2, sticky="w", padx=(0, 12), pady=4)

        btns = ctk.CTkFrame(root, fg_color="transparent")
        btns.grid(row=7, column=0, columnspan=2, sticky="ew", pady=(12, 0))
        ctk.CTkButton(btns, text="Сохранить", fg_color=self._c("accent", "#2563EB"), hover_color=self._c("accent_hover", "#1D4ED8"), command=self._save).pack(side="left")
        if self.task and self.on_delete:
            ctk.CTkButton(btns, text="Удалить", fg_color=self._c("danger", "#DC2626"), hover_color=self._c("danger_hover", "#B91C1C"), command=self._delete).pack(side="left", padx=(8, 0))
        ctk.CTkButton(btns, text="Закрыть", fg_color=self._c("selected_nav_bg", "#64748B"), text_color=self._c("text_primary", "#0F172A"), hover_color=self._c("accent_hover", "#1D4ED8"), command=self.destroy).pack(side="left", padx=(8, 0))

    def _pick_date(self) -> None:
        parsed = ft.parse_due_date_input(self.date_var.get())
        base = datetime.fromisoformat(parsed).date() if parsed else date.today()
        DatePickerPopup(self, base, lambda d: self.date_var.set(d.isoformat()))

    def _save(self) -> None:
        title = self.title_var.get().strip()
        if not title:
            messagebox.showwarning("Семейное дело", "Название не может быть пустым.")
            return
        due_date = ft.parse_due_date_input(self.date_var.get().strip())
        if not due_date:
            messagebox.showwarning("Семейное дело", "Некорректная дата.")
            return
        time_value = ft.parse_time(self.time_var.get().strip())
        if not time_value:
            messagebox.showwarning("Семейное дело", "Некорректное время.")
            return
        try:
            duration = max(0, int(self.duration_var.get().strip()))
        except ValueError:
            messagebox.showwarning("Семейное дело", "Длительность должна быть числом.")
            return
        participants = [key for key, var in self.participant_vars.items() if var.get()]
        if not participants:
            messagebox.showwarning("Семейное дело", "Выберите хотя бы одного участника.")
            return
        workflow_status = WORKFLOW_RU_TO_KEY.get(self.status_var.get(), "todo")
        payload = {
            "title": title,
            "text": title,
            "details": self.details_var.get().strip(),
            "start_at": f"{due_date}T{time_value}",
            "due_date": due_date,
            "time": time_value,
            "duration_minutes": duration,
            "participants": participants,
            "is_family": True,
            "workflow_status": workflow_status,
            "updated_at": datetime.now().isoformat(timespec="seconds"),
        }
        self.on_save(payload)
        self.destroy()

    def _delete(self) -> None:
        if self.on_delete and messagebox.askyesno("Удаление", "Удалить семейное дело?"):
            self.on_delete()
            self.destroy()


class KanbanCard(ctk.CTkFrame):
    def __init__(self, parent, app, todo: dict):
        super().__init__(
            parent,
            corner_radius=10,
            border_width=1,
            border_color=app._c("border"),
            fg_color=app._c("bg_panel"),
        )
        self.app = app
        self.todo = todo
        self.grid_columnconfigure(0, weight=1)
        head = ctk.CTkFrame(self, fg_color="transparent")
        head.grid(row=0, column=0, sticky="ew", padx=10, pady=(8, 2))
        head.grid_columnconfigure(0, weight=1)
        if app.selection_mode:
            checked = ctk.BooleanVar(value=int(todo.get("id") or 0) in app.selected_ids)
            ctk.CTkCheckBox(head, text="", variable=checked, width=18, command=lambda: app.toggle_task_selection(int(todo.get("id") or 0))).grid(row=0, column=0, sticky="w")
        title_label = ctk.CTkLabel(head, text=str(todo.get("title") or todo.get("text") or "Без названия"), anchor="w", font=ctk.CTkFont(size=14, weight="bold"))
        title_label.grid(row=0, column=0, sticky="w", padx=(24 if app.selection_mode else 0, 0))
        details = str(todo.get("details") or "").strip()
        details_label = None
        if details:
            details_label = ctk.CTkLabel(self, text=details[:100], anchor="w", text_color=app._c("text_muted"))
            details_label.grid(row=1, column=0, sticky="ew", padx=10)
        due_label = ctk.CTkLabel(
            self,
            text=f"{todo.get('due_date') or ''} {todo.get('time') or ''}".strip(),
            anchor="w",
            text_color=app._c("text_muted"),
        )
        due_label.grid(row=2, column=0, sticky="ew", padx=10, pady=(2, 6))
        btns = ctk.CTkFrame(self, fg_color="transparent")
        btns.grid(row=3, column=0, sticky="ew", padx=10, pady=(0, 8))
        ctk.CTkButton(btns, text="Открыть", width=68, height=26, command=lambda: app.open_task_editor(todo)).pack(side="left")
        ctk.CTkButton(
            btns,
            text="Готово",
            width=62,
            height=26,
            fg_color=app._c("success"),
            hover_color=app._c("success_hover"),
            command=lambda: app.quick_mark_done(todo),
        ).pack(side="left", padx=(6, 0))
        ctk.CTkButton(
            btns,
            text="Удалить",
            width=62,
            height=26,
            fg_color=app._c("danger"),
            hover_color=app._c("danger_hover"),
            command=lambda: app.delete_task(todo),
        ).pack(side="left", padx=(6, 0))
        drag_targets = [self, head, title_label, due_label]
        if details_label is not None:
            drag_targets.append(details_label)
        for widget in drag_targets:
            widget.bind("<ButtonPress-1>", lambda e, td=self.todo: self.app.start_drag(td, e, source="kanban"))
            widget.bind("<B1-Motion>", lambda e, td=self.todo: self.app.on_drag_motion(td, e))
            widget.bind("<ButtonRelease-1>", lambda e, td=self.todo: self.app.end_drag(td, e))

class DesktopTodoApp(ctk.CTk):
    def __init__(self) -> None:
        super().__init__()
        self.title("Ctrl-Center")
        self.geometry("1520x920")
        self.minsize(1260, 760)
        self._appearance_mode_key = "light"
        self._theme_scheme = THEME_DEFAULT_BY_MODE[self._appearance_mode_key]
        self._theme_tokens = THEME_SCHEMES[self._appearance_mode_key][self._theme_scheme]
        self.configure(fg_color=self._c("bg_app"))
        ft.bootstrap_data()
        self.person_by_name = {p.display_name: p for p in ft.PEOPLE}
        self.display_names = [p.display_name for p in ft.PEOPLE]
        self.person_var = ctk.StringVar(value=self.display_names[0])
        self.family_filter_var = ctk.StringVar(value="upcoming")
        self.search_var = ctk.StringVar(value="")
        self.tasks_date_filter_var = ctk.StringVar(value="")
        self.appearance_var = ctk.StringVar(value=APPEARANCE_KEY_TO_LABEL[self._appearance_mode_key])
        self.theme_scheme_var = ctk.StringVar(value=self._theme_scheme)
        self.current_page = "dashboard"
        self.current_month_anchor = date.today().replace(day=1)
        self.selection_mode = False
        self.selected_ids: set[int] = set()
        self.voice_var = ctk.BooleanVar(value=False)
        self.bot_var = ctk.BooleanVar(value=False)
        self.voice_worker: VoiceWorker | None = None
        self.bot_host = BotProcessHost(on_log=self._append_log)
        self._cache_person_key: str | None = None
        self._cache_todos: list[dict] = []
        self._drag_id: int = 0
        self._drag_source: str | None = None
        self._drag_started = False
        self._drag_start_x = 0
        self._drag_start_y = 0
        self._drag_threshold_px = 7
        self._drag_click_action: Callable[[], None] | None = None
        self._drag_status_hint: str | None = None
        self._drag_preview: ctk.CTkToplevel | None = None
        self._search_after_id: str | None = None
        self._drop_status_frames: dict[str, ctk.CTkBaseClass] = {}
        self._drop_column_frames: dict[str, ctk.CTkFrame] = {}
        self._drop_column_headers: dict[str, ctk.CTkLabel] = {}
        self._calendar_cells: dict[str, ctk.CTkFrame] = {}
        self._column_cards: dict[str, list[KanbanCard]] = {}
        self._kanban_render_token = 0
        self._sync_poll_after_id: str | None = None
        self._sync_poll_interval_ms = 2500
        self._sync_poll_inflight = False
        self._build_layout()
        self._load_person_theme_settings()
        self.apply_theme(refresh=True)
        self.protocol("WM_DELETE_WINDOW", self.on_close)
        self.refresh_all_views()
        self._schedule_sync_poll(initial=True)

    def _build_layout(self) -> None:
        self.grid_columnconfigure(1, weight=1)
        self.grid_rowconfigure(1, weight=1)
        self.top_bar = ctk.CTkFrame(
            self,
            fg_color=self._c("bg_panel"),
            corner_radius=0,
            border_width=1,
            border_color=self._c("border"),
        )
        self.top_bar.grid(row=0, column=0, columnspan=2, sticky="ew")
        self.top_bar.grid_columnconfigure(1, weight=1)
        self.top_title = ctk.CTkLabel(
            self.top_bar,
            text="Ctrl-Center",
            font=ctk.CTkFont(size=22, weight="bold"),
            text_color=self._c("text_primary"),
        )
        self.top_title.grid(row=0, column=0, padx=16, pady=10, sticky="w")
        self.top_actions = ctk.CTkFrame(self.top_bar, fg_color="transparent")
        self.top_actions.grid(row=0, column=2, padx=12, pady=8, sticky="e")
        self.person_menu = ctk.CTkOptionMenu(
            self.top_actions,
            variable=self.person_var,
            values=self.display_names,
            command=lambda _v: self.on_person_changed(),
        )
        self.person_menu.pack(side="left", padx=(0, 8))
        self.appearance_menu = ctk.CTkOptionMenu(
            self.top_actions,
            variable=self.appearance_var,
            values=list(APPEARANCE_LABEL_TO_KEY.keys()),
            command=self.on_appearance_changed,
        )
        self.appearance_menu.pack(side="left", padx=(0, 8))
        self.theme_menu = ctk.CTkOptionMenu(
            self.top_actions,
            variable=self.theme_scheme_var,
            values=self._available_theme_schemes(self._appearance_mode_key),
            command=self.on_theme_scheme_changed,
        )
        self.theme_menu.pack(side="left", padx=(0, 8))
        self.voice_switch = ctk.CTkSwitch(self.top_actions, text="Голос", variable=self.voice_var, command=self.toggle_voice)
        self.voice_switch.pack(side="left", padx=(0, 8))
        self.bot_switch = ctk.CTkSwitch(self.top_actions, text="Бот", variable=self.bot_var, command=self.toggle_bot)
        self.bot_switch.pack(side="left", padx=(0, 8))
        self.new_task_button = ctk.CTkButton(self.top_actions, text="+ Новая задача", command=lambda: self.open_task_editor(None))
        self.new_task_button.pack(side="left")
        self.sidebar = ctk.CTkFrame(
            self,
            fg_color=self._c("bg_panel"),
            corner_radius=0,
            border_width=1,
            border_color=self._c("border"),
            width=220,
        )
        self.sidebar.grid(row=1, column=0, sticky="nsew")
        self.sidebar.grid_propagate(False)
        self.sidebar.grid_rowconfigure(9, weight=1)
        self.nav_buttons = {
            "dashboard": ctk.CTkButton(self.sidebar, text="🏠 Дашборд", anchor="w", command=lambda: self.show_page("dashboard")),
            "tasks": ctk.CTkButton(self.sidebar, text="🗂 Задачи", anchor="w", command=lambda: self.show_page("tasks")),
            "calendar": ctk.CTkButton(self.sidebar, text="📅 Календарь", anchor="w", command=lambda: self.show_page("calendar")),
            "family": ctk.CTkButton(self.sidebar, text="👨‍👩‍👧‍👦 Семейные дела", anchor="w", command=lambda: self.show_page("family")),
        }
        for i, key in enumerate(["dashboard", "tasks", "calendar", "family"], start=1):
            self.nav_buttons[key].grid(row=i, column=0, padx=14, pady=4, sticky="ew")
        self.log_box = ctk.CTkTextbox(self.sidebar, height=200)
        self.log_box.grid(row=10, column=0, padx=12, pady=12, sticky="ew")
        self.log_box.configure(state="disabled")
        self.content = ctk.CTkFrame(self, fg_color=self._c("bg_app"), corner_radius=0)
        self.content.grid(row=1, column=1, sticky="nsew")
        self.content.grid_rowconfigure(1, weight=1)
        self.content.grid_columnconfigure(0, weight=1)
        self.page_title = ctk.CTkLabel(
            self.content,
            text="",
            font=ctk.CTkFont(size=24, weight="bold"),
            text_color=self._c("text_primary"),
        )
        self.page_title.grid(row=0, column=0, padx=16, pady=(14, 8), sticky="w")
        self.page_wrap = ctk.CTkFrame(self.content, fg_color="transparent")
        self.page_wrap.grid(row=1, column=0, sticky="nsew", padx=12, pady=(0, 12))
        self.page_wrap.grid_rowconfigure(0, weight=1)
        self.page_wrap.grid_columnconfigure(0, weight=1)
        self.dashboard_page = ctk.CTkFrame(self.page_wrap, fg_color="transparent")
        self.tasks_page = ctk.CTkFrame(self.page_wrap, fg_color="transparent")
        self.calendar_page = ctk.CTkFrame(self.page_wrap, fg_color="transparent")
        self.family_page = ctk.CTkFrame(self.page_wrap, fg_color="transparent")
        self._build_dashboard_page()
        self._build_tasks_page()
        self._build_calendar_page()
        self._build_family_page()
        self.show_page("dashboard")

    def get_person(self) -> ft.Person:
        return self.person_by_name[self.person_var.get()]

    def _c(self, token: str) -> str:
        return self._theme_tokens[token]

    def _available_theme_schemes(self, appearance_mode: str) -> list[str]:
        return list(THEME_SCHEMES.get(appearance_mode, {}).keys())

    def _normalize_theme_settings(self, settings: dict) -> tuple[str, str]:
        mode = str(settings.get("appearance_mode") or "").strip().lower()
        if mode not in THEME_SCHEMES:
            mode = "light"
        scheme = str(settings.get("theme_scheme") or "").strip()
        if scheme not in THEME_SCHEMES[mode]:
            scheme = THEME_DEFAULT_BY_MODE[mode]
        return mode, scheme

    def _load_person_theme_settings(self) -> None:
        settings = ft.load_ui_settings(self.get_person())
        mode, scheme = self._normalize_theme_settings(settings)
        self._appearance_mode_key = mode
        self._theme_scheme = scheme
        self._theme_tokens = THEME_SCHEMES[mode][scheme]
        self.appearance_var.set(APPEARANCE_KEY_TO_LABEL[mode])
        self.theme_scheme_var.set(scheme)
        self.theme_menu.configure(values=self._available_theme_schemes(mode))

    def _save_person_theme_settings(self) -> None:
        ft.save_ui_settings(
            self.get_person(),
            {
                "appearance_mode": self._appearance_mode_key,
                "theme_scheme": self._theme_scheme,
            },
        )

    def on_appearance_changed(self, selected_label: str) -> None:
        mode = APPEARANCE_LABEL_TO_KEY.get(selected_label, "light")
        scheme = self.theme_scheme_var.get().strip()
        if scheme not in THEME_SCHEMES.get(mode, {}):
            scheme = THEME_DEFAULT_BY_MODE[mode]
        self._appearance_mode_key = mode
        self._theme_scheme = scheme
        self.theme_scheme_var.set(scheme)
        self.theme_menu.configure(values=self._available_theme_schemes(mode))
        self.apply_theme(refresh=True, persist=True)

    def on_theme_scheme_changed(self, selected_scheme: str) -> None:
        mode = APPEARANCE_LABEL_TO_KEY.get(self.appearance_var.get(), "light")
        if selected_scheme not in THEME_SCHEMES.get(mode, {}):
            selected_scheme = THEME_DEFAULT_BY_MODE[mode]
        self._appearance_mode_key = mode
        self._theme_scheme = selected_scheme
        self.theme_scheme_var.set(selected_scheme)
        self.apply_theme(refresh=True, persist=True)

    def apply_theme(self, refresh: bool = True, persist: bool = False) -> None:
        ctk.set_appearance_mode(self._appearance_mode_key)
        self._theme_tokens = THEME_SCHEMES[self._appearance_mode_key][self._theme_scheme]
        self.configure(fg_color=self._c("bg_app"))
        self.top_bar.configure(fg_color=self._c("bg_panel"), border_color=self._c("border"))
        self.top_title.configure(text_color=self._c("text_primary"))
        self.sidebar.configure(fg_color=self._c("bg_panel"), border_color=self._c("border"))
        self.content.configure(fg_color=self._c("bg_app"))
        self.page_title.configure(text_color=self._c("text_primary"))
        self.new_task_button.configure(fg_color=self._c("accent"), hover_color=self._c("accent_hover"))
        self.voice_switch.configure(text_color=self._c("text_primary"))
        self.bot_switch.configure(text_color=self._c("text_primary"))
        for menu in (self.person_menu, self.appearance_menu, self.theme_menu):
            menu.configure(
                fg_color=self._c("selected_nav_bg"),
                button_color=self._c("accent"),
                button_hover_color=self._c("accent_hover"),
                text_color=self._c("text_primary"),
            )
        self.log_box.configure(fg_color=self._c("bg_card"), text_color=self._c("text_primary"))
        if hasattr(self, "calendar_month_label"):
            self.calendar_month_label.configure(text_color=self._c("text_primary"))
        if hasattr(self, "calendar_grid"):
            self.calendar_grid.configure(fg_color=self._c("bg_panel"), border_color=self._c("border"))
        for frame in self._drop_column_frames.values():
            frame.configure(fg_color=self._c("bg_card"), border_color=self._c("border"))
        for header in self._drop_column_headers.values():
            header.configure(text_color=self._c("text_primary"))
        for sc in self.kanban_columns.values():
            sc.configure(fg_color=self._c("bg_card"))
            if hasattr(sc, "_parent_canvas"):
                sc._parent_canvas.configure(bg=self._c("bg_card"))
        if hasattr(self, "family_list"):
            self.family_list.configure(fg_color=self._c("bg_panel"), border_color=self._c("border"))
            if hasattr(self.family_list, "_parent_canvas"):
                self.family_list._parent_canvas.configure(bg=self._c("bg_panel"))
        self.show_page(self.current_page)
        if refresh:
            self.refresh_all_views()
        if persist:
            self._save_person_theme_settings()

    def on_person_changed(self) -> None:
        self.clear_tasks_date_filter(refresh=False)
        self._load_person_theme_settings()
        self.apply_theme(refresh=False)
        self._invalidate_cache()
        self.refresh_all_views()

    def _invalidate_cache(self) -> None:
        self._cache_person_key = None
        self._cache_todos = []

    def _load_cached_todos(self) -> list[dict]:
        person = self.get_person()
        if self._cache_person_key != person.key:
            self._cache_person_key = person.key
            self._cache_todos = ft.load_todos(person, pull_remote=False)
        return self._cache_todos

    def _schedule_sync_poll(self, *, initial: bool = False) -> None:
        if self._sync_poll_after_id is not None:
            try:
                self.after_cancel(self._sync_poll_after_id)
            except Exception:
                pass
            self._sync_poll_after_id = None
        delay = 300 if initial else self._sync_poll_interval_ms
        self._sync_poll_after_id = self.after(delay, self._run_sync_poll)

    def _run_sync_poll(self) -> None:
        if not self.winfo_exists():
            return
        if self._sync_poll_inflight:
            self._schedule_sync_poll()
            return
        self._sync_poll_inflight = True
        worker = threading.Thread(target=self._sync_poll_worker, daemon=True)
        worker.start()

    def _sync_poll_worker(self) -> None:
        sync_result: dict[str, object] | None = None
        sync_error: Exception | None = None
        try:
            sync_result = ft.pull_backend_snapshot_to_local()
        except Exception as exc:
            sync_error = exc

        def finish() -> None:
            if not self.winfo_exists():
                return
            if sync_error is not None:
                self._append_log(f"Ошибка фоновой синхронизации: {sync_error}")
            elif isinstance(sync_result, dict) and bool(sync_result.get("changed")):
                self._invalidate_cache()
                self.refresh_all_views()
                self._notify_sync_changes(sync_result)
            self._sync_poll_inflight = False
            self._schedule_sync_poll()

        self.after(0, finish)

    def _notify_sync_changes(self, sync_result: dict[str, object]) -> None:
        changed_profiles = sync_result.get("changed_profiles")
        profiles = [str(profile) for profile in changed_profiles] if isinstance(changed_profiles, list) else []
        has_family_updates = bool(sync_result.get("family_changed"))
        details: list[str] = []
        if profiles:
            details.append(f"профили: {', '.join(profiles)}")
        if has_family_updates:
            details.append("семейные дела")
        message = "Получены изменения из backend"
        if details:
            message = f"{message} ({'; '.join(details)})"
        self._append_log(message)
        try:
            from notifier import desktop_notify

            desktop_notify(message, title="Синхронизация")
        except Exception:
            pass

    def _save_todos(self, todos: list[dict]) -> None:
        ft.save_todos(self.get_person(), todos)
        self._invalidate_cache()

    def show_page(self, page: str) -> None:
        self.current_page = page
        for w in (self.dashboard_page, self.tasks_page, self.calendar_page, self.family_page):
            w.grid_forget()
        for key, btn in self.nav_buttons.items():
            btn.configure(
                fg_color=self._c("selected_nav_bg") if key == page else self._c("bg_panel"),
                text_color=self._c("text_primary"),
                hover_color=self._c("accent_hover"),
            )
        if page == "dashboard":
            self.page_title.configure(text="Дашборд")
            self.dashboard_page.grid(row=0, column=0, sticky="nsew")
        elif page == "tasks":
            self.page_title.configure(text="Задачи")
            self.tasks_page.grid(row=0, column=0, sticky="nsew")
        elif page == "calendar":
            self.page_title.configure(text="Календарь")
            self.calendar_page.grid(row=0, column=0, sticky="nsew")
        else:
            self.page_title.configure(text="Семейные дела")
            self.family_page.grid(row=0, column=0, sticky="nsew")

    def refresh_all_views(self) -> None:
        self.refresh_dashboard()
        self.refresh_tasks_kanban()
        self.refresh_calendar()
        self.refresh_family_tasks()

    def _build_dashboard_page(self) -> None:
        self.dashboard_page.grid_columnconfigure(0, weight=1)
        kpi = ctk.CTkFrame(self.dashboard_page, fg_color="transparent")
        kpi.grid(row=0, column=0, sticky="ew")
        for i in range(4):
            kpi.grid_columnconfigure(i, weight=1)
        self.kpi_vals: list[ctk.CTkLabel] = []
        for i, title in enumerate(["Всего задач", "В работе", "Завершено", "Просрочено"]):
            card = ctk.CTkFrame(kpi, fg_color=self._c("bg_panel"), border_width=1, border_color=self._c("border"))
            card.grid(row=0, column=i, sticky="ew", padx=(0 if i == 0 else 8, 0))
            ctk.CTkLabel(card, text=title, text_color=self._c("text_muted")).pack(anchor="w", padx=12, pady=(10, 4))
            val = ctk.CTkLabel(card, text="0", font=ctk.CTkFont(size=28, weight="bold"), text_color=self._c("text_primary"))
            val.pack(anchor="w", padx=12, pady=(0, 10))
            self.kpi_vals.append(val)
        charts = ctk.CTkFrame(self.dashboard_page, fg_color="transparent")
        charts.grid(row=1, column=0, sticky="nsew", pady=(10, 0))
        charts.grid_columnconfigure(0, weight=3)
        charts.grid_columnconfigure(1, weight=2)
        left = ctk.CTkFrame(charts, fg_color=self._c("bg_panel"), border_width=1, border_color=self._c("border"))
        left.grid(row=0, column=0, sticky="nsew", padx=(0, 8))
        ctk.CTkLabel(left, text="Динамика (7 дней)", font=ctk.CTkFont(size=16, weight="bold"), text_color=self._c("text_primary")).pack(anchor="w", padx=12, pady=(10, 4))
        self.line_canvas = ctk.CTkCanvas(left, height=220, bg=self._c("bg_panel"), highlightthickness=0)
        self.line_canvas.pack(fill="both", expand=True, padx=10, pady=(0, 10))
        right = ctk.CTkFrame(charts, fg_color=self._c("bg_panel"), border_width=1, border_color=self._c("border"))
        right.grid(row=0, column=1, sticky="nsew")
        ctk.CTkLabel(right, text="Статусы", font=ctk.CTkFont(size=16, weight="bold"), text_color=self._c("text_primary")).pack(anchor="w", padx=12, pady=(10, 4))
        self.donut_canvas = ctk.CTkCanvas(right, height=220, bg=self._c("bg_panel"), highlightthickness=0)
        self.donut_canvas.pack(fill="both", expand=True, padx=10, pady=(0, 10))

    def refresh_dashboard(self) -> None:
        todos = self._load_cached_todos()
        today = date.today().isoformat()
        total = len(todos)
        active = len([t for t in todos if str(t.get("workflow_status") or "todo") in {"in_progress", "in_review"}])
        done = len([t for t in todos if str(t.get("workflow_status") or "todo") == "done"])
        overdue = len([t for t in todos if str(t.get("due_date") or "") < today and str(t.get("workflow_status") or "todo") != "done"])
        for i, v in enumerate([total, active, done, overdue]):
            self.kpi_vals[i].configure(text=str(v))
        self._draw_line_chart(todos)
        self._draw_donut_chart(todos)

    def _draw_line_chart(self, todos: list[dict]) -> None:
        cv = self.line_canvas
        cv.delete("all")
        cv.configure(bg=self._c("bg_panel"))
        w = max(cv.winfo_width(), 620)
        h = max(cv.winfo_height(), 220)
        days = [date.today() - timedelta(days=6 - i) for i in range(7)]
        totals = [len([t for t in todos if str(t.get("due_date") or "") == d.isoformat()]) for d in days]
        dones = [len([t for t in todos if str(t.get("due_date") or "") == d.isoformat() and str(t.get("workflow_status") or "todo") == "done"]) for d in days]
        max_v = max(totals + [1])
        step = (w - 80) / 6
        for i in range(5):
            y = 20 + i * ((h - 50) / 4)
            cv.create_line(40, y, w - 20, y, fill=self._c("border"))
        def pts(vals):
            out = []
            for i, v in enumerate(vals):
                x = 40 + i * step
                y = (h - 30) - ((h - 60) * (v / max_v))
                out.append((x, y))
            return out
        p1 = pts(totals)
        p2 = pts(dones)
        for i in range(len(p1) - 1):
            cv.create_line(*p1[i], *p1[i + 1], fill=self._c("accent"), width=2)
            cv.create_line(*p2[i], *p2[i + 1], fill=self._c("success"), width=2)

    def _draw_donut_chart(self, todos: list[dict]) -> None:
        cv = self.donut_canvas
        cv.delete("all")
        cv.configure(bg=self._c("bg_panel"))
        w = max(cv.winfo_width(), 340)
        h = max(cv.winfo_height(), 220)
        cx, cy = w / 2, h / 2
        r = min(w, h) * 0.32
        counts = {k: len([t for t in todos if str(t.get("workflow_status") or "todo") == k]) for k in WORKFLOW_ORDER}
        total = sum(counts.values()) or 1
        colors = {
            "todo": self._c("border"),
            "in_progress": self._c("accent"),
            "in_review": self._c("calendar_chip_bg"),
            "done": self._c("success"),
        }
        start = 90
        for key in WORKFLOW_ORDER:
            extent = 360 * counts[key] / total
            cv.create_arc(cx - r, cy - r, cx + r, cy + r, start=start, extent=-extent, style="arc", width=20, outline=colors[key])
            start -= extent
        cv.create_text(cx, cy, text=f"{counts['done']}\nготово", font=("Arial", 12, "bold"), fill=self._c("text_primary"))

    def _build_tasks_page(self) -> None:
        self.tasks_page.grid_rowconfigure(1, weight=1)
        self.tasks_page.grid_columnconfigure(0, weight=1)
        toolbar = ctk.CTkFrame(self.tasks_page, fg_color="transparent")
        toolbar.grid(row=0, column=0, sticky="ew", pady=(0, 8))
        toolbar.grid_columnconfigure(0, weight=1)
        self.search_entry = ctk.CTkEntry(toolbar, textvariable=self.search_var, placeholder_text="Поиск задач")
        self.search_entry.grid(row=0, column=0, sticky="ew", padx=(0, 8))
        self.search_entry.bind("<KeyRelease>", lambda _e: self._debounced_refresh_tasks())
        date_filter = ctk.CTkFrame(toolbar, fg_color="transparent")
        date_filter.grid(row=0, column=1, padx=(0, 8))
        self.tasks_date_entry = ctk.CTkEntry(date_filter, width=122, textvariable=self.tasks_date_filter_var, placeholder_text="Все даты")
        self.tasks_date_entry.pack(side="left")
        self.tasks_date_entry.bind("<KeyRelease>", lambda _e: self._debounced_refresh_tasks())
        ctk.CTkButton(date_filter, text="📅", width=40, command=self.open_tasks_date_picker).pack(side="left", padx=(6, 0))
        ctk.CTkButton(date_filter, text="Сегодня", width=74, command=self.set_tasks_date_today).pack(side="left", padx=(6, 0))
        ctk.CTkButton(
            date_filter,
            text="Сброс",
            width=64,
            fg_color=self._c("selected_nav_bg"),
            text_color=self._c("text_primary"),
            hover_color=self._c("accent_hover"),
            command=self.clear_tasks_date_filter,
        ).pack(side="left", padx=(6, 0))
        ctk.CTkButton(toolbar, text="Выбрать", command=self.toggle_selection_mode).grid(row=0, column=2, padx=(0, 8))
        ctk.CTkButton(
            toolbar,
            text="Удалить выбранные",
            fg_color=self._c("danger"),
            hover_color=self._c("danger_hover"),
            command=self.delete_selected_tasks,
        ).grid(row=0, column=3, padx=(0, 8))
        ctk.CTkButton(
            toolbar,
            text="Новая задача",
            fg_color=self._c("accent"),
            hover_color=self._c("accent_hover"),
            command=lambda: self.open_task_editor(None),
        ).grid(row=0, column=4)

        self.kanban_wrap = ctk.CTkFrame(self.tasks_page, fg_color="transparent")
        self.kanban_wrap.grid(row=1, column=0, sticky="nsew")
        self.kanban_wrap.grid_rowconfigure(0, weight=1)
        for i in range(4):
            self.kanban_wrap.grid_columnconfigure(i, weight=1)

        self.kanban_columns: dict[str, ctk.CTkScrollableFrame] = {}
        for i, status in enumerate(WORKFLOW_ORDER):
            col = ctk.CTkFrame(self.kanban_wrap, fg_color=self._c("bg_card"), border_width=1, border_color=self._c("border"))
            col.grid(row=0, column=i, sticky="nsew", padx=(0 if i == 0 else 8, 0))
            col.grid_rowconfigure(1, weight=1)
            col.grid_columnconfigure(0, weight=1)
            setattr(col, "_drop_status", status)
            self._drop_column_frames[status] = col

            header_label = ctk.CTkLabel(
                col,
                text=WORKFLOW_KEY_TO_RU[status],
                font=ctk.CTkFont(size=15, weight="bold"),
                anchor="w",
                text_color=self._c("text_primary"),
            )
            header_label.grid(row=0, column=0, sticky="ew", padx=10, pady=(10, 6))
            self._drop_column_headers[status] = header_label
            sc = ctk.CTkScrollableFrame(col, fg_color="transparent")
            sc.grid(row=1, column=0, sticky="nsew", padx=8)
            sc.grid_columnconfigure(0, weight=1)
            setattr(sc, "_drop_status", status)
            self._drop_status_frames[status] = sc
            self.kanban_columns[status] = sc
            self._column_cards[status] = []

            ctk.CTkButton(
                col,
                text="+ Добавить задачу",
                fg_color=self._c("selected_nav_bg"),
                text_color=self._c("text_primary"),
                hover_color=self._c("accent_hover"),
                command=lambda st=status: self.open_task_editor({"workflow_status": st}),
            ).grid(row=2, column=0, sticky="ew", padx=8, pady=(6, 8))

    def _selected_tasks_due_date(self) -> str | None:
        value = self.tasks_date_filter_var.get().strip()
        if not value:
            return None
        return ft.parse_due_date_input(value)

    def open_tasks_date_picker(self) -> None:
        selected = self._selected_tasks_due_date()
        initial = datetime.fromisoformat(selected).date() if selected else date.today()
        DatePickerPopup(self, initial, self._on_tasks_date_selected)

    def _on_tasks_date_selected(self, selected: date) -> None:
        self.tasks_date_filter_var.set(selected.isoformat())
        self.refresh_tasks_kanban()

    def set_tasks_date_today(self) -> None:
        self.tasks_date_filter_var.set(date.today().isoformat())
        self.refresh_tasks_kanban()

    def clear_tasks_date_filter(self, refresh: bool = True) -> None:
        self.tasks_date_filter_var.set("")
        if refresh:
            self.refresh_tasks_kanban()

    def _debounced_refresh_tasks(self) -> None:
        if self._search_after_id is not None:
            self.after_cancel(self._search_after_id)
        self._search_after_id = self.after(250, self.refresh_tasks_kanban)

    def refresh_tasks_kanban(self) -> None:
        started = datetime.now()
        self._kanban_render_token += 1
        token = self._kanban_render_token
        todos = self._load_cached_todos()
        needle = self.search_var.get().strip().lower()
        selected_due = self._selected_tasks_due_date()
        for col in self.kanban_columns.values():
            for child in col.winfo_children():
                child.destroy()
        self._column_cards = {k: [] for k in WORKFLOW_ORDER}

        grouped = {k: [] for k in WORKFLOW_ORDER}
        for todo in todos:
            if bool(todo.get("is_family")):
                continue
            status = str(todo.get("workflow_status") or "todo")
            if status not in grouped:
                status = "todo"
            if needle:
                hay = " ".join([str(todo.get("title") or "").lower(), str(todo.get("details") or "").lower(), str(todo.get("due_date") or "").lower()])
                if needle not in hay:
                    continue
            if selected_due is not None and str(todo.get("due_date") or "") != selected_due:
                continue
            grouped[status].append(todo)

        queues: dict[str, list[dict]] = {}
        for status in WORKFLOW_ORDER:
            queues[status] = sorted(
                grouped[status],
                key=lambda t: (int(t.get("sort_order") or 0), str(t.get("due_date") or ""), str(t.get("time") or ""), int(t.get("id") or 0)),
            )[:350]

        def render_chunk() -> None:
            if token != self._kanban_render_token:
                return
            has_more = False
            for status in WORKFLOW_ORDER:
                batch = queues[status][:24]
                if not batch:
                    continue
                has_more = True
                del queues[status][:24]
                for todo in batch:
                    card = KanbanCard(self.kanban_columns[status], self, todo)
                    card.grid(sticky="ew", padx=2, pady=4)
                    self._column_cards[status].append(card)
            if has_more:
                self.after(1, render_chunk)
                return
            elapsed = int((datetime.now() - started).total_seconds() * 1000)
            self._append_log(f"telemetry: render_kanban={elapsed}ms")
            log_event("ui_metric", metric="render_kanban", ms=elapsed, person=self.get_person().key)

        render_chunk()

    def quick_mark_done(self, todo: dict) -> None:
        todo_id = int(todo.get("id") or 0)
        if todo_id <= 0:
            return

        def mutate(todos: list[dict], person: ft.Person) -> tuple[bool, str | None, dict]:
            for item in todos:
                if int(item.get("id") or 0) != todo_id:
                    continue
                before = copy.deepcopy(item)
                transition_task(item, "done")
                ft.push_history(person, "update_item", {"id": todo_id, "before": before})
                return True, "todo_done", {
                    "id": todo_id,
                    "title": str(item.get("title") or item.get("text") or ""),
                    "day": str(item.get("day") or ""),
                    "time": str(item.get("time") or ""),
                }
            return False, None, {}

        self._run_todo_operation(mutate)

    def delete_task(self, todo: dict) -> None:
        todo_id = int(todo.get("id") or 0)
        if todo_id <= 0:
            return
        if not messagebox.askyesno("Удаление", "Удалить выбранную задачу?"):
            return

        def mutate(todos: list[dict], person: ft.Person) -> tuple[bool, str | None, dict]:
            for idx, item in enumerate(todos):
                if int(item.get("id") or 0) != todo_id:
                    continue
                removed = todos.pop(idx)
                ft.push_history(person, "restore_items", {"items": [removed]})
                return True, "todo_delete", {
                    "id": todo_id,
                    "title": str(removed.get("title") or removed.get("text") or ""),
                    "day": str(removed.get("day") or ""),
                    "time": str(removed.get("time") or ""),
                }
            return False, None, {}

        self._run_todo_operation(mutate)

    def toggle_selection_mode(self) -> None:
        self.selection_mode = not self.selection_mode
        if not self.selection_mode:
            self.selected_ids.clear()
        self.refresh_tasks_kanban()

    def toggle_task_selection(self, todo_id: int) -> None:
        if todo_id in self.selected_ids:
            self.selected_ids.remove(todo_id)
        else:
            self.selected_ids.add(todo_id)

    def delete_selected_tasks(self) -> None:
        if not self.selected_ids:
            messagebox.showinfo("Удаление", "Нет выбранных задач")
            return
        if not messagebox.askyesno("Удаление", f"Удалить выбранные задачи: {len(self.selected_ids)}?"):
            return
        person = self.get_person()
        todos = self._load_cached_todos()
        removed = [t for t in todos if int(t.get("id") or 0) in self.selected_ids]
        kept = [t for t in todos if int(t.get("id") or 0) not in self.selected_ids]
        ft.save_todos(person, kept)
        ft.push_history(person, "restore_items", {"items": removed})
        log_event("todo_delete_bulk", person=person.key, actor="desktop", count=len(removed))
        self.selected_ids.clear()
        self.selection_mode = False
        self._invalidate_cache()
        self.refresh_all_views()

    def _run_todo_operation(
        self,
        mutate: Callable[[list[dict], ft.Person], tuple[bool, str | None, dict]],
    ) -> bool:
        person = self.get_person()
        todos = self._load_cached_todos()
        changed, event_name, event_fields = mutate(todos, person)
        if not changed:
            return False
        self._save_todos(todos)
        if event_name:
            log_event(event_name, person=person.key, actor="desktop", **event_fields)
        self.refresh_all_views()
        return True

    def open_task_editor(self, todo: dict | None) -> None:
        def on_save(payload: dict) -> None:
            started_save = datetime.now()
            now_iso = datetime.now().isoformat(timespec="seconds")
            due = str(payload.get("due_date") or "")
            time_value = str(payload.get("time") or "")
            person = self.get_person()
            conflicts = ft.family_conflicts_for_person(person.key, due, time_value)
            is_existing_family = bool(todo and todo.get("is_family"))
            if conflicts and not is_existing_family:
                conflict = conflicts[0]
                messagebox.showwarning(
                    "Конфликт",
                    f"Личная задача пересекается с семейным делом: {conflict.get('title') or conflict.get('text')} ({conflict.get('start_at')}).",
                )
                return

            def mutate(todos: list[dict], current_person: ft.Person) -> tuple[bool, str | None, dict]:
                if todo and todo.get("id"):
                    target_id = int(todo.get("id") or 0)
                    for item in todos:
                        if int(item.get("id") or 0) != target_id:
                            continue
                        before = copy.deepcopy(item)
                        item.update(payload)
                        transition_task(item, str(item.get("workflow_status") or "todo"), now_iso=now_iso)
                        ft.push_history(current_person, "update_item", {"id": target_id, "before": before})
                        return True, "todo_update", {
                            "id": target_id,
                            "title": str(item.get("title") or item.get("text") or ""),
                            "day": str(item.get("day") or ""),
                            "time": str(item.get("time") or ""),
                        }
                    return False, None, {}

                next_id = max([int(t.get("id") or 0) for t in todos], default=0) + 1
                item = {
                    "id": next_id,
                    **payload,
                    "sort_order": next_id,
                    "series_id": None,
                    "recurrence_rule": None,
                    "generated_from_rule": False,
                    "is_family": False,
                    "participants": [],
                    "start_at": None,
                    "duration_minutes": None,
                    "created_at": now_iso,
                }
                transition_task(item, str(item.get("workflow_status") or "todo"), now_iso=now_iso)
                todos.append(item)
                ft.push_history(current_person, "add", {"created_ids": [next_id]})
                return True, "todo_add", {
                    "id": next_id,
                    "title": str(item.get("title") or item.get("text") or ""),
                    "day": str(item.get("day") or ""),
                    "time": str(item.get("time") or ""),
                }

            self._run_todo_operation(mutate)
            elapsed = int((datetime.now() - started_save).total_seconds() * 1000)
            self._append_log(f"telemetry: save_popup={elapsed}ms")
            log_event("ui_metric", metric="save_popup", ms=elapsed, person=person.key)

        def on_delete() -> None:
            if not todo or not todo.get("id"):
                return
            target_id = int(todo.get("id") or 0)
            def mutate(todos: list[dict], person: ft.Person) -> tuple[bool, str | None, dict]:
                for idx, item in enumerate(todos):
                    if int(item.get("id") or 0) != target_id:
                        continue
                    removed = todos.pop(idx)
                    ft.push_history(person, "restore_items", {"items": [removed]})
                    return True, "todo_delete", {
                        "id": target_id,
                        "title": str(removed.get("title") or removed.get("text") or ""),
                        "day": str(removed.get("day") or ""),
                        "time": str(removed.get("time") or ""),
                    }
                return False, None, {}
            self._run_todo_operation(mutate)

        started = datetime.now()
        TaskEditorPopup(self, todo, on_save, on_delete, theme_tokens=self._theme_tokens)
        elapsed = int((datetime.now() - started).total_seconds() * 1000)
        self._append_log(f"telemetry: open_popup={elapsed}ms")

    def _detect_drop_target(self, x_root: int, y_root: int) -> tuple[str | None, int | None]:
        widget = self.winfo_containing(x_root, y_root)
        target_status = None
        while widget is not None:
            status = getattr(widget, "_drop_status", None)
            if status:
                target_status = status
                break
            widget = widget.master
        if not target_status:
            return None, None

        cards = self._column_cards.get(target_status, [])
        column = self.kanban_columns.get(target_status)
        if column is None:
            return target_status, None
        local_y = y_root - column.winfo_rooty()
        for idx, card in enumerate(cards):
            middle = card.winfo_y() + (card.winfo_height() / 2)
            if local_y < middle:
                return target_status, idx
        return target_status, len(cards)

    def _detect_calendar_target(self, x_root: int, y_root: int) -> str | None:
        widget = self.winfo_containing(x_root, y_root)
        while widget is not None:
            due = getattr(widget, "_calendar_due", None)
            if due:
                return str(due)
            widget = widget.master
        return None

    def _set_drop_highlight(self, status: str | None) -> None:
        for key, frame in self._drop_column_frames.items():
            frame.configure(border_color=self._c("accent") if key == status else self._c("border"))

    def _set_calendar_drop_highlight(self, due_date: str | None) -> None:
        for key, cell in self._calendar_cells.items():
            cell.configure(border_color=self._c("accent") if key == due_date else self._c("border"))

    def start_drag(self, todo: dict, event, source: str = "kanban", on_click: Callable[[], None] | None = None) -> None:
        self._drag_id = int(todo.get("id") or 0)
        self._drag_source = source
        self._drag_started = False
        self._drag_start_x = int(event.x_root)
        self._drag_start_y = int(event.y_root)
        self._drag_click_action = on_click
        self._drag_status_hint = None

    def _begin_drag_session(self, title: str, event) -> None:
        if self._drag_started:
            return
        self._drag_started = True
        if self._drag_preview is None:
            self._drag_preview = ctk.CTkToplevel(self)
            self._drag_preview.overrideredirect(True)
            self._drag_preview.attributes("-topmost", True)
            self._drag_preview.configure(fg_color=self._c("accent"))
            ctk.CTkLabel(self._drag_preview, text=title, text_color=self._c("text_primary")).pack(padx=10, pady=6)
        self._drag_preview.geometry(f"+{event.x_root + 14}+{event.y_root + 14}")

    def _cleanup_drag_ui(self) -> None:
        if self._drag_preview is not None:
            self._drag_preview.destroy()
            self._drag_preview = None
        self._set_drop_highlight(None)
        self._set_calendar_drop_highlight(None)

    def on_drag_motion(self, _todo: dict, event) -> None:
        if self._drag_id <= 0:
            return
        if not self._drag_started:
            dx = abs(int(event.x_root) - self._drag_start_x)
            dy = abs(int(event.y_root) - self._drag_start_y)
            if max(dx, dy) < self._drag_threshold_px:
                return
            self._begin_drag_session(str(_todo.get("title") or _todo.get("text") or "Задача"), event)
        if self._drag_preview is not None:
            self._drag_preview.geometry(f"+{event.x_root + 14}+{event.y_root + 14}")
        status, _idx = self._detect_drop_target(event.x_root, event.y_root)
        calendar_due = self._detect_calendar_target(event.x_root, event.y_root)
        self._drag_status_hint = status
        self._set_drop_highlight(status)
        self._set_calendar_drop_highlight(calendar_due)

    def end_drag(self, todo: dict, event) -> None:
        drag_id = self._drag_id
        drag_started = self._drag_started
        drag_source = self._drag_source
        click_action = self._drag_click_action
        self._drag_id = 0
        self._drag_source = None
        self._drag_started = False
        self._drag_click_action = None
        self._cleanup_drag_ui()
        status, target_index = self._detect_drop_target(event.x_root, event.y_root)
        calendar_due = self._detect_calendar_target(event.x_root, event.y_root)
        if drag_id <= 0:
            return
        if not drag_started:
            if drag_source == "calendar" and click_action is not None:
                click_action()
            return

        started = datetime.now()

        def mutate(todos: list[dict], _person: ft.Person) -> tuple[bool, str | None, dict]:
            moved = False
            event_fields: dict[str, str | int] = {"id": drag_id}
            if status:
                moved = move_task(todos, drag_id, status, target_index=target_index)
                if moved:
                    event_fields["target_status"] = status
                    if target_index is not None:
                        event_fields["target_index"] = int(target_index)
            elif calendar_due:
                for item in todos:
                    if int(item.get("id") or 0) != drag_id:
                        continue
                    source_day = str(item.get("day") or "")
                    item["due_date"] = calendar_due
                    item["day"] = ft.weekday_ru(datetime.fromisoformat(calendar_due).date())
                    item["updated_at"] = datetime.now().isoformat(timespec="seconds")
                    moved = True
                    event_fields["source_day"] = source_day
                    event_fields["target_day"] = str(item.get("day") or "")
                    break
            if not moved:
                return False, None, {}
            return True, "todo_move", event_fields

        if not self._run_todo_operation(mutate):
            return
        elapsed = int((datetime.now() - started).total_seconds() * 1000)
        self._append_log(f"telemetry: drop_latency={elapsed}ms")
        log_event("ui_metric", metric="drop_latency", ms=elapsed, person=self.get_person().key)

    def _build_calendar_page(self) -> None:
        self.calendar_page.grid_rowconfigure(1, weight=1)
        self.calendar_page.grid_columnconfigure(0, weight=1)
        head = ctk.CTkFrame(self.calendar_page, fg_color="transparent")
        head.grid(row=0, column=0, sticky="ew", pady=(0, 8))
        self.calendar_month_label = ctk.CTkLabel(head, text="", font=ctk.CTkFont(size=20, weight="bold"), text_color=self._c("text_primary"))
        self.calendar_month_label.pack(side="left")
        ctk.CTkButton(head, text="<", width=36, command=lambda: self.shift_calendar_month(-1)).pack(side="left", padx=(8, 4))
        ctk.CTkButton(head, text=">", width=36, command=lambda: self.shift_calendar_month(1)).pack(side="left")
        ctk.CTkButton(head, text="Сегодня", fg_color=self._c("accent"), hover_color=self._c("accent_hover"), command=self.go_calendar_today).pack(side="left", padx=(8, 0))
        self.calendar_grid = ctk.CTkFrame(
            self.calendar_page,
            fg_color=self._c("bg_panel"),
            border_width=1,
            border_color=self._c("border"),
        )
        self.calendar_grid.grid(row=1, column=0, sticky="nsew")
        for r in range(7):
            self.calendar_grid.grid_rowconfigure(r, weight=1)
        for c in range(7):
            self.calendar_grid.grid_columnconfigure(c, weight=1)

    def go_calendar_today(self) -> None:
        self.current_month_anchor = date.today().replace(day=1)
        self.refresh_calendar()

    def shift_calendar_month(self, delta: int) -> None:
        year = self.current_month_anchor.year
        month = self.current_month_anchor.month + delta
        while month < 1:
            month += 12
            year -= 1
        while month > 12:
            month -= 12
            year += 1
        self.current_month_anchor = date(year, month, 1)
        self.refresh_calendar()

    def refresh_calendar(self) -> None:
        started = datetime.now()
        self._calendar_cells = {}
        for child in self.calendar_grid.winfo_children():
            child.destroy()
        y = self.current_month_anchor.year
        m = self.current_month_anchor.month
        self.calendar_month_label.configure(text=f"{MONTH_NAMES_RU[m - 1]} {y}")
        for c, wd in enumerate(WEEKDAY_SHORT_RU):
            ctk.CTkLabel(self.calendar_grid, text=wd, text_color=self._c("text_muted")).grid(row=0, column=c, sticky="n", pady=4)

        todos = [t for t in self._load_cached_todos() if not bool(t.get("is_family"))]
        by_date: dict[str, list[dict]] = {}
        for t in todos:
            due_date = str(t.get("due_date") or "")
            if due_date:
                by_date.setdefault(due_date, []).append(t)

        matrix = calendar.monthcalendar(y, m)
        while len(matrix) < 6:
            matrix.append([0] * 7)

        total_h = max(self.calendar_grid.winfo_height(), 720)
        row_count = max(1, len(matrix))
        cell_h = max(112, int((total_h - 36) / row_count))
        visible_cards = max(1, int((cell_h - 34) / 24))

        for r, week in enumerate(matrix, start=1):
            for c, d in enumerate(week):
                cell = ctk.CTkFrame(
                    self.calendar_grid,
                    fg_color=self._c("bg_panel"),
                    border_width=1,
                    border_color=self._c("border"),
                    height=cell_h,
                )
                cell.grid(row=r, column=c, sticky="nsew", padx=2, pady=2)
                cell.grid_propagate(False)
                if d <= 0:
                    continue
                dt = date(y, m, d)
                due = dt.isoformat()
                setattr(cell, "_calendar_due", due)
                self._calendar_cells[due] = cell
                ctk.CTkButton(
                    cell,
                    text=str(d),
                    width=28,
                    height=24,
                    fg_color="transparent",
                    text_color=self._c("text_primary"),
                    hover_color=self._c("selected_nav_bg"),
                    command=lambda dd=dt: self.open_day_popup(dd),
                ).pack(anchor="ne", padx=2, pady=2)
                tasks = sorted(by_date.get(due, []), key=lambda x: (str(x.get("time") or ""), int(x.get("id") or 0)))
                for t in tasks[:visible_cards]:
                    chip = ctk.CTkButton(
                        cell,
                        text=str(t.get("title") or t.get("text") or "")[:24],
                        height=20,
                        fg_color=self._c("calendar_chip_bg"),
                        text_color=self._c("calendar_chip_text"),
                        hover_color=self._c("accent_hover"),
                    )
                    chip.pack(fill="x", padx=4, pady=1)
                    chip.bind(
                        "<ButtonPress-1>",
                        lambda e, todo=t: self.start_drag(
                            todo,
                            e,
                            source="calendar",
                            on_click=lambda selected=todo: self.open_task_editor(selected),
                        ),
                    )
                    chip.bind("<B1-Motion>", lambda e, todo=t: self.on_drag_motion(todo, e))
                    chip.bind("<ButtonRelease-1>", lambda e, todo=t: self.end_drag(todo, e))
                if len(tasks) > visible_cards:
                    hidden = len(tasks) - visible_cards
                    ctk.CTkButton(
                        cell,
                        text=f"+{hidden} еще",
                        height=20,
                        fg_color="transparent",
                        text_color=self._c("text_muted"),
                        hover_color=self._c("selected_nav_bg"),
                        anchor="w",
                        command=lambda dd=dt: self.open_day_popup(dd),
                    ).pack(fill="x", padx=4, pady=(1, 2))

        elapsed = int((datetime.now() - started).total_seconds() * 1000)
        self._append_log(f"telemetry: calendar_render={elapsed}ms")
        log_event("ui_metric", metric="calendar_month_render", ms=elapsed, person=self.get_person().key)

    def open_day_popup(self, day_date: date) -> None:
        win = ctk.CTkToplevel(self)
        win.title(f"Задачи на {day_date.strftime('%d.%m.%Y')}")
        win.geometry("520x520")
        win.transient(self)
        win.grab_set()
        wrap = ctk.CTkFrame(win, fg_color=self._c("bg_panel"))
        wrap.pack(fill="both", expand=True, padx=12, pady=12)
        ctk.CTkLabel(
            wrap,
            text=f"Задачи на {day_date.strftime('%d.%m.%Y')}",
            font=ctk.CTkFont(size=18, weight="bold"),
            text_color=self._c("text_primary"),
        ).pack(anchor="w", pady=(0, 8))
        sc = ctk.CTkScrollableFrame(wrap)
        sc.pack(fill="both", expand=True)
        due = day_date.isoformat()
        items = [
            t
            for t in self._load_cached_todos()
            if not bool(t.get("is_family")) and str(t.get("due_date") or "") == due
        ]
        if not items:
            ctk.CTkLabel(sc, text="На этот день задач нет", text_color=self._c("text_muted")).pack(anchor="w", padx=8, pady=8)
        for t in items:
            row = ctk.CTkFrame(sc, fg_color=self._c("bg_card"))
            row.pack(fill="x", padx=6, pady=4)
            ctk.CTkLabel(row, text=str(t.get("title") or t.get("text") or ""), anchor="w", font=ctk.CTkFont(size=14, weight="bold")).pack(anchor="w", padx=8, pady=(8, 2))
            ctk.CTkLabel(
                row,
                text=f"{t.get('time') or 'без времени'} · {WORKFLOW_KEY_TO_RU.get(str(t.get('workflow_status') or 'todo'),'К выполнению')}",
                text_color=self._c("text_muted"),
            ).pack(anchor="w", padx=8, pady=(0, 8))
            ctk.CTkButton(row, text="Открыть", width=80, command=lambda todo=t: self.open_task_editor(todo)).pack(anchor="e", padx=8, pady=(0, 8))
        ctk.CTkButton(
            wrap,
            text="+ Добавить задачу",
            fg_color=self._c("accent"),
            hover_color=self._c("accent_hover"),
            command=lambda: self.open_task_editor({"due_date": due}),
        ).pack(anchor="e", pady=(8, 0))

    def _build_family_page(self) -> None:
        self.family_page.grid_rowconfigure(1, weight=1)
        self.family_page.grid_columnconfigure(0, weight=1)
        top = ctk.CTkFrame(self.family_page, fg_color="transparent")
        top.grid(row=0, column=0, sticky="ew", pady=(0, 8))
        ctk.CTkButton(
            top,
            text="+ Семейное дело",
            fg_color=self._c("accent"),
            hover_color=self._c("accent_hover"),
            command=lambda: self.open_family_task_editor(None),
        ).pack(side="left")
        ctk.CTkSegmentedButton(
            top,
            values=["upcoming", "past", "all"],
            variable=self.family_filter_var,
            command=lambda _v: self.refresh_family_tasks(),
        ).pack(side="left", padx=(10, 0))
        self.family_list = ctk.CTkScrollableFrame(
            self.family_page,
            fg_color=self._c("bg_panel"),
            border_width=1,
            border_color=self._c("border"),
        )
        self.family_list.grid(row=1, column=0, sticky="nsew")
        self.family_list.grid_columnconfigure(0, weight=1)

    def refresh_family_tasks(self) -> None:
        for child in self.family_list.winfo_children():
            child.destroy()
        items = ft.load_family_tasks(pull_remote=False)
        now = datetime.now()
        mode = self.family_filter_var.get()
        filtered: list[dict] = []
        for item in items:
            start_at = datetime.fromisoformat(str(item.get("start_at") or now.isoformat()))
            if mode == "upcoming" and start_at < now:
                continue
            if mode == "past" and start_at >= now:
                continue
            filtered.append(item)
        filtered.sort(key=lambda x: str(x.get("start_at") or ""))

        if not filtered:
            ctk.CTkLabel(self.family_list, text="Семейных дел пока нет.", text_color=self._c("text_muted")).grid(row=0, column=0, sticky="w", padx=10, pady=10)
            return
        for idx, item in enumerate(filtered):
            row = ctk.CTkFrame(self.family_list, fg_color=self._c("bg_card"), border_width=1, border_color=self._c("border"))
            row.grid(row=idx, column=0, sticky="ew", padx=6, pady=4)
            row.grid_columnconfigure(0, weight=1)
            title = str(item.get("title") or item.get("text") or "Семейное дело")
            ctk.CTkLabel(row, text=title, font=ctk.CTkFont(size=14, weight="bold"), anchor="w").grid(row=0, column=0, sticky="w", padx=8, pady=(8, 2))
            participants = [ft.person_by_key(k).display_name for k in item.get("participants", []) if ft.person_by_key(k)]
            info = (
                f"{item.get('start_at')} · {item.get('duration_minutes')} мин · "
                f"участники: {', '.join(participants) if participants else '-'}"
            )
            ctk.CTkLabel(row, text=info, text_color=self._c("text_muted"), anchor="w").grid(row=1, column=0, sticky="w", padx=8, pady=(0, 8))
            ctk.CTkButton(row, text="Открыть", width=84, command=lambda t=item: self.open_family_task_editor(t)).grid(row=0, column=1, rowspan=2, padx=8, pady=8)

    def open_family_task_editor(self, task: dict | None) -> None:
        started = datetime.now()

        def on_save(payload: dict) -> None:
            if task and task.get("id"):
                ok, error, _updated = ft.update_family_task(int(task.get("id") or 0), payload)
            else:
                ok, error, _created = ft.create_family_task(
                    title=str(payload.get("title") or ""),
                    details=str(payload.get("details") or ""),
                    start_at=str(payload.get("start_at") or ""),
                    duration_minutes=int(payload.get("duration_minutes") or 0),
                    participants=list(payload.get("participants") or []),
                )
            if not ok:
                messagebox.showwarning("Семейное дело", error)
                return
            self.refresh_family_tasks()

        def on_delete() -> None:
            if not task:
                return
            ft.delete_family_task(int(task.get("id") or 0))
            self.refresh_family_tasks()

        FamilyTaskPopup(self, task, on_save, on_delete if task else None, theme_tokens=self._theme_tokens)
        elapsed = int((datetime.now() - started).total_seconds() * 1000)
        self._append_log(f"telemetry: open_family_popup={elapsed}ms")
        log_event("ui_metric", metric="open_family_popup", ms=elapsed, person=self.get_person().key)

    def _append_log(self, message: str) -> None:
        stamp = datetime.now().strftime("%H:%M:%S")
        self.log_box.configure(state="normal")
        self.log_box.insert("end", f"[{stamp}] {message}\n")
        self.log_box.see("end")
        self.log_box.configure(state="disabled")

    def toggle_voice(self) -> None:
        if self.voice_var.get():
            if self.voice_worker and self.voice_worker.is_alive():
                return
            self.voice_worker = VoiceWorker(on_log=self._append_log, on_state=lambda enabled: self.voice_var.set(enabled))
            self.voice_worker.start()
            return
        if self.voice_worker:
            self.voice_worker.stop()
        self.voice_var.set(False)

    def toggle_bot(self) -> None:
        if self.bot_var.get():
            if not os.getenv("TELEGRAM_BOT_TOKEN", "").strip():
                self._append_log("Нельзя включить бота: TELEGRAM_BOT_TOKEN не задан")
                self.bot_var.set(False)
                return
            self.bot_var.set(self.bot_host.start())
            return
        self.bot_host.stop()
        self.bot_var.set(False)

    def on_close(self) -> None:
        if self._sync_poll_after_id is not None:
            try:
                self.after_cancel(self._sync_poll_after_id)
            except Exception:
                pass
            self._sync_poll_after_id = None
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



