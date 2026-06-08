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
            'conversation_key' => 'grp:project:'.$project['id'],
            'source' => 'project_group',
            'is_primary' => 1,
        ]);
        $this->assertDatabaseHas('chat_conversations', [
            'conversation_key' => 'grp:project:'.$project['id'],
            'kind' => 'group',
            'title' => 'Проект с чатом',
        ]);
    }

    #[Test]
    public function project_owner_can_create_project_named_group_chat_from_attached_group(): void
    {
        $group = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/family-groups/create', [
                'actor_profile' => 'nik',
                'name' => 'Рабочая группа',
                'members' => ['nastya'],
            ])
            ->assertStatus(200)
            ->json('group');

        $project = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/projects/create', [
                'actor_profile' => 'nik',
                'name' => 'Цифра',
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

        $response = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/projects/ensure-chat', [
                'actor_profile' => 'nik',
                'project_id' => $project['id'],
            ])
            ->assertStatus(200)
            ->assertJsonPath('conversation.conversation_key', 'grp:project:'.$project['id'])
            ->assertJsonPath('conversation.title', 'Цифра')
            ->assertJsonPath('binding.conversation_key', 'grp:project:'.$project['id'])
            ->assertJsonPath('binding.source', 'project_group')
            ->json();

        $this->assertEqualsCanonicalizing(
            ['nik', 'nastya', 'tudushker'],
            $response['conversation']['members'],
        );
        $this->assertDatabaseHas('chat_conversations', [
            'conversation_key' => 'grp:project:'.$project['id'],
            'kind' => 'group',
            'title' => 'Цифра',
        ]);
        $this->assertDatabaseHas('project_chat_bindings', [
            'project_id' => $project['id'],
            'group_id' => $group['id'],
            'conversation_key' => 'grp:project:'.$project['id'],
            'source' => 'project_group',
            'is_primary' => 1,
        ]);

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/chat/messages/send', [
                'actor_profile' => 'tudushker',
                'conversation_key' => 'grp:project:'.$project['id'],
                'message_type' => 'text',
                'text' => 'Готов помочь по проекту.',
            ])
            ->assertStatus(200)
            ->assertJsonPath('message.sender_profile', 'tudushker');
    }

    #[Test]
    public function project_owner_cannot_attach_group_they_cannot_see(): void
    {
        $group = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/family-groups/create', [
                'actor_profile' => 'nastya',
                'name' => 'Чужая группа',
                'members' => ['arisha'],
            ])
            ->assertStatus(200)
            ->json('group');

        $project = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/projects/create', [
                'actor_profile' => 'misha',
                'name' => 'Проект Миши',
            ])
            ->assertStatus(200)
            ->json('project');

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/projects/set-groups', [
                'actor_profile' => 'misha',
                'project_id' => $project['id'],
                'group_ids' => [$group['id']],
            ])
            ->assertStatus(403)
            ->assertJsonPath('ok', false);

        $this->assertDatabaseMissing('project_chat_bindings', [
            'project_id' => $project['id'],
            'conversation_key' => 'grp:project:'.$project['id'],
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
                'conversation_key' => 'grp:project:'.$project['id'],
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

        $conversationKey = 'grp:project:'.$project['id'];

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

    #[Test]
    public function project_control_does_not_fallback_to_first_workspace_without_configuration(): void
    {
        $project = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/projects/create', [
                'actor_profile' => 'nik',
                'name' => 'Проект без workspace',
            ])
            ->assertStatus(200)
            ->json('project');

        $this->grantWorkspaceAccess('nik', 'exp76-ru');

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->getJson('/projects/control?actor_profile=nik&project_id='.$project['id'])
            ->assertStatus(200)
            ->assertJsonPath('snapshot.primary_workspace.id', '')
            ->assertJsonPath('snapshot.automation.primary_workspace_id', '')
            ->assertJsonPath('snapshot.permissions.can_use_agent', false);
    }

    #[Test]
    public function project_owner_can_update_primary_workspace(): void
    {
        $project = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/projects/create', [
                'actor_profile' => 'nik',
                'name' => 'Проект с workspace',
            ])
            ->assertStatus(200)
            ->json('project');

        $this->grantWorkspaceAccess('nik', 'pups-shop');

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/projects/automation', [
                'actor_profile' => 'nik',
                'project_id' => $project['id'],
                'primary_workspace_id' => 'pups-shop',
            ])
            ->assertStatus(200)
            ->assertJsonPath('ok', true)
            ->assertJsonPath('automation.primary_workspace_id', 'pups-shop');

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->getJson('/projects/control?actor_profile=nik&project_id='.$project['id'])
            ->assertStatus(200)
            ->assertJsonPath('snapshot.primary_workspace.id', 'pups-shop')
            ->assertJsonPath('snapshot.permissions.can_use_agent', true);
    }

    #[Test]
    public function project_owner_cannot_set_workspace_without_access(): void
    {
        $project = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/projects/create', [
                'actor_profile' => 'nastya',
                'name' => 'Проект с чужим workspace',
            ])
            ->assertStatus(200)
            ->json('project');

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/projects/automation', [
                'actor_profile' => 'nastya',
                'project_id' => $project['id'],
                'primary_workspace_id' => 'foreign-workspace',
            ])
            ->assertStatus(403)
            ->assertJsonPath('ok', false);
    }

    #[Test]
    public function superadmin_can_set_primary_workspace_without_existing_grant(): void
    {
        $project = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/projects/create', [
                'actor_profile' => 'nik',
                'name' => 'Проект суперадмина',
            ])
            ->assertStatus(200)
            ->json('project');

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/projects/automation', [
                'actor_profile' => 'nik',
                'project_id' => $project['id'],
                'primary_workspace_id' => 'workspace-cifra',
            ])
            ->assertStatus(200)
            ->assertJsonPath('automation.primary_workspace_id', 'workspace-cifra');

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->getJson('/projects/control?actor_profile=nik&project_id='.$project['id'])
            ->assertStatus(200)
            ->assertJsonPath('snapshot.primary_workspace.id', 'workspace-cifra')
            ->assertJsonPath('snapshot.permissions.can_use_agent', true);
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
