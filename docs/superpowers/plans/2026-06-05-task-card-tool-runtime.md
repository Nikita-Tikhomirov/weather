# Task Card Tool Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a real task-card tool runtime so agents read and update task cards through app operations instead of relying on prompt-only JSON.

**Architecture:** Backend owns task-card state changes and policy checks. CodeWhale bridge injects task-card CLI environment into the worker. The mobile app launches agents with a task-card session contract and polls/syncs the resulting card updates. `TASK_CARD_ACTIONS_JSON` remains only as a temporary fallback.

**Tech Stack:** Laravel backend, Python bridge/CLI, Flutter mobile app, PHPUnit, Python unittest/pytest, Flutter widget tests.

---

## Scope Check

This plan implements the MVP from `docs/superpowers/specs/2026-06-05-task-card-tool-runtime-design.md`:

- backend task-card operations;
- Python CLI `family-task-card`;
- bridge session metadata and worker env injection;
- mobile launch contract changes;
- mobile models/UI support for agent questions and protocol status;
- tests across backend, bridge/CLI, and Flutter.

It does not replace CLI with MCP yet. CLI is the first stable tool surface.

## File Structure

### Backend

- Modify `laravel_backend_vps/app/Domain/Agent/AgentTaskService.php`
  - Add card snapshot builder, question/comment/checklist/attachment/status/finish operations.
  - Keep existing session/event methods.
- Modify `laravel_backend_vps/app/Http/Controllers/AgentPolicyController.php`
  - Add endpoints for `taskCardRead`, `taskCardComment`, `taskCardQuestion`, `taskCardChecklist`, `taskCardChecklistItem`, `taskCardAttachment`, `taskCardStatus`, `taskCardFinish`.
- Modify `laravel_backend_vps/routes/api.php`
  - Register `/agent/task-card/*` routes.
- Modify `laravel_backend_vps/app/Domain/Sync/SyncRepository.php`
  - Preserve `questions` in `collaboration_json`.
  - Return task version field in context if available.
- Create `laravel_backend_vps/tests/Feature/AgentTaskCardRuntimeTest.php`
  - Cover read, question, checklist, attachment, status, finish, permission denial.

### Python bridge and CLI

- Create `family_task_card_cli.py`
  - CLI used by the agent inside workspace.
  - Reads env ticket/session/workspace/API.
  - Sends task-card operations to backend.
  - Encodes workspace attachments safely.
- Modify `codewhale_bridge.py`
  - Store task-card metadata on session create/update.
  - Inject env vars and PATH into worker process.
  - Materialize a workspace-local command shim named `family-task-card`.
  - Add built-in command catalog entry for `/skill family-task-card`.
- Modify `tests/test_codewhale_bridge.py`
  - Cover session metadata, env injection, shim creation.
- Create `tests/test_family_task_card_cli.py`
  - Cover CLI payloads, attachment path safety, status command.

### Mobile app

- Modify `mobile_app/lib/models/task_collaboration.dart`
  - Add `TaskAgentQuestion`.
  - Preserve `questions` in `TaskCollaboration`.
- Modify `mobile_app/lib/services/sync_api_client.dart`
  - Add task-card operation client methods only if mobile needs direct answers.
  - Preserve context fields returned by backend.
- Modify `mobile_app/lib/services/codewhale_bridge_service.dart`
  - Add task-card metadata to `createSession`.
- Modify `mobile_app/lib/features/tasks/agent_launch_plan.dart`
  - Make `/skill family-task-card` mandatory before selected skills.
  - Make `task_card.read` the first real agent instruction.
  - Keep JSON fallback as final compatibility only.
- Modify `mobile_app/lib/features/tasks/task_editor_sheet.dart`
  - Send task-card metadata when creating a bridge session.
  - Show agent questions.
  - Mark protocol failures.
  - Poll/sync while agent session is active.
- Modify `mobile_app/test/task_item_test.dart`
  - Cover question serialization.
- Modify `mobile_app/test/agent_launch_plan_test.dart`
  - Cover mandatory skill/read ordering.
- Modify `mobile_app/test/task_editor_sheet_test.dart`
  - Cover createSession task-card metadata and visible agent question.

---

## Task 1: Backend Collaboration Shape Supports Agent Questions

**Files:**
- Modify: `laravel_backend_vps/app/Domain/Sync/SyncRepository.php`
- Test: `laravel_backend_vps/tests/Feature/AgentTaskCardRuntimeTest.php`
- Modify: `mobile_app/lib/models/task_collaboration.dart`
- Test: `mobile_app/test/task_item_test.dart`

- [ ] **Step 1: Write failing Laravel test for questions preservation**

Create `laravel_backend_vps/tests/Feature/AgentTaskCardRuntimeTest.php` with:

```php
<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class AgentTaskCardRuntimeTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        config([
            'sync.api_key' => '',
            'sync.locked_actor_profile' => '',
            'sync.agent_policy_ticket_secret' => 'base64:test-policy-secret',
        ]);
    }

    #[Test]
    public function context_pack_preserves_agent_questions(): void
    {
        $this->seedTask([
            'id' => 'task-card-1',
            'title' => 'Форма регистрации',
            'collaboration_json' => json_encode([
                'questions' => [
                    [
                        'id' => 'question-1',
                        'text' => 'Нужен макет формы?',
                        'status' => 'open',
                        'blocking' => true,
                    ],
                ],
            ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
        ]);

        $response = $this->withHeaders(['X-Api-Key' => 'dev-local-key'])
            ->postJson('/agent/context', $this->agentPayload('task-card-1'));

        $response
            ->assertStatus(200)
            ->assertJsonPath('context.questions.0.id', 'question-1')
            ->assertJsonPath('context.questions.0.status', 'open')
            ->assertJsonPath('context.questions.0.blocking', true);
    }

    private function seedTask(array $overrides): void
    {
        DB::table('tasks')->insert(array_merge([
            'id' => 'task-card-1',
            'owner_key' => 'family',
            'title' => 'Задача',
            'details' => '',
            'due_date' => '',
            'time' => '',
            'priority' => 'medium',
            'workflow_status' => 'todo',
            'project_id' => '',
            'group_id' => '',
            'participants_json' => '[]',
            'collaboration_json' => '{}',
            'created_at' => now(),
            'updated_at' => now(),
        ], $overrides));
    }

    private function agentPayload(string $taskId): array
    {
        return [
            'actor_profile' => 'Nikita',
            'actor_phone' => '+79679812438',
            'task_id' => $taskId,
            'task_type' => 'feature',
            'workspace_id' => 'weather',
            'requested_mode' => 'executor',
        ];
    }
}
```

