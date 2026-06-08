<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class AgentPolicyTicketTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        config([
            'app.key' => 'base64:test-policy-secret',
            'sync.api_key' => '',
            'sync.locked_actor_profile' => '',
            'sync.agent_policy_ticket_secret' => 'base64:test-policy-secret',
        ]);
    }

    #[Test]
    public function superadmin_can_request_agent_ticket_with_app_key_secret(): void
    {
        $response = $this->withHeaders(['X-Api-Key' => 'dev-local-key'])
            ->postJson('/agent/ticket', $this->agentPayload('task-agent-ticket'));

        $response
            ->assertStatus(200)
            ->assertJsonPath('ok', true)
            ->assertJsonPath('policy.allowed', true)
            ->assertJsonPath('policy.profile_key', 'Nikita')
            ->assertJsonPath('policy.workspace_id', 'weather');

        $this->assertIsString($response->json('policy_ticket'));
        $this->assertNotSame('', $response->json('policy_ticket'));
    }

    #[Test]
    public function agent_context_returns_placeholder_for_unsynced_task(): void
    {
        $response = $this->withHeaders(['X-Api-Key' => 'dev-local-key'])
            ->postJson('/agent/context', $this->agentPayload('task-not-yet-synced'));

        $response
            ->assertStatus(200)
            ->assertJsonPath('ok', true)
            ->assertJsonPath('context.task.id', 'task-not-yet-synced')
            ->assertJsonPath('context.task.workflow_status', 'todo')
            ->assertJsonPath('context.workspace.id', 'weather');
    }

    #[Test]
    public function agent_session_and_event_accept_unsynced_task(): void
    {
        $session = $this->withHeaders(['X-Api-Key' => 'dev-local-key'])
            ->postJson('/agent/sessions', [
                ...$this->agentPayload('task-not-yet-synced'),
                'agent_session_id' => 'agent-session-test',
                'session_id' => 'bridge-session-test',
                'title' => 'Агентский чат',
                'status' => 'linked',
            ]);

        $session
            ->assertStatus(200)
            ->assertJsonPath('ok', true)
            ->assertJsonPath('session.id', 'agent-session-test')
            ->assertJsonPath('session.session_id', 'bridge-session-test')
            ->assertJsonPath('session.status', 'linked');

        $event = $this->withHeaders(['X-Api-Key' => 'dev-local-key'])
            ->postJson('/agent/events', [
                ...$this->agentPayload('task-not-yet-synced'),
                'agent_session_id' => 'agent-session-test',
                'event_type' => 'agent_queue_completed',
                'payload' => ['steps' => 1],
            ]);

        $event
            ->assertStatus(200)
            ->assertJsonPath('ok', true)
            ->assertJsonPath('event.task_id', 'task-not-yet-synced')
            ->assertJsonPath('event.agent_session_id', 'agent-session-test')
            ->assertJsonPath('event.type', 'agent_queue_completed');
    }

    #[Test]
    public function project_chat_ticket_requires_workspace_access(): void
    {
        $response = $this->withHeaders(['X-Api-Key' => 'dev-local-key'])
            ->postJson('/agent/ticket', [
                'actor_profile' => 'nik',
                'scope' => 'project_chat',
                'project_id' => 'project-1',
                'conversation_key' => 'grp:family:group-1',
                'workspace_id' => 'weather',
                'requested_mode' => 'planner',
            ]);

        $response
            ->assertStatus(403)
            ->assertJsonPath('ok', false)
            ->assertJsonPath('policy.scope', 'project_chat');
    }

    #[Test]
    public function project_chat_ticket_allows_only_safe_session_commands(): void
    {
        $response = $this->withHeaders(['X-Api-Key' => 'dev-local-key'])
            ->postJson('/agent/ticket', [
                'actor_profile' => 'Nikita',
                'actor_phone' => '+79679812438',
                'scope' => 'project_chat',
                'project_id' => 'project-1',
                'conversation_key' => 'grp:family:group-1',
                'workspace_id' => 'weather',
                'requested_mode' => 'planner',
            ]);

        $response
            ->assertStatus(200)
            ->assertJsonPath('ok', true)
            ->assertJsonPath('policy.scope', 'project_chat')
            ->assertJsonPath('policy.project_id', 'project-1')
            ->assertJsonPath('policy.conversation_key', 'grp:family:group-1');

        $commands = $response->json('policy.allowed_commands');
        $this->assertContains('session_create', $commands);
        $this->assertContains('session_send', $commands);
        $this->assertNotContains('session_update_task_card', $commands);
        $this->assertNotContains('session_upload_file', $commands);
        $this->assertNotContains('workspace_create', $commands);
        $this->assertNotContains('workspace_attach', $commands);
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
