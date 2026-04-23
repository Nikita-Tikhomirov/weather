<?php

use App\Services\Push\PushOutboxService;
use App\Services\Push\TaskReminderService;
use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

Artisan::command('push:send-reminders {--limit=200}', function () {
    /** @var TaskReminderService $reminders */
    $reminders = app(TaskReminderService::class);
    /** @var PushOutboxService $outbox */
    $outbox = app(PushOutboxService::class);

    $limit = max(1, (int) $this->option('limit'));
    $reminderStats = $reminders->dispatchDue($limit);
    $pushStats = $outbox->retryDue($limit);

    $this->info(json_encode([
        'ok' => true,
        'reminders' => $reminderStats,
        'push' => $pushStats,
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
})->purpose('Queue and send due task reminder push notifications');

Schedule::command('push:send-reminders --limit=200')
    ->everyMinute()
    ->withoutOverlapping();