- [ ] **Step 2: Run Laravel test and verify it fails**

Run:

```powershell
cd laravel_backend_vps
php artisan test --filter AgentTaskCardRuntimeTest
```

Expected: FAIL because `context.questions` is missing.

- [ ] **Step 3: Preserve `questions` in backend collaboration normalization**

Modify `laravel_backend_vps/app/Domain/Sync/SyncRepository.php` in `normalizeCollaboration`:

```php
return [
    'comments' => array_values(is_array($value['comments'] ?? null) ? $value['comments'] : []),
    'attachments' => array_values(is_array($value['attachments'] ?? null) ? $value['attachments'] : []),
    'checklists' => array_values(is_array($value['checklists'] ?? null) ? $value['checklists'] : []),
    'questions' => array_values(is_array($value['questions'] ?? null) ? $value['questions'] : []),
    'activity' => array_values(is_array($value['activity'] ?? null) ? $value['activity'] : []),
    'agent_sessions' => array_values(is_array($value['agent_sessions'] ?? null) ? $value['agent_sessions'] : []),
];
```

Modify `laravel_backend_vps/app/Domain/Agent/AgentTaskService.php` in `buildContextPack`:

```php
'questions' => array_values(is_array($collaboration['questions'] ?? null) ? $collaboration['questions'] : []),
```

Also add `questions` to fallback collaboration arrays.

- [ ] **Step 4: Add Dart question model failing test**

Modify `mobile_app/test/task_item_test.dart`:

```dart
test('TaskItem serialization preserves agent questions', () {
  final task = _task(
    collaboration: const TaskCollaboration(
      questions: [
        TaskAgentQuestion(
          id: 'question-1',
          text: 'Нужен макет формы?',
          status: 'open',
          createdAt: '2026-06-05T10:00:00Z',
          blocking: true,
        ),
      ],
    ),
  );

  final decoded = TaskItem.fromJson(task.toJson());
  expect(decoded.collaboration.questions.single.id, 'question-1');
  expect(decoded.collaboration.questions.single.blocking, isTrue);
});
```

Expected: FAIL because `TaskAgentQuestion` does not exist.

- [ ] **Step 5: Implement `TaskAgentQuestion` in Dart**

Modify `mobile_app/lib/models/task_collaboration.dart`:

```dart
@immutable
class TaskAgentQuestion {
  const TaskAgentQuestion({
    required this.id,
    required this.text,
    required this.status,
    required this.createdAt,
    this.blocking = false,
    this.answerText = '',
    this.answeredAt = '',
    this.relatedChecklistId = '',
    this.relatedAttachmentId = '',
  });

  final String id;
  final String text;
  final String status;
  final String createdAt;
  final bool blocking;
  final String answerText;
  final String answeredAt;
  final String relatedChecklistId;
  final String relatedAttachmentId;

  bool get isOpen => status == 'open' && answeredAt.trim().isEmpty;

  factory TaskAgentQuestion.fromJson(Map<String, dynamic> json) {
    return TaskAgentQuestion(
      id: (json['id'] ?? '').toString(),
      text: (json['text'] ?? '').toString(),
      status: (json['status'] ?? 'open').toString(),
      createdAt: (json['created_at'] ?? '').toString(),
      blocking: json['blocking'] == true || json['blocking'] == 1,
      answerText: (json['answer_text'] ?? '').toString(),
      answeredAt: (json['answered_at'] ?? '').toString(),
      relatedChecklistId: (json['related_checklist_id'] ?? '').toString(),
      relatedAttachmentId: (json['related_attachment_id'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'status': status,
      'created_at': createdAt,
      'blocking': blocking,
      'answer_text': answerText,
      'answered_at': answeredAt,
      'related_checklist_id': relatedChecklistId,
      'related_attachment_id': relatedAttachmentId,
    };
  }
}
```

Add to `TaskCollaboration` constructor, fields, `isEmpty`, `fromJson`, `toJson`, `copyWith`, equality, and hashCode:

```dart
this.questions = const [],
final List<TaskAgentQuestion> questions;
questions: _decodeMapList(map['questions']).map(TaskAgentQuestion.fromJson).toList(),
'questions': questions.map((item) => item.toJson()).toList(),
```

- [ ] **Step 6: Run focused tests**

Run:

```powershell
cd laravel_backend_vps
php artisan test --filter AgentTaskCardRuntimeTest
cd ..\mobile_app
& 'C:\Users\user\.puro\envs\stable\flutter\bin\flutter.bat' test test/task_item_test.dart
```

Expected: both pass.

- [ ] **Step 7: Commit**

```powershell
git add laravel_backend_vps/app/Domain/Sync/SyncRepository.php laravel_backend_vps/app/Domain/Agent/AgentTaskService.php laravel_backend_vps/tests/Feature/AgentTaskCardRuntimeTest.php mobile_app/lib/models/task_collaboration.dart mobile_app/test/task_item_test.dart
git commit -m "feat: preserve agent questions in task cards"
```

