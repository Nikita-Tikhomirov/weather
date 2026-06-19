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
    expect(service, contains('setDeleteIntent(declinePendingIntent)'));
    expect(
      mainActivity,
      contains('TelecomCallManager.cancelIncomingCallNotification'),
    );
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

  test('Android incoming calls are reported to Telecom before fallback UI', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final service = File(
      'android/app/src/main/kotlin/com/example/family_todo_mobile/FamilyMessagingService.kt',
    ).readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/example/family_todo_mobile/MainActivity.kt',
    ).readAsStringSync();
    final manager = File(
      'android/app/src/main/kotlin/com/example/family_todo_mobile/TelecomCallManager.kt',
    ).readAsStringSync();
    final connectionService = File(
      'android/app/src/main/kotlin/com/example/family_todo_mobile/FamilyConnectionService.kt',
    ).readAsStringSync();
    final connection = File(
      'android/app/src/main/kotlin/com/example/family_todo_mobile/FamilyCallConnection.kt',
    ).readAsStringSync();

    expect(manifest, contains('android.permission.MANAGE_OWN_CALLS'));
    expect(
      manifest,
      contains('android.permission.BIND_TELECOM_CONNECTION_SERVICE'),
    );
    expect(manifest, contains('android.telecom.ConnectionService'));
    expect(service, contains('TelecomCallManager.reportIncomingCall'));
    expect(service, contains('TelecomCallManager.registerPhoneAccounts'));
    expect(manager, contains('addNewIncomingCall'));
    expect(manager, contains('TelecomManager.EXTRA_INCOMING_CALL_ADDRESS'));
    expect(manager, contains('TelecomManager.EXTRA_INCOMING_VIDEO_STATE'));
    expect(manager, contains('PhoneAccount.CAPABILITY_CALL_PROVIDER'));
    expect(manager, contains('PhoneAccount.CAPABILITY_SELF_MANAGED'));
    expect(manager, contains('TelecomManager.ACTION_CHANGE_PHONE_ACCOUNTS'));
    expect(manager, contains('canUseFullScreenIntent'));
    expect(manager, contains('ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT'));
    expect(
      manager,
      contains('fun isManagedPhoneAccountEnabled(context: Context): Boolean'),
    );
    expect(
      manager,
      contains('fun canUseFullScreenIntent(context: Context): Boolean'),
    );
    expect(
      manager,
      contains('fun fullScreenIntentSettingsIntent(context: Context): Intent'),
    );
    expect(
      manager,
      contains(
        'fun cancelIncomingCallNotification(context: Context, data: Map<String, String>)',
      ),
    );
    expect(mainActivity, contains('"family_todo_mobile/telecom"'));
    expect(mainActivity, contains('"registerPhoneAccounts"'));
    expect(mainActivity, contains('"isManagedPhoneAccountEnabled"'));
    expect(mainActivity, contains('"openPhoneAccountSettings"'));
    expect(mainActivity, contains('"canUseFullScreenIntent"'));
    expect(mainActivity, contains('"openFullScreenIntentSettings"'));
    expect(
      mainActivity,
      contains('TelecomCallManager.phoneAccountSettingsIntent()'),
    );
    expect(connectionService, contains('onCreateIncomingConnection'));
    expect(
      connectionService,
      contains('TelecomCallManager.isSelfManagedPhoneAccount'),
    );
    expect(connectionService, contains('onCreateIncomingConnectionFailed'));
    expect(connection, contains('onShowIncomingCallUi'));
    expect(
      connection,
      contains('openCallActivity(appContext, data, "accept")'),
    );
    expect(
      connection,
      contains('setConnectionProperties(PROPERTY_SELF_MANAGED)'),
    );
    expect(connection, contains('onAnswer'));
    expect(connection, contains('onReject'));
    expect(connection, contains('onDisconnect'));
  });

  test(
      'Android gallery image save validates bytes and preserves original bytes',
      () {
    final mainActivity = File(
      'android/app/src/main/kotlin/com/example/family_todo_mobile/MainActivity.kt',
    ).readAsStringSync();

    expect(mainActivity, contains('"saveImageBytes"'));
    expect(mainActivity, contains('call.argument<ByteArray>("bytes")'));
    expect(mainActivity, contains('saveImageBytesToGallery'));
    expect(mainActivity, contains('BitmapFactory.Options'));
    expect(mainActivity, contains('outMimeType'));
    expect(mainActivity, contains('Downloaded file is not a supported image'));
    expect(mainActivity, contains('imageFormatForDecodedMime(decodedMime)'));
    expect(mainActivity, contains('GalleryImage(bytes, imageFormat)'));
    expect(mainActivity, contains('galleryImage.bytes'));
    expect(mainActivity, contains('MediaStore.Images.Media.IS_PENDING'));
    expect(mainActivity, contains('contentResolver.delete'));
    expect(mainActivity, contains('connection.contentType'));
    expect(mainActivity, contains('Decoded gallery image has no MIME type'));
    expect(mainActivity, contains('setRequestProperty("X-Api-Key", apiKey)'));
    expect(mainActivity, contains('call.argument<String>("apiKey")'));
    expect(mainActivity, contains('call.argument<String>("apiBaseUrl")'));
    expect(
      mainActivity,
      contains('shouldAttachApiKey(downloadUrl, apiBaseUrl)'),
    );
    expect(
      mainActivity,
      contains('effectivePort(imageUrl) == effectivePort(apiUrl)'),
    );
    expect(
      mainActivity,
      isNot(contains(r'FamilyTodo_${System.currentTimeMillis()}.jpg')),
    );
    expect(
      mainActivity,
      isNot(contains('MediaStore.Images.Media.MIME_TYPE, "image/jpeg"')),
    );
    expect(
      mainActivity,
      isNot(contains('imageFormatForMime(contentType')),
    );
    expect(
      mainActivity,
      isNot(contains('ByteArrayOutputStream')),
    );
    expect(
      mainActivity,
      isNot(contains('bitmap.compress')),
    );
    expect(
      mainActivity,
      isNot(contains('stream.write(download.bytes)')),
    );
    expect(
      mainActivity,
      isNot(contains('file.writeBytes(download.bytes)')),
    );

    final homeChatSection =
        File('lib/features/home/home_chat_section.dart').readAsStringSync();
    expect(homeChatSection, contains('apiKey: AppConfig.apiKey'));
    expect(homeChatSection, contains('apiBaseUrl: AppConfig.apiBaseUrl'));
    final homePage =
        File('lib/features/home/home_page.dart').readAsStringSync();
    expect(homePage, contains("import '../../app/app_config.dart';"));
    expect(
      homePage,
      contains("import '../../services/gallery_image_saver.dart';"),
    );
    expect(homeChatSection, contains('GalleryImageSaver('));
    expect(homeChatSection, contains('saveNetworkImage(url)'));
  });
}
