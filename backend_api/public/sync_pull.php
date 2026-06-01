<?php

declare(strict_types=1);

if (is_file(dirname(__DIR__) . '/config.php')) {
    require __DIR__ . '/_route.php';
    dispatch_flat_route('GET', '/sync/pull');
    return;
}

require __DIR__ . '/sync_store.php';
sync_handle_pull(load_config());
