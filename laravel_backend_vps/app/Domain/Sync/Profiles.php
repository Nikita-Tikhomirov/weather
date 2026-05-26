<?php

namespace App\Domain\Sync;

use Illuminate\Support\Facades\DB;

final class Profiles
{
    /** @deprecated No longer used — any registered user has full permissions. */
    public const ADULTS = [];
    /** @deprecated No longer used — replaced by dynamic messenger_users lookup. */
    public const ALLOWED = ['nik', 'nastya', 'misha', 'arisha'];
    public const ALLOWED_WORKFLOW = ['todo', 'in_progress', 'in_review', 'done', 'archive'];

    /** Any registered user is considered "adult" — no permission restrictions. */
    public static function isAdult(string $profile): bool
    {
        return self::isAllowed($profile);
    }

    /** Check if a profile exists in messenger_users. */
    public static function isAllowed(string $profile): bool
    {
        if (in_array($profile, self::ALLOWED, true)) {
            return true;
        }
        try {
            return DB::table('messenger_users')->where('profile_key', trim($profile))->exists();
        } catch (\Throwable) {
            return false;
        }
    }
}
