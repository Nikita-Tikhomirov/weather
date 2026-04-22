import json
import os
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent
SYNC_CONFIG_PATH = BASE_DIR / "sync_runtime.json"
SYNC_CONFIG_LOCAL_PATH = BASE_DIR / "sync_runtime.local.json"

DEFAULTS = {
    "backend_url": "http://31.129.97.211",
    "backend_api_key": "dev-local-key",
    "backend_source": "desktop",
}


def _read_json(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}
    return raw if isinstance(raw, dict) else {}


def get_sync_runtime(default_source: str = "desktop") -> dict:
    """Load sync runtime config from defaults + project files + env."""
    cfg = dict(DEFAULTS)
    cfg.update(_read_json(SYNC_CONFIG_PATH))
    cfg.update(_read_json(SYNC_CONFIG_LOCAL_PATH))

    backend_url = os.getenv("TODO_BACKEND_URL", str(cfg.get("backend_url") or "")).strip().rstrip("/")
    backend_api_key = os.getenv("TODO_BACKEND_API_KEY", str(cfg.get("backend_api_key") or "")).strip()
    if not backend_api_key:
        backend_api_key = "dev-local-key"
    backend_source = os.getenv(
        "TODO_BACKEND_SOURCE",
        str(cfg.get("backend_source") or default_source),
    ).strip() or default_source

    return {
        "backend_url": backend_url,
        "backend_api_key": backend_api_key,
        "backend_source": backend_source,
    }
