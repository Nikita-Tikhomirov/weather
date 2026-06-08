<?php

namespace App\Domain\Access;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use InvalidArgumentException;

final class AccessPolicyService
{
    public const SUPERADMIN_PHONE = '79679812438';

    /** @var list<string> */
    private const ALL_CAPABILITIES = [
        'messenger.use',
        'projects.view',
        'projects.manage',
        'tasks.view',
        'tasks.comment',
        'tasks.edit',
        'tasks.change_status',
        'tasks.manage_agent',
        'workspaces.view',
        'workspaces.use',
        'workspaces.grant_access',
        'ai.use',
        'ai.write_task_comments',
        'ai.change_task_status',
        'ai.manage_checklists',
        'ai.autopilot',
        'agent.git_write',
        'agent.github',
        'agent.browser',
        'agent.deploy',
        'admin.audit',
    ];

    /** @var array<string, list<string>> */
    private const DEFAULT_ROLE_CAPABILITIES = [
        'messenger_user' => ['messenger.use'],
        'project_member' => ['messenger.use', 'projects.view', 'tasks.view', 'tasks.comment'],
        'project_admin' => [
            'messenger.use',
            'projects.view',
            'projects.manage',
            'tasks.view',
            'tasks.comment',
            'tasks.edit',
            'tasks.change_status',
            'tasks.manage_agent',
        ],
        'workspace_user' => [
            'messenger.use',
            'projects.view',
            'tasks.view',
            'tasks.comment',
            'workspaces.view',
            'workspaces.use',
            'ai.use',
        ],
        'agent_operator' => [
            'messenger.use',
            'projects.view',
            'tasks.view',
            'tasks.comment',
            'tasks.edit',
            'tasks.change_status',
            'tasks.manage_agent',
            'workspaces.view',
            'workspaces.use',
            'ai.use',
            'ai.write_task_comments',
            'ai.change_task_status',
            'ai.manage_checklists',
            'agent.git_write',
        ],
        'workspace_admin' => [
            'messenger.use',
            'projects.view',
            'projects.manage',
            'tasks.view',
            'tasks.comment',
            'tasks.edit',
            'tasks.change_status',
            'tasks.manage_agent',
            'workspaces.view',
            'workspaces.use',
            'ai.use',
            'ai.write_task_comments',
            'ai.change_task_status',
            'ai.manage_checklists',
            'agent.git_write',
            'agent.github',
            'agent.browser',
        ],
    ];

    /** @return array<string, mixed> */
    public function accessForActor(string $actor, string $fallbackPhone = ''): array
    {
        $profile = trim($actor);
        if ($profile === '') {
            throw new InvalidArgumentException('actor_profile is required');
        }

        $row = DB::table('messenger_users')->where('profile_key', $profile)->first();
        $phone = $row === null
            ? $this->legacyProfilePhone($profile)
            : (string) $row->phone_normalized;
        if (trim($phone) === '' && trim($fallbackPhone) !== '') {
            $phone = $fallbackPhone;
        }

        return $this->accessForPhone($phone, $profile);
    }

    /** @return array<string, mixed> */
    public function accessForPhone(string $phone, string $profileKey = ''): array
    {
        $normalizedPhone = $this->normalizePhone($phone);
        $isSuperadmin = $normalizedPhone === $this->superadminPhone();
        $profile = trim($profileKey) !== ''
            ? trim($profileKey)
            : $this->profileKeyForPhone($normalizedPhone);

        if ($isSuperadmin) {
            return [
                'phone' => $normalizedPhone,
                'profile_key' => $profile,
                'roles' => ['messenger_user', 'superadmin'],
                'capabilities' => self::ALL_CAPABILITIES,
                'workspaces' => $this->workspaceAccessForProfile($profile),
                'is_superadmin' => true,
            ];
        }

        $workspaceAccess = $this->workspaceAccessForProfile($profile);
        $roles = array_values(array_unique(array_merge(
            ['messenger_user'],
            $this->rolesForProfile($profile),
            array_map(static fn (array $row): string => (string)($row['role'] ?? ''), $workspaceAccess),
            empty($workspaceAccess) ? [] : ['workspace_user'],
        )));
        $roles = array_values(array_filter($roles, static fn (string $role): bool => trim($role) !== ''));

        return [
            'phone' => $normalizedPhone,
            'profile_key' => $profile,
            'roles' => $roles,
            'capabilities' => $this->capabilitiesForRoles($roles),
            'workspaces' => $workspaceAccess,
            'is_superadmin' => false,
        ];
    }

