<?php

declare(strict_types=1);

$config = require __DIR__ . '/../config.php';
$token = (string)($config['telegram']['bot_token'] ?? '');
$chat = (string)(($config['telegram']['chat_ids'][0] ?? ''));

$result = [
    'token_set' => $token !== '',
    'chat_set' => $chat !== '',
    'host' => gethostname(),
    'time' => date('c'),
];

if ($token !== '') {
    $url = "https://api.telegram.org/bot{$token}/getMe";
    $ch = curl_init($url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 20);

    $resp = curl_exec($ch);
    $result['curl_errno'] = curl_errno($ch);
    $result['curl_error'] = curl_error($ch);
    $result['http_code'] = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $result['ok'] = $resp !== false && $result['http_code'] >= 200 && $result['http_code'] < 300;

    curl_close($ch);
}

header('Content-Type: application/json; charset=utf-8');
echo json_encode($result, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);

