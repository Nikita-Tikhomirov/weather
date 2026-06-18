import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android incoming call pushes use a full-screen call notification', () {
    final service = File(
      'android/app/src/main/kotlin/com/example/family_todo_mobile/FamilyMessagingService.kt',
    ).readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/example/family_todo_mobile/MainActivity.kt',
    ).readAsStringSync();
    final payloads = File(
      'android/app/src/main/kotlin/com/example/family_todo_mobile/PushPayloads.kt',
    ).readAsStringSync();
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android.permission.USE_FULL_SCREEN_INTENT'));
    expect(payloads, contains('PUSH_CALL_CHANNEL_ID'));
    expect(payloads, contains('family_calls_v2'));
    expect(payloads, contains('PUSH_ACTION_CALL_DECLINE'));
    expect(payloads, contains('isIncomingCallPush'));
    expect(service, contains('showIncomingCallNotification'));
    expect(service, contains('NotificationCompat.CATEGORY_CALL'));
    expect(service, contains('NotificationCompat.CallStyle.forIncomingCall'));
    expect(service, contains('Person.Builder'));
    expect(service, contains('setFullScreenIntent'));
    expect(mainActivity, contains('setShowWhenLocked'));
    expect(mainActivity, contains('setTurnScreenOn'));
    expect(mainActivity, contains('requestDismissKeyguard'));
    expect(service, contains('call_action'));

    final backendPushOutboxFile = File('../backend_api/src/push_outbox.php');
    if (!backendPushOutboxFile.existsSync()) {
      return;
    }

    final backendPushOutbox = backendPushOutboxFile.readAsStringSync();
    expect(backendPushOutbox, contains(r'$isIncomingCall'));
    expect(backendPushOutbox, contains("'ttl' => \$isIncomingCall ? '60s'"));
    expect(backendPushOutbox, contains("'family_calls_v2'"));
    expect(backendPushOutbox, contains(r'if (!$isIncomingCall)'));
  });

  test('Android gallery image save validates bytes and preserves image MIME',
      () {
    final mainActivity = File(
      'android/app/src/main/kotlin/com/example/family_todo_mobile/MainActivity.kt',
    ).readAsStringSync();

    expect(mainActivity, contains('BitmapFactory.Options'));
    expect(mainActivity, contains('outMimeType'));
    expect(mainActivity, contains('Downloaded file is not a supported image'));
    expect(mainActivity, contains('MediaStore.Images.Media.IS_PENDING'));
    expect(mainActivity, contains('contentResolver.delete'));
    expect(mainActivity, contains('connection.contentType'));
    expect(
      mainActivity,
      isNot(contains(r'FamilyTodo_${System.currentTimeMillis()}.jpg')),
    );
    expect(
      mainActivity,
      isNot(contains('MediaStore.Images.Media.MIME_TYPE, "image/jpeg"')),
    );
  });
}
