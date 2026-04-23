<?php

return [
    'enabled' => (bool) env('PUSH_ENABLED', true),
    'max_retries' => (int) env('PUSH_MAX_RETRIES', 5),
    'retry_base_sec' => (int) env('PUSH_RETRY_BASE_SEC', 20),
    'retry_cap_sec' => (int) env('PUSH_RETRY_CAP_SEC', 900),

    'fcm' => [
        'project_id' => env('FCM_PROJECT_ID', ''),
        'client_email' => env('FCM_CLIENT_EMAIL', ''),
        'private_key' => env('FCM_PRIVATE_KEY', ''),
        'android_channel_id' => env('FCM_ANDROID_CHANNEL_ID', 'family_updates'),
        'timeout_sec' => (int) env('FCM_TIMEOUT_SEC', 10),
    ],
];
