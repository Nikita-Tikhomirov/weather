<?php

declare(strict_types=1);

require __DIR__ . '/sync_store.php';

try {
    $config = load_config();
    sync_handle_pull($config, false);
} catch (UnexpectedValueException $exc) {
    json_response(401, ['ok' => false, 'error' => $exc->getMessage()]);
} catch (InvalidArgumentException $exc) {
    json_response(400, ['ok' => false, 'error' => $exc->getMessage()]);
} catch (Throwable $exc) {
    json_response(500, ['ok' => false, 'error' => $exc->getMessage()]);
}