---

## Task 2: Backend Task Card Operations

**Files:**
- Modify: `laravel_backend_vps/app/Domain/Agent/AgentTaskService.php`
- Modify: `laravel_backend_vps/app/Http/Controllers/AgentPolicyController.php`
- Modify: `laravel_backend_vps/routes/api.php`
- Test: `laravel_backend_vps/tests/Feature/AgentTaskCardRuntimeTest.php`

- [ ] **Step 1: Add failing endpoint tests**

Append tests to `AgentTaskCardRuntimeTest`:

```php
#[Test]
public function task_card_question_adds_blocking_question_and_activity(): void
{
    $this->seedTask(['id' => 'task-card-question']);

    $response = $this->withHeaders(['X-Api-Key' => 'dev-local-key'])
        ->postJson('/agent/task-card/question', [
            ...$this->agentPayload('task-card-question'),
            'agent_session_id' => 'agent-session-1',
            'text' => 'Нужен макет формы?',
            'blocking' => true,
        ]);

    $response
        ->assertStatus(200)
        ->assertJsonPath('ok', true)
        ->assertJsonPath('snapshot.questions.0.text', 'Нужен макет формы?')
        ->assertJsonPath('snapshot.questions.0.status', 'open')
        ->assertJsonPath('snapshot.questions.0.blocking', true)
        ->assertJsonPath('snapshot.agent_session.status', 'blocked');
}

#[Test]
public function task_card_finish_moves_executor_task_to_review(): void
{
    $this->seedTask(['id' => 'task-card-finish']);

    $response = $this->withHeaders(['X-Api-Key' => 'dev-local-key'])
        ->postJson('/agent/task-card/finish', [
            ...$this->agentPayload('task-card-finish'),
            'agent_session_id' => 'agent-session-1',
            'summary' => 'Форма готова к проверке.',
            'result_status' => 'ready_for_review',
        ]);

    $response
        ->assertStatus(200)
        ->assertJsonPath('ok', true)
        ->assertJsonPath('snapshot.task.workflow_status', 'in_review')
        ->assertJsonPath('snapshot.comments.0.text', 'Форма готова к проверке.');
}

#[Test]
public function task_card_status_rejects_done_for_executor_without_superadmin_override(): void
{
    $this->seedTask(['id' => 'task-card-status']);

    $response = $this->withHeaders(['X-Api-Key' => 'dev-local-key'])
        ->postJson('/agent/task-card/status', [
            ...$this->agentPayload('task-card-status'),
            'agent_session_id' => 'agent-session-1',
            'status' => 'done',
            'reason' => 'Сам закрыл',
        ]);

    $response
        ->assertStatus(403)
        ->assertJsonPath('ok', false);
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```powershell
cd laravel_backend_vps
php artisan test --filter AgentTaskCardRuntimeTest
```

Expected: FAIL because routes and methods do not exist.

- [ ] **Step 3: Add routes**

Modify `laravel_backend_vps/routes/api.php`:

```php
Route::post('/agent/task-card/read', [AgentPolicyController::class, 'taskCardRead']);
Route::post('/agent/task-card/comment', [AgentPolicyController::class, 'taskCardComment']);
Route::post('/agent/task-card/question', [AgentPolicyController::class, 'taskCardQuestion']);
Route::post('/agent/task-card/checklist', [AgentPolicyController::class, 'taskCardChecklist']);
Route::post('/agent/task-card/checklist-item', [AgentPolicyController::class, 'taskCardChecklistItem']);
Route::post('/agent/task-card/attachment', [AgentPolicyController::class, 'taskCardAttachment']);
Route::post('/agent/task-card/status', [AgentPolicyController::class, 'taskCardStatus']);
Route::post('/agent/task-card/finish', [AgentPolicyController::class, 'taskCardFinish']);
Route::post('/agent/task-card/refresh', [AgentPolicyController::class, 'taskCardRead']);
```

- [ ] **Step 4: Add controller wrappers**

Modify `AgentPolicyController.php`. Add methods:

```php
public function taskCardRead(Request $request): JsonResponse
{
    return $this->taskCardOperation($request, 'read');
}

public function taskCardComment(Request $request): JsonResponse
{
    return $this->taskCardOperation($request, 'comment');
}

public function taskCardQuestion(Request $request): JsonResponse
{
    return $this->taskCardOperation($request, 'question');
}

public function taskCardChecklist(Request $request): JsonResponse
{
    return $this->taskCardOperation($request, 'checklist');
}

public function taskCardChecklistItem(Request $request): JsonResponse
{
    return $this->taskCardOperation($request, 'checklist_item');
}

public function taskCardAttachment(Request $request): JsonResponse
{
    return $this->taskCardOperation($request, 'attachment');
}

public function taskCardStatus(Request $request): JsonResponse
{
    return $this->taskCardOperation($request, 'status');
}

