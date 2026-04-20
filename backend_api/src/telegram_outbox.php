<?php

declare(strict_types=1);

function enqueue_telegram_event(PDO $db, string $eventId, array $payload): void
{
    $stmt = $db->prepare(
        'INSERT INTO telegram_outbox (event_id, payload_json, status, retry_count, next_retry_at, created_at, updated_at)
         VALUES (:event_id, :payload_json, :status, 0, :next_retry_at, :created_at, :updated_at)'
    );
    $now = iso_now();
    $stmt->execute([
        'event_id' => $eventId,
        'payload_json' => json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
        'status' => 'pending',
        'next_retry_at' => $now,
        'created_at' => $now,
        'updated_at' => $now,
    ]);
}

function process_outbox(PDO $db, array $config, int $limit = 100): array
{
    $token = (string)($config['telegram']['bot_token'] ?? '');
    $chatIds = $config['telegram']['chat_ids'] ?? [];
    if ($token === '' || !is_array($chatIds) || !$chatIds) {
        return ['processed' => 0, 'sent' => 0, 'failed' => 0, 'message' => 'telegram config incomplete'];
    }

    $stmt = $db->prepare(
        "SELECT * FROM telegram_outbox
         WHERE status IN ('pending', 'failed') AND next_retry_at <= :now
         ORDER BY created_at ASC
         LIMIT :limit"
    );
    $stmt->bindValue(':now', iso_now());
    $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
    $stmt->execute();
    $rows = $stmt->fetchAll();

    $processed = 0;
    $sent = 0;
    $failed = 0;
    foreach ($rows as $row) {
        $processed++;
        $ok = send_telegram_payload($token, $chatIds, $row['payload_json']);
        if ($ok) {
            $db->prepare(
                "UPDATE telegram_outbox
                 SET status = 'sent', updated_at = :updated_at
                 WHERE id = :id"
            )->execute(['updated_at' => iso_now(), 'id' => (int)$row['id']]);
            $sent++;
            continue;
        }

        $retryCount = (int)$row['retry_count'] + 1;
        $nextRetry = (new DateTimeImmutable('now'))->modify('+' . min(120, 2 * $retryCount) . ' minutes')->format('Y-m-d\TH:i:s');
        $db->prepare(
            "UPDATE telegram_outbox
             SET status = 'failed', retry_count = :retry_count, next_retry_at = :next_retry_at, updated_at = :updated_at
             WHERE id = :id"
        )->execute([
            'retry_count' => $retryCount,
            'next_retry_at' => $nextRetry,
            'updated_at' => iso_now(),
            'id' => (int)$row['id'],
        ]);
        $failed++;
    }

    return ['processed' => $processed, 'sent' => $sent, 'failed' => $failed];
}

function send_telegram_payload(string $token, array $chatIds, string $payloadJson): bool
{
    $payload = json_decode($payloadJson, true);
    if (!is_array($payload)) {
        return false;
    }
    $entity = (string)($payload['entity'] ?? 'task');
    $action = (string)($payload['action'] ?? 'update');
    $actor = (string)($payload['actor_profile'] ?? 'unknown');
    $task = $payload['payload'] ?? [];
    $title = is_array($task) ? (string)($task['title'] ?? '') : '';
    $line = trim("[$actor] $entity/$action: $title");
    if ($line === '') {
        $line = "[$actor] $entity/$action";
    }
    $url = "https://api.telegram.org/bot{$token}/sendMessage";
    foreach ($chatIds as $chatId) {
        $body = json_encode(['chat_id' => $chatId, 'text' => $line], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        $ch = curl_init($url);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
        curl_setopt($ch, CURLOPT_POSTFIELDS, $body);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, 12);
        $response = curl_exec($ch);
        $httpCode = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        if ($response === false || $httpCode < 200 || $httpCode >= 300) {
            return false;
        }
    }
    return true;
}

