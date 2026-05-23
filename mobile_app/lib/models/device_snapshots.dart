import 'chat_models.dart';

class DeviceTokenRegistration {
  DeviceTokenRegistration({
    required this.shouldResetToken,
    required this.previousTokenStatus,
  });

  final bool shouldResetToken;
  final String previousTokenStatus;
}

class PushDeviceStatus {
  PushDeviceStatus({
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
          .map((item) => Map<String, dynamic>.from(item))
          .toList(),
    );
  }
}

class PhoneProfileSession {
  PhoneProfileSession({
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
}