    public function isSuperadminActor(string $actor, string $fallbackPhone = ''): bool
    {
        try {
            return (bool) ($this->accessForActor($actor, $fallbackPhone)['is_superadmin'] ?? false);
        } catch (\Throwable) {
            return false;
        }
    }

    /** @return array<string, mixed> */
    public function agentPolicy(
        string $actor,
        string $taskType,
        string $requestedMode,
        string $workspaceId,
        string $taskId,
        string $actorPhone = '',
    ): array {
        $access = $this->accessForActor($actor, $actorPhone);
        $capabilities = array_map('strval', $access['capabilities'] ?? []);
        $mode = $this->normalizeMode($requestedMode) ?: $this->defaultMode($taskType);
        $workspaceId = trim($workspaceId);
        $taskId = trim($taskId);

        if ($workspaceId === '') {
            return $this->deniedPolicy(
                $access,
                $taskType,
                $mode,
                $workspaceId,
                $taskId,
                'Выберите воркспейс для запуска агента.',
            );
        }

        if (!$this->hasWorkspaceAccess($actor, $workspaceId, $actorPhone)) {
            $this->writeAudit($actor, 'agent.policy_denied', 'workspace', $workspaceId, [
                'task_id' => $taskId,
                'reason' => 'workspace_access_missing',
            ]);
            return $this->deniedPolicy(
                $access,
                $taskType,
                $mode,
                $workspaceId,
                $taskId,
                'Нет доступа к выбранному воркспейсу.',
            );
        }

        foreach (['workspaces.use', 'tasks.manage_agent', 'ai.use'] as $required) {
            if (!in_array($required, $capabilities, true)) {
                $this->writeAudit($actor, 'agent.policy_denied', 'task', $taskId, [
                    'workspace_id' => $workspaceId,
                    'missing_capability' => $required,
                ]);
                return $this->deniedPolicy(
                    $access,
                    $taskType,
                    $mode,
                    $workspaceId,
                    $taskId,
                    'Нет прав на запуск агента из задачи.',
                );
            }
        }

        if (
            in_array($mode, ['executor', 'autopilot', 'yolo'], true)
            && !in_array('tasks.edit', $capabilities, true)
        ) {
            return $this->deniedPolicy(
                $access,
                $taskType,
                $mode,
                $workspaceId,
                $taskId,
                'Нет прав на изменение задачи агентом.',
            );
        }

        if ($mode === 'autopilot' && !in_array('ai.autopilot', $capabilities, true)) {
            return $this->deniedPolicy(
                $access,
                $taskType,
                $mode,
                $workspaceId,
                $taskId,
                'Нет прав на автопилот агента.',
            );
        }

        return [
            'allowed' => true,
            'reason' => '',
            'phone' => (string) ($access['phone'] ?? ''),
            'profile_key' => (string) ($access['profile_key'] ?? ''),
            'roles' => array_map('strval', $access['roles'] ?? []),
            'capabilities' => $capabilities,
            'scope' => 'task',
            'task_type' => $this->normalizeTaskType($taskType),
            'task_id' => $taskId,
            'workspace_id' => $workspaceId,
            'mode' => $mode,
            'mode_label' => $this->modeLabel($mode),
            'plugins' => $this->pluginsForMode($mode, $capabilities),
            'allowed_commands' => $this->commandsForMode($mode, $capabilities),
        ];
    }

