import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'api_client.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Best-effort initialization for background delivery.
  }
}

class FcmService {
  FcmService({
    required this.api,
    required this.actorProfile,
    required this.onForegroundText,
    required this.onOpenPush,
  });

  final ApiClient api;
  final String actorProfile;
  final void Function(String text) onForegroundText;
  final Future<void> Function() onOpenPush;

  Future<void> initialize() async {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      return;
    }
    try {
      await Firebase.initializeApp();
    } catch (_) {}

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    final token = await messaging.getToken();
    if (token != null && token.isNotEmpty) {
      await _registerToken(token);
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      if (newToken.isEmpty) {
        return;
      }
      await _registerToken(newToken);
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage msg) async {
      await onOpenPush();
      final title = msg.notification?.title ?? 'Семейные задачи';
      final body = msg.notification?.body ?? 'Есть новые изменения';
      onForegroundText('$title: $body');
    });

    FirebaseMessaging.onMessageOpenedApp.listen((_) async {
      await onOpenPush();
    });

    final initial = await messaging.getInitialMessage();
    if (initial != null) {
      await onOpenPush();
    }
  }

  Future<void> _registerToken(String token) async {
    await api.registerDeviceToken(
      actorProfile: actorProfile,
      token: token,
      platform: Platform.isAndroid
          ? 'android'
          : (Platform.isIOS ? 'ios' : 'other'),
      appVersion: '0.1.0',
    );
  }
}