public function taskCardFinish(Request $request): JsonResponse
{
    return $this->taskCardOperation($request, 'finish');
}
```

Add private dispatcher:

```php
private function taskCardOperation(Request $request, string $operation): JsonResponse
{
    try {
        $policy = $this->buildPolicy($request);
        if (!((bool)($policy['allowed'] ?? false))) {
            return $this->json(403, [
                'ok' => false,
                'policy' => $policy,
                'error' => (string)($policy['reason'] ?? 'Нет прав на операцию карточки.'),
            ]);
        }

        $snapshot = $this->agentTasks->applyTaskCardOperation(
            (string)$request->input('actor_profile', ''),
            (string)$request->input('task_id', ''),
            (string)$request->input('workspace_id', ''),
            (string)$request->input('agent_session_id', ''),
            $operation,
            $request->all(),
            $policy,
        );

        return $this->json(200, ['ok' => true, 'policy' => $policy, 'snapshot' => $snapshot]);
    } catch (InvalidArgumentException $e) {
        return $this->json(403, ['ok' => false, 'error' => $e->getMessage()]);
    } catch (Throwable $e) {
        return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
    }
}
```

- [ ] **Step 5: Implement backend operation dispatcher**

Modify `AgentTaskService.php`. Add:

```php
public function applyTaskCardOperation(
    string $actor,
    string $taskId,
    string $workspaceId,
    string $agentSessionId,
    string $operation,
    array $payload,
    array $policy,
): array {
    $context = $this->taskContext($actor, $taskId);
    if ($context === null) {
        throw new InvalidArgumentException('Карточка задачи не найдена.');
    }

    return match ($operation) {
        'read' => $this->snapshot($context, $workspaceId, $agentSessionId),
        'comment' => $this->addTaskCardComment($context, $actor, $workspaceId, $agentSessionId, $payload),
        'question' => $this->askTaskCardQuestion($context, $actor, $workspaceId, $agentSessionId, $payload),
        'checklist' => $this->createTaskCardChecklist($context, $actor, $workspaceId, $agentSessionId, $payload),
        'checklist_item' => $this->updateTaskCardChecklistItem($context, $actor, $workspaceId, $agentSessionId, $payload),
        'attachment' => $this->addTaskCardAttachment($context, $actor, $workspaceId, $agentSessionId, $payload),
        'status' => $this->setTaskCardStatus($context, $actor, $workspaceId, $agentSessionId, $payload, $policy),
        'finish' => $this->finishTaskCardRun($context, $actor, $workspaceId, $agentSessionId, $payload, $policy),
        default => throw new InvalidArgumentException('Неизвестная операция карточки.'),
    };
}
```

Implement helpers with these exact behaviors:

- `snapshot` returns `task`, `workspace`, `comments`, `checklists`, `questions`, `attachments`, `activity`, `agent_sessions`, `agent_session`.
- `askTaskCardQuestion` appends question with `status=open`, updates matching agent session status to `blocked`, appends activity `agent_question_added`.
- `addTaskCardComment` appends comment with `author_profile=agent`.
- `createTaskCardChecklist` appends checklist and items.
- `updateTaskCardChecklistItem` marks a known item done/undone; throws if ids are missing.
- `addTaskCardAttachment` accepts `filename`, `mime_type`, `data_base64`, `path`, `caption`; appends attachment.
- `setTaskCardStatus` rejects `done` and `archive` unless policy mode is `yolo` or actor is superadmin.
- `finishTaskCardRun` appends summary comment and moves `ready_for_review` to `in_review`.

- [ ] **Step 6: Run backend tests**

Run:

```powershell
cd laravel_backend_vps
php artisan test --filter AgentTaskCardRuntimeTest
```

Expected: PASS.

- [ ] **Step 7: Commit**

```powershell
git add laravel_backend_vps/app/Domain/Agent/AgentTaskService.php laravel_backend_vps/app/Http/Controllers/AgentPolicyController.php laravel_backend_vps/routes/api.php laravel_backend_vps/tests/Feature/AgentTaskCardRuntimeTest.php
git commit -m "feat: add backend task card operations"
```

---

## Task 3: Python CLI `family-task-card`

**Files:**
- Create: `family_task_card_cli.py`
- Test: `tests/test_family_task_card_cli.py`

- [ ] **Step 1: Write failing CLI tests**

Create `tests/test_family_task_card_cli.py`:

```python
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

        env = {
            "FAMILY_TASK_CARD_API_URL": "https://api.example.test",
            "FAMILY_TASK_CARD_TICKET": "ticket-1",
            "FAMILY_TASK_CARD_TASK_ID": "task-1",
            "FAMILY_TASK_CARD_WORKSPACE_ID": "weather",
            "FAMILY_TASK_CARD_SESSION_ID": "agent-session-1",
            "FAMILY_TASK_CARD_ACTOR_PROFILE": "Nikita",
            "FAMILY_TASK_CARD_ACTOR_PHONE": "+79679812438",
        }

        code = cli.run(
            ["status", "set", "in_review", "--reason", "Готово"],
            env=env,
            post_json=fake_post,
        )

        self.assertEqual(code, 0)
        self.assertEqual(sent["url"], "https://api.example.test/agent/task-card/status")
        self.assertEqual(sent["payload"]["status"], "in_review")
        self.assertEqual(sent["payload"]["policy_ticket"], "ticket-1")

    def test_attachment_rejects_path_outside_workspace(self):
        with tempfile.TemporaryDirectory() as tmp:
            outside = Path(tmp).parent / "secret.txt"
            outside.write_text("secret", encoding="utf-8")
            env = self._env(tmp)

            code = cli.run(
                ["attachment", "add-from-workspace", "--path", str(outside)],
                env=env,
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
                env=self._env(tmp),
                post_json=fake_post,
            )

        self.assertEqual(code, 0)
        self.assertEqual(sent["payload"]["filename"], "result.md")
        self.assertEqual(sent["payload"]["caption"], "Отчет")
        self.assertEqual(sent["payload"]["data_base64"], base64.b64encode(b"report").decode("ascii"))

    def _env(self, cwd):
        return {
            "FAMILY_TASK_CARD_API_URL": "https://api.example.test",
            "FAMILY_TASK_CARD_TICKET": "ticket-1",
            "FAMILY_TASK_CARD_TASK_ID": "task-1",
            "FAMILY_TASK_CARD_WORKSPACE_ID": "weather",
            "FAMILY_TASK_CARD_SESSION_ID": "agent-session-1",
            "FAMILY_TASK_CARD_ACTOR_PROFILE": "Nikita",
            "FAMILY_TASK_CARD_ACTOR_PHONE": "+79679812438",
    "FAMILY_TASK_CARD_WORKSPACE_PATH": str(cwd),
    "FAMILY_TASK_CARD_API_KEY": "dev-local-key",
        }