    /** @return array<string, mixed> */
    public function agentProjectChatPolicy(
        string $actor,
        string $requestedMode,
        string $workspaceId,
        string $projectId,
        string $conversationKey,
        string $actorPhone = '',
    ): array {
        $access = $this->accessForActor($actor, $actorPhone);
        $capabilities = array_map('strval', $access['capabilities'] ?? []);
        $mode = $this->normalizeMode($requestedMode) ?: 'planner';
        $workspaceId = trim($workspaceId);
        $projectId = trim($projectId);
        $conversationKey = trim($conversationKey);

        if ($workspaceId === '') {
            return $this->deniedProjectChatPolicy(
                $access,
                $mode,
                $workspaceId,
                $projectId,
                $conversationKey,
                'Выберите воркспейс проекта для запуска агента.',
            );
        }
        if ($projectId === '' || $conversationKey === '') {
            return $this->deniedProjectChatPolicy(
                $access,
                $mode,
                $workspaceId,
                $projectId,
                $conversationKey,
                'Выберите проект и связанный чат.',
            );
        }

        if (!$this->hasWorkspaceAccess($actor, $workspaceId, $actorPhone)) {
            $this->writeAudit($actor, 'agent.project_chat_policy_denied', 'workspace', $workspaceId, [
                'project_id' => $projectId,
                'conversation_key' => $conversationKey,
                'reason' => 'workspace_access_missing',
            ]);
            return $this->deniedProjectChatPolicy(
                $access,
                $mode,
                $workspaceId,
                $projectId,
                $conversationKey,
                'Нет доступа к воркспейсу проекта.',
            );
        }

        foreach (['projects.view', 'workspaces.use', 'ai.use'] as $required) {
            if (!in_array($required, $capabilities, true)) {
                $this->writeAudit($actor, 'agent.project_chat_policy_denied', 'project', $projectId, [
                    'workspace_id' => $workspaceId,
                    'conversation_key' => $conversationKey,
                    'missing_capability' => $required,
                ]);
                return $this->deniedProjectChatPolicy(
                    $access,
                    $mode,
                    $workspaceId,
                    $projectId,
                    $conversationKey,
                    'Нет прав на агента в чате проекта.',
                );
            }
        }

        return [
            'allowed' => true,
            'reason' => '',
            'phone' => (string)($access['phone'] ?? ''),
            'profile_key' => (string)($access['profile_key'] ?? ''),
            'roles' => array_map('strval', $access['roles'] ?? []),
            'capabilities' => $capabilities,
            'scope' => 'project_chat',
            'task_type' => 'planning',
            'task_id' => '',
            'project_id' => $projectId,
            'conversation_key' => $conversationKey,
            'workspace_id' => $workspaceId,
            'mode' => $mode,
            'mode_label' => $this->modeLabel($mode),
            'plugins' => $this->pluginsForProjectChatMode($capabilities),
            'allowed_commands' => $this->projectChatCommands($capabilities),
        ];
    }

    public function signPolicyTicket(array $policy, string $secret, int $ttlSeconds = 900): string
    {
        $secret = trim($secret);
        if ($secret === '') {
            throw new InvalidArgumentException('agent policy ticket secret is required');
        }
        if (!((bool) ($policy['allowed'] ?? false))) {
            throw new InvalidArgumentException('agent policy is not allowed');
        }

        $now = time();
        $payload = $policy;
        $payload['iat'] = $now;
        $payload['exp'] = $now + $ttlSeconds;
        $payloadJson = json_encode(
            $payload,
            JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES,
        );
        if (!is_string($payloadJson)) {
            throw new InvalidArgumentException('agent policy payload is invalid');
        }

        $signature = hash_hmac('sha256', $payloadJson, $secret, true);
        $ticket = $this->base64Url($payloadJson).'.'.$this->base64Url($signature);
        $this->storePolicyTicket($ticket, $payload);
        return $ticket;
    }

