<?php

namespace App\Http\Controllers;

use App\Domain\Access\AccessPolicyService;
use App\Domain\Chat\ChatRepository;
use App\Domain\Sync\ActorProfileGuard;
use App\Domain\Sync\SyncRepository;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Throwable;
use InvalidArgumentException;

class ProjectGroupController extends Controller
{
    public function __construct(
        private readonly SyncRepository $repo,
        private readonly ChatRepository $chat,
        private readonly AccessPolicyService $access,
    ) {}
    public function listProjects(Request $request): JsonResponse
    {
        try {
            $actor = trim((string)$request->query('actor_profile', ''));
            if ($actor !== '') {
                ActorProfileGuard::ensureAllowed($actor);
                $projects = $this->repo->visibleProjectsForActor($actor);
            } else {
                $projects = $this->repo->allProjects();
            }
            return $this->json(200, [
                'ok' => true,
                'projects' => $projects,
            ]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function projectControl(Request $request): JsonResponse
    {
        try {
            $actor = ActorProfileGuard::ensureAllowed((string)$request->query(
                'actor_profile',
                (string)$request->input('actor_profile', ''),
            ));
            $projectId = trim((string)$request->query(
                'project_id',
                (string)$request->input('project_id', ''),
            ));
            if ($projectId === '') {
                throw new InvalidArgumentException('project_id is required');
            }

            $visibleProjects = $this->repo->visibleProjectsForActor($actor);
            $project = null;
            foreach ($visibleProjects as $candidate) {
                if ((string)($candidate['id'] ?? '') === $projectId) {
                    $project = $candidate;
                    break;
                }
            }
            if ($project === null) {
                throw new InvalidArgumentException('Project not found');
            }

            $bindings = $this->repo->projectChatBindings($projectId);
            $groupsById = [];
            $visibleGroups = $this->access->isSuperadminActor($actor)
                ? $this->repo->allFamilyGroups()
                : $this->repo->visibleGroupsForActor($actor);
            foreach ($visibleGroups as $group) {
                $groupsById[(string)($group['id'] ?? '')] = $group;
            }
            $projectGroupMap = $this->repo->projectGroupMap();
            $projectGroupIds = is_array($projectGroupMap[$projectId] ?? null)
                ? array_map('strval', $projectGroupMap[$projectId])
                : [];
            $bindings = array_map(function (array $binding) use ($groupsById, $project, $projectGroupIds): array {
                $groupId = (string)($binding['group_id'] ?? '');
                $group = is_array($groupsById[$groupId] ?? null) ? $groupsById[$groupId] : [];
                $source = (string)($binding['source'] ?? '');
                return [
                    ...$binding,
                    'title' => $source === 'project_group'
                        ? (string)($project['name'] ?? '')
                        : (string)($group['name'] ?? ''),
                    'members' => $source === 'project_group'
                        ? $this->projectChatMembers($project, $projectGroupIds, $groupsById)
                        : (is_array($group['members'] ?? null) ? $group['members'] : []),
                ];
            }, $bindings);

            $access = $this->access->accessForActor($actor, $this->actorPhone($request));
            $automation = $this->repo->projectAutomationConfig($projectId);
            $workspaces = is_array($access['workspaces'] ?? null) ? $access['workspaces'] : [];
            $workspaceId = trim((string)($automation['primary_workspace_id'] ?? ''));
            $workspaceIsAccessible = $workspaceId !== ''
                && ((bool)($access['is_superadmin'] ?? false) || $this->workspaceIsAccessible($workspaceId, $workspaces));
            $automation['primary_workspace_id'] = $workspaceId;
            $capabilities = array_map('strval', $access['capabilities'] ?? []);

            return $this->json(200, [
                'ok' => true,
                'snapshot' => [
                    'project' => $project,
                    'chat_bindings' => $bindings,
                    'automation' => $automation,
                    'primary_workspace' => [
                        'id' => $workspaceId,
                        'has_access' => $workspaceIsAccessible,
                    ],
                    'available_workspaces' => $workspaces,
                    'permissions' => [
                        'can_manage_project' => (string)($project['owner_key'] ?? '') === $actor
                            || (bool)($access['is_superadmin'] ?? false),
                        'can_use_agent' => $workspaceIsAccessible
                            && in_array('workspaces.use', $capabilities, true)
                            && in_array('ai.use', $capabilities, true),
                        'can_use_workspace' => $workspaceIsAccessible
                            && in_array('workspaces.use', $capabilities, true),
                    ],
                ],
            ]);
        } catch (InvalidArgumentException $e) {
            return $this->json(403, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function updateProjectAutomation(Request $request): JsonResponse
    {
        try {
            $actor = ActorProfileGuard::ensureAllowed((string)$request->input('actor_profile', ''));
            $projectId = trim((string)$request->input('project_id', ''));
            if ($projectId === '') {
                throw new InvalidArgumentException('project_id is required');
            }

            $project = $this->repo->findProject($projectId);
            if ($project === null) {
                throw new InvalidArgumentException('Project not found');
            }
            if ((string)($project['owner_key'] ?? '') !== $actor && !$this->access->isSuperadminActor($actor)) {
                throw new InvalidArgumentException('Only the project owner can edit automation');
            }

            $primaryWorkspaceId = trim((string)$request->input('primary_workspace_id', ''));
            if ($primaryWorkspaceId !== '' && !$this->access->hasWorkspaceAccess(
                $actor,
                $primaryWorkspaceId,
                $this->actorPhone($request),
            )) {
                throw new InvalidArgumentException('Нет доступа к выбранному workspace.');
            }

            $values = ['primary_workspace_id' => $primaryWorkspaceId];
            if ($request->has('agent_enabled')) {
                $values['agent_enabled'] = filter_var(
                    $request->input('agent_enabled'),
                    FILTER_VALIDATE_BOOLEAN,
                    FILTER_NULL_ON_FAILURE,
                ) ?? false;
            }
            if ($request->has('default_agent_mode')) {
                $values['default_agent_mode'] = trim((string)$request->input('default_agent_mode', 'planner'));
            }
            if ($request->has('chat_analysis_message_limit')) {
                $values['chat_analysis_message_limit'] = (int)$request->input('chat_analysis_message_limit', 40);
            }

            $automation = $this->repo->upsertProjectAutomationConfig($projectId, $values);
            return $this->json(200, ['ok' => true, 'automation' => $automation]);
        } catch (InvalidArgumentException $e) {
            return $this->json(403, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function listGroups(Request $request): JsonResponse
    {
        try {
            $actor = trim((string)$request->query('actor_profile', ''));
            if ($actor !== '') {
                ActorProfileGuard::ensureAllowed($actor);
                $groups = $this->repo->visibleGroupsForActor($actor);
                $projectGroups = $this->repo->visibleProjectGroupMap($actor);
            } else {
                $groups = $this->repo->allFamilyGroups();
                $projectGroups = $this->repo->projectGroupMap();
            }
            return $this->json(200, [
                'ok' => true,
                'groups' => $groups,
                'project_groups' => $projectGroups,
            ]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function createProject(Request $request): JsonResponse
    {
        try {
            $actor = ActorProfileGuard::ensureAllowed((string)$request->input('actor_profile', ''));
            $name = trim((string)$request->input('name', ''));
            if ($name === '') {
                throw new InvalidArgumentException('name is required');
            }

            $id = 'prj-' . str_replace('.', '', uniqid('', true));
            $description = trim((string)$request->input('description', ''));
            $now = $this->repo->nowIso();

            $this->repo->upsertProject([
                'id' => $id,
                'name' => $name,
                'description' => $description,
                'owner_key' => $actor,
                'created_at' => $now,
                'updated_at' => $now,
            ]);

            return $this->json(200, [
                'ok' => true,
                'project' => [
                    'id' => $id,
                    'name' => $name,
                    'description' => $description,
                    'owner_key' => $actor,
                    'created_at' => $now,
                    'updated_at' => $now,
                ],
            ]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function updateProject(Request $request): JsonResponse
    {
        try {
            $actor = ActorProfileGuard::ensureAllowed((string)$request->input('actor_profile', ''));
            $id = trim((string)$request->input('id', ''));
            if ($id === '') {
                throw new InvalidArgumentException('id is required');
            }

            // Only the project owner or superadmin can edit.
            $project = $this->repo->findProject($id);
            if ($project === null) {
                throw new InvalidArgumentException('Project not found');
            }
            if ($project['owner_key'] !== $actor && !$this->access->isSuperadminActor($actor)) {
                throw new InvalidArgumentException('Only the project owner can edit');
            }

            $name = trim((string)$request->input('name', ''));
            $description = trim((string)$request->input('description', ''));
            $groupIds = $request->input('group_ids', null);
            $now = $this->repo->nowIso();

            $this->repo->upsertProject([
                'id' => $id,
                'name' => $name,
                'description' => $description,
                'owner_key' => $actor,
                'updated_at' => $now,
            ]);

            if (is_array($groupIds)) {
                $normalizedGroupIds = $this->normalizeAssignableGroupIds($actor, $groupIds);
                $this->repo->setProjectGroups($id, $normalizedGroupIds);
                $this->syncProjectGroupChats($actor, $id, $normalizedGroupIds);
            }

            return $this->json(200, ['ok' => true]);
        } catch (InvalidArgumentException $e) {
            return $this->json(403, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function deleteProject(Request $request): JsonResponse
    {
        try {
            $actor = ActorProfileGuard::ensureAllowed((string)$request->input('actor_profile', ''));
            $id = trim((string)$request->input('id', ''));
            if ($id === '') {
                throw new InvalidArgumentException('id is required');
            }

            // Members can see projects, but only owner or superadmin can delete.
            $project = $this->repo->findProject($id);
            if ($project === null) {
                throw new InvalidArgumentException('Project not found');
            }
            if ($project['owner_key'] !== $actor && !$this->access->isSuperadminActor($actor)) {
                throw new InvalidArgumentException('Only the project owner can delete');
            }

            $this->repo->deleteProject($id);
            return $this->json(200, ['ok' => true]);
        } catch (InvalidArgumentException $e) {
            return $this->json(403, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function setProjectGroups(Request $request): JsonResponse
    {
        try {
            $actor = ActorProfileGuard::ensureAllowed((string)$request->input('actor_profile', ''));
            $projectId = trim((string)$request->input('project_id', ''));
            if ($projectId === '') {
                throw new InvalidArgumentException('project_id is required');
            }

            // Only the project owner or superadmin can assign groups.
            $project = $this->repo->findProject($projectId);
            if ($project === null) {
                throw new InvalidArgumentException('Project not found');
            }
            if ($project['owner_key'] !== $actor && !$this->access->isSuperadminActor($actor)) {
                throw new InvalidArgumentException('Only the project owner can assign groups');
            }

            $groupIds = $request->input('group_ids', []);
            if (!is_array($groupIds)) {
                throw new InvalidArgumentException('group_ids must be array');
            }

            $normalizedGroupIds = $this->normalizeAssignableGroupIds($actor, $groupIds);
            $this->repo->setProjectGroups($projectId, $normalizedGroupIds);
            $this->syncProjectGroupChats($actor, $projectId, $normalizedGroupIds);
            return $this->json(200, ['ok' => true]);
        } catch (InvalidArgumentException $e) {
            return $this->json(403, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function ensureProjectChat(Request $request): JsonResponse
    {
        try {
            $actor = ActorProfileGuard::ensureAllowed((string)$request->input('actor_profile', ''));
            $projectId = trim((string)$request->input('project_id', ''));
            if ($projectId === '') {
                throw new InvalidArgumentException('project_id is required');
            }

            $project = $this->repo->findProject($projectId);
            if ($project === null) {
                throw new InvalidArgumentException('Project not found');
            }
            if ((string)($project['owner_key'] ?? '') !== $actor && !$this->access->isSuperadminActor($actor)) {
                throw new InvalidArgumentException('Only the project owner can create project chat');
            }

            $projectGroups = $this->repo->projectGroupMap();
            $groupIds = is_array($projectGroups[$projectId] ?? null)
                ? array_map('strval', $projectGroups[$projectId])
                : [];
            if ($groupIds === []) {
                throw new InvalidArgumentException('Сначала привяжите группу к проекту.');
            }

            $conversation = $this->syncProjectGroupChats($actor, $projectId, $groupIds);
            $conversationKey = (string)($conversation['conversation_key'] ?? '');
            $binding = $conversationKey === ''
                ? null
                : $this->repo->projectChatBinding($projectId, $conversationKey);

            return $this->json(200, [
                'ok' => true,
                'conversation' => $conversation,
                'binding' => $binding,
            ]);
        } catch (InvalidArgumentException $e) {
            return $this->json(403, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function createGroup(Request $request): JsonResponse
    {
        try {
            $actor = ActorProfileGuard::ensureAllowed((string)$request->input('actor_profile', ''));
            $name = trim((string)$request->input('name', ''));
            if ($name === '') {
                throw new InvalidArgumentException('name is required');
            }

            $members = $request->input('members', []);
            if (!is_array($members)) {
                throw new InvalidArgumentException('members must be array');
            }

            $id = 'grp-' . str_replace('.', '', uniqid('', true));
            $now = $this->repo->nowIso();

            $this->repo->upsertFamilyGroupRecord([
                'id' => $id,
                'name' => $name,
                'members' => $members,
                'owner_key' => $actor,
                'created_at' => $now,
                'updated_at' => $now,
            ]);
            $this->chat->syncFamilyGroupConversation($id, $name, $actor, $members);

            return $this->json(200, [
                'ok' => true,
                'group' => [
                    'id' => $id,
                    'name' => $name,
                    'members' => $members,
                    'owner_key' => $actor,
                    'created_at' => $now,
                    'updated_at' => $now,
                ],
            ]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function updateGroup(Request $request): JsonResponse
    {
        try {
            $actor = ActorProfileGuard::ensureAllowed((string)$request->input('actor_profile', ''));
            $id = trim((string)$request->input('id', ''));
            if ($id === '') {
                throw new InvalidArgumentException('id is required');
            }

            // Only the group owner or superadmin can edit.
            $group = $this->repo->findGroup($id);
            if ($group === null) {
                throw new InvalidArgumentException('Group not found');
            }
            if ($group['owner_key'] !== $actor && !$this->access->isSuperadminActor($actor)) {
                throw new InvalidArgumentException('Only the group owner can edit');
            }

            $name = trim((string)$request->input('name', (string)($group['name'] ?? '')));
            $members = $request->input('members', null);
            $now = $this->repo->nowIso();
            $nextMembers = is_array($members)
                ? array_map('strval', $members)
                : array_map('strval', $group['members'] ?? []);

            $record = [
                'id' => $id,
                'name' => $name,
                'members' => $nextMembers,
                'owner_key' => $actor,
                'created_at' => (string)($group['created_at'] ?? $now),
                'updated_at' => $now,
            ];

            $this->repo->upsertFamilyGroupRecord($record);
            $this->chat->syncFamilyGroupConversation($id, $name, $actor, $nextMembers);

            return $this->json(200, ['ok' => true]);
        } catch (InvalidArgumentException $e) {
            return $this->json(403, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function deleteGroup(Request $request): JsonResponse
    {
        try {
            $actor = ActorProfileGuard::ensureAllowed((string)$request->input('actor_profile', ''));
            $id = trim((string)$request->input('id', ''));
            if ($id === '') {
                throw new InvalidArgumentException('id is required');
            }

            // Members can see groups, but only owner or superadmin can delete.
            $group = $this->repo->findGroup($id);
            if ($group === null) {
                throw new InvalidArgumentException('Group not found');
            }
            if ($group['owner_key'] !== $actor && !$this->access->isSuperadminActor($actor)) {
                throw new InvalidArgumentException('Only the group owner can delete');
            }

            $this->repo->deleteFamilyGroup($id);
            return $this->json(200, ['ok' => true]);
        } catch (InvalidArgumentException $e) {
            return $this->json(403, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    private function json(int $status, array $payload): JsonResponse
    {
        return response()->json($payload, $status, [], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    }

    private function actorPhone(Request $request): string
    {
        return trim((string)$request->query(
            'phone',
            (string)$request->input('actor_phone', (string)$request->input('phone', '')),
        ));
    }

    /** @param list<array<string, mixed>> $workspaces */
    private function workspaceIsAccessible(string $workspaceId, array $workspaces): bool
    {
        foreach ($workspaces as $workspace) {
            if (trim((string)($workspace['workspace_id'] ?? '')) === trim($workspaceId)) {
                return true;
            }
        }
        return false;
    }

    /** @param list<string> $groupIds */
    private function syncProjectGroupChats(string $actor, string $projectId, array $groupIds): array
    {
        $normalizedGroupIds = [];
        foreach ($groupIds as $groupId) {
            $id = trim((string)$groupId);
            if ($id !== '' && !in_array($id, $normalizedGroupIds, true)) {
                $normalizedGroupIds[] = $id;
            }
        }

        if ($normalizedGroupIds === []) {
            $this->repo->syncProjectChatBindings($projectId, []);
            return [];
        }

        $project = $this->repo->findProject($projectId);
        if ($project === null) {
            return [];
        }

        $projectMembers = [];

        foreach ($normalizedGroupIds as $groupId) {
            $group = $this->repo->findGroup($groupId);
            if ($group === null) {
                continue;
            }
            $groupOwner = trim((string)($group['owner_key'] ?? ''));
            if ($groupOwner !== '' && !in_array($groupOwner, $projectMembers, true)) {
                $projectMembers[] = $groupOwner;
            }
            foreach (is_array($group['members'] ?? null) ? $group['members'] : [] as $member) {
                $profile = trim((string)$member);
                if ($profile !== '' && !in_array($profile, $projectMembers, true)) {
                    $projectMembers[] = $profile;
                }
            }
            $this->chat->syncFamilyGroupConversation(
                $groupId,
                (string)($group['name'] ?? ''),
                (string)($group['owner_key'] ?? $actor),
                is_array($group['members'] ?? null) ? $group['members'] : [],
            );
        }

        $conversation = $this->chat->syncProjectConversation(
            $projectId,
            (string)($project['name'] ?? ''),
            (string)($project['owner_key'] ?? $actor),
            $projectMembers,
        );
        $this->repo->syncProjectChatBindings($projectId, $normalizedGroupIds);
        return $conversation;
    }

    /** @param list<mixed> $groupIds */
    private function normalizeAssignableGroupIds(string $actor, array $groupIds): array
    {
        $normalized = [];
        foreach ($groupIds as $groupId) {
            $id = trim((string)$groupId);
            if ($id !== '' && !in_array($id, $normalized, true)) {
                $normalized[] = $id;
            }
        }
        if ($normalized === []) {
            return [];
        }

        $visibleGroups = $this->access->isSuperadminActor($actor)
            ? $this->repo->allFamilyGroups()
            : $this->repo->visibleGroupsForActor($actor);
        $visibleIds = [];
        foreach ($visibleGroups as $group) {
            $visibleIds[(string)($group['id'] ?? '')] = true;
        }
        foreach ($normalized as $groupId) {
            if (!isset($visibleIds[$groupId])) {
                throw new InvalidArgumentException('Нет доступа к выбранной группе.');
            }
        }
        return $normalized;
    }

    /**
     * @param array<string, mixed> $project
     * @param list<string> $groupIds
     * @param array<string, array<string, mixed>> $groupsById
     * @return list<string>
     */
    private function projectChatMembers(array $project, array $groupIds, array $groupsById): array
    {
        $members = [];
        $owner = trim((string)($project['owner_key'] ?? ''));
        if ($owner !== '') {
            $members[] = $owner;
        }
        if (!in_array('tudushker', $members, true)) {
            $members[] = 'tudushker';
        }
        foreach ($groupIds as $groupId) {
            $group = is_array($groupsById[$groupId] ?? null) ? $groupsById[$groupId] : [];
            $groupOwner = trim((string)($group['owner_key'] ?? ''));
            if ($groupOwner !== '' && !in_array($groupOwner, $members, true)) {
                $members[] = $groupOwner;
            }
            foreach (is_array($group['members'] ?? null) ? $group['members'] : [] as $member) {
                $profile = trim((string)$member);
                if ($profile !== '' && !in_array($profile, $members, true)) {
                    $members[] = $profile;
                }
            }
        }
        return $members;
    }
}
