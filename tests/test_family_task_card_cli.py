import base64
import tempfile
import unittest
from pathlib import Path

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
