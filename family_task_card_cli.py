from __future__ import annotations

import argparse
import base64
import json
import mimetypes
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Callable


PostJson = Callable[[str, dict[str, Any]], dict[str, Any]]
ENV_KEYS = {
    "FAMILY_TASK_CARD_API_URL",
    "FAMILY_TASK_CARD_API_KEY",
    "FAMILY_TASK_CARD_TICKET",
    "FAMILY_TASK_CARD_TASK_ID",
    "FAMILY_TASK_CARD_WORKSPACE_ID",
    "FAMILY_TASK_CARD_SESSION_ID",
    "FAMILY_TASK_CARD_ACTOR_PROFILE",
    "FAMILY_TASK_CARD_ACTOR_PHONE",
    "FAMILY_TASK_CARD_TASK_TYPE",
    "FAMILY_TASK_CARD_MODE",
    "FAMILY_TASK_CARD_WORKSPACE_PATH",
    "FAMILY_TASK_CARD_CONTEXT_FILE",
}
CONTEXT_KEY_ALIASES = {
    "api_url": "FAMILY_TASK_CARD_API_URL",
    "api_key": "FAMILY_TASK_CARD_API_KEY",
    "policy_ticket": "FAMILY_TASK_CARD_TICKET",
    "task_id": "FAMILY_TASK_CARD_TASK_ID",
    "workspace_id": "FAMILY_TASK_CARD_WORKSPACE_ID",
    "agent_session_id": "FAMILY_TASK_CARD_SESSION_ID",
    "actor_profile": "FAMILY_TASK_CARD_ACTOR_PROFILE",
    "actor_phone": "FAMILY_TASK_CARD_ACTOR_PHONE",
    "task_type": "FAMILY_TASK_CARD_TASK_TYPE",
    "mode": "FAMILY_TASK_CARD_MODE",
    "workspace_path": "FAMILY_TASK_CARD_WORKSPACE_PATH",
    "context_file": "FAMILY_TASK_CARD_CONTEXT_FILE",
}


class TaskCardHttpError(RuntimeError):
    def __init__(self, status_code: int, payload: dict[str, Any] | None = None):
        self.status_code = int(status_code)
        self.payload = payload or {}
        message = str(self.payload.get("error") or f"HTTP {self.status_code}")
        super().__init__(f"HTTP {self.status_code}: {message}")


def run(
    argv: list[str] | None = None,
    *,
    env: dict[str, str] | None = None,
    post_json: PostJson | None = None,
) -> int:
    env_map = _effective_env(env if env is not None else os.environ)
    args = _parser().parse_args(argv)
    payload = _base_payload(env_map)

    try:
        endpoint = _apply_args_to_payload(args, payload, env_map)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    poster = post_json or (lambda url, request_payload: _post_json(url, request_payload, env_map))
    try:
        response = poster(_url(env_map, endpoint), payload)
    except TaskCardHttpError as exc:
        if exc.status_code != 403 or not _refresh_policy_ticket(env_map, poster):
            print(f"Ошибка операции карточки: {exc}", file=sys.stderr)
            return 1
        payload["policy_ticket"] = env_map.get("FAMILY_TASK_CARD_TICKET", "")
        try:
            response = poster(_url(env_map, endpoint), payload)
        except Exception as retry_exc:
            print(f"Ошибка операции карточки после обновления доступа: {retry_exc}", file=sys.stderr)
            return 1
    except Exception as exc:
        print(f"Ошибка операции карточки: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(response, ensure_ascii=False, indent=2))
    return 0 if response.get("ok") is True else 1


def _apply_args_to_payload(
    args: argparse.Namespace,
    payload: dict[str, Any],
    env: dict[str, str],
) -> str:
    if args.command in {"read", "refresh"}:
        return args.command
    if args.command == "comment" and args.comment_action == "add":
        payload["text"] = args.text
        return "comment"
    if args.command == "question" and args.question_action == "ask":
        payload["text"] = args.text
        payload["blocking"] = bool(args.blocking)
        return "question"
    if args.command == "checklist" and args.checklist_action == "create":
        payload["title"] = args.title
        payload["items"] = list(args.item or [])
        return "checklist"
    if args.command == "checklist" and args.checklist_action == "item-add":
        payload["action"] = "add"
        payload["checklist_id"] = args.checklist_id
        payload["text"] = args.text
        return "checklist-item"
    if args.command == "checklist" and args.checklist_action == "item-done":
        payload["action"] = "done"
        payload["checklist_id"] = args.checklist_id
        payload["item_id"] = args.item_id
        payload["done"] = not bool(args.no_done)
        return "checklist-item"
    if args.command == "attachment" and args.attachment_action == "add-from-workspace":
        payload.update(_attachment_payload(args.path, args.caption, env))
        return "attachment"
    if args.command == "status" and args.status_action == "set":
        payload["status"] = args.status
        payload["reason"] = args.reason
        return "status"
    if args.command == "finish":
        payload["summary"] = args.summary
        payload["result_status"] = args.result_status
        return "finish"
    raise ValueError("Неизвестная команда family-task-card")


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="family-task-card")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("read")
    sub.add_parser("refresh")

    comment = sub.add_parser("comment").add_subparsers(
        dest="comment_action",
        required=True,
    )
    comment_add = comment.add_parser("add")
    comment_add.add_argument("--text", required=True)

    question = sub.add_parser("question").add_subparsers(
        dest="question_action",
        required=True,
    )
    question_ask = question.add_parser("ask")
    question_ask.add_argument("--text", required=True)
    question_ask.add_argument("--blocking", action="store_true")

    checklist = sub.add_parser("checklist").add_subparsers(
        dest="checklist_action",
        required=True,
    )
    checklist_create = checklist.add_parser("create")
    checklist_create.add_argument("--title", required=True)
    checklist_create.add_argument("--item", action="append", default=[])
    checklist_add = checklist.add_parser("item-add")
    checklist_add.add_argument("--checklist-id", required=True)
    checklist_add.add_argument("--text", required=True)
    checklist_done = checklist.add_parser("item-done")
    checklist_done.add_argument("--checklist-id", required=True)
    checklist_done.add_argument("--item-id", required=True)
    checklist_done.add_argument("--no-done", action="store_true")

    attachment = sub.add_parser("attachment").add_subparsers(
        dest="attachment_action",
        required=True,
    )
    attachment_add = attachment.add_parser("add-from-workspace")
    attachment_add.add_argument("--path", required=True)
    attachment_add.add_argument("--caption", default="")

    status = sub.add_parser("status").add_subparsers(
        dest="status_action",
        required=True,
    )
    status_set = status.add_parser("set")
    status_set.add_argument("status")
    status_set.add_argument("--reason", default="")

    finish = sub.add_parser("finish")
    finish.add_argument("--summary", required=True)
    finish.add_argument("--result-status", default="ready_for_review")
    return parser


