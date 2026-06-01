import 'package:flutter/foundation.dart';

@immutable
class CallSession {
  const CallSession({
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
  final String callType;
  final String status;
  final String createdAt;
  final String? endedAt;

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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CallSession &&
          runtimeType == other.runtimeType &&
          sessionId == other.sessionId &&
          callerProfile == other.callerProfile &&
          calleeProfile == other.calleeProfile &&
          conversationKey == other.conversationKey &&
          callType == other.callType &&
          status == other.status &&
          createdAt == other.createdAt &&
          endedAt == other.endedAt;

  @override
  int get hashCode =>
      sessionId.hashCode ^
      callerProfile.hashCode ^
      calleeProfile.hashCode ^
      conversationKey.hashCode ^
      callType.hashCode ^
      status.hashCode ^
      createdAt.hashCode ^
      endedAt.hashCode;

  CallSession copyWith({
    String? sessionId,
    String? callerProfile,
    String? calleeProfile,
    String? conversationKey,
    String? callType,
    String? status,
    String? createdAt,
    String? endedAt,
  }) =>
      CallSession(
        sessionId: sessionId ?? this.sessionId,
        callerProfile: callerProfile ?? this.callerProfile,
        calleeProfile: calleeProfile ?? this.calleeProfile,
        conversationKey: conversationKey ?? this.conversationKey,
        callType: callType ?? this.callType,
        status: status ?? this.status,
        createdAt: createdAt ?? this.createdAt,
        endedAt: endedAt ?? this.endedAt,
      );
}

@immutable
class CallSignal {
  const CallSignal({
    required this.id,
    required this.signalType,
    required this.fromProfile,
    this.sdp,
    this.candidate,
  });

  final String id;
  final String signalType;
  final String fromProfile;
  final dynamic sdp;
  final dynamic candidate;

  factory CallSignal.fromJson(Map<String, dynamic> json) {
    return CallSignal(
      id: (json['id'] ?? '').toString(),
      signalType: (json['signal_type'] ?? '').toString(),
      fromProfile: (json['from_profile'] ?? '').toString(),
      sdp: json['sdp'],
      candidate: json['candidate'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'signal_type': signalType,
      'from_profile': fromProfile,
      'sdp': sdp,
      'candidate': candidate,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CallSignal &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          signalType == other.signalType &&
          fromProfile == other.fromProfile &&
          sdp == other.sdp &&
          candidate == other.candidate;

  @override
  int get hashCode =>
      id.hashCode ^
      signalType.hashCode ^
      fromProfile.hashCode ^
      sdp.hashCode ^
      candidate.hashCode;

  CallSignal copyWith({
    String? id,
    String? signalType,
    String? fromProfile,
    dynamic sdp,
    dynamic candidate,
  }) =>
      CallSignal(
        id: id ?? this.id,
        signalType: signalType ?? this.signalType,
        fromProfile: fromProfile ?? this.fromProfile,
        sdp: sdp ?? this.sdp,
        candidate: candidate ?? this.candidate,
      );
}

@immutable
class CallSignalsPoll {
  const CallSignalsPoll({
    required this.signals,
    required this.cursor,
    required this.sessionStatus,
  });

  final List<CallSignal> signals;
  final String cursor;
  final String sessionStatus;

  Map<String, dynamic> toJson() {
    return {
      'signals': signals.map((s) => s.toJson()).toList(),
      'cursor': cursor,
      'session_status': sessionStatus,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CallSignalsPoll &&
          runtimeType == other.runtimeType &&
          listEquals(signals, other.signals) &&
          cursor == other.cursor &&
          sessionStatus == other.sessionStatus;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(signals),
        cursor,
        sessionStatus,
      );

  CallSignalsPoll copyWith({
    List<CallSignal>? signals,
    String? cursor,
    String? sessionStatus,
  }) =>
      CallSignalsPoll(
        signals: signals ?? this.signals,
        cursor: cursor ?? this.cursor,
        sessionStatus: sessionStatus ?? this.sessionStatus,
      );
}
