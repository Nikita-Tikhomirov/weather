<?php

declare(strict_types=1);

const PUSH_DEDUP_WINDOW_SECONDS = 120;
const PUSH_RETRY_SUPPRESS_SECONDS = 600;

function push_normalize_signature_payload(mixed $value): mixed
{
    if (!is_array($value)) {
        if (is_bool($value) || is_int($value) || is_float($value) || is_string($value) || $value === null) {
            return $value;
        }
        return (string)$value;
    }

    $isList = array_keys($value) === range(0, count($value) - 1);
    if ($isList) {
        $normalized = array_map(static fn($item) => push_normalize_signature_payload($item), $value);
        $allScalars = true;
        foreach ($normalized as $item) {
            if (is_array($item)) {
                $allScalars = false;
                break;
            }
        }
        if ($allScalars) {
            sort($normalized);
        }
        return $normalized;
    }

    ksort($value);
    $normalized = [];
    foreach ($value as $key => $item) {
        $normalized[(string)$key] = push_normalize_signature_payload($item);
    }
    return $normalized;
}

function push_payload_without_volatile_fields(array $payload): array
{
    $clone = $payload;
    foreach (['event_id', 'happened_at', 'updated_at', 'version', 'server_time'] as $key) {
        unset($clone[$key]);
    }
    return $clone;
}

function build_push_dedup_signature(
    string $actorProfile,
    string $entity,
    string $action,
    array $payload,
    string $profileKey
): string {
    $canonical = [
        'actor_profile' => $actorProfile,
        'entity' => $entity,
        'action' => $action,
        'profile_key' => $profileKey,
        'payload' => push_normalize_signature_payload(push_payload_without_volatile_fields($payload)),
    ];

    return hash('sha256', (string)json_encode($canonical, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
}

function extract_push_signature(array $row): string
{
    $decoded = json_decode((string)($row['data_json'] ?? ''), true);
    if (!is_array($decoded)) {
        return '';
    }
    return trim((string)($decoded['dedup_signature'] ?? ''));
}

function has_recent_push_signature(
    PDO $db,
    string $profileKey,
    string $token,
    string $signature,
    string $sinceIso,
    ?int $excludeId = null,
    bool $sentOnly = false
): bool {
    if ($signature === '') {
        return false;
    }

    $statusFilter = $sentOnly ? "AND status = 'sent'" : '';
    $sql = "SELECT id, data_json
            FROM push_outbox
            WHERE created_at >= :since
              AND (profile_key = :profile_key OR token = :token)
              {$statusFilter}
            ORDER BY id DESC
            LIMIT 80";
    $stmt = $db->prepare($sql);
    $stmt->execute([
        'since' => $sinceIso,
        'profile_key' => $profileKey,
        'token' => $token,
    ]);
    $rows = $stmt->fetchAll();
    foreach ($rows as $row) {
        $rowId = isset($row['id']) ? (int)$row['id'] : 0;
        if ($excludeId !== null && $rowId === $excludeId) {
            continue;
        }
        if (extract_push_signature($row) === $signature) {
            return true;
        }
    }

    return false;
}

function enqueue_push_notifications(
    PDO $db,
    string $eventId,
    string $actorProfile,
    string $entity,
    string $action,
    array $payload,
    ?array $recipientProfiles = null
): void {
    $recipients = $recipientProfiles ?? recipients_for_push($actorProfile, $entity, $action, $payload);
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
    $baseData = [
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
    $recentSince = (new DateTimeImmutable('now'))
        ->modify('-' . PUSH_DEDUP_WINDOW_SECONDS . ' seconds')
        ->format('Y-m-d\\TH:i:s');

    foreach ($rows as $row) {
        $profileKey = (string)$row['profile_key'];
        $token = (string)$row['token'];
        $dedupSignature = build_push_dedup_signature($actorProfile, $entity, $action, $payload, $profileKey);
        if (has_recent_push_signature($db, $profileKey, $token, $dedupSignature, $recentSince, null, false)) {
            continue;
        }

        $data = $baseData;
        $data['dedup_signature'] = $dedupSignature;
        $stmt->execute([
            'event_id' => $eventId,
            'token' => $token,
            'profile_key' => $profileKey,
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
        $data = json_decode((string)$row['data_json'], true) ?: [];
        $signature = trim((string)($data['dedup_signature'] ?? ''));

        if ($signature !== '') {
            $retrySince = (new DateTimeImmutable('now'))
                ->modify('-' . PUSH_RETRY_SUPPRESS_SECONDS . ' seconds')
                ->format('Y-m-d\\TH:i:s');
            $alreadySent = has_recent_push_signature(
                $db,
                (string)$row['profile_key'],
                (string)$row['token'],
                $signature,
                $retrySince,
                (int)$row['id'],
                true
            );
            if ($alreadySent) {
                $db->prepare(
                    "UPDATE push_outbox
                     SET status = 'sent', last_error = :last_error, updated_at = :updated_at
                     WHERE id = :id"
                )->execute([
                    'last_error' => 'dedup_suppressed',
                    'updated_at' => iso_now(),
                    'id' => (int)$row['id'],
                ]);
                $sent++;
                continue;
            }
        }

        $result = send_fcm_notification(
            $config,
            (string)$row['token'],
            (string)$row['title'],
            (string)$row['body_text'],
            $data
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
        $nextRetry = (new DateTimeImmutable('now'))->modify('+' . min(120, 2 * $retryCount) . ' minutes')->format('Y-m-d\\TH:i:s');
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
    $privateKey = str_replace('\\n', "\n", $privateKey);
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
