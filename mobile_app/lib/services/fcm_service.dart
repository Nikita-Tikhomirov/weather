import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_client.dart';

const _notificationChannelId = 'family_updates';
const _notificationChannelName = 'Family updates';
const _notificationChannelDescription =
    'Push notifications about family task changes';

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    try {
      await Firebase.initializeApp(options: _firebaseOptionsForCurrentPlatform());
    } catch (_) {
      return;
    }
  }
  await _ensureNotificationChannel();
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

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onOpenSub;
  Timer? _tokenRefreshTimer;
  String _lastRegisteredToken = '';

  Future<void> initialize() async {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      return;
    }

    final initialized = await _initializeFirebaseSafely();
    if (!initialized) {
      return;
    }

    await _ensureNotificationChannel();
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
    _startTokenRefreshLoop(messaging);

    _tokenRefreshSub = messaging.onTokenRefresh.listen((newToken) async {
      if (newToken.isEmpty) {
        return;
      }
      await _registerToken(newToken);
    });

    _onMessageSub = FirebaseMessaging.onMessage.listen((RemoteMessage msg) async {
      await onOpenPush();
      final title = msg.notification?.title ?? 'Family tasks';
      final body = msg.notification?.body ?? 'New changes are available';
      await _showForegroundNotification(title: title, body: body);
      onForegroundText('$title: $body');
    });

    _onOpenSub = FirebaseMessaging.onMessageOpenedApp.listen((_) async {
      await onOpenPush();
    });

    final initial = await messaging.getInitialMessage();
    if (initial != null) {
      await onOpenPush();
    }
  }

  void dispose() {
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = null;
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    _onMessageSub?.cancel();
    _onMessageSub = null;
    _onOpenSub?.cancel();
    _onOpenSub = null;
  }

  Future<void> _registerTokenWithRetry(FirebaseMessaging messaging) async {
    for (var attempt = 0; attempt < 6; attempt++) {
      final registered = await _tryFetchAndRegisterToken(messaging);
      if (registered) {
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  void _startTokenRefreshLoop(FirebaseMessaging messaging) {
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      await _tryFetchAndRegisterToken(messaging);
    });
  }

  Future<bool> _tryFetchAndRegisterToken(FirebaseMessaging messaging) async {
    try {
      var token = await messaging.getToken();
      if (token == null || token.isEmpty) {
        // Some devices need one reset cycle before token becomes available.
        await messaging.deleteToken();
        token = await messaging.getToken();
      }
      if (token == null || token.isEmpty) {
        return false;
      }
      if (token == _lastRegisteredToken) {
        return true;
      }
      await _registerToken(token);
      _lastRegisteredToken = token;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _registerToken(String token) async {
    await api.registerDeviceToken(
      actorProfile: actorProfile,
      token: token,
      platform: Platform.isAndroid
          ? 'android'
          : (Platform.isIOS ? 'ios' : 'other'),
      appVersion: '0.1.2',
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

  Future<void> _showForegroundNotification({
    required String title,
    required String body,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _notificationChannelId,
        _notificationChannelName,
        channelDescription: _notificationChannelDescription,
        importance: Importance.max,
        priority: Priority.high,
        visibility: NotificationVisibility.public,
        icon: '@mipmap/ic_launcher',
      ),
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      details,
    );
  }
}

Future<void> _ensureNotificationChannel() async {
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initializationSettings = InitializationSettings(
    android: androidSettings,
  );
  await _localNotifications.initialize(initializationSettings);

  const channel = AndroidNotificationChannel(
    _notificationChannelId,
    _notificationChannelName,
    description: _notificationChannelDescription,
    importance: Importance.max,
    playSound: true,
  );

  await _localNotifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);
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
