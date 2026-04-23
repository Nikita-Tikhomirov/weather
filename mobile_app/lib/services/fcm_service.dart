import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'api_client.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    try {
      await Firebase.initializeApp(options: _firebaseOptionsForCurrentPlatform());
    } catch (_) {
      // Best-effort initialization for background delivery.
    }
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
    final initialized = await _initializeFirebaseSafely();
    if (!initialized) {
      return;
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    final messaging = FirebaseMessaging.instance;
    await messaging.setAutoInitEnabled(true);
    final permission = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (permission.authorizationStatus == AuthorizationStatus.denied) {
      return;
    }

    await _registerTokenWithRetry(messaging);

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

  Future<void> _registerTokenWithRetry(FirebaseMessaging messaging) async {
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        final token = await messaging.getToken();
        if (token != null && token.isNotEmpty) {
          await _registerToken(token);
          return;
        }
      } catch (_) {
        // Best-effort retry. Token may be unavailable right after startup.
      }
      await Future<void>.delayed(const Duration(seconds: 2));
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

  Future<bool> _initializeFirebaseSafely() async {
    try {
      if (Firebase.apps.isNotEmpty) {
        return true;
      }
      await Firebase.initializeApp();
      return true;
    } catch (_) {
      try {
        if (Firebase.apps.isNotEmpty) {
          return true;
        }
        await Firebase.initializeApp(
          options: _firebaseOptionsForCurrentPlatform(),
        );
        return true;
      } catch (_) {
        return false;
      }
    }
  }
}

FirebaseOptions _firebaseOptionsForCurrentPlatform() {
  if (Platform.isAndroid) {
    const appId = String.fromEnvironment(
      'FIREBASE_APP_ID',
      defaultValue: '1:223906415067:android:68a62bb31cc4471895a7fe',
    );
    const projectId = String.fromEnvironment(
      'FIREBASE_PROJECT_ID',
      defaultValue: 'famillytodo-2758f',
    );
    const senderId = String.fromEnvironment(
      'FIREBASE_MESSAGING_SENDER_ID',
      defaultValue: '223906415067',
    );
    const apiKey = String.fromEnvironment(
      'FIREBASE_API_KEY',
      defaultValue: 'AIzaSyBtO5Nbcb91lk3WViNIHzwYX_5yazfG6K8',
    );
    const storageBucket = String.fromEnvironment(
      'FIREBASE_STORAGE_BUCKET',
      defaultValue: 'famillytodo-2758f.firebasestorage.app',
    );

    return const FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: senderId,
      projectId: projectId,
      storageBucket: storageBucket,
    );
  }

  throw UnsupportedError('Firebase options are not configured for this platform');
}
