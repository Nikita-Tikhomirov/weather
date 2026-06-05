<?php

namespace App\Domain\Agent;

use App\Domain\Sync\SyncRepository;
use InvalidArgumentException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

final class AgentTaskService
{
    public function __construct(private readonly SyncRepository $repo)
    {
    }

    /** @return array<string, mixed> */
    public function buildContextPack(string $actor, string $taskId, string $workspaceId): array
    {
        $context = $this->taskContext($actor, $taskId) ?? $this->placeholderContext($taskId);
        $collaboration = $this->collaboration($context);

        return [
            'task' => [
                'id' => (string)($context['id'] ?? ''),
                'title' => (string)($context['title'] ?? ''),
                'details' => (string)($context['details'] ?? ''),
                'due_date' => (string)($context['due_date'] ?? ''),
                'time' => (string)($context['time'] ?? ''),
                'workflow_status' => (string)($context['workflow_status'] ?? 'todo'),
                'priority' => (string)($context['priority'] ?? 'medium'),
                'project_id' => (string)($context['project_id'] ?? ''),
                'group_id' => (string)($context['group_id'] ?? ''),
                'participants' => array_values(is_array($context['participants'] ?? null) ? $context['participants'] : []),
            ],
            'workspace' => [
                'id' => trim($workspaceId),
            ],
            'comments' => array_values(is_array($collaboration['comments'] ?? null) ? $collaboration['comments'] : []),
            'checklists' => array_values(is_array($collaboration['checklists'] ?? null) ? $collaboration['checklists'] : []),
            'attachments' => array_values(is_array($collaboration['attachments'] ?? null) ? $collaboration['attachments'] : []),
            'questions' => array_values(is_array($collaboration['questions'] ?? null) ? $collaboration['questions'] : []),
            'activity' => array_values(is_array($collaboration['activity'] ?? null) ? $collaboration['activity'] : []),
            'agent_sessions' => array_values(is_array($collaboration['agent_sessions'] ?? null) ? $collaboration['agent_sessions'] : []),
        ];
    }

    /**
     * @param array<string, mixed> $payload
     * @param array<string, mixed> $policy
     * @return array<string, mixed>
     */
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

    /** @param array<string, mixed> $context @return array<string, mixed> */
    public function snapshot(array $context, string $workspaceId, string $agentSessionId): array
    {
        $collaboration = $this->collaboration($context);
        return [
            'task' => [
                'id' => (string)($context['id'] ?? ''),
                'title' => (string)($context['title'] ?? ''),
                'details' => (string)($context['details'] ?? ''),
                'workflow_status' => (string)($context['workflow_status'] ?? 'todo'),
                'priority' => (string)($context['priority'] ?? 'medium'),
                'project_id' => (string)($context['project_id'] ?? ''),
                'group_id' => (string)($context['group_id'] ?? ''),
                'due_date' => (string)($context['due_date'] ?? ''),
                'version' => (int)($context['version'] ?? 1),
            ],
            'workspace' => ['id' => trim($workspaceId)],
            'comments' => array_values(is_array($collaboration['comments'] ?? null) ? $collaboration['comments'] : []),
            'checklists' => array_values(is_array($collaboration['checklists'] ?? null) ? $collaboration['checklists'] : []),
            'attachments' => array_values(is_array($collaboration['attachments'] ?? null) ? $collaboration['attachments'] : []),
            'questions' => array_values(is_array($collaboration['questions'] ?? null) ? $collaboration['questions'] : []),
            'activity' => array_values(is_array($collaboration['activity'] ?? null) ? $collaboration['activity'] : []),
            'agent_sessions' => array_values(is_array($collaboration['agent_sessions'] ?? null) ? $collaboration['agent_sessions'] : []),
            'agent_session' => $this->agentSessionSnapshot($collaboration, $agentSessionId),
        ];
    }

