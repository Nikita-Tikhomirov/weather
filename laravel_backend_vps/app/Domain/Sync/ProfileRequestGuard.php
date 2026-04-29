<?php

namespace App\Domain\Sync;

use Illuminate\Http\Request;
use InvalidArgumentException;

final class ProfileRequestGuard
{
    public static function ensureAllowed(Request $request, string $actor): string
    {
        $profile = SyncRules::ensureActor($actor);
        $lockedProfile = self::lockedProfileForRequest($request);
        if ($lockedProfile === null || $lockedProfile === $profile) {
            return $profile;
        }

        throw new InvalidArgumentException('Profile is locked for this device');
    }

    private static function lockedProfileForRequest(Request $request): ?string
    {
        $locks = self::profileIpLocks();
        if ($locks === []) {
            return null;
        }

        $ips = array_values(array_filter([
            trim((string) $request->headers->get('X-Forwarded-For')),
            trim((string) $request->server('REMOTE_ADDR', '')),
            trim((string) $request->ip()),
        ]));

        foreach ($ips as $rawIp) {
            $ip = trim(explode(',', $rawIp)[0]);
            if ($ip !== '' && array_key_exists($ip, $locks)) {
                return $locks[$ip];
            }
        }

        return null;
    }

    /**
     * @return array<string, string>
     */
    private static function profileIpLocks(): array
    {
        $raw = trim((string) config('sync.profile_ip_locks', ''));
        if ($raw === '') {
            return [];
        }

        $locks = [];
        foreach (explode(',', $raw) as $item) {
            [$profile, $ip] = array_pad(explode('=', trim($item), 2), 2, '');
            $profile = trim($profile);
            $ip = trim($ip);
            if ($ip !== '' && Profiles::isAllowed($profile)) {
                $locks[$ip] = $profile;
            }
        }

        return $locks;
    }
}
