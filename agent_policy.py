from __future__ import annotations

import base64
import hashlib
import hmac
import json
import re
import time
from typing import Any


SUPERADMIN_PHONE = "79679812438"

MESSENGER_CAPABILITIES = {"messenger.use"}
WORKSPACE_AGENT_CAPABILITIES = {
    "projects.view",
    "projects.manage",
    "tasks.view",
    "tasks.comment",
    "tasks.edit",
    "tasks.change_status",
    "tasks.manage_agent",
    "workspaces.view",
    "workspaces.use",
    "workspaces.grant_access",
    "ai.use",
    "ai.write_task_comments",
    "ai.change_task_status",
    "ai.manage_checklists",
    "ai.autopilot",
    "agent.git_write",
    "agent.github",
    "agent.browser",
    "agent.deploy",
    "admin.audit",
}
ALL_CAPABILITIES = sorted(MESSENGER_CAPABILITIES | WORKSPACE_AGENT_CAPABILITIES)

ROLE_CAPABILITIES: dict[str, set[str]] = {
    "messenger_user": {"messenger.use"},
    "project_member": {"messenger.use", "projects.view", "tasks.view", "tasks.comment"},
    "project_admin": {
        "messenger.use",
        "projects.view",
        "projects.manage",
        "tasks.view",
        "tasks.comment",
        "tasks.edit",
        "tasks.change_status",
        "tasks.manage_agent",
    },
    "workspace_user": {
        "messenger.use",
        "projects.view",
        "tasks.view",
        "tasks.comment",
        "workspaces.view",
        "workspaces.use",
    },
    "agent_operator": {
        "messenger.use",
        "tasks.view",
        "tasks.comment",
        "tasks.manage_agent",
        "ai.use",
        "ai.write_task_comments",
    },
    "superadmin": set(ALL_CAPABILITIES),
    "blocked": set(),
}

MODE_LABELS = {
    "planner": "План",
    "chat": "Чат",
    "commentator": "Комментатор",
    "executor": "Исполнитель",
    "reviewer": "Ревьюер",
    "autopilot": "Автопилот",
    "yolo": "YOLO",
}
MODE_ALIASES = {
    "план": "planner",
    "plan": "planner",
    "planner": "planner",
    "чат": "chat",
    "chat": "chat",
    "комментатор": "commentator",
    "commentator": "commentator",
    "исполнитель": "executor",
    "executor": "executor",
    "agent": "executor",
    "ревьюер": "reviewer",
    "reviewer": "reviewer",
    "review": "reviewer",
    "автопилот": "autopilot",
    "autopilot": "autopilot",
    "yolo": "yolo",
}

TASK_DEFAULT_MODES = {
    "bugfix": "executor",
    "feature": "executor",
    "review": "reviewer",
    "docs": "commentator",
    "planning": "planner",
}

TASK_ALLOWED_MODES = {
    "bugfix": {"planner", "chat", "commentator", "executor", "reviewer", "autopilot"},
    "feature": {"planner", "chat", "commentator", "executor", "reviewer", "autopilot"},
    "review": {"planner", "chat", "commentator", "reviewer"},
    "docs": {"planner", "chat", "commentator", "reviewer"},
    "planning": {"planner", "chat", "commentator"},
}

PROTECTED_COMMANDS = {
    "workspace_list",
    "workspace_discover",
    "workspace_folder_list",
    "workspace_file_list",
    "workspace_file_read",
    "workspace_create",
    "workspace_attach",
    "session_list",
    "session_create",
    "session_open",
    "session_update_task_card",
    "session_update_settings",
    "session_send",
    "session_upload_file",
    "session_task_poll",
    "session_health",
    "session_stop",
    "session_kill",
    "session_start",
}

READ_COMMANDS = {
    "workspace_list",
    "workspace_discover",
    "workspace_folder_list",
    "workspace_file_list",
    "workspace_file_read",
    "session_list",
    "session_open",
    "session_health",
}

RUN_COMMANDS = {
    "session_create",
    "session_send",
    "session_update_task_card",
    "session_upload_file",
    "session_task_poll",
    "session_stop",
    "session_start",
}

MANAGE_COMMANDS = {
    "session_update_settings",
    "session_kill",
}

WORKSPACE_MANAGE_COMMANDS = {
    "workspace_create",
    "workspace_attach",
}


def normalize_phone(value: str) -> str:
    digits = re.sub(r"[^0-9]+", "", str(value or ""))
    if len(digits) == 11 and digits.startswith("8"):
        return f"7{digits[1:]}"
    if len(digits) == 10:
        return f"7{digits}"
    return digits


