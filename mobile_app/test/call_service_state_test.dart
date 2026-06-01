import 'dart:async';

import 'package:family_todo_mobile/models/call_models.dart';
import 'package:family_todo_mobile/services/api_client.dart';
import 'package:family_todo_mobile/services/call_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _PendingAcceptApi extends ApiClient {
  _PendingAcceptApi(this.acceptCompleter)
      : super(baseUrl: 'http://localhost', apiKey: 'test');

  final Completer<CallSession> acceptCompleter;

  @override
  Future<CallSession> callAccept({
    required String actorProfile,
    required String sessionId,
  }) {
    return acceptCompleter.future;
  }
}

void main() {
  test('acceptCall does not report connected before signaling is ready',
      () async {
    final completer = Completer<CallSession>();
    final service = CallService(
      api: _PendingAcceptApi(completer),
      actorProfile: 'nik',
    );
    const session = CallSession(
      sessionId: 'call-1',
      callerProfile: 'misha',
      calleeProfile: 'nik',
      conversationKey: 'dm:misha:nik',
      callType: 'audio',
      status: 'ringing',
      createdAt: '2026-05-31T12:00:00',
    );
    service.notifyIncomingCall(session);

    final states = <CallState>[];
    final sub = service.onStateChange.listen(states.add);
    unawaited(service.acceptCall(session.sessionId));
    await Future<void>.delayed(Duration.zero);

    expect(states, isNot(contains(CallState.connected)));

    await sub.cancel();
    service.dispose();
  });
}
