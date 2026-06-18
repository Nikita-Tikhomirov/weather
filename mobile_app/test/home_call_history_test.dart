import 'package:family_todo_mobile/features/home/home_call_history.dart';
import 'package:family_todo_mobile/models/call_models.dart';
import 'package:family_todo_mobile/services/call_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds a missed incoming audio call chat message', () {
    const session = CallSession(
      sessionId: 'call-1',
      callerProfile: 'misha',
      calleeProfile: 'nik',
      conversationKey: 'dm:misha:nik',
      callType: 'audio',
      status: 'ringing',
      createdAt: '2026-06-18T10:00:00Z',
    );

    final message = buildCallHistoryMessage(
      session: session,
      owner: 'nik',
      previousState: CallState.ringing,
      endedAt: DateTime.parse('2026-06-18T10:01:00Z'),
    );

    expect(message.messageType, 'call');
    expect(message.text, 'Missed audio call');
    expect(message.senderProfile, 'nik');
    expect(message.imageMeta['call_status'], 'missed');
    expect(message.imageMeta['call_type'], 'audio');
    expect(message.imageMeta['duration_seconds'], 0);
  });

  test('builds a completed outgoing video call chat message with duration', () {
    const session = CallSession(
      sessionId: 'call-2',
      callerProfile: 'nik',
      calleeProfile: 'misha',
      conversationKey: 'dm:misha:nik',
      callType: 'video',
      status: 'connected',
      createdAt: '2026-06-18T10:00:00Z',
    );

    final message = buildCallHistoryMessage(
      session: session,
      owner: 'nik',
      previousState: CallState.connected,
      endedAt: DateTime.parse('2026-06-18T10:02:05Z'),
    );

    expect(message.messageType, 'call');
    expect(message.text, 'Video call ended');
    expect(message.senderProfile, 'nik');
    expect(message.imageMeta['call_status'], 'completed');
    expect(message.imageMeta['call_type'], 'video');
    expect(message.imageMeta['duration_seconds'], 125);
  });
}