def build_user_access(
    phone: str,
    *,
    profile_key: str = "",
    roles: list[str] | None = None,
    capabilities: list[str] | None = None,
) -> dict[str, Any]:
    normalized_phone = normalize_phone(phone)
    if normalized_phone == SUPERADMIN_PHONE:
        role_list = _ordered_roles(["messenger_user", "superadmin"])
        capability_list = ALL_CAPABILITIES
    else:
        role_list = _ordered_roles(roles or ["messenger_user"])
        capability_set: set[str] = set(capabilities or [])
        for role in role_list:
            capability_set.update(ROLE_CAPABILITIES.get(role, set()))
        if "blocked" in role_list:
            capability_set = set()
        capability_list = _ordered_capabilities(capability_set)

    return {
        "phone": normalized_phone,
        "profile_key": profile_key,
        "roles": role_list,
        "capabilities": capability_list,
        "is_superadmin": "superadmin" in role_list,
    }


def build_agent_run_policy(
    user_access: dict[str, Any],
    *,
    task_type: str,
    requested_mode: str,
    workspace_id: str,
    task_id: str,
) -> dict[str, Any]:
    capabilities = set(_string_list(user_access.get("capabilities")))
    task_kind = _normalize_task_type(task_type)
    mode = _normalize_mode(requested_mode) or TASK_DEFAULT_MODES.get(task_kind, "chat")
    missing = [
        capability
        for capability in ("workspaces.use", "tasks.manage_agent", "ai.use")
        if capability not in capabilities
    ]
    if missing:
        return _denied_policy(
            user_access,
            task_kind,
            mode,
            workspace_id,
            task_id,
            "Нет прав на запуск агента из задачи.",
        )

    allowed_modes = set(TASK_ALLOWED_MODES.get(task_kind, TASK_ALLOWED_MODES["feature"]))
    if mode not in allowed_modes:
        return _denied_policy(
            user_access,
            task_kind,
            mode,
            workspace_id,
            task_id,
            "Этот режим агента недоступен для выбранного типа задачи.",
        )
    if mode in {"executor", "autopilot", "yolo"} and "tasks.edit" not in capabilities:
        return _denied_policy(
            user_access,
            task_kind,
            mode,
            workspace_id,
            task_id,
            "Нет прав на изменение задачи агентом.",
        )
    if mode == "autopilot" and "ai.autopilot" not in capabilities:
        return _denied_policy(
            user_access,
            task_kind,
            mode,
            workspace_id,
            task_id,
            "Нет прав на автопилот агента.",
        )
    if mode == "yolo" and "superadmin" not in set(_string_list(user_access.get("roles"))):
        return _denied_policy(
            user_access,
            task_kind,
            mode,
            workspace_id,
            task_id,
            "YOLO-режим доступен только суперадмину.",
        )

    plugins = _plugins_for_mode(mode, capabilities)
    commands = _commands_for_mode(mode, capabilities)
    return {
        "allowed": True,
        "reason": "",
        "phone": str(user_access.get("phone") or ""),
        "profile_key": str(user_access.get("profile_key") or ""),
        "roles": _string_list(user_access.get("roles")),
        "capabilities": _ordered_capabilities(capabilities),
        "task_type": task_kind,
        "task_id": str(task_id or ""),
        "workspace_id": str(workspace_id or ""),
        "mode": mode,
        "mode_label": MODE_LABELS[mode],
        "plugins": plugins,
        "allowed_commands": commands,
    }


def command_allowed_by_policy(command_type: str, policy: dict[str, Any]) -> bool:
    if not bool(policy.get("allowed")):
        return False
    command = str(command_type or "").strip()
    allowed_commands = set(_string_list(policy.get("allowed_commands")))
    return command in allowed_commands


def sign_policy_ticket(
    policy: dict[str, Any],
    *,
    secret: str,
    now: int | None = None,
    ttl_seconds: int = 900,
) -> str:
    if not secret:
        raise ValueError("policy ticket secret is required")
    issued_at = int(time.time() if now is None else now)
    payload = dict(policy)
    payload["iat"] = issued_at
    payload["exp"] = issued_at + int(ttl_seconds)
    payload_bytes = _canonical_json(payload)
    signature = hmac.new(secret.encode("utf-8"), payload_bytes, hashlib.sha256).digest()
    return f"{_b64encode(payload_bytes)}.{_b64encode(signature)}"


