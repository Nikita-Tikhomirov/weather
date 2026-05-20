<?php

namespace App\Domain\Call;

use App\Domain\Sync\Profiles;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use InvalidArgumentException;

final class CallRepository
{
    /**
     * Initiate a new call session.
     *
     * @return array{session_id:string, status:string, call_type:string, caller_profile:string, callee_profile:string}
     */
    public function initiate(string $actor, string $conversationKey, string $callType, ?string $calleeProfile = null): array
    {
        $actor = $this->resolveLegacyProfile($actor);
        $this->ensureActor($actor);

        $callType = in_array(trim($callType), ['audio', 'video'], true)
            ? trim($callType)
            : 'audio';

        // Determine callee from conversation
        $key = trim($conversationKey);
        if ($calleeProfile !== null && trim($calleeProfile) !== '') {
            $callee = $this->resolveLegacyProfile(trim($calleeProfile));
            $this->ensureActor($callee);
        } elseif ($key !== '' && str_starts_with($key, 'dm:')) {
            $members = $this->parseDmMembers($key);
            if ($members === null) {
                throw new InvalidArgumentException('Invalid direct conversation key');
            }
            $callee = ($members[0] === $actor) ? $members[1] : $members[0];
        } else {
            throw new InvalidArgumentException(
                'For group calls, specify callee_profile'
            );
        }

        if ($callee === $actor) {
            throw new InvalidArgumentException('Cannot call yourself');
        }

        // Check no active call between these two
        $existing = DB::table('call_sessions')
            ->where(function ($q) use ($actor, $callee): void {
                $q->where('caller_profile', $actor)->where('callee_profile', $callee);
            })
            ->orWhere(function ($q) use ($actor, $callee): void {
                $q->where('caller_profile', $callee)->where('callee_profile', $actor);
            })
            ->whereIn('status', ['ringing', 'active'])
            ->first();

        if ($existing !== null) {
            throw new InvalidArgumentException(
                'Active call already exists between these users'
            );
        }

        $sessionId = 'call-' . Str::ulid();
        $now = $this->nowIso();

        DB::table('call_sessions')->insert([
            'session_id' => $sessionId,
            'caller_profile' => $actor,
            'callee_profile' => $callee,
            'conversation_key' => $key,
            'call_type' => $callType,
            'status' => 'ringing',
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        return [
            'session_id' => $sessionId,
            'status' => 'ringing',
            'call_type' => $callType,
            'caller_profile' => $actor,
            'callee_profile' => $callee,
        ];
    }

    /**
     * Accept an incoming call.
     */
    public function accept(string $actor, string $sessionId): array
    {
        $actor = $this->resolveLegacyProfile($actor);
        $session = $this->getSession($sessionId);

        if ($session->callee_profile !== $actor) {
            throw new InvalidArgumentException('Only callee can accept the call');
        }
        if ($session->status !== 'ringing') {
            throw new InvalidArgumentException('Call is not in ringing state');
        }

        $now = $this->nowIso();
        DB::table('call_sessions')
            ->where('id', $session->id)
            ->update(['status' => 'active', 'updated_at' => $now]);

        return $this->mapSession(
            DB::table('call_sessions')->where('id', $session->id)->first()
        );
    }

    /**
     * Reject an incoming call.
     */
    public function reject(string $actor, string $sessionId): array
    {
        $actor = $this->resolveLegacyProfile($actor);
        $session = $this->getSession($sessionId);

        if ($session->callee_profile !== $actor) {
            throw new InvalidArgumentException('Only callee can reject the call');
        }
        if (!in_array($session->status, ['ringing', 'active'], true)) {
            throw new InvalidArgumentException('Call is not active');
        }

        $now = $this->nowIso();
        DB::table('call_sessions')
            ->where('id', $session->id)
            ->update([
                'status' => 'rejected',
                'ended_at' => $now,
                'updated_at' => $now,
            ]);

        return $this->mapSession(
            DB::table('call_sessions')->where('id', $session->id)->first()
        );
    }

    /**
     * End a call (either side).
     */
    public function end(string $actor, string $sessionId): array
    {
        $actor = $this->resolveLegacyProfile($actor);
        $session = $this->getSession($sessionId);

        if (!in_array($actor, [$session->caller_profile, $session->callee_profile], true)) {
            throw new InvalidArgumentException('Not a participant of this call');
        }
        if (!in_array($session->status, ['ringing', 'active'], true)) {
            throw new InvalidArgumentException('Call is not active');
        }

        $now = $this->nowIso();
        DB::table('call_sessions')
            ->where('id', $session->id)
            ->update([
                'status' => 'ended',
                'ended_at' => $now,
                'updated_at' => $now,
            ]);

        return $this->mapSession(
            DB::table('call_sessions')->where('id', $session->id)->first()
        );
    }

    /**
     * Store a WebRTC signal (SDP offer/answer or ICE candidate).
     */
    public function storeSignal(string $actor, string $sessionId, string $signalType, ?string $sdp, ?string $candidate): void
    {
        $actor = $this->resolveLegacyProfile($actor);
        $session = $this->getSession($sessionId);

        if (!in_array($actor, [$session->caller_profile, $session->callee_profile], true)) {
            throw new InvalidArgumentException('Not a participant of this call');
        }
        if (!in_array($session->status, ['ringing', 'active'], true)) {
            throw new InvalidArgumentException('Call is not active');
        }

        $type = trim($signalType);
        if (!in_array($type, ['offer', 'answer', 'ice_candidate', 'hangup'], true)) {
            throw new InvalidArgumentException('Invalid signal type');
        }

        DB::table('call_signals')->insert([
            'session_id' => $sessionId,
            'from_profile' => $actor,
            'signal_type' => $type,
            'sdp' => $sdp,
            'candidate' => $candidate,
            'created_at' => $this->nowIso(),
        ]);
    }

    /**
     * Poll for new signals in a call session since a cursor.
     *
     * @return array{signals:array, session_status:string}
     */
    public function pollSignals(string $actor, string $sessionId, ?string $cursor): array
    {
        $actor = $this->resolveLegacyProfile($actor);
        $session = $this->getSession($sessionId);

        if (!in_array($actor, [$session->caller_profile, $session->callee_profile], true)) {
            throw new InvalidArgumentException('Not a participant of this call');
        }

        $query = DB::table('call_signals')
            ->where('session_id', $sessionId)
            ->where('from_profile', '!=', $actor) // only signals from the other side
            ->orderBy('id');

        if ($cursor !== null && trim($cursor) !== '') {
            $query->where('id', '>', (int) $cursor);
        }

        $rows = $query->get();
        $signals = [];
        $lastId = $cursor !== null ? (int) $cursor : 0;

        foreach ($rows as $row) {
            $lastId = max($lastId, (int) $row->id);
            $signal = [
                'id' => (string) $row->id,
                'signal_type' => (string) $row->signal_type,
                'from_profile' => (string) $row->from_profile,
            ];

            if ($row->sdp !== null) {
                $decoded = json_decode($row->sdp, true);
                $signal['sdp'] = is_array($decoded) ? $decoded : $row->sdp;
            }
            if ($row->candidate !== null) {
                $decoded = json_decode($row->candidate, true);
                $signal['candidate'] = is_array($decoded) ? $decoded : $row->candidate;
            }

            $signals[] = $signal;
        }

        // Refresh session status
        $refreshed = DB::table('call_sessions')->where('id', $session->id)->first();

        return [
            'signals' => $signals,
            'cursor' => $lastId > 0 ? (string) $lastId : ($cursor ?? '0'),
            'session_status' => $refreshed !== null ? (string) $refreshed->status : 'ended',
        ];
    }

    /**
     * Get incoming call session for callee (polled on contacts screen).
     */
    public function incomingCall(string $actor): ?array
    {
        $actor = $this->resolveLegacyProfile($actor);
        $this->ensureActor($actor);

        $session = DB::table('call_sessions')
            ->where('callee_profile', $actor)
            ->where('status', 'ringing')
            ->orderByDesc('created_at')
            ->first();

        if ($session === null) {
            return null;
        }

        return $this->mapSession($session);
    }

    private function getSession(string $sessionId): object
    {
        $session = DB::table('call_sessions')->where('session_id', $sessionId)->first();
        if ($session === null) {
            throw new InvalidArgumentException('Call session not found');
        }
        return $session;
    }

    private function mapSession(object $row): array
    {
        return [
            'session_id' => (string) $row->session_id,
            'caller_profile' => (string) $row->caller_profile,
            'callee_profile' => (string) $row->callee_profile,
            'conversation_key' => (string) $row->conversation_key,
            'call_type' => (string) $row->call_type,
            'status' => (string) $row->status,
            'created_at' => (string) $row->created_at,
            'ended_at' => $row->ended_at !== null ? (string) $row->ended_at : null,
        ];
    }

    private function resolveLegacyProfile(string $profile): string
    {
        $key = trim($profile);
        $phone = match ($key) {
            'nik' => '79679812438',
            'misha' => '79206555644',
            'nastya' => '79109764267',
            default => '',
        };
        if ($phone === '') {
            return $key;
        }
        $dynamic = DB::table('messenger_users')->where('phone_normalized', $phone)->value('profile_key');
        return is_string($dynamic) && trim($dynamic) !== '' ? trim($dynamic) : $key;
    }

    private function ensureActor(string $actor): void
    {
        if (!$this->isAllowedProfile(trim($actor))) {
            throw new InvalidArgumentException('Unknown actor_profile');
        }
    }

    private function isAllowedProfile(string $profile): bool
    {
        return Profiles::isAllowed($profile) || DB::table('messenger_users')->where('profile_key', $profile)->exists();
    }

    /**
     * @return array{string, string}|null
     */
    private function parseDmMembers(string $key): ?array
    {
        if (!preg_match('/^dm:([a-z0-9_]+):([a-z0-9_]+)$/', $key, $matches)) {
            return null;
        }
        $a = $this->resolveLegacyProfile($matches[1]);
        $b = $this->resolveLegacyProfile($matches[2]);
        return [$a, $b];
    }

    private function nowIso(): string
    {
        return now()->format('Y-m-d\\TH:i:s');
    }
}