    /** @return array<string, mixed> */
    public function validatePolicyTicket(string $ticket, string $secret): array
    {
        $ticket = trim($ticket);
        $secret = trim($secret);
        if ($ticket === '' || $secret === '') {
            throw new InvalidArgumentException('policy ticket is required');
        }
        $parts = explode('.', $ticket);
        if (count($parts) !== 2) {
            throw new InvalidArgumentException('policy ticket format is invalid');
        }
        [$payloadPart, $signaturePart] = $parts;
        $payloadJson = $this->base64UrlDecode($payloadPart);
        $expected = hash_hmac('sha256', $payloadJson, $secret, true);
        $actual = $this->base64UrlDecode($signaturePart);
        if (!hash_equals($expected, $actual)) {
            throw new InvalidArgumentException('policy ticket signature is invalid');
        }
        $payload = json_decode($payloadJson, true);
        if (!is_array($payload)) {
            throw new InvalidArgumentException('policy ticket payload is invalid');
        }
        if ((int)($payload['exp'] ?? 0) < time()) {
            throw new InvalidArgumentException('policy ticket expired');
        }
        return $payload;
    }

    /** @return array<string, mixed> */
    public function grantWorkspaceAccess(
        string $actor,
        string $profileKey,
        string $workspaceId,
        string $role = 'workspace_user',
        string $actorPhone = '',
    ): array {
        if (!$this->isSuperadminActor($actor, $actorPhone)) {
            $this->writeAudit($actor, 'workspace_access.grant_denied', 'workspace', trim($workspaceId), [
                'profile_key' => trim($profileKey),
            ]);
            throw new InvalidArgumentException('Выдавать доступ к воркспейсам может только суперадмин.');
        }

        $profileKey = trim($profileKey);
        $workspaceId = trim($workspaceId);
        $role = $this->normalizeWorkspaceRole($role);
        if ($profileKey === '') {
            throw new InvalidArgumentException('profile_key is required');
        }
        if ($workspaceId === '') {
            throw new InvalidArgumentException('workspace_id is required');
        }
        if (!Schema::hasTable('workspace_access')) {
            throw new InvalidArgumentException('workspace_access table is not ready');
        }

        $now = $this->nowIso();
        DB::table('workspace_access')->updateOrInsert(
            ['workspace_id' => $workspaceId, 'profile_key' => $profileKey],
            [
                'role' => $role,
                'granted_by' => trim($actor),
                'created_at' => $now,
                'updated_at' => $now,
                'revoked_at' => null,
            ],
        );

        $grant = [
            'workspace_id' => $workspaceId,
            'profile_key' => $profileKey,
            'role' => $role,
            'granted_by' => trim($actor),
            'created_at' => $now,
            'updated_at' => $now,
            'revoked_at' => null,
        ];
        $this->writeAudit($actor, 'workspace_access.grant', 'workspace', $workspaceId, $grant);
        return $grant;
    }

    public function revokeWorkspaceAccess(
        string $actor,
        string $profileKey,
        string $workspaceId,
        string $actorPhone = '',
    ): void
    {
        if (!$this->isSuperadminActor($actor, $actorPhone)) {
            $this->writeAudit($actor, 'workspace_access.revoke_denied', 'workspace', trim($workspaceId), [
                'profile_key' => trim($profileKey),
            ]);
            throw new InvalidArgumentException('Отзывать доступ к воркспейсам может только суперадмин.');
        }
        if (!Schema::hasTable('workspace_access')) {
            throw new InvalidArgumentException('workspace_access table is not ready');
        }

        $now = $this->nowIso();
        DB::table('workspace_access')
            ->where('workspace_id', trim($workspaceId))
            ->where('profile_key', trim($profileKey))
            ->update(['revoked_at' => $now, 'updated_at' => $now]);
        $this->writeAudit($actor, 'workspace_access.revoke', 'workspace', trim($workspaceId), [
            'profile_key' => trim($profileKey),
        ]);
    }