```

- [ ] **Step 2: Run test and verify failure**

Run:

```powershell
python -m pytest tests/test_family_task_card_cli.py -q
```

Expected: FAIL because `family_task_card_cli.py` does not exist.

- [ ] **Step 3: Implement CLI**

Create `family_task_card_cli.py` with:

```python
from __future__ import annotations

import argparse
import base64
import json
import mimetypes
import os
import sys
import urllib.request
from pathlib import Path
from typing import Any, Callable


PostJson = Callable[[str, dict[str, Any]], dict[str, Any]]


def run(
    argv: list[str] | None = None,
    *,
    env: dict[str, str] | None = None,
    post_json: PostJson | None = None,
) -> int:
    env_map = env if env is not None else os.environ
    args = _parser().parse_args(argv)
    payload = _base_payload(env_map)
    endpoint = ""

    if args.command == "read":
        endpoint = "read"
    elif args.command == "refresh":
        endpoint = "refresh"
    elif args.command == "comment" and args.comment_action == "add":
        endpoint = "comment"
        payload["text"] = args.text
    elif args.command == "question" and args.question_action == "ask":
        endpoint = "question"
        payload["text"] = args.text
        payload["blocking"] = bool(args.blocking)
    elif args.command == "status" and args.status_action == "set":
        endpoint = "status"
        payload["status"] = args.status
        payload["reason"] = args.reason
    elif args.command == "finish":
        endpoint = "finish"
        payload["summary"] = args.summary
        payload["result_status"] = args.result_status
    elif args.command == "attachment" and args.attachment_action == "add-from-workspace":
        endpoint = "attachment"
        try:
            payload.update(_attachment_payload(args.path, args.caption, env_map))
        except ValueError as exc:
            print(str(exc), file=sys.stderr)
            return 2
    else:
        print("Неизвестная команда family-task-card", file=sys.stderr)
        return 2

    poster = post_json or _post_json
    try:
        response = poster(_url(env_map, endpoint), payload)
    except Exception as exc:
        print(f"Ошибка операции карточки: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(response, ensure_ascii=False, indent=2))
    return 0 if response.get("ok") is True else 1


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="family-task-card")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("read")
    sub.add_parser("refresh")

    comment = sub.add_parser("comment").add_subparsers(dest="comment_action", required=True)
    comment_add = comment.add_parser("add")
    comment_add.add_argument("--text", required=True)

    question = sub.add_parser("question").add_subparsers(dest="question_action", required=True)
    question_ask = question.add_parser("ask")
    question_ask.add_argument("--text", required=True)
    question_ask.add_argument("--blocking", action="store_true")

    attachment = sub.add_parser("attachment").add_subparsers(dest="attachment_action", required=True)
    attachment_add = attachment.add_parser("add-from-workspace")
    attachment_add.add_argument("--path", required=True)
    attachment_add.add_argument("--caption", default="")

    status = sub.add_parser("status").add_subparsers(dest="status_action", required=True)
    status_set = status.add_parser("set")
    status_set.add_argument("status")
    status_set.add_argument("--reason", default="")

    finish = sub.add_parser("finish")
    finish.add_argument("--summary", required=True)
    finish.add_argument("--result-status", default="ready_for_review")
    return parser


def _base_payload(env: dict[str, str]) -> dict[str, Any]:
    return {
        "policy_ticket": env.get("FAMILY_TASK_CARD_TICKET", ""),
        "actor_profile": env.get("FAMILY_TASK_CARD_ACTOR_PROFILE", ""),
        "actor_phone": env.get("FAMILY_TASK_CARD_ACTOR_PHONE", ""),
        "task_id": env.get("FAMILY_TASK_CARD_TASK_ID", ""),
        "workspace_id": env.get("FAMILY_TASK_CARD_WORKSPACE_ID", ""),
        "agent_session_id": env.get("FAMILY_TASK_CARD_SESSION_ID", ""),
        "task_type": env.get("FAMILY_TASK_CARD_TASK_TYPE", "feature"),
        "requested_mode": env.get("FAMILY_TASK_CARD_MODE", "executor"),
    }


def _attachment_payload(path: str, caption: str, env: dict[str, str]) -> dict[str, Any]:
    base = Path(env.get("FAMILY_TASK_CARD_WORKSPACE_PATH") or os.getcwd()).resolve()
    target = (base / path).resolve()
    if not str(target).startswith(str(base)):
        raise ValueError("Файл находится вне рабочего пространства.")
    if not target.exists() or not target.is_file():
        raise ValueError(f"Файл не найден в рабочем пространстве: {path}")
    raw = target.read_bytes()
    return {
        "path": str(Path(path).as_posix()),
        "filename": target.name,
        "caption": caption,
        "mime_type": mimetypes.guess_type(target.name)[0] or "application/octet-stream",
        "data_base64": base64.b64encode(raw).decode("ascii"),
        "size_bytes": len(raw),
    }


def _url(env: dict[str, str], endpoint: str) -> str:
    base = env.get("FAMILY_TASK_CARD_API_URL", "").rstrip("/")
    return f"{base}/agent/task-card/{endpoint}"


def _post_json(url: str, payload: dict[str, Any]) -> dict[str, Any]:
    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json", "X-Api-Key": os.environ.get("FAMILY_TASK_CARD_API_KEY", "dev-local-key")},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode("utf-8", "replace"))


if __name__ == "__main__":
    raise SystemExit(run())
