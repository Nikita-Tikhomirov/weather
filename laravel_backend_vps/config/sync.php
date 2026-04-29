<?php

return [
    'api_key' => env('TODO_BACKEND_API_KEY', env('SYNC_API_KEY', '')),
    'profile_ip_locks' => env('SYNC_PROFILE_IP_LOCKS', ''),
];
