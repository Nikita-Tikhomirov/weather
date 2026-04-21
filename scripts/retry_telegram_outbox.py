import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from sync_runtime import get_sync_runtime


def main() -> int:
    runtime = get_sync_runtime(default_source="desktop")
    base_url = runtime["backend_url"].rstrip("/")
    api_key = runtime["backend_api_key"]
    if not base_url:
        print("TODO_BACKEND_URL is required")
        return 1
    if not api_key:
        print("TODO_BACKEND_API_KEY is required")
        return 1

    candidates = ("/telegram_outbox_retry.php", "/telegram/outbox/retry")
    last_error = None
    for path in candidates:
        req = urllib.request.Request(
            f"{base_url}{path}",
            method="POST",
            headers={
                "Content-Type": "application/json; charset=utf-8",
                "X-Api-Key": api_key,
            },
            data=b"{}",
        )
        try:
            with urllib.request.urlopen(req, timeout=20) as resp:
                body = resp.read().decode("utf-8")
                parsed = json.loads(body) if body else {}
                print(json.dumps(parsed, ensure_ascii=False, indent=2))
                return 0
        except (urllib.error.URLError, urllib.error.HTTPError) as exc:
            last_error = exc
    print(f"retry failed: {last_error}")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
