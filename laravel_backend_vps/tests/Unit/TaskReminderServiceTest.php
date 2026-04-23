<?php

namespace Tests\Unit;

use App\Contracts\PushGateway;
use App\Services\Push\PushOutboxService;
use App\Services\Push\TaskReminderService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class TaskReminderServiceTest extends TestCase
{
    use RefreshDatabase;

    #[Test]
    public function it_dispatches_due_personal_reminder_to_owner(): void
    {
        config(['push.enabled' => true, 'app.timezone' => 'Europe/Moscow']);

        $gateway = new class implements PushGateway
        {
            public function isConfigured(): bool
            {
                return true;
            }

            public function sendToToken(string $token, string $title, string $body, array $data): array
            {
                return ['success' => true, 'permanent_failure' => false, 'error' => ''];
            }
        };
        $this->app->instance(PushGateway::class, $gateway);

        DB::table('device_tokens')->insert([
            'token' => 'token-personal',
            'profile_key' => 'nik',
            'platform' => 'android',
            'app_version' => '0.1.0',
            'device_id' => 'dev-1',
            'is_active' => 1,
            'last_seen_at' => now()->format('Y-m-d\TH:i:s'),
            'created_at' => now()->format('Y-m-d\TH:i:s'),
            'updated_at' => now()->format('Y-m-d\TH:i:s'),
        ]);

        /** @var TaskReminderService $reminders */
        $reminders = $this->app->make(TaskReminderService::class);
        /** @var PushOutboxService $outbox */
        $outbox = $this->app->make(PushOutboxService::class);

        $due = now()->addMinutes(31);
        $task = [
            'id' => 'task-1',
            'owner_key' => 'nik',
            'is_family' => false,
            'title' => 'Личная задача',
            'details' => '',
            'due_date' => $due->format('Y-m-d'),
            'time' => $due->format('H:i'),
            'participants' => [],
            'reminder_offsets_minutes' => [30],
        ];

        $reminders->rescheduleForTask($task);
        $stats = $reminders->dispatchDue(50);
        $this->assertSame(1, $stats['processed']);

        $push = $outbox->retryDue(50);
        $this->assertSame(1, $push['sent']);

        $this->assertDatabaseHas('push_outbox', [
            'profile_key' => 'nik',
            'status' => 'sent',
        ]);
    }

    #[Test]
    public function family_reminders_are_created_only_for_assignees(): void
    {
        config(['push.enabled' => true, 'app.timezone' => 'Europe/Moscow']);

        /** @var TaskReminderService $reminders */
        $reminders = $this->app->make(TaskReminderService::class);

        $due = now()->addMinutes(90);
        $task = [
            'id' => 'family-1',
            'owner_key' => 'family',
            'is_family' => true,
            'title' => 'Семейная задача',
            'details' => '',
            'due_date' => $due->format('Y-m-d'),
            'time' => $due->format('H:i'),
            'assignees' => ['nastya', 'misha'],
            'reminder_offsets_minutes' => [60],
        ];

        $reminders->rescheduleForFamilyTask($task);

        $rows = DB::table('task_reminders')->orderBy('recipient_key')->get();
        $this->assertCount(2, $rows);
        $this->assertSame('misha', (string) $rows[0]->recipient_key);
        $this->assertSame('nastya', (string) $rows[1]->recipient_key);
    }
}
