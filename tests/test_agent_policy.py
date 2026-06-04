import time
import unittest

from agent_policy import (
    SUPERADMIN_PHONE,
    build_agent_run_policy,
    build_user_access,
    sign_policy_ticket,
    validate_policy_ticket,
)


class AgentPolicyTests(unittest.TestCase):
    def test_nikita_is_superadmin_with_workspace_grant_rights(self) -> None:
        access = build_user_access("+7 967 981-24-38", profile_key="nikita")

        self.assertEqual(SUPERADMIN_PHONE, "79679812438")
        self.assertIn("superadmin", access["roles"])
        self.assertIn("workspaces.grant_access", access["capabilities"])
        self.assertIn("ai.autopilot", access["capabilities"])
        self.assertIn("agent.deploy", access["capabilities"])

    def test_regular_user_gets_messenger_only_by_default(self) -> None:
        access = build_user_access("+7 900 000-00-00", profile_key="guest")

        self.assertEqual(access["roles"], ["messenger_user"])
        self.assertEqual(access["capabilities"], ["messenger.use"])

    def test_task_agent_operator_gets_executor_policy_for_bugfix(self) -> None:
        access = build_user_access(
            "+7 900 000-00-00",
            profile_key="developer",
            roles=["workspace_user", "agent_operator"],
            capabilities=[
                "messenger.use",
                "projects.view",
                "tasks.view",
                "tasks.comment",
                "tasks.edit",
                "tasks.change_status",
                "tasks.manage_agent",
                "workspaces.view",
                "workspaces.use",
                "ai.use",
                "ai.write_task_comments",
                "ai.change_task_status",
                "ai.manage_checklists",
                "agent.git_write",
            ],
        )

        policy = build_agent_run_policy(
            access,
            task_type="bugfix",
            requested_mode="executor",
            workspace_id="weather",
            task_id="task-1",
        )

        self.assertTrue(policy["allowed"])
        self.assertEqual(policy["mode"], "executor")
        self.assertIn("task_context", policy["plugins"])
        self.assertIn("task_write", policy["plugins"])
        self.assertIn("workspace_write", policy["plugins"])
        self.assertIn("git", policy["plugins"])
        self.assertNotIn("deploy", policy["plugins"])
        self.assertIn("session_send", policy["allowed_commands"])
        self.assertNotIn("workspace_delete", policy["allowed_commands"])

    def test_agent_policy_denies_without_workspace_and_task_rights(self) -> None:
        access = build_user_access("+7 900 000-00-00", profile_key="guest")

        policy = build_agent_run_policy(
            access,
            task_type="bugfix",
            requested_mode="executor",
            workspace_id="weather",
            task_id="task-1",
        )

        self.assertFalse(policy["allowed"])
        self.assertIn("Нет прав", policy["reason"])
        self.assertEqual(policy["plugins"], [])
        self.assertEqual(policy["allowed_commands"], [])

    def test_policy_ticket_validates_signature_and_expiration(self) -> None:
        access = build_user_access("+7 967 981-24-38", profile_key="nikita")
        policy = build_agent_run_policy(
            access,
            task_type="feature",
            requested_mode="autopilot",
            workspace_id="weather",
            task_id="task-2",
        )
        ticket = sign_policy_ticket(policy, secret="secret", now=1000, ttl_seconds=60)

        validated = validate_policy_ticket(ticket, secret="secret", now=1010)
        self.assertEqual(validated["workspace_id"], "weather")
        self.assertEqual(validated["task_id"], "task-2")

        with self.assertRaises(ValueError):
            validate_policy_ticket(ticket + "tampered", secret="secret", now=1010)

        with self.assertRaises(ValueError):
            validate_policy_ticket(ticket, secret="secret", now=2000)


if __name__ == "__main__":
    unittest.main()
