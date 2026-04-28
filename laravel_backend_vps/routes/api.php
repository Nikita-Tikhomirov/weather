<?php

use App\Http\Controllers\SyncController;
use App\Http\Controllers\ChatController;
use Illuminate\Support\Facades\Route;

Route::get('/health', [SyncController::class, 'health']);

Route::middleware('sync.apikey')->group(function (): void {
    Route::get('/sync/pull', [SyncController::class, 'pull']);
    Route::get('/sync/changes', [SyncController::class, 'pull']);

    Route::get('/sync_pull.php', [SyncController::class, 'pull']);
    Route::get('/sync_changes.php', [SyncController::class, 'pull']);

    Route::post('/sync/push', [SyncController::class, 'push']);
    Route::post('/sync_push.php', [SyncController::class, 'push']);

    Route::post('/telegram/events', [SyncController::class, 'telegramEvents']);
    Route::post('/telegram_events.php', [SyncController::class, 'telegramEvents']);

    Route::post('/devices/register', [SyncController::class, 'registerDevice']);
    Route::post('/devices_register.php', [SyncController::class, 'registerDevice']); 
    Route::post('/devices/status', [SyncController::class, 'reportDeviceStatus']);
    Route::post('/devices_status.php', [SyncController::class, 'reportDeviceStatus']);
    Route::get('/push/device_status', [SyncController::class, 'getDeviceStatus']);
    Route::get('/push_device_status.php', [SyncController::class, 'getDeviceStatus']);
    Route::get('/push/diagnostics', [SyncController::class, 'pushDiagnostics']);
    Route::get('/push_diagnostics.php', [SyncController::class, 'pushDiagnostics']);
    Route::post('/push/test', [SyncController::class, 'pushTest']);
    Route::post('/push_test.php', [SyncController::class, 'pushTest']);

    Route::post('/devices/unregister', [SyncController::class, 'unregisterDevice']);
    Route::post('/devices_unregister.php', [SyncController::class, 'unregisterDevice']);

    Route::post('/telegram/outbox/retry', [SyncController::class, 'telegramOutboxRetry']);
    Route::post('/telegram_outbox_retry.php', [SyncController::class, 'telegramOutboxRetry']);

    Route::post('/push/outbox/retry', [SyncController::class, 'pushOutboxRetry']);
    Route::post('/push_outbox_retry.php', [SyncController::class, 'pushOutboxRetry']);

    Route::get('/chat/bootstrap', [ChatController::class, 'bootstrap']);
    Route::get('/chat/messages', [ChatController::class, 'messages']);
    Route::post('/chat/messages/send', [ChatController::class, 'sendMessage']);
    Route::post('/chat/messages/edit', [ChatController::class, 'editMessage']);
    Route::post('/chat/messages/delete', [ChatController::class, 'deleteMessage']);
    Route::post('/chat/stickers/upload', [ChatController::class, 'uploadSticker']);
    Route::get('/chat/stickers/packs', [ChatController::class, 'stickerPacks']);
});

Route::fallback(function () {
    return response()->json([
        'ok' => false,
        'error' => 'Not found',
    ], 404, [], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
});
