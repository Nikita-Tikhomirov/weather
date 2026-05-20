class CallSession {
  CallSession({
    required this.sessionId,
    required this.callerProfile,
    required this.calleeProfile,
    required this.conversationKey,
    required this.callType,
    required this.status,
    required this.createdAt,
    this.endedAt,
  });

  final String sessionId;
  final String callerProfile;
  final String calleeProfile;
  final String conversationKey;
  final String callType; // audio | video
  final String status; // ringing | active | ended | rejected | missed
  final String createdAt;
  final String? endedAt;

  bool get isIncoming => status == 'ringing';
  bool get isActive => status == 'active';
  bool get isEnded => status == 'ended' || status == 'rejected';

  factory CallSession.fromJson(Map<String, dynamic> json) {
    return CallSession(
      sessionId: (json['session_id'] ?? '').toString(),
      callerProfile: (json['caller_profile'] ?? '').toString(),
      calleeProfile: (json['callee_profile'] ?? '').toString(),
      conversationKey: (json['conversation_key'] ?? '').toString(),
      callType: (json['call_type'] ?? 'audio').toString(),
      status: (json['status'] ?? '').toString(),
      createdAt: (json['created_at'] ?? '').toString(),
      endedAt: json['ended_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'session_id': sessionId,
      'caller_profile': callerProfile,
      'callee_profile': calleeProfile,
      'conversation_key': conversationKey,
      'call_type': callType,
      'status': status,
      'created_at': createdAt,
      'ended_at': endedAt,
    };
  }
}

class CallSignal {
  CallSignal({
    required this.id,
    required this.signalType,
    required this.fromProfile,
    this.sdp,
    this.candidate,
  });

  final String id;
  final String signalType; // offer | answer | ice_candidate | hangup
  final String fromProfile;
  final dynamic sdp; // Map for SDP, can be String from raw JSON
  final dynamic candidate; // Map for ICE candidate

  factory CallSignal.fromJson(Map<String, dynamic> json) {
    return CallSignal(
      id: (json['id'] ?? '').toString(),
      signalType: (json['signal_type'] ?? '').toString(),
      fromProfile: (json['from_profile'] ?? '').toString(),
      sdp: json['sdp'],
      candidate: json['candidate'],
    );
  }
}

class CallSignalsPoll {
  CallSignalsPoll({
    required this.signals,
    required this.cursor,
    required this.sessionStatus,
  });

  final List<CallSignal> signals;
  final String cursor;
  final String sessionStatus;
}
