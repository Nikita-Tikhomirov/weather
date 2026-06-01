import 'dart:convert';

import '../contracts/call_api.dart';
import '../models/call_models.dart';
import 'http_client_base.dart';

class CallApiClient extends HttpApiClient implements CallApi {
  CallApiClient({required super.baseUrl, required super.apiKey});

  @override
  Future<CallSession> callInitiate({
    required String actorProfile,
    required String conversationKey,
    String callType = 'audio',
    String? calleeProfile,
  }) async {
    final body = await postJsonWithFallback(
      paths: const ['/call/initiate'],
      body: jsonEncode({
        'actor_profile': actorProfile,
        'conversation_key': conversationKey,
        'call_type': callType,
        if (calleeProfile != null) 'callee_profile': calleeProfile,
      }),
    );
    return CallSession.fromJson(
      Map<String, dynamic>.from((body['session'] as Map?) ?? const {}),
    );
  }

  @override
  Future<CallSession> callAccept({
    required String actorProfile,
    required String sessionId,
  }) async {
    final body = await postJsonWithFallback(
      paths: const ['/call/accept'],
      body: jsonEncode({
        'actor_profile': actorProfile,
        'session_id': sessionId,
      }),
    );
    return CallSession.fromJson(
      Map<String, dynamic>.from((body['session'] as Map?) ?? const {}),
    );
  }

  @override
  Future<CallSession> callReject({
    required String actorProfile,
    required String sessionId,
  }) async {
    final body = await postJsonWithFallback(
      paths: const ['/call/reject'],
      body: jsonEncode({
        'actor_profile': actorProfile,
        'session_id': sessionId,
      }),
    );
    return CallSession.fromJson(
      Map<String, dynamic>.from((body['session'] as Map?) ?? const {}),
    );
  }

  @override
  Future<CallSession> callEnd({
    required String actorProfile,
    required String sessionId,
  }) async {
    final body = await postJsonWithFallback(
      paths: const ['/call/end'],
      body: jsonEncode({
        'actor_profile': actorProfile,
        'session_id': sessionId,
      }),
    );
    return CallSession.fromJson(
      Map<String, dynamic>.from((body['session'] as Map?) ?? const {}),
    );
  }

  @override
  Future<void> callSignal({
    required String actorProfile,
    required String sessionId,
    required String signalType,
    dynamic sdp,
    dynamic candidate,
  }) async {
    await postWithFallback(
      paths: const ['/call/signal'],
      body: jsonEncode({
        'actor_profile': actorProfile,
        'session_id': sessionId,
        'signal_type': signalType,
        if (sdp != null) 'sdp': sdp is String ? sdp : jsonEncode(sdp),
        if (candidate != null)
          'candidate': candidate is String ? candidate : jsonEncode(candidate),
      }),
    );
  }

  @override
  Future<CallSignalsPoll> callPollSignals({
    required String actorProfile,
    required String sessionId,
    String? cursor,
  }) async {
    final query = <String, String>{
      'actor_profile': actorProfile,
      'session_id': sessionId,
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };
    final body = await getJsonWithFallback(
      paths: const ['/call/signals'],
      query: query,
    );
    final signals = (body['signals'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => CallSignal.fromJson(Map<String, dynamic>.from(row)))
        .toList();
    return CallSignalsPoll(
      signals: signals,
      cursor: (body['cursor'] ?? '0').toString(),
      sessionStatus: (body['session_status'] ?? 'ringing').toString(),
    );
  }

  @override
  Future<CallSession?> callCheckIncoming({
    required String actorProfile,
  }) async {
    final body = await getJsonWithFallback(
      paths: const ['/call/incoming'],
      query: {'actor_profile': actorProfile},
    );
    final incoming = body['incoming_call'];
    if (incoming == null) return null;
    return CallSession.fromJson(Map<String, dynamic>.from(incoming as Map));
  }
}
