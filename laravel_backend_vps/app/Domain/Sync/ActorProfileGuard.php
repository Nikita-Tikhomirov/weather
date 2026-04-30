<?php

namespace App\Domain\Sync;

use Illuminate\Support\Facades\DB;
use InvalidArgumentException;

final class ActorProfileGuard
{
    public static function ensureAllowed(string $actor): string
    {
        $profile = trim($actor);
        if ($profile === '') {
            throw new InvalidArgumentException('Unknown actor_profile');
        }
        if (!Profiles::isAllowed($profile) && !self::dynamicProfileExists($profile)) {
            throw new InvalidArgumentException('Unknown actor_profile');
        }
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

    private static function dynamicProfileExists(string $profile): bool
    {
        try {
            return DB::table('messenger_users')->where('profile_key', $profile)->exists();
        } catch (\Throwable) {
            return false;
        }
    }
}
