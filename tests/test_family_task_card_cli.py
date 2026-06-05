import base64
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import family_task_card_cli as cli


class FamilyTaskCardCliTests(unittest.TestCase):
    def test_status_command_posts_to_backend(self):
        sent = {}

        def fake_post(url, payload):
            sent["url"] = url
            sent["payload"] = payload
            return {"ok": True, "snapshot": {"task": {"workflow_status": "in_review"}}}

        code = cli.run(
            ["status", "set", "in_review", "--reason", "Готово"],
            env=self._env(),
            post_json=fake_post,
        )

        self.assertEqual(code, 0)
        self.assertEqual(sent["url"], "https://api.example.test/agent/task-card/status")
        self.assertEqual(sent["payload"]["status"], "in_review")
        self.assertEqual(sent["payload"]["policy_ticket"], "ticket-1")
        self.assertEqual(sent["payload"]["reason"], "Готово")

    def test_attachment_rejects_path_outside_workspace(self):
        with tempfile.TemporaryDirectory() as tmp:
            outside = Path(tmp).parent / "secret.txt"
            outside.write_text("secret", encoding="utf-8")

            code = cli.run(
                ["attachment", "add-from-workspace", "--path", str(outside)],
                env=self._env(workspace_path=tmp),
                post_json=lambda url, payload: {"ok": True},
            )

        self.assertEqual(code, 2)

    def test_attachment_encodes_workspace_file(self):
        sent = {}

        def fake_post(url, payload):
            sent["payload"] = payload
            return {"ok": True, "snapshot": {}}

        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "reports" / "result.md"
            path.parent.mkdir()
            path.write_text("report", encoding="utf-8")

            code = cli.run(
                [
                    "attachment",
                    "add-from-workspace",
                    "--path",
                    "reports/result.md",
                    "--caption",
                    "Отчет",
                ],
                env=self._env(workspace_path=tmp),
                post_json=fake_post,
            )

        self.assertEqual(code, 0)
        self.assertEqual(sent["payload"]["filename"], "result.md")
        self.assertEqual(sent["payload"]["caption"], "Отчет")
        self.assertEqual(
            sent["payload"]["data_base64"],
            base64.b64encode(b"report").decode("ascii"),
        )

    def test_read_uses_workspace_context_when_env_is_missing(self):
        sent = {}

        def fake_post(url, payload):
            sent["url"] = url
            sent["payload"] = payload
            return {"ok": True, "snapshot": {"task": {"id": "task-from-file"}}}

        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            context_dir = workspace / ".family-task-card"
            context_dir.mkdir()
            (context_dir / "context.json").write_text(
                json.dumps(
                    {
                        "FAMILY_TASK_CARD_API_URL": "https://api.example.test",
                        "FAMILY_TASK_CARD_API_KEY": "context-key",
                        "FAMILY_TASK_CARD_TICKET": "ticket-from-file",
                        "FAMILY_TASK_CARD_TASK_ID": "task-from-file",
                        "FAMILY_TASK_CARD_WORKSPACE_ID": "exp76-ru",
                        "FAMILY_TASK_CARD_SESSION_ID": "agent-session-file",
                        "FAMILY_TASK_CARD_ACTOR_PROFILE": "Nikita",
                        "FAMILY_TASK_CARD_ACTOR_PHONE": "+79679812438",
                        "FAMILY_TASK_CARD_TASK_TYPE": "feature",
                        "FAMILY_TASK_CARD_MODE": "executor",
                        "FAMILY_TASK_CARD_WORKSPACE_PATH": str(workspace),
                    }
                ),
                encoding="utf-8",
            )
            previous = Path.cwd()
            try:
                os.chdir(workspace)
                code = cli.run(["read"], env={}, post_json=fake_post)
            finally:
                os.chdir(previous)

        self.assertEqual(code, 0)
        self.assertEqual(sent["url"], "https://api.example.test/agent/task-card/read")
        self.assertEqual(sent["payload"]["task_id"], "task-from-file")
        self.assertEqual(sent["payload"]["workspace_id"], "exp76-ru")
        self.assertEqual(sent["payload"]["policy_ticket"], "ticket-from-file")

    def test_post_json_uses_context_api_key_when_env_is_missing(self):
        sent = {}

        class FakeResponse:
            def __enter__(self):
                return self

            def __exit__(self, *args):
                return None

            def read(self):
                return b'{"ok": true, "snapshot": {}}'

        def fake_urlopen(request, timeout):
            headers = {key.lower(): value for key, value in request.headers.items()}
            sent["api_key"] = headers.get("x-api-key")
            sent["timeout"] = timeout
            return FakeResponse()

        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            context_dir = workspace / ".family-task-card"
            context_dir.mkdir()
            (context_dir / "context.json").write_text(
                json.dumps(
                    {
                        "api_url": "https://api.example.test",
                        "api_key": "context-key",
                        "policy_ticket": "ticket-from-file",
                        "task_id": "task-from-file",
                        "workspace_id": "exp76-ru",
                        "workspace_path": str(workspace),
                    }
                ),
                encoding="utf-8",
            )
            previous = Path.cwd()
            try:
                os.chdir(workspace)
                with patch("family_task_card_cli.urllib.request.urlopen", fake_urlopen):
                    code = cli.run(["read"], env={})
            finally:
                os.chdir(previous)

        self.assertEqual(code, 0)
        self.assertEqual(sent["api_key"], "context-key")
        self.assertEqual(sent["timeout"], 30)

    def _env(self, workspace_path=""):
        return {
            "FAMILY_TASK_CARD_API_URL": "https://api.example.test",
            "FAMILY_TASK_CARD_API_KEY": "dev-local-key",
            "FAMILY_TASK_CARD_TICKET": "ticket-1",
            "FAMILY_TASK_CARD_TASK_ID": "task-1",
            "FAMILY_TASK_CARD_WORKSPACE_ID": "weather",
            "FAMILY_TASK_CARD_SESSION_ID": "agent-session-1",
            "FAMILY_TASK_CARD_ACTOR_PROFILE": "Nikita",
            "FAMILY_TASK_CARD_ACTOR_PHONE": "+79679812438",
            "FAMILY_TASK_CARD_TASK_TYPE": "feature",
            "FAMILY_TASK_CARD_MODE": "executor",
            "FAMILY_TASK_CARD_WORKSPACE_PATH": workspace_path,
        }
