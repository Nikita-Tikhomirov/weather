<?php

namespace App\Services\Push;

use App\Contracts\PushGateway;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use RuntimeException;

class FcmPushGateway implements PushGateway
{
    private const TOKEN_CACHE_KEY = 'push.fcm.oauth_token';
    private const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

    public function isConfigured(): bool
    {
        if (!config('push.enabled', true)) {
            return false;
        }

        return $this->projectId() !== ''
            && $this->clientEmail() !== ''
            && $this->privateKey() !== '';
    }

    public function sendToToken(string $token, string $title, string $body, array $data): array
    {
        if (!$this->isConfigured()) {
            return [
                'success' => false,
                'permanent_failure' => false,
                'error' => 'push gateway is not configured',
            ];
        }

        try {
            $accessToken = $this->getAccessToken();
        } catch (RuntimeException $e) {
            return [
                'success' => false,
                'permanent_failure' => false,
                'error' => $e->getMessage(),
            ];
        }

        $payload = [
            'message' => [
                'token' => $token,
                'notification' => [
                    'title' => $title,
                    'body' => $body,
                ],
                'data' => $this->normalizeData($data),
                'android' => [
                    'priority' => 'high',
                    'notification' => [
                        'channel_id' => (string) config('push.fcm.android_channel_id', 'family_updates'),
                        'sound' => 'default',
                        'visibility' => 'PUBLIC',
                    ],
                ],
            ],
        ];

        $timeoutSec = max(3, (int) config('push.fcm.timeout_sec', 10));
        $response = Http::timeout($timeoutSec)
            ->withToken($accessToken)
            ->post(
                sprintf('https://fcm.googleapis.com/v1/projects/%s/messages:send', $this->projectId()),
                $payload
            );

        if ($response->successful()) {
            return [
                'success' => true,
                'permanent_failure' => false,
                'error' => '',
            ];
        }

        $raw = (string) $response->body();
        $json = $response->json();
        $errorText = $this->extractErrorText($json, $raw);
        $permanent = $this->isPermanentTokenError($response->status(), $errorText);

        return [
            'success' => false,
            'permanent_failure' => $permanent,
            'error' => $errorText,
        ];
    }

    private function getAccessToken(): string
    {
        return (string) Cache::remember(self::TOKEN_CACHE_KEY, now()->addMinutes(50), function (): string {
            $assertion = $this->buildJwtAssertion();
            $response = Http::timeout(10)->asForm()->post('https://oauth2.googleapis.com/token', [
                'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                'assertion' => $assertion,
            ]);

            if (!$response->successful()) {
                throw new RuntimeException('unable to fetch FCM OAuth token: '.$response->status().' '.$response->body());
            }

            $token = trim((string) data_get($response->json(), 'access_token', ''));
            if ($token === '') {
                throw new RuntimeException('FCM OAuth token response has no access_token');
            }

            return $token;
        });
    }

    private function buildJwtAssertion(): string
    {
        $now = time();

        $header = $this->base64UrlEncode(json_encode([
            'alg' => 'RS256',
            'typ' => 'JWT',
        ], JSON_UNESCAPED_SLASHES));

        $claims = $this->base64UrlEncode(json_encode([
            'iss' => $this->clientEmail(),
            'scope' => self::FCM_SCOPE,
            'aud' => 'https://oauth2.googleapis.com/token',
            'iat' => $now,
            'exp' => $now + 3600,
        ], JSON_UNESCAPED_SLASHES));

        $unsigned = $header.'.'.$claims;
        $privateKey = openssl_pkey_get_private($this->privateKey());
        if ($privateKey === false) {
            throw new RuntimeException('unable to parse FCM private key');
        }

        $signature = '';
        $signed = openssl_sign($unsigned, $signature, $privateKey, OPENSSL_ALGO_SHA256);
        if (!$signed) {
            throw new RuntimeException('unable to sign FCM JWT assertion');
        }

        return $unsigned.'.'.$this->base64UrlEncode($signature);
    }

    private function normalizeData(array $data): array
    {
        $out = [];
        foreach ($data as $key => $value) {
            $k = trim((string) $key);
            if ($k === '') {
                continue;
            }
            if (is_scalar($value) || $value === null) {
                $out[$k] = (string) ($value ?? '');
                continue;
            }
            $out[$k] = json_encode($value, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        }

        return $out;
    }

    private function extractErrorText(mixed $json, string $raw): string
    {
        $message = trim((string) data_get($json, 'error.message', ''));
        $status = trim((string) data_get($json, 'error.status', ''));

        if ($status !== '' && $message !== '') {
            return $status.': '.$message;
        }
        if ($message !== '') {
            return $message;
        }
        if ($status !== '') {
            return $status;
        }

        return trim($raw) !== '' ? trim($raw) : 'unknown FCM error';
    }

    private function isPermanentTokenError(int $statusCode, string $errorText): bool
    {
        $text = strtoupper($errorText);
        if (str_contains($text, 'UNREGISTERED')) {
            return true;
        }
        if (str_contains($text, 'INVALID_ARGUMENT') && str_contains($text, 'TOKEN')) {
            return true;
        }
        if (str_contains($text, 'REGISTRATION TOKEN') && str_contains($text, 'INVALID')) {
            return true;
        }

        return in_array($statusCode, [400, 404], true);
    }

    private function base64UrlEncode(string $input): string
    {
        return rtrim(strtr(base64_encode($input), '+/', '-_'), '=');
    }

    private function projectId(): string
    {
        return trim((string) config('push.fcm.project_id', ''));
    }

    private function clientEmail(): string
    {
        return trim((string) config('push.fcm.client_email', ''));
    }

    private function privateKey(): string
    {
        $value = trim((string) config('push.fcm.private_key', ''));
        return str_replace('\n', "\n", $value);
    }
}
