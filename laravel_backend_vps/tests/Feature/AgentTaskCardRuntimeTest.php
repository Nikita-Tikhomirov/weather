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

    #[Test]
    public function task_card_question_adds_blocking_question_and_activity(): void
    {
        $this->seedTask(['id' => 'task-card-question']);

        $response = $this->withHeaders(['X-Api-Key' => 'dev-local-key'])
            ->postJson('/agent/task-card/question', [
                ...$this->agentPayloadWithTicket('task-card-question'),
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
                ...$this->agentPayloadWithTicket('task-card-finish'),
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
                ...$this->agentPayloadWithTicket('task-card-status'),
                'agent_session_id' => 'agent-session-1',
                'status' => 'done',
                'reason' => 'Сам закрыл',
            ]);

        $response
            ->assertStatus(403)
            ->assertJsonPath('ok', false);
    }

    /** @param array<string, mixed> $overrides */
    private function seedTask(array $overrides): void
    {
        DB::table('tasks')->insert(array_merge([
            'id' => 'task-card-1',
            'owner_key' => 'Nikita',
            'is_family' => false,
            'title' => 'Задача',
            'details' => '',
            'due_date' => '',
            'time_value' => '',
            'workflow_status' => 'todo',
            'priority' => 'medium',
            'tags_json' => '[]',
            'participants_json' => '[]',
            'collaboration_json' => '{}',
            'duration_minutes' => 0,
            'updated_at' => now()->format('Y-m-d\TH:i:s'),
            'version' => 1,
        ], $overrides));
    }

    /** @return array<string, string> */
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

    /** @return array<string, string> */
    private function agentPayloadWithTicket(string $taskId): array
    {
        $payload = $this->agentPayload($taskId);
        $ticket = $this->withHeaders(['X-Api-Key' => 'dev-local-key'])
            ->postJson('/agent/ticket', $payload)
            ->json('policy_ticket');
        return [
            ...$payload,
            'policy_ticket' => (string)$ticket,
        ];
    }
}
