import 'package:family_todo_mobile/features/chat/call_screen.dart';
import 'package:family_todo_mobile/models/call_models.dart';
import 'package:family_todo_mobile/services/api_client.dart';
import 'package:family_todo_mobile/services/call_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class _NoopApi extends ApiClient {
  _NoopApi() : super(baseUrl: 'http://localhost', apiKey: 'test');
}

class _NoopCallAudioDevice implements CallAudioDevice {
  @override
  Future<void> clearCommunicationDevice() async {}

  @override
  Future<void> configureForCall(
    AndroidAudioConfiguration configuration,
  ) async {}

  @override
  Future<void> preferHeadsetOrBluetooth() async {}

  @override
  Future<void> setMicrophoneMuted(
    bool muted,
    MediaStreamTrack track,
  ) async {}

  @override
  Future<void> setSpeakerOn(bool enabled) async {}
}

void main() {
  testWidgets('audio call body keeps status and controls visible',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CallAudioBody(
            peerLabel: 'User misha',
            state: CallState.connected,
            statusText: 'Разговор',
            durationText: '00:05',
            errorText: '',
            actions: Text('call controls'),
          ),
        ),
      ),
    );

    expect(find.text('User misha'), findsOneWidget);
    expect(find.text('Разговор'), findsOneWidget);
    expect(find.text('00:05'), findsOneWidget);
    expect(find.text('call controls'), findsOneWidget);
    expect(find.byIcon(Icons.call), findsOneWidget);
  });

  testWidgets('audio call screen disposes without initialized video renderers',
      (tester) async {
    final service = CallService(
      api: _NoopApi(),
      actorProfile: 'nik',
      audioDevice: _NoopCallAudioDevice(),
    );
    const session = CallSession(
      sessionId: 'call-1',
      callerProfile: 'misha',
      calleeProfile: 'nik',
      conversationKey: 'dm:misha:nik',
      callType: 'audio',
      status: 'ringing',
      createdAt: '2026-06-01T12:00:00',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CallScreen(
          callService: service,
          session: session,
          isIncoming: true,
          peerLabel: 'misha',
          onCallFinished: () {},
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());

    expect(tester.takeException(), isNull);
    service.dispose();
  });
}
