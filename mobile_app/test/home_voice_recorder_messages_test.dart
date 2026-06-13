import 'package:family_todo_mobile/features/home/home_voice_recorder_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses English fallback voice recorder messages without localizations',
      () {
    final messages = buildHomeVoiceRecorderMessages(null);

    expect(messages.permissionRequired, 'Microphone permission is required');
    expect(messages.microphoneErrorPrefix, 'Microphone error: ');
    expect(messages.tooShort, 'Recording is too short');
    expect(messages.voiceMessage, 'Voice message');
    expect(messages.sendErrorPrefix, 'Error: ');
  });
}
