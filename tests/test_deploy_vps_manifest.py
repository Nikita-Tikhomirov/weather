from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_vps_deploy_manifest_includes_access_and_agent_backend_files() -> None:
    script = (ROOT / "deploy_vps.ps1").read_text(encoding="utf-8")

    for path in [
        "laravel_backend_vps\\config\\sync.php",
        "laravel_backend_vps\\app\\Domain\\Access\\AccessPolicyService.php",
        "laravel_backend_vps\\app\\Domain\\Agent\\AgentTaskService.php",
        "laravel_backend_vps\\app\\Http\\Controllers\\AgentPolicyController.php",
        "laravel_backend_vps\\app\\Http\\Controllers\\AuthController.php",
        "laravel_backend_vps\\database\\migrations\\2026_06_04_001000_create_access_and_agent_orchestration_tables.php",
        "laravel_backend_vps\\database\\migrations\\2026_06_08_001100_create_project_control_center_tables.php",
    ]:
        assert path in script
