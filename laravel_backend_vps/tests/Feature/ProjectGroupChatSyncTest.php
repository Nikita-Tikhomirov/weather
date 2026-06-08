<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class ProjectGroupChatSyncTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        config(['sync.api_key' => 'prod-key', 'sync.locked_actor_profile' => '']);
    }

    #[Test]
    public function creating_family_group_creates_matching_group_chat(): void
    {
        $group = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/family-groups/create', [
                'actor_profile' => 'nik',
                'name' => 'Рабочая группа',
                'members' => ['nastya'],
            ])
            ->assertStatus(200)
            ->assertJsonPath('ok', true)
            ->json('group');

        $conversationKey = 'grp:family:'.$group['id'];

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->getJson('/chat/bootstrap?actor_profile=nik')
            ->assertStatus(200)
            ->assertJsonFragment([
                'conversation_key' => $conversationKey,
                'kind' => 'group',
                'title' => 'Рабочая группа',
            ]);

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->getJson('/chat/bootstrap?actor_profile=nastya')
            ->assertStatus(200)
            ->assertJsonFragment([
                'conversation_key' => $conversationKey,
                'kind' => 'group',
                'title' => 'Рабочая группа',
            ]);
    }

    #[Test]
    public function updating_family_group_adds_new_member_to_matching_group_chat(): void
    {
        $group = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/family-groups/create', [
                'actor_profile' => 'nik',
                'name' => 'Команда',
                'members' => ['nastya'],
            ])
            ->assertStatus(200)
            ->json('group');

        $conversationKey = 'grp:family:'.$group['id'];

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/family-groups/update', [
                'actor_profile' => 'nik',
                'id' => $group['id'],
                'name' => 'Команда',
                'members' => ['nastya', 'misha'],
            ])
            ->assertStatus(200)
            ->assertJsonPath('ok', true);

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->getJson('/chat/bootstrap?actor_profile=misha')
            ->assertStatus(200)
            ->assertJsonFragment([
                'conversation_key' => $conversationKey,
                'kind' => 'group',
                'title' => 'Команда',
            ]);
    }

    #[Test]
    public function updating_family_group_members_preserves_chat_title_when_name_is_omitted(): void
    {
        $group = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/family-groups/create', [
                'actor_profile' => 'nik',
                'name' => 'Команда',
                'members' => ['nastya'],
            ])
            ->assertStatus(200)
            ->json('group');

        $conversationKey = 'grp:family:'.$group['id'];

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/family-groups/update', [
                'actor_profile' => 'nik',
                'id' => $group['id'],
                'members' => ['nastya', 'misha'],
            ])
            ->assertStatus(200)
            ->assertJsonPath('ok', true);

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->getJson('/chat/bootstrap?actor_profile=misha')
            ->assertStatus(200)
            ->assertJsonFragment([
                'conversation_key' => $conversationKey,
                'kind' => 'group',
                'title' => 'Команда',
            ]);
    }

    #[Test]
    public function assigning_group_to_project_creates_project_chat_binding(): void
    {
        $group = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/family-groups/create', [
                'actor_profile' => 'nik',
                'name' => 'Команда проекта',
                'members' => ['nastya'],
            ])
            ->assertStatus(200)
            ->json('group');

        $project = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/projects/create', [
                'actor_profile' => 'nik',
                'name' => 'Проект с чатом',
            ])
            ->assertStatus(200)
            ->json('project');

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/projects/set-groups', [
                'actor_profile' => 'nik',
                'project_id' => $project['id'],
                'group_ids' => [$group['id']],
            ])
            ->assertStatus(200)
            ->assertJsonPath('ok', true);

        $this->assertDatabaseHas('project_chat_bindings', [
            'project_id' => $project['id'],
            'group_id' => $group['id'],
            'conversation_key' => 'grp:family:'.$group['id'],
            'source' => 'family_group',
            'is_primary' => 1,
        ]);
    }

    #[Test]
    public function project_chat_context_rejects_non_member(): void
    {
        $group = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/family-groups/create', [
                'actor_profile' => 'nik',
                'name' => 'Закрытая команда',
                'members' => ['nastya'],
            ])
            ->assertStatus(200)
            ->json('group');

        $project = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/projects/create', [
                'actor_profile' => 'nik',
                'name' => 'Закрытый проект',
            ])
            ->assertStatus(200)
            ->json('project');

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/projects/set-groups', [
                'actor_profile' => 'nik',
                'project_id' => $project['id'],
                'group_ids' => [$group['id']],
            ])
            ->assertStatus(200);

        $this->grantWorkspaceAccess('misha', 'weather');

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/agent/project-chat/context', [
                'actor_profile' => 'misha',
                'project_id' => $project['id'],
                'conversation_key' => 'grp:family:'.$group['id'],
                'workspace_id' => 'weather',
            ])
            ->assertStatus(403)
            ->assertJsonPath('ok', false);
    }

    #[Test]
    public function project_chat_context_returns_recent_messages_and_project_binding(): void
    {
        $group = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/family-groups/create', [
                'actor_profile' => 'nik',
                'name' => 'Контекстная команда',
                'members' => ['nastya'],
            ])
            ->assertStatus(200)
            ->json('group');

        $project = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/projects/create', [
                'actor_profile' => 'nik',
                'name' => 'Контекстный проект',
            ])
            ->assertStatus(200)
            ->json('project');

        $conversationKey = 'grp:family:'.$group['id'];

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/projects/set-groups', [
                'actor_profile' => 'nik',
                'project_id' => $project['id'],
                'group_ids' => [$group['id']],
            ])
            ->assertStatus(200);
        $this->grantWorkspaceAccess('nastya', 'weather');

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/chat/messages/send', [
                'actor_profile' => 'nik',
                'conversation_key' => $conversationKey,
                'message_type' => 'text',
                'text' => 'Нужно сделать экран связей проекта.',
            ])
            ->assertStatus(200);

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/agent/project-chat/context', [
                'actor_profile' => 'nastya',
                'project_id' => $project['id'],
                'conversation_key' => $conversationKey,
                'workspace_id' => 'weather',
            ])
            ->assertStatus(200)
            ->assertJsonPath('ok', true)
            ->assertJsonPath('context.project.id', $project['id'])
            ->assertJsonPath('context.binding.conversation_key', $conversationKey)
            ->assertJsonPath('context.messages.0.text', 'Нужно сделать экран связей проекта.');
    }

    private function grantWorkspaceAccess(string $profileKey, string $workspaceId): void
    {
        $now = now()->format('Y-m-d\TH:i:s');
        DB::table('workspace_access')->insert([
            'workspace_id' => $workspaceId,
            'profile_key' => $profileKey,
            'role' => 'workspace_user',
            'granted_by' => 'nik',
            'created_at' => $now,
            'updated_at' => $now,
            'revoked_at' => null,
        ]);
    }
}
