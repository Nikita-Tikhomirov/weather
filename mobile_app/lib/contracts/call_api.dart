import '../models/call_models.dart';

/// Abstract API surface for audio/video call operations.
abstract class CallApi {
  Future<CallSession> callInitiate({
    required String actorProfile,
    required String conversationKey,
    String callType = 'audio',
    String? calleeProfile,
  });

  Future<CallSession> callAccept({
    required String actorProfile,
    required String sessionId,
  });

  Future<CallSession> callReject({
    required String actorProfile,
    required String sessionId,
  });

  Future<CallSession> callEnd({
    required String actorProfile,
    required String sessionId,
  });

  Future<void> callSignal({
    required String actorProfile,
    required String sessionId,
    required String signalType,
    dynamic sdp,
    dynamic candidate,
  });

  Future<CallSignalsPoll> callPollSignals({
    required String actorProfile,
    required String sessionId,
    String? cursor,
  });

  Future<CallSession?> callCheckIncoming({
    required String actorProfile,
  });
}
