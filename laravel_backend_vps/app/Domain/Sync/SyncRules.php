<?php

namespace App\Domain\Sync;

use Illuminate\Support\Facades\DB;
use InvalidArgumentException;

final class SyncRules
{
    public static function ensureActor(string $actor): string
    {
        $actor = trim($actor);
        if (!Profiles::isAllowed($actor) && !self::profileExists($actor)) {
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
        if ($isFamily && Profiles::isAllowed($actor) && !Profiles::isAdult($actor)) {
            throw new InvalidArgumentException('Only adults can edit family tasks');
        }
        if (!$isFamily && $owner !== $actor) {
            throw new InvalidArgumentException('Personal task can be changed only by owner');
        }
    }

    public static function ensureFamilyPermissions(string $actor): void
    {
        if (Profiles::isAllowed($actor) && !Profiles::isAdult($actor)) {
            throw new InvalidArgumentException('Only adults can edit family tasks');
        }
        if (!Profiles::isAllowed($actor) && !self::profileExists($actor)) {
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
            if ($key === '') {
                continue;
            }
            // Accept any profile that exists in messenger_users or has an active device token
            if (!Profiles::isAllowed($key) && !self::profileExists($key) && !self::hasActiveToken($key)) {
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
            try {
                // 1) Actor's family-group members (the real contact list)
                $familyMembers = DB::table('family_group_members')
                    ->join('family_groups', 'family_groups.id', '=', 'family_group_members.family_group_id')
                    ->where('family_groups.owner_profile_key', $actor)
                    ->pluck('family_group_members.profile_key')
                    ->unique()
                    ->toArray();

                // 2) Any other profiles with active device tokens (catch profiles not yet in a family group)
                $activeTokens = DB::table('device_tokens')
                    ->where('is_active', 1)
                    ->pluck('profile_key')
                    ->unique()
                    ->toArray();

                $profiles = array_unique(array_merge($familyMembers, $activeTokens));
            } catch (\Throwable) {
                // Fallback: all profiles with active tokens
                try {
                    $profiles = DB::table('device_tokens')
                        ->where('is_active', 1)
                        ->pluck('profile_key')
                        ->unique()
                        ->toArray();
                } catch (\Throwable) {
                    return [];
                }
            }
            // Don't push back to the actor
            return array_values(array_filter($profiles, static fn (string $p): bool => $p !== $actor));
        }

        // Personal tasks: push to owner + assignees (but not back to actor)
        $owner = trim((string)($payload['owner_key'] ?? $actor));
        if ($owner === '') {
            $owner = $actor;
        }
        $assignees = self::normalizeAssignees($payload);
        $recipients = array_unique(array_merge([$owner], $assignees));
        // Don't push back to the actor
        $recipients = array_values(array_filter($recipients, static fn (string $p): bool => $p !== $actor));
        // Filter to valid profiles
        return array_values(array_filter($recipients, static fn (string $p): bool =>
            Profiles::isAllowed($p) || self::profileExists($p)
        ));
    }

    public static function recipientsForReminder(string $entity, array $payload): array
    {
        if ($entity === 'family_task') {
            return self::normalizeAssignees($payload);
        }

        // Personal tasks: remind owner + assignees
        $owner = trim((string)($payload['owner_key'] ?? ''));
        $assignees = self::normalizeAssignees($payload);
        $recipients = array_unique(array_merge([$owner], $assignees));
        return array_values(array_filter($recipients, static fn (string $p): bool =>
            Profiles::isAllowed($p) || self::profileExists($p)
        ));
    }

    private static function profileExists(string $profile): bool
    {
        try {
            return DB::table('messenger_users')->where('profile_key', trim($profile))->exists();
        } catch (\Throwable) {
            return false;
        }
    }

    private static function hasActiveToken(string $profile): bool
    {
        try {
            return DB::table('device_tokens')
                ->where('profile_key', trim($profile))
                ->where('is_active', 1)
                ->exists();
        } catch (\Throwable) {
            return false;
        }
    }
}
