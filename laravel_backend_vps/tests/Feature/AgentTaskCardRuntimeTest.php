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
}
