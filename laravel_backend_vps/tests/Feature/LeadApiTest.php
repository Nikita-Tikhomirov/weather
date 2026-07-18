<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class LeadApiTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        config(['sync.api_key' => 'prod-key']);
    }

    #[Test]
    public function kwork_lead_is_ingested_for_nikita_edited_and_approved_once(): void
    {
        $nikita = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/auth/device-start', [
                'phone' => '+7 967 981-24-38',
                'device_id' => 'nikita-lead-device',
                'display_name' => 'Nikita',
            ])
            ->assertStatus(200)
            ->json('user.profile_key');

        $payload = [
            'external_key' => 'kwork:41',
            'owner_phone' => '79679812438',
            'source' => 'kwork',
            'source_url' => 'https://kwork.ru/projects/41',
            'title' => 'Сверстать лендинг',
            'raw_brief' => 'Нужна адаптивная страница.',
            'summary' => 'HTML/CSS лендинг без Bitrix.',
            'attachment_report' => 'ТЗ прочитано.',
            'draft_reply' => 'Сделаю аккуратную адаптивную страницу.',
            'proposal_title' => 'Адаптивная верстка лендинга',
            'proposal_price_rub' => 5000,
            'proposal_days' => 3,
            'offer_count' => 2,
        ];

        $created = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/leads/ingest', $payload)
            ->assertStatus(200)
            ->assertJsonPath('ok', true)
            ->assertJsonPath('lead.owner_profile', $nikita)
            ->assertJsonPath('lead.status', 'new');

        $leadId = $created->json('lead.id');

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/leads/edit', [
                'actor_profile' => $nikita,
                'lead_id' => $leadId,
                'draft_reply' => 'Сделаю страницу, адаптив и проверю форму.',
                'proposal_price_rub' => 6000,
                'proposal_days' => 4,
            ])
            ->assertStatus(200)
            ->assertJsonPath('lead.status', 'edited')
            ->assertJsonPath('lead.proposal_price_rub', 6000);

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/leads/approve', [
                'actor_profile' => $nikita,
                'lead_id' => $leadId,
            ])
            ->assertStatus(200)
            ->assertJsonPath('lead.status', 'approved');

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/leads/approve', [
                'actor_profile' => $nikita,
                'lead_id' => $leadId,
            ])
            ->assertStatus(200)
            ->assertJsonPath('lead.status', 'approved');

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->getJson('/leads/commands?executor_id=desktop-main')
            ->assertStatus(200)
            ->assertJsonCount(1, 'commands')
            ->assertJsonPath('commands.0.id', $leadId)
            ->assertJsonPath('commands.0.status', 'approved');

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/leads/claim', [
                'lead_id' => $leadId,
                'executor_id' => 'desktop-main',
            ])
            ->assertStatus(200)
            ->assertJsonPath('lead.status', 'sending');

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/leads/claim', [
                'lead_id' => $leadId,
                'executor_id' => 'desktop-main',
            ])
            ->assertStatus(200)
            ->assertJsonPath('lead', null);

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/leads/result', [
                'lead_id' => $leadId,
                'executor_id' => 'desktop-main',
                'sent' => true,
            ])
            ->assertStatus(200)
            ->assertJsonPath('lead.status', 'sent');
    }

    #[Test]
    public function nikita_can_create_read_update_and_delete_a_manual_lead(): void
    {
        $nikita = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/auth/device-start', [
                'phone' => '+7 967 981-24-38',
                'device_id' => 'nikita-crud-device',
                'display_name' => 'Nikita',
            ])
            ->assertStatus(200)
            ->json('user.profile_key');

        $created = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/leads/create', [
                'actor_profile' => $nikita,
                'title' => 'Ручной заказ на лендинг',
                'source_url' => 'https://kwork.ru/projects/55',
                'raw_brief' => 'Нужна адаптивная страница с формой.',
                'summary' => 'Создано вручную.',
                'draft_reply' => 'Здравствуйте! Сделаю адаптивную страницу.',
                'proposal_title' => 'Адаптивная верстка',
                'proposal_price_rub' => 7000,
                'proposal_days' => 4,
            ])
            ->assertStatus(200)
            ->assertJsonPath('lead.status', 'new');

        $leadId = $created->json('lead.id');

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->getJson('/leads/show?actor_profile='.$nikita.'&lead_id='.$leadId)
            ->assertStatus(200)
            ->assertJsonPath('lead.id', $leadId)
            ->assertJsonPath('lead.title', 'Ручной заказ на лендинг');

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/leads/edit', [
                'actor_profile' => $nikita,
                'lead_id' => $leadId,
                'title' => 'Уточненный ручной заказ',
                'raw_brief' => 'Нужны адаптив, форма и подключение аналитики.',
                'draft_reply' => 'Обновленный отклик с планом работ.',
                'proposal_title' => 'Лендинг с адаптивом',
                'proposal_price_rub' => 8000,
                'proposal_days' => 5,
            ])
            ->assertStatus(200)
            ->assertJsonPath('lead.status', 'edited')
            ->assertJsonPath('lead.title', 'Уточненный ручной заказ')
            ->assertJsonPath('lead.proposal_price_rub', 8000);

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/leads/delete', [
                'actor_profile' => $nikita,
                'lead_id' => $leadId,
            ])
            ->assertStatus(200)
            ->assertJsonPath('deleted', true);

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->getJson('/leads?actor_profile='.$nikita)
            ->assertStatus(200)
            ->assertJsonCount(0, 'leads');

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->getJson('/leads/show?actor_profile='.$nikita.'&lead_id='.$leadId)
            ->assertStatus(400);
    }

    #[Test]
    public function only_nikita_phone_profile_can_access_kwork_leads(): void
    {
        $otherProfile = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/auth/device-start', [
                'phone' => '+7 999 100-20-30',
                'device_id' => 'other-lead-device',
                'display_name' => 'Other user',
            ])
            ->assertStatus(200)
            ->json('user.profile_key');

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->getJson('/leads?actor_profile='.$otherProfile)
            ->assertStatus(400)
            ->assertJsonPath('ok', false);

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/leads/create', [
                'actor_profile' => $otherProfile,
                'title' => 'Чужой заказ',
            ])
            ->assertStatus(400)
            ->assertJsonPath('ok', false);

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/leads/monitor/command', [
                'actor_profile' => $otherProfile,
                'command' => 'start',
            ])
            ->assertStatus(400)
            ->assertJsonPath('ok', false);
    }

    #[Test]
    public function nikita_can_start_stop_and_request_a_kwork_scan_from_the_mobile_app(): void
    {
        $nikita = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/auth/device-start', [
                'phone' => '+7 967 981-24-38',
                'device_id' => 'nikita-monitor-device',
                'display_name' => 'Nikita',
            ])
            ->assertStatus(200)
            ->json('user.profile_key');

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->getJson('/leads/monitor?actor_profile='.$nikita)
            ->assertStatus(200)
            ->assertJsonPath('monitor.desired_state', 'stopped')
            ->assertJsonPath('monitor.scan_requested', false);

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/leads/monitor/command', [
                'actor_profile' => $nikita,
                'command' => 'start',
            ])
            ->assertStatus(200)
            ->assertJsonPath('monitor.desired_state', 'running');

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/leads/monitor/command', [
                'actor_profile' => $nikita,
                'command' => 'scan',
            ])
            ->assertStatus(200)
            ->assertJsonPath('monitor.desired_state', 'running')
            ->assertJsonPath('monitor.scan_requested', true);

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/leads/monitor/command', [
                'actor_profile' => $nikita,
                'command' => 'stop',
            ])
            ->assertStatus(200)
            ->assertJsonPath('monitor.desired_state', 'stopped')
            ->assertJsonPath('monitor.scan_requested', false);
    }
}