```

- [ ] **Step 4: Run CLI tests**

Run:

```powershell
python -m pytest tests/test_family_task_card_cli.py -q
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add family_task_card_cli.py tests/test_family_task_card_cli.py
git commit -m "feat: add family task card cli"
```

---

## Task 4: Bridge Injects Task Card Runtime Into Agent Worker

**Files:**
- Modify: `codewhale_bridge.py`
- Modify: `tests/test_codewhale_bridge.py`

- [ ] **Step 1: Write failing bridge test**

Append to `tests/test_codewhale_bridge.py`:

```python
def test_session_create_stores_task_card_runtime_metadata(self) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        server = self._server(tmp)
        workspace = server.workspaces.create_workspace("weather")
        reply = server.handle_message({
            "type": "session_create",
            "workspace_id": workspace["id"],
            "title": "Агент",
            "task_card": {
                "task_id": "task-1",
                "agent_session_id": "agent-session-1",
                "actor_profile": "Nikita",
                "actor_phone": "+79679812438",
                "api_url": "https://api.example.test",
                "policy_ticket": "ticket-1",
                "task_type": "feature",
                "mode": "executor",
            },
        })

        session = reply["session"]
        self.assertEqual(session["task_card"]["task_id"], "task-1")
        self.assertEqual(session["task_card"]["policy_ticket"], "ticket-1")
```

- [ ] **Step 2: Run test and verify failure**

Run:

```powershell
python -m pytest tests/test_codewhale_bridge.py -q
```

Expected: FAIL because `task_card` is not stored.

- [ ] **Step 3: Store task-card metadata in session**

Modify `SessionRegistry.create_session` to accept `task_card: dict[str, Any] | None = None`.

Add default session key:

```python
"task_card": dict(task_card or {}),
```

Modify `CodeWhaleBridgeServer._handle_message` for `session_create`:

```python
session = self.sessions.create_session(
    str(workspace["id"]),
    str(message.get("title") or ""),
    task_card=self._task_card_metadata(message),
)
```

Add helper:

```python
def _task_card_metadata(self, message: dict[str, Any]) -> dict[str, str]:
    raw = message.get("task_card")
    if not isinstance(raw, dict):
        return {}
    allowed = [
        "task_id",
        "agent_session_id",
        "actor_profile",
        "actor_phone",
        "api_url",
        "policy_ticket",
        "task_type",
        "mode",
    ]
    return {key: str(raw.get(key) or "").strip() for key in allowed}
```

- [ ] **Step 4: Inject env and command shim into worker**

Modify `CodeWhaleWorkerManager.start_worker`:

```python
session = self.sessions.get_session(workspace_id, session_id)
task_card = session.get("task_card") if isinstance(session.get("task_card"), dict) else {}
tool_dir = self._materialize_task_card_tool(workspace, task_card)
if tool_dir is not None:
    env["PATH"] = f"{tool_dir}{os.pathsep}{env.get('PATH', '')}"
    env.update(self._task_card_env(workspace, task_card))
```

Add helpers:

```python
def _materialize_task_card_tool(self, workspace: Path, task_card: dict[str, Any]) -> Path | None:
    if not task_card:
        return None
    tool_dir = workspace / ".family-task-card"
    tool_dir.mkdir(exist_ok=True)
    repo_cli = Path(__file__).resolve().parent / "family_task_card_cli.py"
    cmd = tool_dir / "family-task-card.cmd"
    cmd.write_text(f'@echo off\r\npython "{repo_cli}" %*\r\n', encoding="utf-8")
    ps1 = tool_dir / "family-task-card.ps1"
    ps1.write_text(f'python "{repo_cli}" @args\r\n', encoding="utf-8")
    return tool_dir

def _task_card_env(self, workspace: Path, task_card: dict[str, Any]) -> dict[str, str]:
    return {
        "FAMILY_TASK_CARD_API_URL": str(task_card.get("api_url") or ""),
        "FAMILY_TASK_CARD_TICKET": str(task_card.get("policy_ticket") or ""),
        "FAMILY_TASK_CARD_TASK_ID": str(task_card.get("task_id") or ""),
        "FAMILY_TASK_CARD_WORKSPACE_ID": str(task_card.get("workspace_id") or ""),
        "FAMILY_TASK_CARD_SESSION_ID": str(task_card.get("agent_session_id") or ""),
        "FAMILY_TASK_CARD_ACTOR_PROFILE": str(task_card.get("actor_profile") or ""),
        "FAMILY_TASK_CARD_ACTOR_PHONE": str(task_card.get("actor_phone") or ""),
        "FAMILY_TASK_CARD_TASK_TYPE": str(task_card.get("task_type") or "feature"),
        "FAMILY_TASK_CARD_MODE": str(task_card.get("mode") or "executor"),
        "FAMILY_TASK_CARD_WORKSPACE_PATH": str(workspace),
    }
