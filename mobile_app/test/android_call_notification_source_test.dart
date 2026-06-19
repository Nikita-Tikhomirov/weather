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
    expect(manifest, contains('android.permission.VIBRATE'));
    expect(payloads, contains('family_calls_v3'));
    expect(payloads, isNot(contains('family_calls_v2')));
    expect(payloads, contains('PUSH_ACTION_CALL_DECLINE'));
    expect(payloads, contains('isIncomingCallPush'));
    expect(service, contains('showIncomingCallNotification'));
    expect(service, contains('IncomingCallAlertManager.start(context)'));
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
    expect(backendPushOutbox, contains("'channel_id' => 'family_updates'"));
    expect(backendPushOutbox, isNot(contains("'family_calls_v2'")));
    expect(backendPushOutbox, contains(r'if (!$isIncomingCall)'));
    expect(
      backendPushOutbox,
      isNot(
        contains(
          r"'channel_id' => $isIncomingCall ? 'family_calls_v3' : 'family_updates'",
        ),
      ),
    );
    expect(backendPushOutbox, isNot(contains("'family_calls_v3'")));
  });

  test('Android incoming calls play and stop a native ringtone loop', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final service = File(
      'android/app/src/main/kotlin/com/example/family_todo_mobile/FamilyMessagingService.kt',
    ).readAsStringSync();
    final manager = File(
      'android/app/src/main/kotlin/com/example/family_todo_mobile/TelecomCallManager.kt',
    ).readAsStringSync();
    final receiver = File(
      'android/app/src/main/kotlin/com/example/family_todo_mobile/PushActionReceiver.kt',
    ).readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/example/family_todo_mobile/IncomingCallActivity.kt',
    ).readAsStringSync();
    final connection = File(
      'android/app/src/main/kotlin/com/example/family_todo_mobile/FamilyCallConnection.kt',
    ).readAsStringSync();
    final alertManagerFile = File(
      'android/app/src/main/kotlin/com/example/family_todo_mobile/IncomingCallAlertManager.kt',
    );
    expect(alertManagerFile.existsSync(), isTrue);
    final alertManager = alertManagerFile.existsSync()
        ? alertManagerFile.readAsStringSync()
        : '';

    expect(manifest, contains('android.permission.VIBRATE'));
    expect(alertManager, contains('object IncomingCallAlertManager'));
    expect(alertManager, contains('MediaPlayer'));
    expect(alertManager, contains('RingtoneManager.TYPE_RINGTONE'));
    expect(
      alertManager,
      contains('AudioAttributes.USAGE_NOTIFICATION_RINGTONE'),
    );
    expect(alertManager, contains('isLooping = true'));
    expect(alertManager, contains('VibrationEffect.createWaveform'));
    expect(alertManager, contains('CALL_RING_TIMEOUT_MS'));
    expect(alertManager, contains('handler.postDelayed(stopRunnable'));
    expect(alertManager, contains('fun stop()'));
    expect(service, contains('IncomingCallAlertManager.start(context)'));
    expect(activity, contains('IncomingCallAlertManager.start(this)'));
    expect(activity, contains('IncomingCallAlertManager.stop()'));
    expect(manager, contains('IncomingCallAlertManager.stop()'));
    expect(receiver, contains('IncomingCallAlertManager.stop()'));
    expect(
      receiver,
      contains('TelecomCallManager.rejectIncomingConnection(data)'),
    );
    final cancelIndex =
        receiver.indexOf('manager.cancel(callNotificationId(data))');
    final missingDataReturnIndex =
        receiver.indexOf('if (sessionId.isEmpty() || actor.isEmpty()) return');
    expect(cancelIndex, isNonNegative);
    expect(missingDataReturnIndex, isNonNegative);
    expect(cancelIndex, lessThan(missingDataReturnIndex));
    expect(connection, contains('IncomingCallAlertManager.stop()'));
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
    expect(manager, contains('activeConnections'));
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
    expect(
      manager,
      contains(
        'fun openIncomingCallActivity(context: Context, data: Map<String, String>)',
      ),
    );
    expect(
      manager,
      contains('Intent(context, IncomingCallActivity::class.java)'),
    );
    expect(
      manager,
      contains(
        'fun trackIncomingConnection(data: Map<String, String>, connection: FamilyCallConnection)',
      ),
    );
    expect(
      manager,
      contains('fun answerIncomingConnection(data: Map<String, String>)'),
    );
    expect(
      manager,
      contains(
        'fun rejectIncomingConnection(context: Context, data: Map<String, String>)',
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
    expect(
      connectionService,
      contains('val data = TelecomCallManager.callDataFromRequest(request)'),
    );
    expect(
      connectionService,
      contains('TelecomCallManager.showIncomingCallFallback(this, data)'),
    );
    expect(
      manager,
      contains(
        'fun showIncomingCallFallback(context: Context, data: Map<String, String>)',
      ),
    );
    expect(
      connection,
      contains('TelecomCallManager.trackIncomingConnection(data, this)'),
    );
    expect(connection, contains('fun answerFromNative()'));
    expect(connection, contains('fun rejectFromNative()'));
    expect(connection, contains('fun endFromNative()'));
    expect(connection, contains('onShowIncomingCallUi'));
    expect(
      connection,
      contains('TelecomCallManager.openIncomingCallActivity(appContext, data)'),
    );
    expect(
      connection,
      contains('openCallActivity(appContext, data, "accept")'),
    );
    expect(
      manager,
      contains('scheduleSelfManagedUiFallback(context, data)'),
    );
    expect(manager, contains('Handler(Looper.getMainLooper())'));
    expect(manager, contains('SELF_MANAGED_UI_FALLBACK_DELAY_MS'));
    expect(manager, contains('connection.hasShownIncomingUi()'));
    expect(
      manager,
      contains('FamilyMessagingService.showIncomingCallNotification'),
    );
    expect(
      manager,
      contains('openIncomingCallActivity(appContext, data)'),
    );
    expect(connection, contains('private var incomingUiShown = false'));
    expect(connection, contains('incomingUiShown = true'));
    expect(connection, contains('fun hasShownIncomingUi(): Boolean'));
    expect(
      connection,
      contains('setConnectionProperties(PROPERTY_SELF_MANAGED)'),
    );
    expect(connection, contains('onAnswer'));
    expect(connection, contains('onReject'));
    expect(connection, contains('onDisconnect'));
  });

  test('Android incoming call QA receiver simulates audio and video calls', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final payloads = File(
      'android/app/src/main/kotlin/com/example/family_todo_mobile/PushPayloads.kt',
    ).readAsStringSync();
    final receiverFile = File(
      'android/app/src/main/kotlin/com/example/family_todo_mobile/IncomingCallTestReceiver.kt',
    );

    expect(receiverFile.existsSync(), isTrue);
    final receiver =
        receiverFile.existsSync() ? receiverFile.readAsStringSync() : '';

    expect(payloads, contains('PUSH_ACTION_TEST_INCOMING_CALL'));
    expect(manifest, contains('android:name=".IncomingCallTestReceiver"'));
    expect(manifest, contains('android:exported="true"'));
    expect(manifest, contains('android:permission="android.permission.DUMP"'));
    expect(
      manifest,
      contains(
        '<action android:name="com.example.family_todo_mobile.action.TEST_INCOMING_CALL" />',
      ),
    );
    expect(
      receiver,
      contains('class IncomingCallTestReceiver : BroadcastReceiver()'),
    );
    expect(receiver, contains('PUSH_ACTION_TEST_INCOMING_CALL'));
    expect(
      receiver,
      contains('TelecomCallManager.registerPhoneAccounts(context)'),
    );
    expect(
      receiver,
      contains('TelecomCallManager.reportIncomingCall(context, data)'),
    );
    expect(
      receiver,
      contains(
        'FamilyMessagingService.showIncomingCallNotification(context, data)',
      ),
    );
    expect(receiver, contains('"entity" to "call_incoming"'));
    expect(receiver, contains('"type" to "call_incoming"'));
    expect(receiver, contains('"session_id"'));
    expect(receiver, contains('"call_type" to callType'));
    expect(
      receiver,
      contains('rawCallType.equals("video", ignoreCase = true)'),
    );
  });

  test(
    'Android incoming call full-screen intent opens native lockscreen UI',
    () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      final service = File(
        'android/app/src/main/kotlin/com/example/family_todo_mobile/FamilyMessagingService.kt',
      ).readAsStringSync();
      final activity = File(
        'android/app/src/main/kotlin/com/example/family_todo_mobile/IncomingCallActivity.kt',
      ).readAsStringSync();
      final styles =
          File('android/app/src/main/res/values/styles.xml').readAsStringSync();

      expect(manifest, contains('android:name=".IncomingCallActivity"'));
      expect(manifest, contains('android:showWhenLocked="true"'));
      expect(manifest, contains('android:turnScreenOn="true"'));
      expect(manifest, contains('android:excludeFromRecents="true"'));
      expect(manifest, contains('android:exported="false"'));
      expect(manifest, contains('android:theme="@style/IncomingCallTheme"'));
      expect(styles, contains('name="IncomingCallTheme"'));
      expect(
        styles,
        contains(
          '<item name="android:windowBackground">@android:color/black</item>',
        ),
      );
      expect(
        styles,
        contains('<item name="android:windowFullscreen">true</item>'),
      );
      expect(
        styles,
        contains('<item name="android:windowNoTitle">true</item>'),
      );
      expect(styles, isNot(contains('android:windowShowWhenLocked')));
      expect(styles, isNot(contains('android:windowTurnScreenOn')));

      expect(service, contains('IncomingCallActivity::class.java'));
      expect(service, contains('if (callAction == "show")'));
      expect(service, contains('setFullScreenIntent(openPendingIntent, true)'));

      expect(activity, contains('class IncomingCallActivity : Activity()'));
      expect(activity, contains('setShowWhenLocked(true)'));
      expect(activity, contains('setTurnScreenOn(true)'));
      expect(activity, contains('requestDismissKeyguard'));
      expect(activity, contains('FLAG_SHOW_WHEN_LOCKED'));
      expect(activity, contains('FLAG_TURN_SCREEN_ON'));
      expect(activity, contains('FLAG_DISMISS_KEYGUARD'));
      expect(
        activity,
        contains('TelecomCallManager.answerIncomingConnection(data)'),
      );
      expect(
        activity,
        contains('TelecomCallManager.openCallActivity(this, data, "accept")'),
      );
      expect(
        activity,
        contains('TelecomCallManager.rejectIncomingConnection(this, data)'),
      );
      expect(
        activity,
        contains('TelecomCallManager.cancelIncomingCallNotification'),
      );
      expect(activity, contains('finish()'));
      expect(activity, contains('Принять'));
      expect(activity, contains('Отклонить'));
      expect(activity, contains('Видеозвонок'));
      expect(activity, contains('GradientDrawable.OVAL'));
      expect(activity, contains('actionButtonColumn('));
      expect(activity, contains('callActionCircle('));
      expect(activity, contains('contentDescription = label'));
      expect(activity, isNot(contains('GradientDrawable.RECTANGLE')));
    },
  );

  test('Android gallery image save writes decoded gallery-safe bytes', () {
    final mainActivity = File(
      'android/app/src/main/kotlin/com/example/family_todo_mobile/MainActivity.kt',
    ).readAsStringSync();

    expect(mainActivity, contains('"saveImageBytes"'));
    expect(mainActivity, contains('call.argument<ByteArray>("bytes")'));
    expect(mainActivity, contains('saveImageBytesToGallery'));
    expect(mainActivity, contains('BitmapFactory.Options'));
    expect(
      mainActivity,
      contains('BitmapFactory.decodeByteArray(bytes, 0, bytes.size)'),
    );
    expect(mainActivity, contains('outMimeType'));
    expect(mainActivity, contains('Downloaded file is not a supported image'));
    expect(mainActivity, contains('imageFormatForDecodedMime(decodedMime)'));
    expect(
      mainActivity,
      contains('normaliseGalleryImageBytes(bytes, imageFormat)'),
    );
    expect(mainActivity, contains('Bitmap.CompressFormat.PNG'));
    expect(mainActivity, contains('Bitmap.CompressFormat.JPEG'));
    expect(mainActivity, contains('ByteArrayOutputStream'));
    expect(mainActivity, contains('bitmap.compress'));
    expect(mainActivity, contains('Cannot encode gallery image'));
    expect(mainActivity, contains('Encoded gallery image is empty'));
    expect(mainActivity, contains('return GalleryImage('));
    expect(mainActivity, contains('galleryBytes,'));
    expect(mainActivity, contains('options.outWidth'));
    expect(mainActivity, contains('options.outHeight'));
    expect(mainActivity, contains('galleryImage.width'));
    expect(mainActivity, contains('galleryImage.height'));
    expect(mainActivity, contains('galleryImage.bytes'));
    expect(mainActivity, contains('stream.flush()'));
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
      isNot(contains('return GalleryImage(\n            bytes,')),
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
