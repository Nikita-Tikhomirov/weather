<?php

declare(strict_types=1);

if (is_file(dirname(__DIR__) . '/config.php')) {
    require __DIR__ . '/_route.php';
    dispatch_flat_route('POST', '/sync/push');
    return;
}

require __DIR__ . '/sync_store.php';
sync_handle_push(load_config());
