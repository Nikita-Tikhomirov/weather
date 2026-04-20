import json
import os
import urllib.error
import urllib.request


def main() -> int:
    base_url = os.getenv("TODO_BACKEND_URL", "").strip().rstrip("/")
    api_key = os.getenv("TODO_BACKEND_API_KEY", "").strip()
    if not base_url:
        print("TODO_BACKEND_URL is required")
        return 1
    if not api_key:
        print("TODO_BACKEND_API_KEY is required")
        return 1

    req = urllib.request.Request(
        f"{base_url}/push/outbox/retry",
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
        print(f"retry failed: {exc}")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

