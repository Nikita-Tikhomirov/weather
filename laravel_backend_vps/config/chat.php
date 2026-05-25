<?php

return [
    'media_disk' => env('CHAT_MEDIA_DISK', env('FILESYSTEM_DISK', 'public')),
];
