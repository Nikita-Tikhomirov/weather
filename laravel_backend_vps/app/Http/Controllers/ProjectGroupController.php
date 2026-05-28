<?php

namespace App\Http\Controllers;

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

            // Only the project owner can edit
            $project = $this->repo->findProject($id);
            if ($project === null) {
                throw new InvalidArgumentException('Project not found');
            }
            if ($project['owner_key'] !== $actor) {
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
                $this->repo->setProjectGroups($id, array_map('strval', $groupIds));
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

            // Only the project owner can delete
            $project = $this->repo->findProject($id);
            if ($project !== null && $project['owner_key'] !== $actor) {
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

            // Only the project owner can assign groups
            $project = $this->repo->findProject($projectId);
            if ($project === null) {
                throw new InvalidArgumentException('Project not found');
            }
            if ($project['owner_key'] !== $actor) {
                throw new InvalidArgumentException('Only the project owner can assign groups');
            }

            $groupIds = $request->input('group_ids', []);
            if (!is_array($groupIds)) {
                throw new InvalidArgumentException('group_ids must be array');
            }

            $this->repo->setProjectGroups($projectId, array_map('strval', $groupIds));
            return $this->json(200, ['ok' => true]);
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

            // Only the group owner can edit
            $group = $this->repo->findGroup($id);
            if ($group === null) {
                throw new InvalidArgumentException('Group not found');
            }
            if ($group['owner_key'] !== $actor) {
                throw new InvalidArgumentException('Only the group owner can edit');
            }

            $name = trim((string)$request->input('name', ''));
            $members = $request->input('members', null);
            $now = $this->repo->nowIso();

            $record = [
                'id' => $id,
                'name' => $name,
                'owner_key' => $actor,
            ];

            if (is_array($members)) {
                $record['members'] = $members;
            }

            $this->repo->upsertFamilyGroupRecord($record);

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

            // Only the group owner can delete
            $group = $this->repo->findGroup($id);
            if ($group !== null && $group['owner_key'] !== $actor) {
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
}
