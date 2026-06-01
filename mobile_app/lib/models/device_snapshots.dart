import 'package:flutter/foundation.dart';

import 'chat_models.dart';

@immutable
class DeviceTokenRegistration {
  const DeviceTokenRegistration({
    required this.shouldResetToken,
    required this.previousTokenStatus,
  });

  final bool shouldResetToken;
  final String previousTokenStatus;

  Map<String, dynamic> toJson() {
    return {
      'should_reset_token': shouldResetToken,
      'previous_token_status': previousTokenStatus,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceTokenRegistration &&
          runtimeType == other.runtimeType &&
          shouldResetToken == other.shouldResetToken &&
          previousTokenStatus == other.previousTokenStatus;

  @override
  int get hashCode => shouldResetToken.hashCode ^ previousTokenStatus.hashCode;

  DeviceTokenRegistration copyWith({
    bool? shouldResetToken,
    String? previousTokenStatus,
  }) =>
      DeviceTokenRegistration(
        shouldResetToken: shouldResetToken ?? this.shouldResetToken,
        previousTokenStatus: previousTokenStatus ?? this.previousTokenStatus,
      );
}

@immutable
class PushDeviceStatus {
  const PushDeviceStatus({
    required this.actorProfile,
    required this.effectiveTokenStatus,
    required this.activeTokenCount,
    required this.status,
    required this.tokens,
  });

  final String actorProfile;
  final String effectiveTokenStatus;
  final int activeTokenCount;
  final Map<String, dynamic> status;
  final List<Map<String, dynamic>> tokens;

  factory PushDeviceStatus.fromJson(Map<String, dynamic> json) {
    final result = Map<String, dynamic>.from(json['result'] as Map? ?? {});
    return PushDeviceStatus(
      actorProfile: (result['actor_profile'] ?? '').toString(),
      effectiveTokenStatus: (result['effective_token_status'] ?? '').toString(),
      activeTokenCount: (result['active_token_count'] as num?)?.toInt() ?? 0,
      status: Map<String, dynamic>.from(result['status'] as Map? ?? {}),
      tokens: (result['tokens'] as List? ?? const [])
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'actor_profile': actorProfile,
      'effective_token_status': effectiveTokenStatus,
      'active_token_count': activeTokenCount,
      'status': status,
      'tokens': tokens,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PushDeviceStatus &&
          runtimeType == other.runtimeType &&
          actorProfile == other.actorProfile &&
          effectiveTokenStatus == other.effectiveTokenStatus &&
          activeTokenCount == other.activeTokenCount &&
          mapEquals(status, other.status) &&
          listEquals(tokens, other.tokens);

  @override
  int get hashCode => Object.hash(
        actorProfile,
        effectiveTokenStatus,
        activeTokenCount,
        Object.hashAll(status.entries.map((e) => Object.hash(e.key, e.value))),
        Object.hashAll(tokens),
      );

  PushDeviceStatus copyWith({
    String? actorProfile,
    String? effectiveTokenStatus,
    int? activeTokenCount,
    Map<String, dynamic>? status,
    List<Map<String, dynamic>>? tokens,
  }) =>
      PushDeviceStatus(
        actorProfile: actorProfile ?? this.actorProfile,
        effectiveTokenStatus: effectiveTokenStatus ?? this.effectiveTokenStatus,
        activeTokenCount: activeTokenCount ?? this.activeTokenCount,
        status: status ?? this.status,
        tokens: tokens ?? this.tokens,
      );
}

@immutable
class PhoneProfileSession {
  const PhoneProfileSession({
    required this.profileKey,
    required this.phone,
    required this.displayName,
    required this.deviceId,
    required this.familyMembers,
  });

  final String profileKey;
  final String phone;
  final String displayName;
  final String deviceId;
  final List<ChatContact> familyMembers;

  Map<String, dynamic> toJson() {
    return {
      'profile_key': profileKey,
      'phone': phone,
      'display_name': displayName,
      'device_id': deviceId,
      'family_members': familyMembers.map((m) => m.toJson()).toList(),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PhoneProfileSession &&
          runtimeType == other.runtimeType &&
          profileKey == other.profileKey &&
          phone == other.phone &&
          displayName == other.displayName &&
          deviceId == other.deviceId &&
          listEquals(familyMembers, other.familyMembers);

  @override
  int get hashCode => Object.hash(
        profileKey,
        phone,
        displayName,
        deviceId,
        Object.hashAll(familyMembers),
      );

  PhoneProfileSession copyWith({
    String? profileKey,
    String? phone,
    String? displayName,
    String? deviceId,
    List<ChatContact>? familyMembers,
  }) =>
      PhoneProfileSession(
        profileKey: profileKey ?? this.profileKey,
        phone: phone ?? this.phone,
        displayName: displayName ?? this.displayName,
        deviceId: deviceId ?? this.deviceId,
        familyMembers: familyMembers ?? this.familyMembers,
      );
}
