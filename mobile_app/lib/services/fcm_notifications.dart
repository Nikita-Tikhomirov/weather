part of 'fcm_service.dart';

// ── Notification display ───────────────────────────────────────

Future<void> _showForegroundNotification({
  required String title, required String body, required Map<String, dynamic> data,
}) async {
  final payload = jsonEncode(data);
  final details = NotificationDetails(
    android: AndroidNotificationDetails(
      _notificationChannelId, _notificationChannelName,
      channelDescription: _notificationChannelDescription,
      importance: Importance.max, priority: Priority.high,
      visibility: NotificationVisibility.public,
      icon: '@mipmap/ic_launcher',
      actions: isChatMessageData(data)
          ? const [
              AndroidNotificationAction(_openChatActionId, 'Перейти',
                  cancelNotification: true, showsUserInterface: true),
              AndroidNotificationAction(_markReadActionId, 'Пометить прочитанным',
                  cancelNotification: true, showsUserInterface: false),
            ]
          : null,
    ),
  );
  await _localNotifications.show(
    DateTime.now().millisecondsSinceEpoch.remainder(100000),
    title, body, details, payload: payload,
  );
}

// ── Top-level notification helpers ─────────────────────────────

Future<void> _ensureNotificationChannel() async {
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initializationSettings = InitializationSettings(android: androidSettings);
  await _localNotifications.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: _handleNotificationResponse,
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );

  const channel = AndroidNotificationChannel(
    _notificationChannelId, _notificationChannelName,
    description: _notificationChannelDescription,
    importance: Importance.max, playSound: true,
  );
  await _localNotifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
}

Future<void> _showChatNotificationFromData(Map<String, dynamic> data, {String? title, String? body}) async {
  final notificationTitle = (title ?? data['title'] ?? 'Сообщение').toString();
  final notificationBody = (body ?? data['body'] ?? 'Новое сообщение').toString();
  const details = NotificationDetails(
    android: AndroidNotificationDetails(
      _notificationChannelId, _notificationChannelName,
      channelDescription: _notificationChannelDescription,
      importance: Importance.max, priority: Priority.high,
      visibility: NotificationVisibility.public,
      icon: '@mipmap/ic_launcher',
      actions: [
        AndroidNotificationAction(_openChatActionId, 'Перейти',
            cancelNotification: true, showsUserInterface: true),
        AndroidNotificationAction(_markReadActionId, 'Пометить прочитанным',
            cancelNotification: true, showsUserInterface: false),
      ],
    ),
  );
  await _localNotifications.show(
    DateTime.now().millisecondsSinceEpoch.remainder(100000),
    notificationTitle, notificationBody, details, payload: jsonEncode(data),
  );
}

@pragma('vm:entry-point')
Future<void> notificationTapBackground(NotificationResponse response) async {
  await _handleNotificationResponse(response);
}

Future<void> _handleNotificationResponse(NotificationResponse response) async {
  final actionId = response.actionId ?? '';
  if (actionId.isEmpty || actionId == _openChatActionId) {
    final data = _decodeNotificationPayload(response.payload ?? '');
    if (data != null) _notificationOpenEvents.add(data);
    return;
  }
  if (actionId != _markReadActionId) return;
  final data = _decodeNotificationPayload(response.payload ?? '');
  if (data == null) return;
  final conversationKey = (data['conversation_key'] ?? '').toString().trim();
  if (conversationKey.isEmpty) return;
  var actor = (data['recipient_profile'] ?? '').toString().trim();
  if (actor.isEmpty) {
    try {
      final prefs = await SharedPreferences.getInstance();
      actor = prefs.getString('actor_profile')?.trim() ?? '';
    } catch (_) {}
  }
  if (actor.isEmpty) return;
  try {
    await ApiClient(baseUrl: _defaultApiBaseUrl, apiKey: _defaultApiKey)
        .chatMarkRead(actorProfile: actor, conversationKey: conversationKey);
  } catch (_) {}
}

