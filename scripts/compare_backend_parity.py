import argparse
import json
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any


def _request_json(
    *,
    method: str,
    base_url: str,
    path: str,
    api_key: str,
    payload: dict[str, Any] | None = None,
    timeout: int = 20,
) -> tuple[int, dict[str, Any] | None, str]:
    url = f"{base_url.rstrip('/')}{path}"
    headers = {"Content-Type": "application/json; charset=utf-8"}
    if api_key:
        headers["X-Api-Key"] = api_key
    body = None
    if payload is not None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(url=url, data=body, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            parsed = None
            try:
                parsed = json.loads(raw) if raw else {}
            except Exception:
                parsed = None
            return int(resp.status), parsed if isinstance(parsed, dict) else None, raw
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        parsed = None
        try:
            parsed = json.loads(raw) if raw else {}
        except Exception:
            parsed = None
        return int(exc.code), parsed if isinstance(parsed, dict) else None, raw
    except Exception as exc:  # noqa: BLE001
        return 0, None, str(exc)


@dataclass
class CaseResult:
    ok: bool
    status: int
    path_used: str
    body_preview: str
    json_keys: list[str]
    contract_ok: bool
    contract_errors: list[str]


class BackendClient:
    def __init__(self, *, base_url: str, api_key: str):
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key

    def _call_with_fallback(
        self,
        *,
        method: str,
        paths: list[str],
        payload: dict[str, Any] | None = None,
    ) -> tuple[str, int, dict[str, Any] | None, str]:
        last_path = paths[-1]
        last_status = 0
        last_json = None
        last_raw = ""
        for path in paths:
            status, parsed, raw = _request_json(
                method=method,
                base_url=self.base_url,
                path=path,
                api_key=self.api_key,
                payload=payload,
            )
            last_path = path
            last_status = status
            last_json = parsed
            last_raw = raw
            if 200 <= status < 300:
                return path, status, parsed, raw
        return last_path, last_status, last_json, last_raw

    def health(self) -> tuple[str, int, dict[str, Any] | None, str]:
        return self._call_with_fallback(method="GET", paths=["/health", "/health.php"])

    def pull_snapshot(self, actor_profile: str) -> tuple[str, int, dict[str, Any] | None, str]:
        query = urllib.parse.urlencode({"since": "1970-01-01T00:00:00", "actor_profile": actor_profile})
        return self._call_with_fallback(
            method="GET",
            paths=[f"/sync/pull?{query}", f"/sync_pull.php?{query}"],
        )

    def pull_changes(self, actor_profile: str) -> tuple[str, int, dict[str, Any] | None, str]:
        query = urllib.parse.urlencode({"cursor": "1970-01-01T00:00:00", "actor_profile": actor_profile})
        return self._call_with_fallback(
            method="GET",
            paths=[f"/sync/changes?{query}", f"/sync_changes.php?{query}"],
        )

    def push(self, payload: dict[str, Any]) -> tuple[str, int, dict[str, Any] | None, str]:
        return self._call_with_fallback(
            method="POST",
            paths=["/sync/push", "/sync_push.php"],
            payload=payload,
        )


def _check_health_contract(payload: dict[str, Any] | None) -> list[str]:
    errors: list[str] = []
    if payload is None:
        return ["body is not JSON object"]
    for key in ("ok", "time"):
        if key not in payload:
            errors.append(f"missing key '{key}'")
    if payload.get("ok") is not True:
        errors.append("ok != true")
    return errors


def _check_pull_contract(payload: dict[str, Any] | None) -> list[str]:
    errors: list[str] = []
    if payload is None:
        return ["body is not JSON object"]
    required = ("ok", "tasks", "family_tasks", "server_time", "cursor", "next_cursor", "mode")
    for key in required:
        if key not in payload:
            errors.append(f"missing key '{key}'")
    if "tasks" in payload and not isinstance(payload.get("tasks"), list):
        errors.append("tasks is not list")
    if "family_tasks" in payload and not isinstance(payload.get("family_tasks"), list):
        errors.append("family_tasks is not list")
    if "mode" in payload and payload.get("mode") not in ("snapshot", "changes"):
        errors.append("mode is not snapshot|changes")
    return errors


def _check_push_contract(payload: dict[str, Any] | None) -> list[str]:
    errors: list[str] = []
    if payload is None:
        return ["body is not JSON object"]
    required = ("ok", "accepted", "duplicates", "telegram", "push")
    for key in required:
        if key not in payload:
            errors.append(f"missing key '{key}'")
    if "accepted" in payload and not isinstance(payload.get("accepted"), int):
        errors.append("accepted is not int")
    if "duplicates" in payload and not isinstance(payload.get("duplicates"), int):
        errors.append("duplicates is not int")
    return errors


def _build_case_result(
    *,
    status: int,
    path_used: str,
    parsed: dict[str, Any] | None,
    raw: str,
    contract_errors: list[str],
) -> CaseResult:
    return CaseResult(
        ok=200 <= status < 300,
        status=status,
        path_used=path_used,
        body_preview=(raw[:320] if raw else ""),
        json_keys=sorted(parsed.keys()) if isinstance(parsed, dict) else [],
        contract_ok=len(contract_errors) == 0,
        contract_errors=contract_errors,
    )


def run_suite(*, label: str, client: BackendClient, actor_profile: str) -> dict[str, Any]:
    nonce = f"{int(time.time())}-{label}"
    task_id = f"parity-{nonce}"
    event_upsert = {
        "actor_profile": actor_profile,
        "source": f"parity-{label}",
        "events": [
            {
                "event_id": f"evt-upsert-{nonce}",
                "entity": "task",
                "action": "upsert",
                "payload": {
                    "id": task_id,
                    "owner_key": actor_profile,
                    "is_family": False,
                    "title": f"Parity {label}",
                    "details": "",
                    "due_date": "2026-04-23",
                    "time": "12:00",
                    "workflow_status": "todo",
                    "priority": "medium",
                    "tags": [],
                    "participants": [],
                    "duration_minutes": 0,
                    "updated_at": "2026-04-23T12:00:00",
                    "version": 1,
                },
                "happened_at": "2026-04-23T12:00:00",
            }
        ],
    }
    event_delete = {
        "actor_profile": actor_profile,
        "source": f"parity-{label}",
        "events": [
            {
                "event_id": f"evt-delete-{nonce}",
                "entity": "task",
                "action": "delete",
                "payload": {"id": task_id, "owner_key": actor_profile, "is_family": False},
                "happened_at": "2026-04-23T12:01:00",
            }
        ],
    }

    cases: dict[str, CaseResult] = {}

    path, status, parsed, raw = client.health()
    cases["health"] = _build_case_result(
        status=status,
        path_used=path,
        parsed=parsed,
        raw=raw,
        contract_errors=_check_health_contract(parsed) if 200 <= status < 300 else [f"status={status}"],
    )

    path, status, parsed, raw = client.pull_snapshot(actor_profile)
    cases["pull_snapshot"] = _build_case_result(
        status=status,
        path_used=path,
        parsed=parsed,
        raw=raw,
        contract_errors=_check_pull_contract(parsed) if 200 <= status < 300 else [f"status={status}"],
    )

    path, status, parsed, raw = client.push(event_upsert)
    cases["push_upsert"] = _build_case_result(
        status=status,
        path_used=path,
        parsed=parsed,
        raw=raw,
        contract_errors=_check_push_contract(parsed) if 200 <= status < 300 else [f"status={status}"],
    )

    path, status, parsed, raw = client.pull_changes(actor_profile)
    pull_changes_errors = _check_pull_contract(parsed) if 200 <= status < 300 else [f"status={status}"]
    if 200 <= status < 300 and isinstance(parsed, dict):
        ids = {str(item.get("id")) for item in parsed.get("tasks", []) if isinstance(item, dict)}
        if task_id not in ids:
            pull_changes_errors.append(f"task '{task_id}' not present in changes response")
    cases["pull_changes"] = _build_case_result(
        status=status,
        path_used=path,
        parsed=parsed,
        raw=raw,
        contract_errors=pull_changes_errors,
    )

    path, status, parsed, raw = client.push(event_delete)
    cases["cleanup_delete"] = _build_case_result(
        status=status,
        path_used=path,
        parsed=parsed,
        raw=raw,
        contract_errors=_check_push_contract(parsed) if 200 <= status < 300 else [f"status={status}"],
    )

    passed = all(item.contract_ok for item in cases.values())
    return {
        "label": label,
        "base_url": client.base_url,
        "passed": passed,
        "cases": {k: vars(v) for k, v in cases.items()},
    }


def compare_suites(old: dict[str, Any] | None, new: dict[str, Any]) -> dict[str, Any]:
    if old is None:
        return {
            "comparable": False,
            "status": "old_unavailable",
            "differences": ["old suite unavailable, ran contract-only validation on new backend"],
        }

    old_cases = old.get("cases", {})
    old_any_ok = any(bool(case.get("ok")) for case in old_cases.values())
    if not old_any_ok:
        return {
            "comparable": False,
            "status": "old_unavailable",
            "differences": ["old suite returned no successful cases, likely infra/auth/database outage"],
        }

    differences: list[str] = []
    for case_name, new_case in new["cases"].items():
        old_case = old["cases"].get(case_name)
        if old_case is None:
            differences.append(f"old missing case '{case_name}'")
            continue
        if new_case["status"] != old_case["status"]:
            differences.append(f"{case_name}: status mismatch old={old_case['status']} new={new_case['status']}")
        old_keys = set(old_case.get("json_keys", []))
        new_keys = set(new_case.get("json_keys", []))
        if old_keys != new_keys:
            differences.append(
                f"{case_name}: json key mismatch old={sorted(old_keys)} new={sorted(new_keys)}"
            )

    return {
        "comparable": True,
        "status": "pass" if not differences else "fail",
        "differences": differences,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Compare old backend API and Laravel API contract parity.")
    parser.add_argument("--old-base", default="https://familly.nikportfolio.ru/backend_api/public")
    parser.add_argument("--new-base", default="http://31.129.97.211")
    parser.add_argument("--api-key", default="dev-local-key")
    parser.add_argument("--actor-profile", default="nik")
    parser.add_argument("--out-json", default="docs/phase3_parity_report.json")
    args = parser.parse_args()

    old_suite: dict[str, Any] | None = None
    old_error: str | None = None
    try:
        old_suite = run_suite(
            label="old",
            client=BackendClient(base_url=args.old_base, api_key=args.api_key),
            actor_profile=args.actor_profile,
        )
    except Exception as exc:  # noqa: BLE001
        old_error = str(exc)

    new_suite = run_suite(
        label="new",
        client=BackendClient(base_url=args.new_base, api_key=args.api_key),
        actor_profile=args.actor_profile,
    )

    comparison = compare_suites(old_suite, new_suite)
    report = {
        "timestamp_epoch": int(time.time()),
        "old_base": args.old_base,
        "new_base": args.new_base,
        "actor_profile": args.actor_profile,
        "old_error": old_error,
        "old_suite": old_suite,
        "new_suite": new_suite,
        "comparison": comparison,
    }

    out_path = Path(args.out_json)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"Report saved: {out_path}")
    print(f"New backend contract pass: {new_suite['passed']}")
    print(f"Comparison status: {comparison['status']}")
    if old_error:
        print(f"Old backend suite failed to run: {old_error}")
    if comparison["differences"]:
        for diff in comparison["differences"]:
            print(f"- {diff}")

    if not new_suite["passed"]:
        return 2
    if comparison["status"] == "fail":
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