    /**
     * @param array<string, mixed> $policy
     * @return array<string, mixed>
     */
    public function recordSession(
        string $actor,
        string $taskId,
        string $workspaceId,
        string $agentSessionId,
        string $sessionId,
        string $mode,
        string $status,
        string $title,
        array $policy = [],
    ): array {
        $context = $this->taskContext($actor, $taskId);
        $now = $this->repo->nowIso();
        $id = $agentSessionId !== '' ? $agentSessionId : $this->newId('agent-session');
        $session = [
            'id' => $id,
            'workspace_id' => trim($workspaceId),
            'session_id' => trim($sessionId),
            'title' => trim($title) !== '' ? trim($title) : 'Агентский чат',
            'mode' => trim($mode) !== '' ? trim($mode) : 'chat',
            'status' => trim($status) !== '' ? trim($status) : 'pending',
            'created_by' => trim($actor),
            'created_at' => $now,
        ];

        if (Schema::hasTable('task_agent_sessions')) {
            DB::table('task_agent_sessions')->updateOrInsert(
                ['id' => $id],
                [
                    'task_id' => (string)($context['id'] ?? $taskId),
                    'workspace_id' => $session['workspace_id'],
                    'session_id' => $session['session_id'],
                    'actor_profile' => trim($actor),
                    'mode' => $session['mode'],
                    'status' => $session['status'],
                    'title' => $session['title'],
                    'policy_json' => json_encode($policy, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
                    'created_at' => $now,
                    'updated_at' => $now,
                ],
            );
        }

        if ($context !== null) {
            $this->appendAgentSessionToTask($context, $session, $actor);
        }
        return $session;
    }

    /**
     * @param array<string, mixed> $payload
     * @return array<string, mixed>
     */
    public function recordEvent(
        string $actor,
        string $taskId,
        string $workspaceId,
        string $agentSessionId,
        string $eventType,
        array $payload,
    ): array {
        $context = $this->taskContext($actor, $taskId);
        $now = $this->repo->nowIso();
        $event = [
            'id' => $this->newId('agent-event'),
            'task_id' => (string)($context['id'] ?? $taskId),
            'agent_session_id' => trim($agentSessionId),
            'workspace_id' => trim($workspaceId),
            'type' => trim($eventType) !== '' ? trim($eventType) : 'agent_event',
            'actor_profile' => trim($actor),
            'payload' => $payload,
            'created_at' => $now,
        ];

        if (Schema::hasTable('task_agent_events')) {
            DB::table('task_agent_events')->insert([
                'id' => $event['id'],
                'task_id' => $event['task_id'],
                'agent_session_id' => $event['agent_session_id'],
                'workspace_id' => $event['workspace_id'],
                'type' => $event['type'],
                'actor_profile' => $event['actor_profile'],
                'payload_json' => json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
                'created_at' => $now,
            ]);
        }

        if ($context !== null) {
            $this->appendAgentEventToTask($context, $event, $actor);
        }
        return $event;
    }

    /** @param array<string, mixed> $session */
    public function appendAgentSessionToTask(array $context, array $session, string $actor): void
    {
        $collaboration = $this->collaboration($context);
        $sessions = array_values(is_array($collaboration['agent_sessions'] ?? null) ? $collaboration['agent_sessions'] : []);
        $replaced = false;
        foreach ($sessions as $index => $existing) {
            if (is_array($existing) && (string)($existing['id'] ?? '') === (string)($session['id'] ?? '')) {
                $sessions[$index] = array_merge($existing, $session);
                $replaced = true;
                break;
            }
        }
        if (!$replaced) {
            $sessions[] = $session;
        }

        $now = $this->repo->nowIso();
        $activity = array_values(is_array($collaboration['activity'] ?? null) ? $collaboration['activity'] : []);
        $activity[] = [
            'id' => $this->newId('activity'),
            'type' => 'agent_session_recorded',
            'actor_profile' => trim($actor),
            'text' => 'подключил агентский чат',
            'created_at' => $now,
            'target_id' => (string)($session['id'] ?? ''),
        ];

        $collaboration['agent_sessions'] = $sessions;
        $collaboration['activity'] = $activity;
        $workflow = ((string)($context['workflow_status'] ?? 'todo')) === 'todo' ? 'in_progress' : '';
        $this->repo->updateTaskCollaboration($context, $collaboration, $workflow);
    }

    /** @param array<string, mixed> $event */
    public function appendAgentEventToTask(array $context, array $event, string $actor): void
    {
        $collaboration = $this->collaboration($context);
        $now = $this->repo->nowIso();
        $activity = array_values(is_array($collaboration['activity'] ?? null) ? $collaboration['activity'] : []);
        $activity[] = [
            'id' => $this->newId('activity'),
            'type' => (string)($event['type'] ?? 'agent_event'),
            'actor_profile' => trim($actor),
            'text' => $this->activityText((string)($event['type'] ?? '')),
            'created_at' => $now,
            'target_id' => (string)($event['agent_session_id'] ?? ''),
        ];

        $payload = is_array($event['payload'] ?? null) ? $event['payload'] : [];
        $summary = trim((string)($payload['summary'] ?? $payload['text'] ?? ''));
        if ($summary !== '' && in_array((string)($event['type'] ?? ''), ['agent_summary', 'agent_completed'], true)) {
            $comments = array_values(is_array($collaboration['comments'] ?? null) ? $collaboration['comments'] : []);
            $comments[] = [
                'id' => $this->newId('comment'),
                'author_profile' => trim($actor) !== '' ? trim($actor) : 'agent',
                'text' => $summary,
                'created_at' => $now,
                'attachment_ids' => [],
                'reply_to_comment_id' => '',
                'edited_at' => '',
                'deleted_at' => '',
            ];
            $collaboration['comments'] = $comments;
        }

        $collaboration['activity'] = $activity;
        $this->repo->updateTaskCollaboration($context, $collaboration, $this->workflowForEvent((string)($event['type'] ?? '')));
    }

    /**
     * @param array<string, mixed> $context
     * @param array<string, mixed> $payload
     * @return array<string, mixed>
     */
    public function addTaskCardComment(
        array $context,
        string $actor,
        string $workspaceId,
        string $agentSessionId,
        array $payload,
    ): array {
        $text = trim((string)($payload['text'] ?? ''));
        if ($text === '') {
            throw new InvalidArgumentException('Текст комментария обязателен.');
        }
        $collaboration = $this->collaboration($context);
        $now = $this->repo->nowIso();
        $comments = array_values(is_array($collaboration['comments'] ?? null) ? $collaboration['comments'] : []);
        $comments[] = [
            'id' => $this->newId('comment'),
            'author_profile' => 'agent',
            'text' => $text,
            'created_at' => $now,
            'attachment_ids' => $this->stringList($payload['attachment_ids'] ?? []),
            'reply_to_comment_id' => (string)($payload['reply_to_comment_id'] ?? ''),
            'edited_at' => '',
            'deleted_at' => '',
        ];
        $collaboration['comments'] = $comments;
        $collaboration = $this->appendActivity($collaboration, 'agent_comment_added', 'добавил комментарий', $actor, $agentSessionId);
        $this->repo->updateTaskCollaboration($context, $collaboration);
        $context['collaboration'] = $collaboration;
        return $this->snapshot($context, $workspaceId, $agentSessionId);
    }

    /**
     * @param array<string, mixed> $context
     * @param array<string, mixed> $payload
     * @return array<string, mixed>
     */
    public function askTaskCardQuestion(
        array $context,
        string $actor,
        string $workspaceId,
        string $agentSessionId,
        array $payload,
    ): array {
        $text = trim((string)($payload['text'] ?? ''));
        if ($text === '') {
            throw new InvalidArgumentException('Текст вопроса обязателен.');
        }
        $blocking = $this->boolValue($payload['blocking'] ?? false);
        $collaboration = $this->collaboration($context);
        $now = $this->repo->nowIso();
        $questions = array_values(is_array($collaboration['questions'] ?? null) ? $collaboration['questions'] : []);
        $questions[] = [
            'id' => $this->newId('question'),
            'text' => $text,
            'status' => 'open',
            'created_at' => $now,
            'blocking' => $blocking,
            'answer_text' => '',
            'answered_at' => '',
            'related_checklist_id' => (string)($payload['related_checklist_id'] ?? ''),
            'related_attachment_id' => (string)($payload['related_attachment_id'] ?? ''),
        ];
        $collaboration['questions'] = $questions;
        if ($blocking) {
            $collaboration = $this->upsertAgentSessionStatus($collaboration, $agentSessionId, $workspaceId, 'blocked', $actor);
        }
        $collaboration = $this->appendActivity($collaboration, 'agent_question_added', 'задал вопрос по карточке', $actor, $agentSessionId);
        $this->repo->updateTaskCollaboration($context, $collaboration);
        $context['collaboration'] = $collaboration;
        return $this->snapshot($context, $workspaceId, $agentSessionId);
    }

    /**
     * @param array<string, mixed> $context
     * @param array<string, mixed> $payload
     * @return array<string, mixed>
     */
    public function createTaskCardChecklist(
        array $context,
        string $actor,
        string $workspaceId,
        string $agentSessionId,
        array $payload,
    ): array {
        $title = trim((string)($payload['title'] ?? ''));
        if ($title === '') {
            throw new InvalidArgumentException('Название чеклиста обязательно.');
        }
        $now = $this->repo->nowIso();
        $items = [];
        foreach ($this->stringList($payload['items'] ?? []) as $text) {
            $items[] = [
                'id' => $this->newId('checklist-item'),
                'text' => $text,
                'done' => false,
                'created_by' => 'agent',
                'created_at' => $now,
                'completed_by' => '',
                'completed_at' => '',
            ];
        }
        $collaboration = $this->collaboration($context);
        $checklists = array_values(is_array($collaboration['checklists'] ?? null) ? $collaboration['checklists'] : []);
        $checklists[] = [
            'id' => $this->newId('checklist'),
            'title' => $title,
            'created_by' => 'agent',
            'created_at' => $now,
            'items' => $items,
        ];
        $collaboration['checklists'] = $checklists;
        $collaboration = $this->appendActivity($collaboration, 'agent_checklist_created', 'создал чеклист', $actor, $agentSessionId);
        $this->repo->updateTaskCollaboration($context, $collaboration);
        $context['collaboration'] = $collaboration;
        return $this->snapshot($context, $workspaceId, $agentSessionId);
    }

    /**
     * @param array<string, mixed> $context
     * @param array<string, mixed> $payload
     * @return array<string, mixed>
     */
    public function updateTaskCardChecklistItem(
        array $context,
        string $actor,
        string $workspaceId,
        string $agentSessionId,
        array $payload,
    ): array {
        $checklistId = trim((string)($payload['checklist_id'] ?? ''));
        $itemId = trim((string)($payload['item_id'] ?? ''));
        if ($checklistId === '' || $itemId === '') {
            throw new InvalidArgumentException('Нужны checklist_id и item_id.');
        }
        $collaboration = $this->collaboration($context);
        $checklists = array_values(is_array($collaboration['checklists'] ?? null) ? $collaboration['checklists'] : []);
        $found = false;
        $now = $this->repo->nowIso();
        foreach ($checklists as $checklistIndex => $checklist) {
            if (!is_array($checklist) || (string)($checklist['id'] ?? '') !== $checklistId) {
                continue;
            }
            $items = array_values(is_array($checklist['items'] ?? null) ? $checklist['items'] : []);
            foreach ($items as $itemIndex => $item) {
                if (!is_array($item) || (string)($item['id'] ?? '') !== $itemId) {
                    continue;
                }
                $done = $this->boolValue($payload['done'] ?? true);
                $item['done'] = $done;
                $item['completed_by'] = $done ? 'agent' : '';
                $item['completed_at'] = $done ? $now : '';
                $items[$itemIndex] = $item;
                $found = true;
                break;
            }
            $checklist['items'] = $items;
            $checklists[$checklistIndex] = $checklist;
            break;
        }
        if (!$found) {
            throw new InvalidArgumentException('Пункт чеклиста не найден.');
        }
        $collaboration['checklists'] = $checklists;
        $collaboration = $this->appendActivity($collaboration, 'agent_checklist_updated', 'обновил чеклист', $actor, $agentSessionId);
        $this->repo->updateTaskCollaboration($context, $collaboration);
        $context['collaboration'] = $collaboration;
        return $this->snapshot($context, $workspaceId, $agentSessionId);
    }

    /**
     * @param array<string, mixed> $context
     * @param array<string, mixed> $payload
     * @return array<string, mixed>
     */
    public function addTaskCardAttachment(
        array $context,
        string $actor,
        string $workspaceId,
        string $agentSessionId,
        array $payload,
    ): array {
        $filename = trim((string)($payload['filename'] ?? ''));
        if ($filename === '') {
            $filename = basename((string)($payload['path'] ?? 'agent-file'));
        }
        $mimeType = trim((string)($payload['mime_type'] ?? 'application/octet-stream'));
        $collaboration = $this->collaboration($context);
        $now = $this->repo->nowIso();
        $attachments = array_values(is_array($collaboration['attachments'] ?? null) ? $collaboration['attachments'] : []);
        $attachments[] = [
            'id' => $this->newId('attachment'),
            'kind' => str_starts_with($mimeType, 'image/') ? 'photo' : 'file',
            'filename' => $filename,
            'mime_type' => $mimeType,
            'data_base64' => (string)($payload['data_base64'] ?? ''),
            'asset_url' => (string)($payload['path'] ?? ''),
            'image_meta' => [],
            'caption' => (string)($payload['caption'] ?? ''),
            'author_profile' => 'agent',
            'created_at' => $now,
            'size_bytes' => (int)($payload['size_bytes'] ?? $payload['size'] ?? 0),
        ];
        $collaboration['attachments'] = $attachments;
        $collaboration = $this->appendActivity($collaboration, 'agent_attachment_added', 'прикрепил файл', $actor, $agentSessionId);
        $this->repo->updateTaskCollaboration($context, $collaboration);
        $context['collaboration'] = $collaboration;
        return $this->snapshot($context, $workspaceId, $agentSessionId);
    }

    /**
     * @param array<string, mixed> $context
     * @param array<string, mixed> $payload
     * @param array<string, mixed> $policy
     * @return array<string, mixed>
     */
    public function setTaskCardStatus(
        array $context,
        string $actor,
        string $workspaceId,
        string $agentSessionId,
        array $payload,
        array $policy,
    ): array {
        $status = $this->normalizeStatus((string)($payload['status'] ?? ''));
        if ($status === '') {
            throw new InvalidArgumentException('Некорректный статус карточки.');
        }
        if (in_array($status, ['done', 'archive'], true) && (string)($policy['mode'] ?? '') !== 'yolo') {
            throw new InvalidArgumentException('Агент не может закрыть задачу без подтверждения.');
        }
        $collaboration = $this->appendActivity($this->collaboration($context), 'agent_task_status_changed', 'изменил статус карточки', $actor, $agentSessionId);
        $this->repo->updateTaskCollaboration($context, $collaboration, $status);
        $context['collaboration'] = $collaboration;
        $context['workflow_status'] = $status;
        return $this->snapshot($context, $workspaceId, $agentSessionId);
    }

    /**
     * @param array<string, mixed> $context
     * @param array<string, mixed> $payload
     * @param array<string, mixed> $policy
     * @return array<string, mixed>
     */
    public function finishTaskCardRun(
        array $context,
        string $actor,
        string $workspaceId,
        string $agentSessionId,
        array $payload,
        array $policy,
    ): array {
        $summary = trim((string)($payload['summary'] ?? ''));
        if ($summary === '') {
            throw new InvalidArgumentException('Итог агента обязателен.');
        }
        $resultStatus = trim((string)($payload['result_status'] ?? 'ready_for_review'));
        $collaboration = $this->collaboration($context);
        $now = $this->repo->nowIso();
        $comments = array_values(is_array($collaboration['comments'] ?? null) ? $collaboration['comments'] : []);
        $comments[] = [
            'id' => $this->newId('comment'),
            'author_profile' => 'agent',
            'text' => $summary,
            'created_at' => $now,
            'attachment_ids' => $this->stringList($payload['attachment_ids'] ?? []),
            'reply_to_comment_id' => '',
            'edited_at' => '',
            'deleted_at' => '',
        ];
        $collaboration['comments'] = $comments;
        $sessionStatus = $resultStatus === 'blocked' ? 'blocked' : 'completed';
        $collaboration = $this->upsertAgentSessionStatus($collaboration, $agentSessionId, $workspaceId, $sessionStatus, $actor);
        $collaboration = $this->appendActivity($collaboration, 'agent_completed', 'завершил агентскую работу', $actor, $agentSessionId);
        $workflow = $resultStatus === 'ready_for_review' ? 'in_review' : '';
        $this->repo->updateTaskCollaboration($context, $collaboration, $workflow);
        $context['collaboration'] = $collaboration;
        if ($workflow !== '') {
            $context['workflow_status'] = $workflow;
        }
        return $this->snapshot($context, $workspaceId, $agentSessionId);
    }

    /** @return array<string, mixed> */
    private function taskContext(string $actor, string $taskId): ?array
    {
        return $this->repo->contextTask($taskId, $actor);
    }

    /** @return array<string, mixed> */
    private function placeholderContext(string $taskId): array
    {
        return [
            'id' => trim($taskId),
            'title' => '',
            'details' => '',
            'due_date' => '',
            'time' => '',
            'workflow_status' => 'todo',
            'priority' => 'medium',
            'project_id' => '',
            'group_id' => '',
            'participants' => [],
            'collaboration' => [
                'comments' => [],
                'attachments' => [],
                'checklists' => [],
                'questions' => [],
                'activity' => [],
                'agent_sessions' => [],
            ],
        ];
    }

    /** @param array<string, mixed> $context @return array<string, mixed> */
    private function collaboration(array $context): array
    {
        $value = $context['collaboration'] ?? [];
        return is_array($value)
            ? $value
            : [
                'comments' => [],
                'attachments' => [],
                'checklists' => [],
                'questions' => [],
                'activity' => [],
                'agent_sessions' => [],
            ];
    }

    /** @param array<string, mixed> $collaboration @return array<string, mixed> */
    private function agentSessionSnapshot(array $collaboration, string $agentSessionId): array
    {
        $agentSessionId = trim($agentSessionId);
        $sessions = array_values(is_array($collaboration['agent_sessions'] ?? null) ? $collaboration['agent_sessions'] : []);
        foreach ($sessions as $session) {
            if (is_array($session) && (string)($session['id'] ?? '') === $agentSessionId) {
                return $session;
            }
        }
        if ($agentSessionId === '') {
            return [];
        }
        return [
            'id' => $agentSessionId,
            'workspace_id' => '',
            'session_id' => '',
            'title' => 'Агентский чат',
            'mode' => 'executor',
            'status' => 'linked',
            'created_by' => 'agent',
            'created_at' => $this->repo->nowIso(),
        ];
    }

    /**
     * @param array<string, mixed> $collaboration
     * @return array<string, mixed>
     */
    private function upsertAgentSessionStatus(
        array $collaboration,
        string $agentSessionId,
        string $workspaceId,
        string $status,
        string $actor,
    ): array {
        $agentSessionId = trim($agentSessionId);
        if ($agentSessionId === '') {
            return $collaboration;
        }
        $sessions = array_values(is_array($collaboration['agent_sessions'] ?? null) ? $collaboration['agent_sessions'] : []);
        $now = $this->repo->nowIso();
        $updated = false;
        foreach ($sessions as $index => $session) {
            if (is_array($session) && (string)($session['id'] ?? '') === $agentSessionId) {
                $session['status'] = $status;
                $sessions[$index] = $session;
                $updated = true;
                break;
            }
        }
        if (!$updated) {
            $sessions[] = [
                'id' => $agentSessionId,
                'workspace_id' => trim($workspaceId),
                'session_id' => '',
                'title' => 'Агентский чат',
                'mode' => 'executor',
                'status' => $status,
                'created_by' => trim($actor),
                'created_at' => $now,
            ];
        }
        $collaboration['agent_sessions'] = $sessions;
        return $collaboration;
    }

    /**
     * @param array<string, mixed> $collaboration
     * @return array<string, mixed>
     */
    private function appendActivity(
        array $collaboration,
        string $type,
        string $text,
        string $actor,
        string $targetId,
    ): array {
        $activity = array_values(is_array($collaboration['activity'] ?? null) ? $collaboration['activity'] : []);
        $activity[] = [
            'id' => $this->newId('activity'),
            'type' => $type,
            'actor_profile' => trim($actor),
            'text' => $text,
            'created_at' => $this->repo->nowIso(),
            'target_id' => trim($targetId),
        ];
        $collaboration['activity'] = $activity;
        return $collaboration;
    }

    /** @return array<int, string> */
    private function stringList(mixed $value): array
    {
        if (!is_array($value)) {
            return [];
        }
        return array_values(array_filter(array_map(
            fn(mixed $item): string => trim((string)$item),
            $value,
        ), fn(string $item): bool => $item !== ''));
    }

    private function boolValue(mixed $value): bool
    {
        return $value === true || $value === 1 || $value === '1' || $value === 'true';
    }

    private function normalizeStatus(string $value): string
    {
        $status = trim(strtolower($value));
        return in_array($status, ['todo', 'in_progress', 'in_review', 'done', 'archive'], true)
            ? $status
            : '';
    }

    private function workflowForEvent(string $type): string
    {
        return match ($type) {
            'agent_session_started', 'agent_session_created', 'agent_task_started' => 'in_progress',
            'agent_review_requested' => 'in_review',
            'agent_completed' => 'done',
            default => '',
        };
    }

    private function activityText(string $type): string
    {
        return match ($type) {
            'agent_session_started' => 'запустил агента',
            'agent_session_created' => 'создал агентский чат',
            'agent_task_started' => 'передал задачу агенту',
            'agent_review_requested' => 'передал задачу на проверку',
            'agent_completed' => 'завершил агентскую работу',
            'agent_summary' => 'добавил итог агента',
            default => 'обновил агентский чат',
        };
    }

    private function newId(string $prefix): string
    {
        return $prefix.'-'.str_replace('.', '', uniqid('', true));
    }
}
