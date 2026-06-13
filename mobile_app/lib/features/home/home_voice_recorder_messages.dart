import '../../l10n/app_localizations.dart';
import '../../services/voice_recorder_service.dart';

VoiceRecorderMessages buildHomeVoiceRecorderMessages(AppLocalizations? l10n) {
  const defaults = VoiceRecorderMessages();
  return VoiceRecorderMessages(
    permissionRequired:
        l10n?.voicePermissionRequired ?? defaults.permissionRequired,
    microphoneErrorPrefix:
        l10n?.voiceMicrophoneErrorPrefix ?? defaults.microphoneErrorPrefix,
    tooShort: l10n?.voiceRecordingTooShort ?? defaults.tooShort,
    voiceMessage: l10n?.voiceMessage ?? defaults.voiceMessage,
    sendErrorPrefix: l10n?.voiceSendErrorPrefix ?? defaults.sendErrorPrefix,
  );
}