def _base_payload(env: dict[str, str]) -> dict[str, Any]:
    return {
        "policy_ticket": env.get("FAMILY_TASK_CARD_TICKET", ""),
        "actor_profile": env.get("FAMILY_TASK_CARD_ACTOR_PROFILE", ""),
        "actor_phone": env.get("FAMILY_TASK_CARD_ACTOR_PHONE", ""),
        "task_id": env.get("FAMILY_TASK_CARD_TASK_ID", ""),
        "workspace_id": env.get("FAMILY_TASK_CARD_WORKSPACE_ID", ""),
        "agent_session_id": env.get("FAMILY_TASK_CARD_SESSION_ID", ""),
        "task_type": env.get("FAMILY_TASK_CARD_TASK_TYPE", "feature"),
        "requested_mode": env.get("FAMILY_TASK_CARD_MODE", "executor"),
    }


def _effective_env(env: dict[str, str]) -> dict[str, str]:
    result = {str(key): str(value) for key, value in env.items()}
    context = _load_context_env(result)
    for key, value in context.items():
        if not result.get(key):
            result[key] = value
    if _same_task_scope(result, context) and context.get("FAMILY_TASK_CARD_TICKET"):
        result["FAMILY_TASK_CARD_TICKET"] = context["FAMILY_TASK_CARD_TICKET"]
    return result


def _load_context_env(env: dict[str, str]) -> dict[str, str]:
    for path in _context_candidates(env):
        if not path.exists() or not path.is_file():
            continue
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            continue
        if not isinstance(raw, dict):
            continue
        return _normalize_context(raw)
    return {}


def _context_candidates(env: dict[str, str]) -> list[Path]:
    candidates = []
    explicit = env.get("FAMILY_TASK_CARD_CONTEXT_FILE", "").strip()
    if explicit:
        candidates.append(Path(explicit).expanduser())
    workspace_path = env.get("FAMILY_TASK_CARD_WORKSPACE_PATH", "").strip()
    start = Path(workspace_path).expanduser() if workspace_path else Path.cwd()
    start = start.resolve()
    for folder in [start, *start.parents]:
        candidates.append(folder / ".family-task-card" / "context.json")
    unique = []
    seen = set()
    for candidate in candidates:
        key = str(candidate.resolve()) if candidate.exists() else str(candidate)
        if key in seen:
            continue
        seen.add(key)
        unique.append(candidate)
    return unique


def _normalize_context(raw: dict[str, Any]) -> dict[str, str]:
    result = {}
    for key, value in raw.items():
        env_key = key if key in ENV_KEYS else CONTEXT_KEY_ALIASES.get(str(key))
        if not env_key:
            continue
        text = "" if value is None else str(value)
        if text:
            result[env_key] = text
    return result