```

- [ ] **Step 5: Add built-in family-task-card skill command**

Modify `_codewhale_command_catalog` or `_list_skill_commands` so command list always includes:

```python
{
    "label": "Family Task Card",
    "value": "/skill family-task-card",
    "group": "Навыки",
    "description": "читать и обновлять карточку задачи через family-task-card",
}
```

- [ ] **Step 6: Run bridge tests**

Run:

```powershell
python -m pytest tests/test_codewhale_bridge.py tests/test_family_task_card_cli.py -q
```

Expected: PASS.

- [ ] **Step 7: Commit**

```powershell
git add codewhale_bridge.py tests/test_codewhale_bridge.py
git commit -m "feat: inject task card tool into bridge workers"
```

---

## Task 5: Mobile Sends Task Card Runtime Metadata

**Files:**
- Modify: `mobile_app/lib/services/codewhale_bridge_service.dart`
- Modify: `mobile_app/lib/features/tasks/task_editor_sheet.dart`
- Modify: `mobile_app/test/codewhale_bridge_service_test.dart`
- Modify: `mobile_app/test/task_editor_sheet_test.dart`

- [ ] **Step 1: Write failing service test**

Modify `mobile_app/test/codewhale_bridge_service_test.dart`:

```dart
test('createSession sends task card runtime metadata', () async {
  final socket = _FakeSocket();
  final service = CodeWhaleBridgeService(
    onMessage: (_) {},
    onStatusChange: (_, __) {},
    socketFactory: (_) async => socket,
  );

  await service.connect();
  service.createSession(
    'weather',
    title: 'Агент',
    taskCard: const {
      'task_id': 'task-1',
      'agent_session_id': 'agent-session-1',
      'policy_ticket': 'ticket-1',
    },
  );

  final sent = jsonDecode(socket.sentLines.last) as Map<String, dynamic>;
  expect(sent['task_card']['task_id'], 'task-1');
  expect(sent['task_card']['policy_ticket'], 'ticket-1');
});
```

- [ ] **Step 2: Run test and verify failure**

Run:

```powershell
cd mobile_app
& 'C:\Users\user\.puro\envs\stable\flutter\bin\flutter.bat' test test/codewhale_bridge_service_test.dart
```

Expected: FAIL because `createSession` has no `taskCard`.

- [ ] **Step 3: Extend `createSession`**

Modify `mobile_app/lib/services/codewhale_bridge_service.dart`:

```dart
void createSession(
  String workspaceId, {
  String title = '',
  Map<String, dynamic> taskCard = const {},
}) {
  _sendCommand({
    'type': 'session_create',
    'workspace_id': workspaceId,
    'title': title,
    if (taskCard.isNotEmpty) 'task_card': taskCard,
  });
}
```

- [ ] **Step 4: Send metadata from task editor**

Modify `_startNewAgentChat` in `task_editor_sheet.dart`.

Replace:

```dart
bridge.createSession(workspaceId, title: title);
```

With:

```dart
bridge.createSession(
  workspaceId,
  title: title,
  taskCard: {
    'task_id': saved.id,
    'agent_session_id': session.id,
    'actor_profile': widget.store.owner.value,
    'actor_phone': widget.actorPhone,
    'api_url': widget.store.repository.api.baseUrl,
    'policy_ticket': ticket.policyTicket,
    'task_type': _taskTypeForAgent(saved),
    'mode': policy.mode,
  },
);
```

If `api.baseUrl` is private, add a read-only getter to `ApiClient`:

```dart
String get publicBaseUrl => baseUrl;
```

Use `publicBaseUrl` in task editor.

- [ ] **Step 5: Update fake bridge and widget test**

Modify `_FakeAgentBridge.createSession` in `task_editor_sheet_test.dart` to capture taskCard metadata.

Add expectations:

```dart
expect(bridge!.lastTaskCard['task_id'], _editableTask.id);
expect(bridge!.lastTaskCard['agent_session_id'], isNotEmpty);
expect(bridge!.lastTaskCard['policy_ticket'], 'test-policy-ticket');
```

- [ ] **Step 6: Run focused Flutter tests**

Run:

```powershell
cd mobile_app
& 'C:\Users\user\.puro\envs\stable\flutter\bin\flutter.bat' test test/codewhale_bridge_service_test.dart test/task_editor_sheet_test.dart --concurrency=1
```

Expected: PASS.

- [ ] **Step 7: Commit**

```powershell
git add mobile_app/lib/services/codewhale_bridge_service.dart mobile_app/lib/features/tasks/task_editor_sheet.dart mobile_app/test/codewhale_bridge_service_test.dart mobile_app/test/task_editor_sheet_test.dart
git commit -m "feat: send task card runtime metadata to bridge"
```

---

## Task 6: Mandatory Agent Launch Contract

**Files:**
- Modify: `mobile_app/lib/features/tasks/agent_launch_plan.dart`
- Modify: `mobile_app/test/agent_launch_plan_test.dart`

- [ ] **Step 1: Write failing launch plan test**

Modify `mobile_app/test/agent_launch_plan_test.dart`:

```dart
test('AgentLaunchPlan always starts with family task card skill and read', () {
  final plan = AgentLaunchPlan.build(
    contextPrompt: 'Контекст задачи',
    selectedCommandValues: const ['/skill tdd'],
    commands: const [
      {'label': 'TDD', 'value': '/skill tdd'},
    ],
  );

  expect(plan.steps[0].text, '/skill family-task-card');
  expect(plan.steps[1].text, contains('family-task-card read'));
  expect(plan.steps[2].text, '/skill tdd');
});
```

- [ ] **Step 2: Run test and verify failure**

Run:

```powershell
cd mobile_app
& 'C:\Users\user\.puro\envs\stable\flutter\bin\flutter.bat' test test/agent_launch_plan_test.dart
```

Expected: FAIL because current first step is app context.

- [ ] **Step 3: Change launch plan ordering**

Modify `AgentLaunchPlan.build`:

```dart
final steps = <AgentLaunchStep>[
  const AgentLaunchStep(
    label: 'Карточка задачи',
    text: '/skill family-task-card',
    kind: AgentLaunchStepKind.command,
  ),
  const AgentLaunchStep(
    label: 'Чтение карточки',
    text: 'Выполни команду family-task-card read. Если команда недоступна или вернула ошибку, остановись и напиши, что карточка задачи недоступна.',
    kind: AgentLaunchStepKind.taskCardRead,
  ),
];
```

Add enum value:

```dart
enum AgentLaunchStepKind { command, taskCardRead, appContext, taskPrompt }
```

Keep selected plugins after mandatory read. Keep task prompt after selected plugins.

- [ ] **Step 4: Make fallback visibly secondary**

Change task prompt text:

```dart
'Основной способ обновления карточки - команда family-task-card. TASK_CARD_ACTIONS_JSON разрешен только если команда family-task-card недоступна.',
```

- [ ] **Step 5: Run launch plan tests**

Run:

```powershell
cd mobile_app
& 'C:\Users\user\.puro\envs\stable\flutter\bin\flutter.bat' test test/agent_launch_plan_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add mobile_app/lib/features/tasks/agent_launch_plan.dart mobile_app/test/agent_launch_plan_test.dart
git commit -m "feat: require task card tool in agent launch plan"
```

---

## Task 7: Mobile Displays Agent Questions and Protocol State

**Files:**
- Modify: `mobile_app/lib/features/tasks/task_editor_sheet.dart`
- Modify: `mobile_app/test/task_editor_sheet_test.dart`

- [ ] **Step 1: Write failing widget test for visible agent question**

Modify `mobile_app/test/task_editor_sheet_test.dart`:

```dart
testWidgets('showTaskEditorSheet displays open agent questions', (tester) async {
  final task = _editableTask.copyWith(
    collaboration: const TaskCollaboration(
      questions: [
        TaskAgentQuestion(
          id: 'question-1',
          text: 'Нужен макет формы?',
          status: 'open',
          createdAt: '2026-06-05T10:00:00Z',
          blocking: true,
        ),
      ],
    ),
  );
  final repository = _FakeTaskRepository();
  repository.tasks.add(task);
  final store = _FakeTaskStore(repository);

  await tester.pumpWidget(MaterialApp(
    home: TaskEditorScreen(
      store: store,
      knownContacts: const [],
      contactLabel: (c) => c.displayName,
      dateKey: (d) => d.toIso8601String(),
      onSaved: () async {},
      existing: task,
    ),
  ));

  await tester.tap(find.text('Агент'));
  await tester.pumpAndSettle();

  expect(find.text('Вопросы агента'), findsOneWidget);
  expect(find.text('Нужен макет формы?'), findsOneWidget);
});
```

- [ ] **Step 2: Run test and verify failure**

Run:

```powershell
cd mobile_app
& 'C:\Users\user\.puro\envs\stable\flutter\bin\flutter.bat' test test/task_editor_sheet_test.dart --plain-name "displays open agent questions"
```

Expected: FAIL because UI does not render questions.

- [ ] **Step 3: Render questions in Agent tab**

In `task_editor_sheet.dart`, inside Agent tab content, add:

```dart
final openQuestions = _collaboration.questions.where((item) => item.isOpen).toList();
if (openQuestions.isNotEmpty) ...[
  const SizedBox(height: 16),
  Text(
    'Вопросы агента',
    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
  ),
  const SizedBox(height: 8),
  ...openQuestions.map((question) => _AgentQuestionTile(question: question)),
],
```

Add `_AgentQuestionTile` widget near other small task editor widgets:

```dart
class _AgentQuestionTile extends StatelessWidget {
  const _AgentQuestionTile({required this.question});

