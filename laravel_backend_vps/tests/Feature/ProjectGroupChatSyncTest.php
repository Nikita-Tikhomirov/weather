<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
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
}
