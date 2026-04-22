<?php

namespace App\Domain\Sync;

final class Profiles
{
    public const ADULTS = ['nik', 'nastya'];
    public const ALLOWED = ['nik', 'nastya', 'misha', 'arisha'];
    public const ALLOWED_WORKFLOW = ['todo', 'in_progress', 'in_review', 'done'];

    public static function isAdult(string $profile): bool
    {
        return in_array($profile, self::ADULTS, true);
    }

    public static function isAllowed(string $profile): bool
    {
        return in_array($profile, self::ALLOWED, true);
    }
}
