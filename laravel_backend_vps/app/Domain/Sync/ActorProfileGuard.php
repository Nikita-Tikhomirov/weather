<?php

namespace App\Domain\Sync;

use InvalidArgumentException;

final class ActorProfileGuard
{
    public static function ensureAllowed(string $actor): string
    {
        $profile = SyncRules::ensureActor($actor);
        $locked = trim((string) config('sync.locked_actor_profile', ''));
        if ($locked === '') {
            return $profile;
        }
        if (!Profiles::isAllowed($locked)) {
            throw new InvalidArgumentException('Invalid locked actor profile');
        }
        if ($profile !== $locked) {
            throw new InvalidArgumentException('Profile switching is disabled');
        }

        return $profile;
    }
}
