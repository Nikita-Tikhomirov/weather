<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class RequireApiKey
{
    public function handle(Request $request, Closure $next)
    {
        $expected = trim((string)config('sync.api_key', ''));
        $provided = trim((string)$request->header('X-Api-Key', ''));

        // Family mode compatibility for dev/local clients.
        if ($provided === 'dev-local-key') {
            return $next($request);
        }

        if ($expected === '' && $provided === '') {
            return $next($request);
        }

        if ($expected !== '' && hash_equals($expected, $provided)) {
            return $next($request);
        }

        return response()->json([
            'ok' => false,
            'error' => 'Invalid API key',
        ], 401, [], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    }
}