    /** @return list<array<string, mixed>> */
    public function listWorkspaceAccess(string $actor, string $workspaceId = '', string $actorPhone = ''): array
    {
        if (!$this->isSuperadminActor($actor, $actorPhone)) {
            throw new InvalidArgumentException('Просмотр доступов к воркспейсам доступен только суперадмину.');
        }
        if (!Schema::hasTable('workspace_access')) {
            return [];
        }

        $query = DB::table('workspace_access')->orderBy('workspace_id')->orderBy('profile_key');
        if (trim($workspaceId) !== '') {
            $query->where('workspace_id', trim($workspaceId));
        }

        return $query->get()->map(static fn ($row): array => [
            'workspace_id' => (string) $row->workspace_id,
            'profile_key' => (string) $row->profile_key,
            'role' => (string) $row->role,
            'granted_by' => (string) ($row->granted_by ?? ''),
            'created_at' => (string) ($row->created_at ?? ''),
            'updated_at' => (string) ($row->updated_at ?? ''),
            'revoked_at' => (string) ($row->revoked_at ?? ''),
        ])->values()->all();
    }

    /** @return list<array<string, mixed>> */
    public function auditLogs(string $actor, int $limit = 100, string $actorPhone = ''): array
    {
        if (!$this->isSuperadminActor($actor, $actorPhone)) {
            throw new InvalidArgumentException('Аудит доступен только суперадмину.');
        }
        if (!Schema::hasTable('audit_logs')) {
            return [];
        }

        return DB::table('audit_logs')
            ->orderByDesc('created_at')
            ->limit(max(1, min(500, $limit)))
            ->get()
            ->map(function ($row): array {
                return [
                    'id' => (string) $row->id,
                    'actor_profile' => (string) $row->actor_profile,
                    'action' => (string) $row->action,
                    'target_type' => (string) $row->target_type,
                    'target_id' => (string) $row->target_id,
                    'payload' => $this->decodeJsonArray($row->payload_json),
                    'created_at' => (string) $row->created_at,
                ];
            })
            ->values()
            ->all();
    }

    public function hasWorkspaceAccess(string $actor, string $workspaceId, string $actorPhone = ''): bool
    {
        $workspaceId = trim($workspaceId);
        if ($workspaceId === '') {
            return false;
        }
        $access = $this->accessForActor($actor, $actorPhone);
        if ((bool)($access['is_superadmin'] ?? false)) {
            return true;
        }
        $profile = (string)($access['profile_key'] ?? trim($actor));
        if ($profile === '' || !Schema::hasTable('workspace_access')) {
            return false;
        }

        return DB::table('workspace_access')
            ->where('profile_key', $profile)
            ->where('workspace_id', $workspaceId)
            ->whereNull('revoked_at')
            ->exists();
    }

    /** @param array<string, mixed> $payload */
    public function writeAudit(string $actor, string $action, string $targetType, string $targetId, array $payload = []): void
    {
        try {
            if (!Schema::hasTable('audit_logs')) {
                return;
            }
            DB::table('audit_logs')->insert([
                'id' => 'audit-'.str_replace('.', '', uniqid('', true)),
                'actor_profile' => trim($actor),
                'action' => trim($action),
                'target_type' => trim($targetType),
                'target_id' => trim($targetId),
                'payload_json' => json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
                'created_at' => $this->nowIso(),
            ]);
        } catch (\Throwable) {
        }
    }

    private function normalizePhone(string $phone): string
    {
        $digits = preg_replace('/\D+/', '', $phone) ?? '';
        if (strlen($digits) === 11 && str_starts_with($digits, '8')) {
            return '7'.substr($digits, 1);
        }
        if (strlen($digits) === 10) {
            return '7'.$digits;
        }
        return $digits;
    }

    private function legacyProfilePhone(string $profile): string
    {
        return match (strtolower(trim($profile))) {
            'nik', 'nikita' => $this->superadminPhone(),
            default => '',
        };
    }

