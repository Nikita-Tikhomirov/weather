<?php

namespace App\Domain\Access;

use Illuminate\Support\Facades\DB;
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

    /** @return array<string, mixed> */
    public function accessForActor(string $actor): array
    {
        $profile = trim($actor);
        if ($profile === '') {
            throw new InvalidArgumentException('actor_profile is required');
        }

        $row = DB::table('messenger_users')->where('profile_key', $profile)->first();
        $phone = $row === null
            ? $this->legacyProfilePhone($profile)
            : (string) $row->phone_normalized;

        return $this->accessForPhone($phone, $profile);
    }

    /** @return array<string, mixed> */
    public function accessForPhone(string $phone, string $profileKey = ''): array
    {
        $normalizedPhone = $this->normalizePhone($phone);
        $isSuperadmin = $normalizedPhone === $this->superadminPhone();

        return [
            'phone' => $normalizedPhone,
            'profile_key' => trim($profileKey),
            'roles' => $isSuperadmin
                ? ['messenger_user', 'superadmin']
                : ['messenger_user'],
            'capabilities' => $isSuperadmin
                ? self::ALL_CAPABILITIES
                : ['messenger.use'],
            'is_superadmin' => $isSuperadmin,
        ];
    }

    public function isSuperadminActor(string $actor): bool
    {
        try {
            return (bool) ($this->accessForActor($actor)['is_superadmin'] ?? false);
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
    ): array {
        $access = $this->accessForActor($actor);
        $capabilities = array_map('strval', $access['capabilities'] ?? []);
        $mode = $this->normalizeMode($requestedMode) ?: $this->defaultMode($taskType);

        foreach (['workspaces.use', 'tasks.manage_agent', 'ai.use'] as $required) {
            if (!in_array($required, $capabilities, true)) {
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
            'task_type' => $this->normalizeTaskType($taskType),
            'task_id' => trim($taskId),
            'workspace_id' => trim($workspaceId),
            'mode' => $mode,
            'mode_label' => $this->modeLabel($mode),
            'plugins' => $this->pluginsForMode($mode, $capabilities),
            'allowed_commands' => $this->commandsForMode($mode, $capabilities),
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
        return $this->base64Url($payloadJson).'.'.$this->base64Url($signature);
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
        return match (trim($profile)) {
            'nik' => $this->superadminPhone(),
            default => '',
        };
    }

    private function superadminPhone(): string
    {
        $configured = (string) config('sync.superadmin_phone', self::SUPERADMIN_PHONE);
        return $this->normalizePhone($configured) ?: self::SUPERADMIN_PHONE;
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
            'task_type' => $this->normalizeTaskType($taskType),
            'task_id' => trim($taskId),
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
}
