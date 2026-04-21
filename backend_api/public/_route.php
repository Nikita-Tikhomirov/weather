<?php

declare(strict_types=1);

/**
 * Route flat endpoint files (sync_pull.php, sync_push.php, ...) into index.php router.
 */
function dispatch_flat_route(string $method, string $path): void
{
    $_SERVER['REQUEST_METHOD'] = $method;
    $_SERVER['REQUEST_URI'] = $path;
    require __DIR__ . '/index.php';
}

