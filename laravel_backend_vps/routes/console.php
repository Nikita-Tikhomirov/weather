<?php

use App\Domain\Profiles\PhoneProfileRepository;
use App\Services\Push\PushOutboxService;
use App\Services\Push\TaskReminderService;
use App\Support\ChatMediaStorage;
use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schedule;
use Illuminate\Support\Facades\Storage;

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

Artisan::command('profile:reset-device {phone}', function (PhoneProfileRepository $profiles) {
    $result = $profiles->markDeviceRebindPending((string) $this->argument('phone'));
    $this->info(json_encode([
        'ok' => true,
        'result' => $result,
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
})->purpose('Allow a phone profile to bind to a new device on next login');

Artisan::command('chat:media-migrate {--delete-local}', function () {
    $diskName = ChatMediaStorage::disk();
    $disk = Storage::disk($diskName);
    $deleteLocal = (bool) $this->option('delete-local');
    $stats = ['copied' => 0, 'updated' => 0, 'deleted' => 0, 'skipped' => 0];

    $copyLegacy = function (string $url) use ($disk, $deleteLocal, &$stats): ?string {
        $path = null;
        foreach ([
            '/chat_stickers/' => 'chat_stickers/',
            '/chat_documents/' => 'chat_documents/',
            '/storage/profile_avatars/' => 'profile_avatars/',
        ] as $prefix => $targetPrefix) {
            if (str_starts_with($url, $prefix)) {
                $path = $targetPrefix.basename($url);
                break;
            }
        }

        if ($path === null || str_starts_with($url, '/chat/media/')) {
            $stats['skipped']++;
            return null;
        }

        $sources = [
            storage_path('app/public/'.$path),
            public_path($path),
            public_path('storage/'.$path),
        ];
        $source = null;
        foreach ($sources as $candidate) {
            if (is_file($candidate)) {
                $source = $candidate;
                break;
            }
        }
        if ($source === null) {
            $stats['skipped']++;
            return null;
        }

        if (!$disk->exists($path)) {
            $handle = fopen($source, 'rb');
            if ($handle === false) {
                $stats['skipped']++;
                return null;
            }
            $disk->put($path, $handle);
            fclose($handle);
            $stats['copied']++;
        }

        if ($deleteLocal && is_file($source) && @unlink($source)) {
            $stats['deleted']++;
        }

        return ChatMediaStorage::urlForPath($path);
    };

    foreach (DB::table('chat_message_attachments')->get(['id', 'asset_url']) as $row) {
        $newUrl = $copyLegacy((string) $row->asset_url);
        if ($newUrl !== null && $newUrl !== (string) $row->asset_url) {
            DB::table('chat_message_attachments')->where('id', $row->id)->update(['asset_url' => $newUrl]);
            $stats['updated']++;
        }
    }

    foreach (DB::table('chat_messages')->whereNotNull('image_url')->get(['id', 'image_url']) as $row) {
        $newUrl = $copyLegacy((string) $row->image_url);
        if ($newUrl !== null && $newUrl !== (string) $row->image_url) {
            DB::table('chat_messages')->where('id', $row->id)->update(['image_url' => $newUrl]);
            $stats['updated']++;
        }
    }

    foreach (DB::table('chat_stickers')->get(['sticker_id', 'asset_url']) as $row) {
        $newUrl = $copyLegacy((string) $row->asset_url);
        if ($newUrl !== null && $newUrl !== (string) $row->asset_url) {
            DB::table('chat_stickers')->where('sticker_id', $row->sticker_id)->update(['asset_url' => $newUrl]);
            $stats['updated']++;
        }
    }

    foreach (DB::table('messenger_users')->get(['profile_key', 'avatar_url']) as $row) {
        $newUrl = $copyLegacy((string) $row->avatar_url);
        if ($newUrl !== null && $newUrl !== (string) $row->avatar_url) {
            DB::table('messenger_users')->where('profile_key', $row->profile_key)->update(['avatar_url' => $newUrl]);
            $stats['updated']++;
        }
    }

    $this->info(json_encode(['ok' => true, 'disk' => $diskName, 'stats' => $stats], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
})->purpose('Move legacy chat media files to the configured chat media disk and rewrite URLs');

Schedule::command('push:send-reminders --limit=200')
    ->everyMinute()
    ->withoutOverlapping();
