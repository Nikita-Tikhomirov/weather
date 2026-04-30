<?php

namespace App\Domain\Profiles;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use InvalidArgumentException;

final class PhoneProfileRepository
{
    public function startDevice(string $phone, string $deviceId, string $displayName = '', string $platform = 'android', string $appVersion = ''): array
    {
        $normalizedPhone = $this->normalizePhone($phone);
        $normalizedDevice = trim($deviceId);
        if ($normalizedDevice === '') {
            throw new InvalidArgumentException('device_id is required');
        }

        $now = $this->nowIso();
        $existing = DB::table('messenger_users')
            ->where('phone_normalized', $normalizedPhone)
            ->first();

        if ($existing !== null) {
            if ((string)$existing->primary_device_id !== $normalizedDevice) {
                throw new InvalidArgumentException('Phone is already linked to another device');
            }
            DB::table('messenger_users')->where('id', (int)$existing->id)->update([
                'display_name' => trim($displayName) !== '' ? trim($displayName) : (string)$existing->display_name,
                'updated_at' => $now,
            ]);
            DB::table('messenger_devices')->updateOrInsert(
                ['device_id' => $normalizedDevice],
                [
                    'user_id' => (int)$existing->id,
                    'platform' => trim($platform) !== '' ? trim($platform) : 'android',
                    'app_version' => trim($appVersion),
                    'created_at' => $now,
                    'updated_at' => $now,
                ]
            );
            $this->ensureFamilyGroup((string)$existing->profile_key);
            return $this->userPayload((int)$existing->id);
        }

        $profileKey = $this->newProfileKey();
        $userId = (int) DB::table('messenger_users')->insertGetId([
            'profile_key' => $profileKey,
            'phone_normalized' => $normalizedPhone,
            'display_name' => trim($displayName) !== '' ? trim($displayName) : $normalizedPhone,
            'primary_device_id' => $normalizedDevice,
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        DB::table('messenger_devices')->insert([
            'device_id' => $normalizedDevice,
            'user_id' => $userId,
            'platform' => trim($platform) !== '' ? trim($platform) : 'android',
            'app_version' => trim($appVersion),
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        $this->ensureFamilyGroup($profileKey);

        return $this->userPayload($userId);
    }

    public function resolveContacts(string $actor, array $phones): array
    {
        if (!$this->profileExists($actor)) {
            throw new InvalidArgumentException('Unknown actor_profile');
        }

        $normalized = [];
        foreach ($phones as $phone) {
            try {
                $value = $this->normalizePhone((string)$phone);
            } catch (InvalidArgumentException) {
                continue;
            }
            if (!in_array($value, $normalized, true)) {
                $normalized[] = $value;
            }
        }
        if ($normalized === []) {
            return [];
        }

        return DB::table('messenger_users')
            ->whereIn('phone_normalized', $normalized)
            ->where('profile_key', '<>', $actor)
            ->orderBy('display_name')
            ->get()
            ->map(fn ($row): array => [
                'profile_key' => (string)$row->profile_key,
                'phone' => (string)$row->phone_normalized,
                'display_name' => (string)$row->display_name,
            ])
            ->values()
            ->all();
    }

    public function familyMembers(string $actor): array
    {
        $group = $this->ensureFamilyGroup($actor);
        return DB::table('family_group_members')
            ->join('messenger_users', 'messenger_users.profile_key', '=', 'family_group_members.profile_key')
            ->where('family_group_members.family_group_id', (int)$group->id)
            ->orderBy('messenger_users.display_name')
            ->get(['messenger_users.profile_key', 'messenger_users.phone_normalized', 'messenger_users.display_name', 'family_group_members.role'])
            ->map(fn ($row): array => [
                'profile_key' => (string)$row->profile_key,
                'phone' => (string)$row->phone_normalized,
                'display_name' => (string)$row->display_name,
                'role' => (string)$row->role,
            ])
            ->values()
            ->all();
    }

    public function addFamilyMembers(string $actor, array $profiles): array
    {
        $group = $this->ensureFamilyGroup($actor);
        $now = $this->nowIso();
        foreach ($profiles as $profile) {
            $key = trim((string)$profile);
            if ($key === '' || !$this->profileExists($key)) {
                continue;
            }
            DB::table('family_group_members')->updateOrInsert(
                ['family_group_id' => (int)$group->id, 'profile_key' => $key],
                ['role' => $key === $actor ? 'owner' : 'member', 'joined_at' => $now]
            );
        }

        return $this->familyMembers($actor);
    }

    public function removeFamilyMember(string $actor, string $profile): array
    {
        $group = $this->ensureFamilyGroup($actor);
        $key = trim($profile);
        if ($key !== $actor) {
            DB::table('family_group_members')
                ->where('family_group_id', (int)$group->id)
                ->where('profile_key', $key)
                ->delete();
        }
        return $this->familyMembers($actor);
    }

    public function profileExists(string $profileKey): bool
    {
        return DB::table('messenger_users')->where('profile_key', trim($profileKey))->exists();
    }

    public function normalizePhone(string $phone): string
    {
        $digits = preg_replace('/\D+/', '', $phone) ?? '';
        if (strlen($digits) === 11 && str_starts_with($digits, '8')) {
            $digits = '7'.substr($digits, 1);
        }
        if (strlen($digits) < 7) {
            throw new InvalidArgumentException('phone is required');
        }
        return $digits;
    }

    public function ensureFamilyGroup(string $actor): object
    {
        $profile = trim($actor);
        if (!$this->profileExists($profile)) {
            throw new InvalidArgumentException('Unknown actor_profile');
        }
        $now = $this->nowIso();
        $group = DB::table('family_groups')->where('owner_profile_key', $profile)->first();
        if ($group === null) {
            $id = (int) DB::table('family_groups')->insertGetId([
                'owner_profile_key' => $profile,
                'title' => 'Family',
                'created_at' => $now,
                'updated_at' => $now,
            ]);
            $group = DB::table('family_groups')->where('id', $id)->first();
        }

        DB::table('family_group_members')->updateOrInsert(
            ['family_group_id' => (int)$group->id, 'profile_key' => $profile],
            ['role' => 'owner', 'joined_at' => $now]
        );

        return $group;
    }

    private function userPayload(int $userId): array
    {
        $row = DB::table('messenger_users')->where('id', $userId)->first();
        if ($row === null) {
            throw new InvalidArgumentException('User not found');
        }

        return [
            'id' => (int)$row->id,
            'profile_key' => (string)$row->profile_key,
            'phone' => (string)$row->phone_normalized,
            'display_name' => (string)$row->display_name,
            'device_id' => (string)$row->primary_device_id,
        ];
    }

    private function newProfileKey(): string
    {
        do {
            $key = 'u_'.strtolower(Str::random(12));
        } while (DB::table('messenger_users')->where('profile_key', $key)->exists());

        return $key;
    }

    private function nowIso(): string
    {
        return now()->format('Y-m-d\\TH:i:s');
    }
}
