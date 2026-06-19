import 'dart:async';

import 'package:family_todo_mobile/models/call_models.dart';
import 'package:family_todo_mobile/services/api_client.dart';
import 'package:family_todo_mobile/services/call_service.dart';
import 'package:flutter/services.dart';
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

class _LifecycleApi extends ApiClient {
  _LifecycleApi() : super(baseUrl: 'http://localhost', apiKey: 'test');

  @override
  Future<CallSession> callReject({
    required String actorProfile,
    required String sessionId,
  }) async {
    return _session(sessionId, 'rejected');
  }

  @override
  Future<CallSession> callEnd({
    required String actorProfile,
    required String sessionId,
  }) async {
    return _session(sessionId, 'ended');
  }

  CallSession _session(String sessionId, String status) {
    return CallSession(
      sessionId: sessionId,
      callerProfile: 'misha',
      calleeProfile: 'nik',
      conversationKey: 'dm:misha:nik',
      callType: 'audio',
      status: status,
      createdAt: '2026-05-31T12:00:00',
    );
  }
}

CallSession _incomingSession(String sessionId) {
  return CallSession(
    sessionId: sessionId,
    callerProfile: 'misha',
    calleeProfile: 'nik',
    conversationKey: 'dm:misha:nik',
    callType: 'audio',
    status: 'ringing',
    createdAt: '2026-05-31T12:00:00',
  );
}

Future<List<MethodCall>> _recordTelecomCalls(
  Future<void> Function() body,
) async {
  const channel = MethodChannel('family_todo_mobile/telecom');
  final calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    calls.add(call);
    return true;
  });
  try {
    await body();
  } finally {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  }
  return calls;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('callSignalingErrorMessage uses English diagnostic text', () {
    expect(
      callSignalingErrorMessage('bad sdp'),
      'Call signaling error: bad sdp',
    );
  });

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

  test('acceptCall marks native Telecom connection active', () async {
    final completer = Completer<CallSession>();
    final service = CallService(
      api: _PendingAcceptApi(completer),
      actorProfile: 'nik',
    );
    final session = _incomingSession('call-native-accept');
    service.notifyIncomingCall(session);

    final calls = await _recordTelecomCalls(() async {
      unawaited(service.acceptCall(session.sessionId));
      await Future<void>.delayed(Duration.zero);
    });

    expect(
      calls.map((call) => call.method),
      contains('answerIncomingConnection'),
    );
    expect(
      calls
          .where((call) => call.method == 'answerIncomingConnection')
          .single
          .arguments,
      {'sessionId': session.sessionId},
    );
    service.dispose();
  });

  test('rejectCall closes native Telecom connection locally', () async {
    final service = CallService(
      api: _LifecycleApi(),
      actorProfile: 'nik',
    );

    final calls = await _recordTelecomCalls(() async {
      await service.rejectCall('call-native-reject');
    });

    expect(
      calls.map((call) => call.method),
      contains('rejectIncomingConnection'),
    );
    expect(
      calls
          .where((call) => call.method == 'rejectIncomingConnection')
          .single
          .arguments,
      {'sessionId': 'call-native-reject'},
    );
    service.dispose();
  });

  test('endCall closes native Telecom connection locally', () async {
    final service = CallService(
      api: _LifecycleApi(),
      actorProfile: 'nik',
    );
    service.notifyIncomingCall(_incomingSession('call-native-end'));

    final calls = await _recordTelecomCalls(() async {
      await service.endCall();
    });

    expect(calls.map((call) => call.method), contains('endIncomingConnection'));
    expect(
      calls
          .where((call) => call.method == 'endIncomingConnection')
          .single
          .arguments,
      {'sessionId': 'call-native-end'},
    );
    service.dispose();
  });
}
