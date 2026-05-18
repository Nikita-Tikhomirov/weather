<?php

namespace App\Domain\Sync;

use InvalidArgumentException;

final class SyncRules
{
    public static function ensureActor(string $actor): string
    {
        $actor = trim($actor);
        if (!Profiles::isAllowed($actor)) {
            throw new InvalidArgumentException('Unknown actor_profile');
        }

        return $actor;
    }

    public static function ensureWorkflow(string $value): string
    {
        return in_array($value, Profiles::ALLOWED_WORKFLOW, true) ? $value : 'todo';
    }

    public static function ensureTaskPermissions(string $actor, array $task): void
    {
        $owner = (string)($task['owner_key'] ?? '');
        $isFamily = (bool)($task['is_family'] ?? false);

        if ($owner === '') {
            throw new InvalidArgumentException('owner_key is required');
        }
        if ($isFamily && !Profiles::isAdult($actor)) {
            throw new InvalidArgumentException('Only adults can edit family tasks');
        }
        if (!$isFamily && $owner !== $actor) {
            throw new InvalidArgumentException('Personal task can be changed only by owner');
        }
    }

    public static function ensureFamilyPermissions(string $actor): void
    {
        if (!Profiles::isAdult($actor)) {
            throw new InvalidArgumentException('Only adults can edit family tasks');
        }
    }

    public static function normalizeAssignees(array $payload): array
    {
        $source = $payload['assignees'] ?? $payload['participants'] ?? [];
        if (!is_array($source)) {
            $source = [];
        }

        $normalized = [];
        foreach ($source as $item) {
            $key = trim((string)$item);
            if ($key === '' || !Profiles::isAllowed($key)) {
                continue;
            }
            if (!in_array($key, $normalized, true)) {
                $normalized[] = $key;
            }
        }

        return $normalized;
    }

    public static function recipientsForPush(string $actor, string $entity, string $action, array $payload): array
    {
        if ($entity === 'family_task') {
            return Profiles::ALLOWED;
        }

        $owner = trim((string)($payload['owner_key'] ?? $actor));
        if ($owner === '') {
            $owner = $actor;
        }

        return Profiles::isAllowed($owner) ? [$owner] : [];
    }
}