def _same_task_scope(env: dict[str, str], context: dict[str, str]) -> bool:
    if not context:
        return False
    for key in (
        "FAMILY_TASK_CARD_TASK_ID",
        "FAMILY_TASK_CARD_WORKSPACE_ID",
        "FAMILY_TASK_CARD_ACTOR_PROFILE",
        "FAMILY_TASK_CARD_ACTOR_PHONE",
        "FAMILY_TASK_CARD_MODE",
    ):
        env_value = env.get(key, "")
        context_value = context.get(key, "")
        if env_value and context_value and env_value != context_value:
            return False
    return True


def _attachment_payload(path: str, caption: str, env: dict[str, str]) -> dict[str, Any]:
    base = Path(env.get("FAMILY_TASK_CARD_WORKSPACE_PATH") or os.getcwd()).resolve()
    target = (base / path).resolve()
    try:
        relative = target.relative_to(base)
    except ValueError as exc:
        raise ValueError("Файл находится вне рабочего пространства.") from exc
    if not target.exists() or not target.is_file():
        raise ValueError(f"Файл не найден в рабочем пространстве: {path}")
    raw = target.read_bytes()
    return {
        "path": relative.as_posix(),
        "filename": target.name,
        "caption": caption,
        "mime_type": mimetypes.guess_type(target.name)[0] or "application/octet-stream",
        "data_base64": base64.b64encode(raw).decode("ascii"),
        "size_bytes": len(raw),
    }


def _url(env: dict[str, str], endpoint: str) -> str:
    base = env.get("FAMILY_TASK_CARD_API_URL", "").rstrip("/")
    return f"{base}/agent/task-card/{endpoint}"


def _ticket_url(env: dict[str, str]) -> str:
    base = env.get("FAMILY_TASK_CARD_API_URL", "").rstrip("/")
    return f"{base}/agent/ticket"


def _refresh_policy_ticket(env: dict[str, str], poster: PostJson) -> bool:
    try:
        response = poster(_ticket_url(env), _ticket_payload(env))
    except Exception:
        return False
    if response.get("ok") is not True:
        return False
    ticket = str(response.get("policy_ticket") or "").strip()
    if not ticket:
        return False
    env["FAMILY_TASK_CARD_TICKET"] = ticket
    _write_context_env(env)
    return True


def _ticket_payload(env: dict[str, str]) -> dict[str, Any]:
    return {
        "actor_profile": env.get("FAMILY_TASK_CARD_ACTOR_PROFILE", ""),
        "actor_phone": env.get("FAMILY_TASK_CARD_ACTOR_PHONE", ""),
        "task_id": env.get("FAMILY_TASK_CARD_TASK_ID", ""),
        "workspace_id": env.get("FAMILY_TASK_CARD_WORKSPACE_ID", ""),
        "task_type": env.get("FAMILY_TASK_CARD_TASK_TYPE", "feature"),
        "requested_mode": env.get("FAMILY_TASK_CARD_MODE", "executor"),
    }


def _write_context_env(env: dict[str, str]) -> None:
    path = _context_write_path(env)
    if path is None:
        return
    raw: dict[str, Any] = {}
    if path.exists() and path.is_file():
        try:
            loaded = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(loaded, dict):
                raw.update(loaded)
        except Exception:
            raw = {}
    env["FAMILY_TASK_CARD_CONTEXT_FILE"] = str(path)
    for key in ENV_KEYS:
        value = env.get(key, "")
        if value:
            raw[key] = value
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(raw, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def _context_write_path(env: dict[str, str]) -> Path | None:
    explicit = env.get("FAMILY_TASK_CARD_CONTEXT_FILE", "").strip()
    if explicit:
        return Path(explicit).expanduser().resolve()
    for candidate in _context_candidates(env):
        if candidate.exists() and candidate.is_file():
            return candidate.resolve()
    workspace_path = env.get("FAMILY_TASK_CARD_WORKSPACE_PATH", "").strip()
    if workspace_path:
        return (Path(workspace_path).expanduser().resolve() / ".family-task-card" / "context.json")
    return (Path.cwd().resolve() / ".family-task-card" / "context.json")


def _post_json(
    url: str,
    payload: dict[str, Any],
    env: dict[str, str] | None = None,
) -> dict[str, Any]:
    data = json.dumps(payload).encode("utf-8")
    env_map = env or os.environ
    request = urllib.request.Request(
        url,
        data=data,
        headers={
            "Content-Type": "application/json",
            "X-Api-Key": env_map.get("FAMILY_TASK_CARD_API_KEY", "dev-local-key"),
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            decoded = json.loads(response.read().decode("utf-8", "replace"))
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", "replace")
        try:
            decoded_error = json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            decoded_error = {"error": raw or exc.reason}
        if not isinstance(decoded_error, dict):
            decoded_error = {"error": raw or exc.reason}
        raise TaskCardHttpError(exc.code, decoded_error) from exc
    if not isinstance(decoded, dict):
        raise ValueError("backend returned non-object JSON")
    return decoded


if __name__ == "__main__":
    raise SystemExit(run())
