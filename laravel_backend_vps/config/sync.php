<?php

return [
    'api_key' => env('TODO_BACKEND_API_KEY', env('SYNC_API_KEY', '')),
    'locked_actor_profile' => env('SYNC_LOCKED_ACTOR_PROFILE', ''),
    'superadmin_phone' => env('SUPERADMIN_PHONE', '79679812438'),
    'agent_policy_ticket_secret' => env(
        'AGENT_POLICY_TICKET_SECRET',
        env('TODO_BACKEND_API_KEY', env('SYNC_API_KEY', '')),
    ),
];
