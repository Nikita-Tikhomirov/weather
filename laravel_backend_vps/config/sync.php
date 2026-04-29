<?php

return [
    'api_key' => env('TODO_BACKEND_API_KEY', env('SYNC_API_KEY', '')),
    'locked_actor_profile' => env('SYNC_LOCKED_ACTOR_PROFILE', ''),
];
