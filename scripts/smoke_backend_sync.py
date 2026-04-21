import json
import os
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from sync_runtime import get_sync_runtime


def _request(url: str, method: str = "GET", payload: dict | None = None, api_key: str = "") -> tuple[int, str]:
    data = None
    headers = {"Content-Type": "application/json; charset=utf-8"}
    if api_key:
        headers["X-Api-Key"] = api_key
    if payload is not None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    with urllib.request.urlopen(req, timeout=20) as resp:
        body = resp.read().decode("utf-8", errors="replace")
        return int(resp.status), body


def _check_tls(host_url: str) -> tuple[bool, str]:
    test_url = f"{host_url}/health.php"
    try:
        _request(test_url, "GET")
        return True, "ok"
    except ssl.SSLCertVerificationError as exc:
        return False, f"tls verify failed: {exc}"
    except urllib.error.URLError as exc:
        reason = getattr(exc, "reason", exc)
        if isinstance(reason, ssl.SSLCertVerificationError):
            return False, f"tls verify failed: {reason}"
        return False, f"url error: {reason}"
    except Exception as exc:
        return False, str(exc)


def main() -> int:
    runtime = get_sync_runtime(default_source=os.getenv("TODO_BACKEND_SOURCE", "desktop"))
    base = runtime["backend_url"].rstrip("/")
    api_key = runtime["backend_api_key"]
    if not base:
        print("backend_url is empty")
        return 1

    tls_ok, tls_msg = _check_tls(base)
    print(f"TLS: {'OK' if tls_ok else 'FAIL'} ({tls_msg})")
    if not tls_ok:
        return 2

    since = urllib.parse.urlencode({"since": "1970-01-01T00:00:00"})
    checks = [
        ("GET", f"{base}/sync_pull.php?{since}", None),
        (
            "POST",
            f"{base}/sync_push.php",
            {
                "actor_profile": "nik",
                "source": "smoke",
                "events": [],
            },
        ),
        (
            "POST",
            f"{base}/devices_register.php",
            {
                "actor_profile": "nik",
                "token": "smoke-token-do-not-use",
                "platform": "android",
                "app_version": "smoke",
            },
        ),
        (
            "POST",
            f"{base}/devices_unregister.php",
            {
                "actor_profile": "nik",
                "token": "smoke-token-do-not-use",
            },
        ),
        ("POST", f"{base}/telegram_outbox_retry.php", {}),
        ("POST", f"{base}/push_outbox_retry.php", {}),
    ]

    exit_code = 0
    for method, url, payload in checks:
        try:
            status, body = _request(url=url, method=method, payload=payload, api_key=api_key)
            print(f"{method} {url} -> {status} {body[:180]}")
            if status < 200 or status >= 300:
                exit_code = 3
        except Exception as exc:
            print(f"{method} {url} -> ERROR {exc}")
            exit_code = 3
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