def validate_policy_ticket(
    ticket: str,
    *,
    secret: str,
    now: int | None = None,
) -> dict[str, Any]:
    if not secret:
        raise ValueError("policy ticket secret is required")
    raw_ticket = str(ticket or "").strip()
    if "." not in raw_ticket:
        raise ValueError("policy ticket is required")
    payload_part, signature_part = raw_ticket.split(".", 1)
    payload_bytes = _b64decode(payload_part)
    expected = hmac.new(secret.encode("utf-8"), payload_bytes, hashlib.sha256).digest()
    actual = _b64decode(signature_part)
    if not hmac.compare_digest(expected, actual):
        raise ValueError("policy ticket signature is invalid")
    payload = json.loads(payload_bytes.decode("utf-8"))
    expires_at = int(payload.get("exp") or 0)
    current_time = int(time.time() if now is None else now)
    if expires_at <= current_time:
        raise ValueError("policy ticket expired")
    if not bool(payload.get("allowed")):
        raise ValueError("policy ticket is not allowed")
    return payload


def _plugins_for_mode(mode: str, capabilities: set[str]) -> list[str]:
    plugins: list[str] = ["task_context"]
    if "ai.write_task_comments" in capabilities:
        plugins.append("task_write")
    if "workspaces.view" in capabilities:
        plugins.append("workspace_read")
    if mode in {"executor", "autopilot", "yolo"} and "workspaces.use" in capabilities:
        plugins.append("workspace_write")
    if mode in {"executor", "reviewer", "autopilot", "yolo"}:
        if "agent.git_write" in capabilities:
            plugins.append("git")
        if "agent.github" in capabilities:
            plugins.append("github")
    if "agent.browser" in capabilities:
        plugins.append("browser")
    if mode in {"autopilot", "yolo"} and "agent.deploy" in capabilities:
        plugins.append("deploy")
    if "admin.audit" in capabilities:
        plugins.append("audit")
    return _unique_ordered(plugins)


def _commands_for_mode(mode: str, capabilities: set[str]) -> list[str]:
    commands = set(READ_COMMANDS)
    if "workspaces.use" in capabilities and mode in {
        "chat",
        "commentator",
        "executor",
        "reviewer",
        "autopilot",
        "yolo",
    }:
        commands.update(RUN_COMMANDS)
    if "tasks.manage_agent" in capabilities:
        commands.update(MANAGE_COMMANDS)
    if "workspaces.grant_access" in capabilities:
        commands.update(WORKSPACE_MANAGE_COMMANDS)
    return sorted(commands)


def _denied_policy(
    user_access: dict[str, Any],
    task_type: str,
    mode: str,
    workspace_id: str,
    task_id: str,
    reason: str,
) -> dict[str, Any]:
    return {
        "allowed": False,
        "reason": reason,
        "phone": str(user_access.get("phone") or ""),
        "profile_key": str(user_access.get("profile_key") or ""),
        "roles": _string_list(user_access.get("roles")),
        "capabilities": _string_list(user_access.get("capabilities")),
        "task_type": task_type,
        "task_id": str(task_id or ""),
        "workspace_id": str(workspace_id or ""),
        "mode": mode,
        "mode_label": MODE_LABELS.get(mode, ""),
        "plugins": [],
        "allowed_commands": [],
    }


def _ordered_roles(roles: list[str]) -> list[str]:
    order = [
        "blocked",
        "messenger_user",
        "project_member",
        "project_admin",
        "workspace_user",
        "agent_operator",
        "superadmin",
    ]
    items = _unique_ordered(str(role or "").strip() for role in roles)
    return sorted(items, key=lambda item: order.index(item) if item in order else len(order))


def _ordered_capabilities(capabilities: set[str]) -> list[str]:
    return sorted(str(item) for item in capabilities if str(item).strip())


def _normalize_task_type(value: str) -> str:
    normalized = str(value or "").strip().lower()
    return normalized if normalized in TASK_ALLOWED_MODES else "feature"


def _normalize_mode(value: str) -> str:
    normalized = str(value or "").strip().lower()
    return MODE_ALIASES.get(normalized, normalized if normalized in MODE_LABELS else "")


def _string_list(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    return [str(item) for item in value if str(item).strip()]


def _unique_ordered(values) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for raw in values:
        item = str(raw or "").strip()
        if not item or item in seen:
            continue
        seen.add(item)
        result.append(item)
    return result


def _canonical_json(value: dict[str, Any]) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")


def _b64encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).decode("ascii").rstrip("=")


def _b64decode(value: str) -> bytes:
    padded = value + ("=" * ((4 - len(value) % 4) % 4))
    try:
        return base64.urlsafe_b64decode(padded.encode("ascii"))
    except Exception as exc:
        raise ValueError("policy ticket is invalid") from exc
