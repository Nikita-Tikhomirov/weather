<?php

namespace App\Domain\Sync;

final class Cursor
{
    public static function nextSyncCursor(array $tasks, array $familyTasks, string $fallback): string
    {
        $cursor = $fallback;

        foreach ([$tasks, $familyTasks] as $bucket) {
            foreach ($bucket as $row) {
                if (!is_array($row)) {
                    continue;
                }
                $updatedAt = trim((string)($row['updated_at'] ?? ''));
                if ($updatedAt !== '' && $updatedAt > $cursor) {
                    $cursor = $updatedAt;
                }
            }
        }

        return $cursor;
    }
}
