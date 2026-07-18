import 'package:family_todo_mobile/models/call_models.dart';
import 'package:family_todo_mobile/services/api_client.dart';
import 'package:family_todo_mobile/services/push_notification_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('passes native accept action for incoming call pushes', () async {
    CallSession? receivedSession;
    IncomingCallPushAction? receivedAction;
    var syncCalled = false;

    final handler = PushNotificationHandler(
      api: ApiClient(baseUrl: 'https://example.invalid', apiKey: 'test'),
      owner: 'nik',
      onIncomingCall: (session, action) {
        receivedSession = session;
        receivedAction = action;
      },
      onSyncDelta: ({required bool showErrors}) async {
        syncCalled = true;
      },
    );

    await handler.handleOpenedPush({
      'type': 'call_incoming',
      'session_id': 'call-123',
      'conversation_key': 'dm:nik:misha',
      'caller_profile': 'misha',
      'call_type': 'video',
      'call_action': 'accept',
    });

    expect(syncCalled, isTrue);
    expect(receivedSession?.sessionId, 'call-123');
    expect(receivedSession?.callType, 'video');
    expect(receivedAction, IncomingCallPushAction.accept);
  });

  test('defaults incoming call pushes to showing the call screen', () async {
    IncomingCallPushAction? receivedAction;

    final handler = PushNotificationHandler(
      api: ApiClient(baseUrl: 'https://example.invalid', apiKey: 'test'),
      owner: 'nik',
      onIncomingCall: (_, action) {
        receivedAction = action;
      },
    );

    await handler.handleOpenedPush({
      'type': 'call_incoming',
      'session_id': 'call-123',
      'conversation_key': 'dm:nik:misha',
      'caller_profile': 'misha',
    });

    expect(receivedAction, IncomingCallPushAction.show);
  });

  test('opens the lead inbox for a Kwork lead push', () async {
    var opened = false;
    var synced = false;
    final handler = PushNotificationHandler(
      api: ApiClient(baseUrl: 'https://example.invalid', apiKey: 'test'),
      owner: 'nik',
      onNavigateToLeads: () async {
        opened = true;
      },
      onSyncDelta: ({required bool showErrors}) async {
        synced = true;
      },
    );

    await handler.handleOpenedPush({'type': 'kwork_lead', 'lead_id': '1'});

    expect(synced, isTrue);
    expect(opened, isTrue);
  });
}
