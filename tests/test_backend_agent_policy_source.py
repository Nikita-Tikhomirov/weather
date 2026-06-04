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
    assert "AgentPolicyController::class" in routes


def test_access_policy_service_declares_superadmin_agent_capabilities_and_ticket() -> None:
    service = read_backend("app/Domain/Access/AccessPolicyService.php")

    assert "SUPERADMIN_PHONE = '79679812438'" in service
    assert "'workspaces.grant_access'" in service
    assert "'ai.autopilot'" in service
    assert "'agent.deploy'" in service
    assert "hash_hmac('sha256'" in service
    assert "'session_create'" in service
    assert "'session_send'" in service


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
