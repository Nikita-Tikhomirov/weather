import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android incoming call pushes use a full-screen call notification', () {
    final service = File(
      'android/app/src/main/kotlin/com/example/family_todo_mobile/FamilyMessagingService.kt',
    ).readAsStringSync();
    final payloads = File(
      'android/app/src/main/kotlin/com/example/family_todo_mobile/PushPayloads.kt',
    ).readAsStringSync();
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android.permission.USE_FULL_SCREEN_INTENT'));
    expect(payloads, contains('PUSH_CALL_CHANNEL_ID'));
    expect(payloads, contains('PUSH_ACTION_CALL_DECLINE'));
    expect(payloads, contains('isIncomingCallPush'));
    expect(service, contains('showIncomingCallNotification'));
    expect(service, contains('NotificationCompat.CATEGORY_CALL'));
    expect(service, contains('setFullScreenIntent'));
    expect(service, contains('call_action'));

    final backendPushOutboxFile = File('../backend_api/src/push_outbox.php');
    if (!backendPushOutboxFile.existsSync()) {
      return;
    }

    final backendPushOutbox = backendPushOutboxFile.readAsStringSync();
    expect(backendPushOutbox, contains(r'$isIncomingCall'));
    expect(backendPushOutbox, contains("'ttl' => \$isIncomingCall ? '60s'"));
    expect(backendPushOutbox, contains("'family_calls'"));
    expect(backendPushOutbox, contains(r'if (!$isIncomingCall)'));
  });
}
