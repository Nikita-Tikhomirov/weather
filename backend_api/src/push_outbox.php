<?php

declare(strict_types=1);

function enqueue_push_notifications(
    PDO $db,
    string $eventId,
    string $actorProfile,
    string $entity,
    string $action,
    array $payload
): void {
    $recipients = recipient_adults_except_actor($actorProfile);
    if (!$recipients) {
        return;
    }
    $rows = active_device_tokens_for_profiles($db, $recipients);
    if (!$rows) {
        return;
    }
    $actorDisplay = actor_display_name($actorProfile);
    $titleValue = trim((string)($payload['title'] ?? $payload['text'] ?? ''));
    $title = "{$actorDisplay} изменил(а) задачу";
    $body = $titleValue !== '' ? $titleValue : "{$entity}/{$action}";
    $data = [
        'kind' => 'todo_update',
        'event_id' => $eventId,
        'entity' => $entity,
        'action' => $action,
        'actor_profile' => $actorProfile,
    ];

    $stmt = $db->prepare(
        "INSERT INTO push_outbox (
            event_id, token, profile_key, title, body_text, data_json, status, retry_count, next_retry_at, last_error, created_at, updated_at
         ) VALUES (
            :event_id, :token, :profile_key, :title, :body_text, :data_json, 'pending', 0, :next_retry_at, '', :created_at, :updated_at
         )
         ON DUPLICATE KEY UPDATE updated_at = VALUES(updated_at)"
    );
    $now = iso_now();
    foreach ($rows as $row) {
        $stmt->execute([
            'event_id' => $eventId,
            'token' => (string)$row['token'],
            'profile_key' => (string)$row['profile_key'],
            'title' => $title,
            'body_text' => $body,
            'data_json' => json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
            'next_retry_at' => $now,
            'created_at' => $now,
            'updated_at' => $now,
        ]);
    }
}

function process_push_outbox(PDO $db, array $config, int $limit = 100): array
{
    $stmt = $db->prepare(
        "SELECT * FROM push_outbox
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
        $result = send_fcm_notification(
            $config,
            (string)$row['token'],
            (string)$row['title'],
            (string)$row['body_text'],
            json_decode((string)$row['data_json'], true) ?: []
        );
        if ($result['ok']) {
            $db->prepare(
                "UPDATE push_outbox SET status = 'sent', updated_at = :updated_at WHERE id = :id"
            )->execute(['updated_at' => iso_now(), 'id' => (int)$row['id']]);
            $sent++;
            continue;
        }

        $error = (string)($result['error'] ?? 'fcm_send_failed');
        if (str_contains($error, 'UNREGISTERED') || str_contains($error, 'INVALID_ARGUMENT')) {
            deactivate_device_token($db, (string)$row['token'], null);
        }

        $retryCount = (int)$row['retry_count'] + 1;
        $nextRetry = (new DateTimeImmutable('now'))->modify('+' . min(120, 2 * $retryCount) . ' minutes')->format('Y-m-d\TH:i:s');
        $db->prepare(
            "UPDATE push_outbox
             SET status = 'failed', retry_count = :retry_count, next_retry_at = :next_retry_at, last_error = :last_error, updated_at = :updated_at
             WHERE id = :id"
        )->execute([
            'retry_count' => $retryCount,
            'next_retry_at' => $nextRetry,
            'last_error' => substr($error, 0, 500),
            'updated_at' => iso_now(),
            'id' => (int)$row['id'],
        ]);
        $failed++;
    }

    return ['processed' => $processed, 'sent' => $sent, 'failed' => $failed];
}

function send_fcm_notification(array $config, string $token, string $title, string $body, array $data): array
{
    $projectId = trim((string)($config['fcm']['project_id'] ?? ''));
    $clientEmail = trim((string)($config['fcm']['service_account_email'] ?? ''));
    $privateKey = (string)($config['fcm']['private_key'] ?? '');
    if ($projectId === '' || $clientEmail === '' || trim($privateKey) === '') {
        return ['ok' => false, 'error' => 'fcm_config_incomplete'];
    }

    $accessToken = fcm_access_token($clientEmail, $privateKey);
    if ($accessToken === null) {
        return ['ok' => false, 'error' => 'fcm_access_token_failed'];
    }

    $url = "https://fcm.googleapis.com/v1/projects/{$projectId}/messages:send";
    $payload = [
        'message' => [
            'token' => $token,
            'notification' => [
                'title' => $title,
                'body' => $body,
            ],
            'data' => array_map(static fn($v): string => (string)$v, $data),
            'android' => [
                'priority' => 'HIGH',
                'notification' => ['channel_id' => 'family_updates'],
            ],
        ],
    ];
    $ch = curl_init($url);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_HTTPHEADER, [
        'Content-Type: application/json',
        'Authorization: Bearer ' . $accessToken,
    ]);
    curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 15);
    $response = curl_exec($ch);
    $httpCode = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    if ($response === false || $httpCode < 200 || $httpCode >= 300) {
        return ['ok' => false, 'error' => 'fcm_http_' . $httpCode . ':' . (string)$response];
    }
    return ['ok' => true];
}

function fcm_access_token(string $clientEmail, string $privateKey): ?string
{
    $privateKey = str_replace('\n', "\n", $privateKey);
    $header = ['alg' => 'RS256', 'typ' => 'JWT'];
    $now = time();
    $claimSet = [
        'iss' => $clientEmail,
        'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
        'aud' => 'https://oauth2.googleapis.com/token',
        'iat' => $now,
        'exp' => $now + 3600,
    ];
    $segments = [];
    $segments[] = base64url_encode(json_encode($header, JSON_UNESCAPED_SLASHES));
    $segments[] = base64url_encode(json_encode($claimSet, JSON_UNESCAPED_SLASHES));
    $signingInput = implode('.', $segments);
    $signature = '';
    $ok = openssl_sign($signingInput, $signature, $privateKey, OPENSSL_ALGO_SHA256);
    if (!$ok) {
        return null;
    }
    $jwt = $signingInput . '.' . base64url_encode($signature);
    $ch = curl_init('https://oauth2.googleapis.com/token');
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/x-www-form-urlencoded']);
    curl_setopt($ch, CURLOPT_POSTFIELDS, http_build_query([
        'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        'assertion' => $jwt,
    ]));
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 15);
    $response = curl_exec($ch);
    $httpCode = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    if ($response === false || $httpCode < 200 || $httpCode >= 300) {
        return null;
    }
    $decoded = json_decode((string)$response, true);
    if (!is_array($decoded)) {
        return null;
    }
    $token = $decoded['access_token'] ?? null;
    return is_string($token) && $token !== '' ? $token : null;
}

function base64url_encode(string $input): string
{
    return rtrim(strtr(base64_encode($input), '+/', '-_'), '=');
}