    private function profileKeyForPhone(string $phone): string
    {
        try {
            if (!Schema::hasTable('messenger_users')) {
                return '';
            }
            $profile = DB::table('messenger_users')
                ->where('phone_normalized', $phone)
                ->value('profile_key');
            return is_string($profile) ? $profile : '';
        } catch (\Throwable) {
            return '';
        }
    }

    private function superadminPhone(): string
    {
        $configured = (string) config('sync.superadmin_phone', self::SUPERADMIN_PHONE);
        return $this->normalizePhone($configured) ?: self::SUPERADMIN_PHONE;
    }

    /** @return list<string> */
    private function rolesForProfile(string $profile): array
    {
        if ($profile === '' || !Schema::hasTable('user_roles')) {
            return [];
        }
        try {
            return DB::table('user_roles')
                ->where('profile_key', $profile)
                ->pluck('role')
                ->map(static fn ($value): string => (string) $value)
                ->filter(static fn (string $value): bool => trim($value) !== '')
                ->values()
                ->all();
        } catch (\Throwable) {
            return [];
        }
    }

    /** @param list<string> $roles @return list<string> */
    private function capabilitiesForRoles(array $roles): array
    {
        if (in_array('superadmin', $roles, true)) {
            return self::ALL_CAPABILITIES;
        }

        $capabilities = [];
        foreach ($roles as $role) {
            foreach (self::DEFAULT_ROLE_CAPABILITIES[$role] ?? [] as $capability) {
                $capabilities[] = $capability;
            }
        }

        if (Schema::hasTable('role_capabilities')) {
            try {
                $dbCaps = DB::table('role_capabilities')
                    ->whereIn('role', $roles)
                    ->pluck('capability')
                    ->map(static fn ($value): string => (string) $value)
                    ->values()
                    ->all();
                $capabilities = array_merge($capabilities, $dbCaps);
            } catch (\Throwable) {
            }
        }

        $allowed = array_flip(self::ALL_CAPABILITIES);
        return array_values(array_unique(array_filter(
            $capabilities,
            static fn (string $capability): bool => isset($allowed[$capability]),
        )));
    }

    /** @return list<array<string, mixed>> */
    private function workspaceAccessForProfile(string $profile): array
    {
        if ($profile === '' || !Schema::hasTable('workspace_access')) {
            return [];
        }
        try {
            return DB::table('workspace_access')
                ->where('profile_key', $profile)
                ->whereNull('revoked_at')
                ->orderBy('workspace_id')
                ->get()
                ->map(static fn ($row): array => [
                    'workspace_id' => (string) $row->workspace_id,
                    'profile_key' => (string) $row->profile_key,
                    'role' => (string) $row->role,
                    'granted_by' => (string) ($row->granted_by ?? ''),
                    'created_at' => (string) ($row->created_at ?? ''),
                    'updated_at' => (string) ($row->updated_at ?? ''),
                    'revoked_at' => (string) ($row->revoked_at ?? ''),
                ])
                ->values()
                ->all();
        } catch (\Throwable) {
            return [];
        }
    }

    private function normalizeWorkspaceRole(string $role): string
    {
        $value = strtolower(trim($role));
        return in_array($value, ['workspace_user', 'agent_operator', 'workspace_admin'], true)
            ? $value
            : 'workspace_user';
    }

    /** @param array<string, mixed> $payload */
    private function storePolicyTicket(string $ticket, array $payload): void
    {
        try {
            if (!Schema::hasTable('agent_policy_tickets')) {
                return;
            }
            DB::table('agent_policy_tickets')->updateOrInsert(
                ['id' => hash('sha256', $ticket)],
                [
                    'actor_profile' => (string)($payload['profile_key'] ?? ''),
                    'task_id' => (string)($payload['task_id'] ?? ''),
                    'workspace_id' => (string)($payload['workspace_id'] ?? ''),
                    'mode' => (string)($payload['mode'] ?? ''),
                    'allowed_commands_json' => json_encode(
                        array_values(is_array($payload['allowed_commands'] ?? null) ? $payload['allowed_commands'] : []),
                        JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES,
                    ),
                    'expires_at' => date('Y-m-d\TH:i:s', (int)($payload['exp'] ?? time())),
                    'created_at' => $this->nowIso(),
                    'revoked_at' => null,
                ],
            );
        } catch (\Throwable) {
        }
    }

