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
                $path = $targetPrefix.ltrim(substr($url, strlen($prefix)), '/');
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

Artisan::command('chat:stickers-import {source=assets/stickers} {--keep-existing} {--dry-run}', function () {
    $sourceArg = trim((string) $this->argument('source'));
    $sourceRoot = str_starts_with($sourceArg, '/') ? $sourceArg : base_path($sourceArg);

    $libraries = [
        ['name' => 'library_v2', 'id_prefix' => '', 'path_prefix' => '', 'sort_offset' => 0],
        ['name' => 'library', 'id_prefix' => 'gen1_', 'path_prefix' => 'gen1/', 'sort_offset' => 100000],
    ];
    $libraries = array_values(array_filter(
        $libraries,
        static fn (array $library): bool => is_dir($sourceRoot.'/'.$library['name']),
    ));
    if ($libraries === []) {
        $this->error("Sticker directories not found: {$sourceRoot}/library_v2 or {$sourceRoot}/library");
        return 1;
    }

    $disk = Storage::disk(ChatMediaStorage::disk());
    $dryRun = (bool) $this->option('dry-run');
    $keepExisting = (bool) $this->option('keep-existing');
    $now = now()->format('Y-m-d\TH:i:s');
    $seenIds = [];
    $importedIds = [];
    $stats = [
        'scanned' => 0,
        'uploaded' => 0,
        'upserted' => 0,
        'deactivated' => 0,
        'duplicates' => 0,
        'skipped' => 0,
    ];

    $files = [];
    foreach ($libraries as $library) {
        $libraryDir = $sourceRoot.'/'.$library['name'];
        $iterator = new \RecursiveIteratorIterator(new \RecursiveDirectoryIterator($libraryDir));
        foreach ($iterator as $file) {
            if ($file instanceof \SplFileInfo && $file->isFile() && strtolower($file->getExtension()) === 'png') {
                $files[] = [
                    'path' => $file->getPathname(),
                    'root' => $libraryDir,
                    'id_prefix' => $library['id_prefix'],
                    'path_prefix' => $library['path_prefix'],
                    'sort_offset' => $library['sort_offset'],
                    'source' => $library['name'],
                ];
            }
        }
    }
    usort(
        $files,
        static fn (array $left, array $right): int => [$left['source'], $left['path']] <=> [$right['source'], $right['path']],
    );

    $humanTitle = static function (string $category, string $baseName): string {
        if (preg_match('/_(\d+)$/', $baseName, $match) === 1) {
            return str_replace('_', ' ', $category).' '.$match[1];
        }
        return str_replace('_', ' ', $baseName);
    };

    foreach ($files as $entry) {
        $stats['scanned']++;
        $path = (string) $entry['path'];
        $relative = str_replace('\\', '/', substr($path, strlen((string) $entry['root']) + 1));
        $parts = explode('/', $relative);
        if (count($parts) < 4) {
            $stats['skipped']++;
            continue;
        }

        [$group, $style, $category] = array_slice($parts, 0, 3);
        $filename = basename($path);
        $baseName = pathinfo($filename, PATHINFO_FILENAME);
        $stickerId = ((string) $entry['id_prefix']).$baseName;
        if (isset($seenIds[$stickerId])) {
            $stats['duplicates']++;
            continue;
        }
        $seenIds[$stickerId] = true;
        $importedIds[] = $stickerId;

        $packKey = "{$group}_{$style}_{$category}";
        $sortOrder = $stats['scanned'];
        if (preg_match('/_(\d+)$/', $baseName, $match) === 1) {
            $sortOrder = (int) $match[1];
        }
        $sortOrder += (int) $entry['sort_offset'];

        $targetPath = "chat_stickers/{$entry['path_prefix']}{$packKey}/{$filename}";
        if (!$dryRun) {
            $handle = fopen($path, 'rb');
            if ($handle === false) {
                $stats['skipped']++;
                continue;
            }
            $disk->put($targetPath, $handle);
            fclose($handle);
            $stats['uploaded']++;
        }

        if (!$dryRun) {
            DB::table('chat_stickers')->updateOrInsert(
                ['sticker_id' => $stickerId],
                [
                    'pack_key' => $packKey,
                    'title' => $humanTitle($category, $baseName),
                    'asset_url' => ChatMediaStorage::urlForPath($targetPath),
                    'is_active' => 1,
                    'sort_order' => $sortOrder,
                    'created_at' => $now,
                    'updated_at' => $now,
                ],
            );
            $stats['upserted']++;
        }
    }

    if (!$dryRun && !$keepExisting && $importedIds !== []) {
        $stats['deactivated'] = DB::table('chat_stickers')
            ->whereNotIn('sticker_id', $importedIds)
            ->update(['is_active' => 0, 'updated_at' => $now]);
    }

    $this->info(json_encode([
        'ok' => true,
        'disk' => ChatMediaStorage::disk(),
        'source' => $sourceRoot,
        'libraries' => array_column($libraries, 'name'),
        'keep_existing' => $keepExisting,
        'dry_run' => $dryRun,
        'stats' => $stats,
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));

    return 0;
})->purpose('Import generated sticker PNG files into chat_stickers and deactivate pre-generation stickers');

Schedule::command('push:send-reminders --limit=200')
    ->everyMinute()
    ->withoutOverlapping();
