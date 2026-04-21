<?php
return [
    'db' => [
        'host' => '127.0.0.1',
        'port' => 3306,
        'name' => 'family_todo',
        'user' => 'root',
        'pass' => '',
        'charset' => 'utf8mb4',
    ],
    'api_key' => 'CHANGE_ME_STRONG_KEY',
    'telegram' => [
        'bot_token' => '',
        'chat_ids' => [],
        'chat_ids_by_profile' => [
            // 'nik' => [-1001234567890],
            // 'nastya' => [-1001234567891],
            // 'misha' => [-1001234567892],
            // 'arisha' => [-1001234567893],
        ],
    ],
    'fcm' => [
        'project_id' => '',
        'service_account_email' => '',
        'private_key' => '',
    ],
];