    private function nowIso(): string
    {
        return now()->format('Y-m-d\TH:i:s');
    }

    /** @return array<int|string, mixed> */
    private function decodeJsonArray(mixed $value): array
    {
        if (is_array($value)) {
            return $value;
        }
        if (!is_string($value) || trim($value) === '') {
            return [];
        }
        $decoded = json_decode($value, true);
        return is_array($decoded) ? $decoded : [];
    }

    private function normalizeTaskType(string $taskType): string
    {
        $value = strtolower(trim($taskType));
        return in_array($value, ['bugfix', 'feature', 'review', 'docs', 'planning'], true)
            ? $value
            : 'feature';
    }

    private function defaultMode(string $taskType): string
    {
        return match ($this->normalizeTaskType($taskType)) {
            'review' => 'reviewer',
            'docs' => 'commentator',
            'planning' => 'planner',
            default => 'executor',
        };
    }

    private function normalizeMode(string $mode): string
    {
        return match (strtolower(trim($mode))) {
            'план', 'plan', 'planner' => 'planner',
            'чат', 'chat' => 'chat',
            'комментатор', 'commentator' => 'commentator',
            'исполнитель', 'agent', 'executor' => 'executor',
            'ревьюер', 'review', 'reviewer' => 'reviewer',
            'автопилот', 'autopilot' => 'autopilot',
            'yolo' => 'yolo',
            default => '',
        };
    }

    private function modeLabel(string $mode): string
    {
        return match ($mode) {
            'planner' => 'План',
            'chat' => 'Чат',
            'commentator' => 'Комментатор',
            'executor' => 'Исполнитель',
            'reviewer' => 'Ревьюер',
            'autopilot' => 'Автопилот',
            'yolo' => 'YOLO',
            default => '',
        };
    }

    /** @param list<string> $capabilities @return list<string> */
    private function pluginsForMode(string $mode, array $capabilities): array
    {
        $plugins = ['task_context'];
        if (in_array('ai.write_task_comments', $capabilities, true)) {
            $plugins[] = 'task_write';
        }
        if (in_array('workspaces.view', $capabilities, true)) {
            $plugins[] = 'workspace_read';
        }
        if (
            in_array($mode, ['executor', 'autopilot', 'yolo'], true)
            && in_array('workspaces.use', $capabilities, true)
        ) {
            $plugins[] = 'workspace_write';
        }
        if (in_array('agent.git_write', $capabilities, true)) {
            $plugins[] = 'git';
        }
        if (in_array('agent.github', $capabilities, true)) {
            $plugins[] = 'github';
        }
        if (in_array('agent.browser', $capabilities, true)) {
            $plugins[] = 'browser';
        }
        if (
            in_array($mode, ['autopilot', 'yolo'], true)
            && in_array('agent.deploy', $capabilities, true)
        ) {
            $plugins[] = 'deploy';
        }
        if (in_array('admin.audit', $capabilities, true)) {
            $plugins[] = 'audit';
        }

        return array_values(array_unique($plugins));
    }

