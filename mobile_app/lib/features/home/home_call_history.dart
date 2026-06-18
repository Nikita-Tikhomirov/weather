import '../../models/call_models.dart';
import '../../models/chat_models.dart';
import '../../services/call_service.dart';
import '../chat/chat_call_helpers.dart';

ChatMessage buildCallHistoryMessage({
  required CallSession session,
  required String owner,
  required CallState previousState,
  required DateTime endedAt,
}) {
  final callType =
      session.callType.trim().toLowerCase() == 'video' ? 'video' : 'audio';
  final status = previousState == CallState.connected ? 'completed' : 'missed';
  final durationSeconds = status == 'completed'
      ? _callDurationSeconds(session.createdAt, endedAt)
      : 0;
  final clientMessageId = 'call-${session.sessionId}-$status';

  return ChatMessage(
    id: clientMessageId,
    conversationKey: session.conversationKey,
    senderProfile: owner,
    messageType: 'call',
    text: defaultChatCallTitle(status: status, callType: callType),
    createdAt: endedAt.toIso8601String(),
    clientMessageId: clientMessageId,
    deliveryStatus: 'sending',
    imageMeta: {
      'session_id': session.sessionId,
      'call_status': status,
      'call_type': callType,
      'duration_seconds': durationSeconds,
      'caller_profile': session.callerProfile,
      'callee_profile': session.calleeProfile,
      'direction': session.callerProfile == owner ? 'outgoing' : 'incoming',
    },
  );
}

int _callDurationSeconds(String createdAt, DateTime endedAt) {
  try {
    final startedAt = DateTime.parse(createdAt);
    final duration = endedAt.difference(startedAt).inSeconds;
    return duration < 0 ? 0 : duration;
  } catch (_) {
    return 0;
  }
}
