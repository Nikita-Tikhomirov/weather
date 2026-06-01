import 'package:family_todo_mobile/models/chat_snapshots.dart';
import 'package:family_todo_mobile/services/voice_recorder_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buildVoiceAttachment marks uploaded voice as playable attachment', () {
    final attachment = buildVoiceAttachment(
      const ChatUploadResult(
        assetUrl: '/chat/media/voice-123',
        imageMeta: {'mime_type': 'audio/mp4'},
      ),
      durationMs: 3000,
    );

    expect(attachment.kind, 'voice');
    expect(attachment.assetUrl, '/chat/media/voice-123');
    expect(attachment.imageMeta['mime_type'], 'audio/mp4');
    expect(attachment.imageMeta['duration_ms'], 3000);
    expect(attachment.sortOrder, 0);
  });
}
