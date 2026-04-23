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
const _appVersion = '0.1.3';

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
  String _playServicesState = 'unknown';
  String _lastTokenError = '';

  Future<void> initialize() async {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      return;
    }

    final initialized = await _initializeFirebaseSafely();
    if (!initialized) {
      await _reportStatus(tokenStatus: 'firebase_init_failed');
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
      await _reportStatus(tokenStatus: 'permission_denied');
      return;
    }

    final registered = await _registerTokenWithRetry(messaging);
    if (!registered) {
      await _reportStatus(tokenStatus: 'token_unavailable');
    }
    _startTokenRefreshLoop(messaging);

    _tokenRefreshSub = messaging.onTokenRefresh.listen((newToken) async {
      if (newToken.isEmpty) {
        return;
      }
      await _registerToken(newToken);
      await _reportStatus(tokenStatus: 'active', token: newToken, lastError: '');
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

  Future<bool> _registerTokenWithRetry(FirebaseMessaging messaging) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      final token = await _tryFetchToken(messaging);
      if (token != null && token.isNotEmpty) {
        await _registerToken(token);
        await _reportStatus(tokenStatus: 'active', token: token, lastError: '');
        return true;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return false;
  }

  void _startTokenRefreshLoop(FirebaseMessaging messaging) {
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      final token = await _tryFetchToken(messaging);
      if (token == null || token.isEmpty) {
        await _reportStatus(tokenStatus: 'token_unavailable');
        return;
      }
      if (token == _lastRegisteredToken) {
        await _reportStatus(tokenStatus: 'active', token: token, lastError: '');
        return;
      }
      await _registerToken(token);
      await _reportStatus(tokenStatus: 'active', token: token, lastError: '');
    });
  }

  Future<String?> _tryFetchToken(FirebaseMessaging messaging) async {
    try {
      var token = await messaging.getToken();
      if (token == null || token.isEmpty) {
        await messaging.deleteToken();
        token = await messaging.getToken();
      }
      if (token != null && token.isNotEmpty) {
        _playServicesState = 'available';
      }
      _lastTokenError = '';
      return token;
    } catch (error) {
      _playServicesState = 'unavailable_or_restricted';
      _lastTokenError = error.toString();
      return null;
    }
  }

  Future<void> _registerToken(String token) async {
    await api.registerDeviceToken(
      actorProfile: actorProfile,
      token: token,
      platform: Platform.isAndroid
          ? 'android'
          : (Platform.isIOS ? 'ios' : 'other'),
      appVersion: _appVersion,
      playServices: _playServicesState,
      tokenStatus: 'active',
      lastError: '',
    );
    _lastRegisteredToken = token;
  }

  Future<void> _reportStatus({
    required String tokenStatus,
    String? token,
    String? lastError,
  }) async {
    final errorText = (lastError ?? _lastTokenError).trim();
    try {
      await api.reportDeviceStatus(
        actorProfile: actorProfile,
        platform: Platform.isAndroid
            ? 'android'
            : (Platform.isIOS ? 'ios' : 'other'),
        appVersion: _appVersion,
        tokenStatus: tokenStatus,
        playServices: _playServicesState,
        token: token,
        lastError: errorText,
      );
    } catch (_) {
      // Diagnostics must never break app behavior.
    }
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
        _lastTokenError = 'firebase_init_failed';
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
