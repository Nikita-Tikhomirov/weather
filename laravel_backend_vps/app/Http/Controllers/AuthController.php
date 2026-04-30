<?php

namespace App\Http\Controllers;

use App\Domain\Profiles\PhoneProfileRepository;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use InvalidArgumentException;
use Throwable;

class AuthController extends Controller
{
    public function __construct(private readonly PhoneProfileRepository $profiles)
    {
    }

    public function deviceStart(Request $request): JsonResponse
    {
        try {
            $user = $this->profiles->startDevice(
                (string)$request->input('phone', ''),
                (string)$request->input('device_id', ''),
                (string)$request->input('display_name', ''),
                (string)$request->input('platform', 'android'),
                (string)$request->input('app_version', ''),
            );

            return $this->json(200, [
                'ok' => true,
                'user' => $user,
                'family_members' => $this->profiles->familyMembers((string)$user['profile_key']),
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
