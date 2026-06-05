from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BACKEND = ROOT / "laravel_backend_vps"


def read_backend(path: str) -> str:
    return (BACKEND / path).read_text(encoding="utf-8")


def test_laravel_agent_policy_routes_are_registered() -> None:
    routes = read_backend("routes/api.php")

    assert "/me/access" in routes
    assert "/agent/policy" in routes
    assert "/agent/ticket" in routes
    assert "/agent/context" in routes
    assert "/agent/events" in routes
    assert "/admin/workspace-access" in routes
    assert "/admin/audit" in routes
    assert "AgentPolicyController::class" in routes


def test_laravel_access_and_agent_migration_declares_required_tables() -> None:
    migrations = "\n".join(path.read_text(encoding="utf-8") for path in (BACKEND / "database/migrations").glob("*.php"))

    for table in [
        "user_roles",
        "role_capabilities",
        "workspace_access",
        "agent_mode_catalog",
        "agent_plugin_catalog",
        "task_agent_sessions",
        "task_agent_events",
        "agent_policy_tickets",
        "audit_logs",
    ]:
        assert f"'{table}'" in migrations

    assert "unique(['workspace_id', 'profile_key']" in migrations
    assert "'policy_json'" in migrations
    assert "'payload_json'" in migrations


def test_access_policy_service_declares_superadmin_agent_capabilities_and_ticket() -> None:
    service = read_backend("app/Domain/Access/AccessPolicyService.php")

    assert "SUPERADMIN_PHONE = '79679812438'" in service
    assert "'workspaces.grant_access'" in service
    assert "'ai.autopilot'" in service
    assert "'agent.deploy'" in service
    assert "hash_hmac('sha256'" in service
    assert "'session_create'" in service
    assert "'session_send'" in service
    assert "'session_update_task_card'" in service
    assert "workspace_access" in service
    assert "grantWorkspaceAccess" in service
    assert "revokeWorkspaceAccess" in service
    assert "writeAudit" in service


def test_access_policy_uses_phone_fallback_when_actor_profile_is_not_resolved() -> None:
    service = read_backend("app/Domain/Access/AccessPolicyService.php")
    controller = read_backend("app/Http/Controllers/AgentPolicyController.php")

    assert "accessForActor(string $actor, string $fallbackPhone = '')" in service
    assert "fallbackPhone" in service
    assert "strtolower(trim($profile))" in service
    assert "'nikita' => $this->superadminPhone()" in service
    assert "accessForActor($actor, $phone)" in controller


def test_agent_task_service_updates_task_collaboration_and_events() -> None:
    service = read_backend("app/Domain/Agent/AgentTaskService.php")

    assert "buildContextPack" in service
    assert "recordSession" in service
    assert "recordEvent" in service
    assert "appendAgentSessionToTask" in service
    assert "appendAgentEventToTask" in service
    assert "agent_sessions" in service
    assert "comments" in service
    assert "workflow_status" in service


def test_auth_device_start_returns_access_contract() -> None:
    controller = read_backend("app/Http/Controllers/AuthController.php")

    assert "AccessPolicyService" in controller
    assert "'access' => $this->access->accessForPhone" in controller


def test_project_and_chat_management_are_not_visibility_only() -> None:
    project_controller = read_backend("app/Http/Controllers/ProjectGroupController.php")
    chat_repository = read_backend("app/Domain/Chat/ChatRepository.php")

    assert "isSuperadminActor($actor)" in project_controller
    assert "Only the project owner can delete" in project_controller
    assert "Only the group owner can delete" in project_controller
    assert "Actor is not a member of this conversation" in chat_repository


def test_task_collaboration_keeps_agent_sessions_on_backend() -> None:
    repo = read_backend("app/Domain/Sync/SyncRepository.php")

    assert "'agent_sessions'" in repo
    assert "updateTaskCollaboration" in repo
    assert "contextTask" in repo


def test_task_collaboration_keeps_agent_questions_on_backend() -> None:
    repo = read_backend("app/Domain/Sync/SyncRepository.php")
    service = read_backend("app/Domain/Agent/AgentTaskService.php")

    assert "'questions'" in repo
    assert "'questions'" in service


def test_laravel_task_card_tool_runtime_routes_and_handlers_exist() -> None:
    routes = read_backend("routes/api.php")
    controller = read_backend("app/Http/Controllers/AgentPolicyController.php")
    service = read_backend("app/Domain/Agent/AgentTaskService.php")

    for route in [
        "/agent/task-card/read",
        "/agent/task-card/comment",
        "/agent/task-card/question",
        "/agent/task-card/checklist",
        "/agent/task-card/checklist-item",
        "/agent/task-card/attachment",
        "/agent/task-card/status",
        "/agent/task-card/finish",
        "/agent/task-card/refresh",
    ]:
        assert route in routes

    for method in [
        "taskCardRead",
        "taskCardComment",
        "taskCardQuestion",
        "taskCardChecklist",
        "taskCardChecklistItem",
        "taskCardAttachment",
        "taskCardStatus",
        "taskCardFinish",
        "taskCardOperation",
    ]:
        assert method in controller

    for method in [
        "applyTaskCardOperation",
        "askTaskCardQuestion",
        "finishTaskCardRun",
        "setTaskCardStatus",
        "addTaskCardAttachment",
    ]:
        assert method in service

    assert "agent_question_added" in service
    assert "ready_for_review" in service
    assert "Агент не может закрыть задачу без подтверждения" in service
    assert "validatePolicyTicket" in read_backend("app/Domain/Access/AccessPolicyService.php")
    assert "policy_ticket" in controller
    assert "validateTaskCardPolicyTicket" in controller