    /** @param list<string> $capabilities @return list<string> */
    private function commandsForMode(string $mode, array $capabilities): array
    {
        $commands = [
            'session_health',
            'session_list',
            'session_open',
            'workspace_discover',
            'workspace_file_list',
            'workspace_file_read',
            'workspace_folder_list',
            'workspace_list',
        ];
        if (
            in_array('workspaces.use', $capabilities, true)
            && in_array($mode, ['chat', 'commentator', 'executor', 'reviewer', 'autopilot', 'yolo'], true)
        ) {
            array_push(
                $commands,
                'session_create',
                'session_send',
                'session_start',
                'session_stop',
                'session_task_poll',
                'session_update_task_card',
                'session_upload_file',
            );
        }
        if (in_array('tasks.manage_agent', $capabilities, true)) {
            array_push($commands, 'session_kill', 'session_update_settings');
        }
        if (in_array('workspaces.grant_access', $capabilities, true)) {
            array_push($commands, 'workspace_attach', 'workspace_create');
        }

        sort($commands);
        return array_values(array_unique($commands));
    }

    /** @param list<string> $capabilities @return list<string> */
    private function pluginsForProjectChatMode(array $capabilities): array
    {
        $plugins = ['project_chat_context'];
        if (in_array('workspaces.view', $capabilities, true)) {
            $plugins[] = 'workspace_read';
        }
        if (in_array('admin.audit', $capabilities, true)) {
            $plugins[] = 'audit';
        }
        return array_values(array_unique($plugins));
    }

    /** @param list<string> $capabilities @return list<string> */
    private function projectChatCommands(array $capabilities): array
    {
        $commands = [
            'session_health',
            'session_list',
            'session_open',
            'workspace_discover',
            'workspace_file_list',
            'workspace_file_read',
            'workspace_folder_list',
            'workspace_list',
        ];
        if (in_array('workspaces.use', $capabilities, true) && in_array('ai.use', $capabilities, true)) {
            array_push(
                $commands,
                'session_create',
                'session_send',
                'session_start',
                'session_stop',
                'session_task_poll',
            );
        }
        sort($commands);
        return array_values(array_unique($commands));
    }

    /** @return array<string, mixed> */
    private function deniedPolicy(
        array $access,
        string $taskType,
        string $mode,
        string $workspaceId,
        string $taskId,
        string $reason,
    ): array {
        return [
            'allowed' => false,
            'reason' => $reason,
            'phone' => (string) ($access['phone'] ?? ''),
            'profile_key' => (string) ($access['profile_key'] ?? ''),
            'roles' => array_map('strval', $access['roles'] ?? []),
            'capabilities' => array_map('strval', $access['capabilities'] ?? []),
            'scope' => 'task',
            'task_type' => $this->normalizeTaskType($taskType),
            'task_id' => trim($taskId),
            'workspace_id' => trim($workspaceId),
            'mode' => $mode,
            'mode_label' => $this->modeLabel($mode),
            'plugins' => [],
            'allowed_commands' => [],
        ];
    }

    /** @return array<string, mixed> */
    private function deniedProjectChatPolicy(
        array $access,
        string $mode,
        string $workspaceId,
        string $projectId,
        string $conversationKey,
        string $reason,
    ): array {
        return [
            'allowed' => false,
            'reason' => $reason,
            'phone' => (string)($access['phone'] ?? ''),
            'profile_key' => (string)($access['profile_key'] ?? ''),
            'roles' => array_map('strval', $access['roles'] ?? []),
            'capabilities' => array_map('strval', $access['capabilities'] ?? []),
            'scope' => 'project_chat',
            'task_type' => 'planning',
            'task_id' => '',
            'project_id' => trim($projectId),
            'conversation_key' => trim($conversationKey),
            'workspace_id' => trim($workspaceId),
            'mode' => $mode,
            'mode_label' => $this->modeLabel($mode),
            'plugins' => [],
            'allowed_commands' => [],
        ];
    }

    private function base64Url(string $value): string
    {
        return rtrim(strtr(base64_encode($value), '+/', '-_'), '=');
    }

    private function base64UrlDecode(string $value): string
    {
        $padded = $value.str_repeat('=', (4 - strlen($value) % 4) % 4);
        $decoded = base64_decode(strtr($padded, '-_', '+/'), true);
        if (!is_string($decoded)) {
            throw new InvalidArgumentException('policy ticket base64 is invalid');
        }
        return $decoded;
    }
}