  final TaskAgentQuestion question;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withOpacity(0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.error.withOpacity(0.25)),
      ),
      child: Text(question.text),
    );
  }
}
```

- [ ] **Step 4: Run focused widget test**

Run:

```powershell
cd mobile_app
& 'C:\Users\user\.puro\envs\stable\flutter\bin\flutter.bat' test test/task_editor_sheet_test.dart --plain-name "displays open agent questions"
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add mobile_app/lib/features/tasks/task_editor_sheet.dart mobile_app/test/task_editor_sheet_test.dart
git commit -m "feat: show agent questions in task cards"
```

---

## Task 8: Verification and Release

**Files:**
- All changed files from Tasks 1-7.

- [ ] **Step 1: Run full Python tests**

Run:

```powershell
python -m pytest -q
```

Expected: PASS or known skips only.

- [ ] **Step 2: Run Laravel agent tests**

Run:

```powershell
cd laravel_backend_vps
php artisan test --filter Agent
```

Expected: PASS.

- [ ] **Step 3: Run Flutter analyze**

Run:

```powershell
cd mobile_app
& 'C:\Users\user\.puro\envs\stable\flutter\bin\flutter.bat' analyze
```

Expected: `No issues found!`

- [ ] **Step 4: Run full Flutter suite**

Run:

```powershell
cd mobile_app
& 'C:\Users\user\.puro\envs\stable\flutter\bin\flutter.bat' test --concurrency=1
```

Expected: all tests pass.

- [ ] **Step 5: Check diff**

Run:

```powershell
git diff --check
git status --short
```

Expected: no whitespace errors; only expected files changed before final commit.

- [ ] **Step 6: Final commit if any changes remain**

```powershell
git add -A
git commit -m "feat: connect agents to task cards through tools"
```

- [ ] **Step 7: Push**

```powershell
git push origin master
```

- [ ] **Step 8: Check GitHub Actions**

Use GitHub API for the pushed SHA. Expected workflows:

- `Tests: completed: success`;
- `Mobile APK Build: completed: success`.

- [ ] **Step 9: Confirm APK release**

Expected:

- tag `latest` points to final commit;
- release asset `family-todo-release.apk` is updated.

---

## Self-Review Checklist

- Spec coverage:
  - Backend operations covered by Tasks 1-2.
  - CLI covered by Task 3.
  - Bridge injection covered by Task 4.
  - Mobile metadata and launch contract covered by Tasks 5-6.
  - Agent questions UI covered by Task 7.
  - Full verification covered by Task 8.
- Placeholder scan:
  - No placeholder markers.
  - No unscoped "add tests".
  - Each task has concrete commands and expected result.
- Type consistency:
  - `TaskAgentQuestion` uses `questions` in collaboration JSON.
  - CLI env names match bridge plan.
  - Mobile task-card metadata keys match bridge metadata keys.
