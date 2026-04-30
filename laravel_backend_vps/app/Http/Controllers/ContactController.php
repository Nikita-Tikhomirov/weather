<?php

namespace App\Http\Controllers;

use App\Domain\Profiles\PhoneProfileRepository;
use App\Domain\Sync\ActorProfileGuard;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use InvalidArgumentException;
use Throwable;

class ContactController extends Controller
{
    public function __construct(private readonly PhoneProfileRepository $profiles)
    {
    }

    public function resolve(Request $request): JsonResponse
    {
        try {
            $actor = ActorProfileGuard::ensureAllowed((string)$request->input('actor_profile', ''));
            $phones = $request->input('phones', []);
            if (!is_array($phones)) {
                throw new InvalidArgumentException('phones must be array');
            }

            return $this->json(200, [
                'ok' => true,
                'contacts' => $this->profiles->resolveContacts($actor, $phones),
            ]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function familyMembers(Request $request): JsonResponse
    {
        try {
            $actor = ActorProfileGuard::ensureAllowed((string)$request->query('actor_profile', ''));
            return $this->json(200, [
                'ok' => true,
                'members' => $this->profiles->familyMembers($actor),
            ]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function addFamilyMembers(Request $request): JsonResponse
    {
        try {
            $actor = ActorProfileGuard::ensureAllowed((string)$request->input('actor_profile', ''));
            $profiles = $request->input('profiles', []);
            if (!is_array($profiles)) {
                throw new InvalidArgumentException('profiles must be array');
            }

            return $this->json(200, [
                'ok' => true,
                'members' => $this->profiles->addFamilyMembers($actor, $profiles),
            ]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function removeFamilyMember(Request $request): JsonResponse
    {
        try {
            $actor = ActorProfileGuard::ensureAllowed((string)$request->input('actor_profile', ''));
            $profile = trim((string)$request->input('profile', ''));
            return $this->json(200, [
                'ok' => true,
                'members' => $this->profiles->removeFamilyMember($actor, $profile),
            ]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    private function json(int $status, array $payload): JsonResponse
    {
        return response()->json($payload, $status, [], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    }
}
