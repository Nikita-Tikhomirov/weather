import '../../l10n/app_localizations.dart';

String chatCallType(Map<String, dynamic> meta) {
  final raw = (meta['call_type'] ?? meta['type'] ?? 'audio')
      .toString()
      .trim()
      .toLowerCase();
  return raw == 'video' ? 'video' : 'audio';
}

String chatCallStatus(Map<String, dynamic> meta) {
  final raw = (meta['call_status'] ?? meta['status'] ?? 'completed')
      .toString()
      .trim()
      .toLowerCase();
  if (raw == 'missed' || raw == 'rejected' || raw == 'declined') {
    return 'missed';
  }
  return 'completed';
}

int chatCallDurationSeconds(Map<String, dynamic> meta) {
  final value = meta['duration_seconds'];
  if (value is int) return value.clamp(0, 24 * 60 * 60);
  if (value is num) return value.toInt().clamp(0, 24 * 60 * 60);
  return (int.tryParse((value ?? '').toString()) ?? 0).clamp(0, 24 * 60 * 60);
}

String formatChatCallDuration(int seconds) {
  final safeSeconds = seconds < 0 ? 0 : seconds;
  final minutes = safeSeconds ~/ 60;
  final remainder = safeSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${remainder.toString().padLeft(2, '0')}';
}

String defaultChatCallTitle({
  required String status,
  required String callType,
}) {
  final isVideo = callType == 'video';
  if (status == 'missed') {
    return isVideo ? 'Missed video call' : 'Missed audio call';
  }
  return isVideo ? 'Video call ended' : 'Audio call ended';
}

String localizedChatCallTitle(
  AppLocalizations? l10n, {
  required String status,
  required String callType,
}) {
  final isVideo = callType == 'video';
  if (status == 'missed') {
    if (isVideo) return l10n?.missedVideoCall ?? 'Missed video call';
    return l10n?.missedAudioCall ?? 'Missed audio call';
  }
  if (isVideo) return l10n?.videoCallEnded ?? 'Video call ended';
  return l10n?.audioCallEnded ?? 'Audio call ended';
}
