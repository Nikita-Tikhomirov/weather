<?php

namespace App\Domain\Agent;

use App\Domain\Sync\SyncRepository;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use InvalidArgumentException;

final class AgentTaskService
{
    public function __construct(private readonly SyncRepository $repo)
    {
    }

    /** @return array<string, mixed> */
    public function buildContextPack(string $actor, string $taskId, string $workspaceId): array
    {
        $context = $this->requireTaskContext($actor, $taskId);
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
            'activity' => array_values(is_array($collaboration['activity'] ?? null) ? $collaboration['activity'] : []),
            'agent_sessions' => array_values(is_array($collaboration['agent_sessions'] ?? null) ? $collaboration['agent_sessions'] : []),
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
        $context = $this->requireTaskContext($actor, $taskId);
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

        $this->appendAgentSessionToTask($context, $session, $actor);
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
        $context = $this->requireTaskContext($actor, $taskId);
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

        $this->appendAgentEventToTask($context, $event, $actor);
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

    /** @return array<string, mixed> */
    private function requireTaskContext(string $actor, string $taskId): array
    {
        $context = $this->repo->contextTask($taskId, $actor);
        if ($context === null) {
            throw new InvalidArgumentException('Task not found');
        }
        return $context;
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
                'activity' => [],
                'agent_sessions' => [],
            ];
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
