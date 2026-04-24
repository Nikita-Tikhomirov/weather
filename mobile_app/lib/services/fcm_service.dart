import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';

import 'api_client.dart';

const _notificationChannelId = 'family_updates';
const _notificationChannelName = 'Семейные уведомления';
const _notificationChannelDescription =
    'Пуш-уведомления о задачах и напоминаниях';
const _appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.1.6');

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();
const MethodChannel _firebaseInstallationsChannel =
    MethodChannel('family_todo_mobile/firebase_installations');

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    try {
      await Firebase.initializeApp(
          options: _firebaseOptionsForCurrentPlatform());
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
    required this.onDiagnosticsChanged,
    required this.onOpenPush,
  });

  final ApiClient api;
  final String actorProfile;
  final void Function(String text) onForegroundText;
  final void Function(String text) onDiagnosticsChanged;
  final Future<void> Function() onOpenPush;

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onOpenSub;
  Timer? _tokenRefreshTimer;
  String _lastRegisteredToken = '';
  String _playServicesState = 'unknown';
  String _lastTokenError = '';
  DateTime? _lastStatusReportedAt;
  String _lastStatusReportedKey = '';
  DateTime? _lastFisRecoveryAt;
  bool _isFisRecoveryInProgress = false;
  String _diagnosticsText = 'FCM: starting';
  String _installationId = '';
  String _packageName = '';
  String _playServicesNativeStatus = '';
  String _lastStep = 'created';

  Future<void> initialize() async {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      return;
    }

    _updateDiagnostics('initialize:start');
    await _refreshNativeDiagnostics();

    final initialized = await _initializeFirebaseSafely();
    if (!initialized) {
      _updateDiagnostics('initialize:firebase_init_failed');
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

    _updateDiagnostics(
      'permission:${permission.authorizationStatus.name}',
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
      await _reportStatus(
          tokenStatus: 'active', token: newToken, lastError: '');
    });

    _onMessageSub =
        FirebaseMessaging.onMessage.listen((RemoteMessage msg) async {
      await onOpenPush();
      final title = msg.notification?.title ?? 'Семейные задачи';
      final body = msg.notification?.body ?? 'Появились новые изменения';
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
      _updateDiagnostics('token:attempt_${attempt + 1}');
      final token = await _tryFetchToken(FirebaseMessaging.instance);
      if (token != null && token.isNotEmpty) {
        await _registerToken(token);
        await _reportStatus(tokenStatus: 'active', token: token, lastError: '');
        _updateDiagnostics('token:active');
        return true;
      }
      if (_isFisAuthError(_lastTokenError)) {
        _updateDiagnostics('token:fis_recovery');
        await _recoverFromFisAuthError();
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    _updateDiagnostics('token:retry_exhausted');
    return false;
  }

  void _startTokenRefreshLoop(FirebaseMessaging messaging) {
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      final token = await _tryFetchToken(FirebaseMessaging.instance);
      if (token == null || token.isEmpty) {
        if (_isFisAuthError(_lastTokenError)) {
          await _recoverFromFisAuthError();
        }
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
      _updateDiagnostics('token:getToken');
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        _playServicesState = 'available';
      }
      _lastTokenError = '';
      await _refreshNativeDiagnostics();
      _updateDiagnostics('token:getToken_success', token: token);
      return token;
    } catch (error) {
      final errorText = error.toString();
      _playServicesState = _detectPlayServicesState(errorText);
      _lastTokenError = errorText;
      await _refreshNativeDiagnostics();
      _updateDiagnostics('token:getToken_error');
      return null;
    }
  }

  bool _isFisAuthError(String text) {
    final lower = text.toLowerCase();
    return lower.contains('fis_auth_error') ||
        lower.contains('firebaseinstallations') ||
        lower.contains('auth_error');
  }

  String _detectPlayServicesState(String errorText) {
    final lower = errorText.toLowerCase();
    if (lower.contains('fis_auth_error')) {
      return 'fis_auth_error';
    }
    if (lower.contains('service_not_available') ||
        lower.contains('google play services')) {
      return 'unavailable_or_restricted';
    }
    return 'unknown_or_network';
  }

  Future<void> _recoverFromFisAuthError() async {
    if (_isFisRecoveryInProgress) {
      return;
    }
    final now = DateTime.now();
    final last = _lastFisRecoveryAt;
    if (last != null && now.difference(last) < const Duration(minutes: 3)) {
      return;
    }

    _isFisRecoveryInProgress = true;
    _lastFisRecoveryAt = now;
    try {
      _updateDiagnostics('recovery:start');
      final messaging = FirebaseMessaging.instance;
      try {
        await messaging.setAutoInitEnabled(false);
      } catch (_) {}
      try {
        await messaging.deleteToken();
      } catch (_) {}
      try {
        await _firebaseInstallationsChannel.invokeMethod<bool>(
          'deleteInstallation',
        );
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 500));
      try {
        if (Firebase.apps.isNotEmpty) {
          await Firebase.app().delete();
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 500));
      try {
        await Firebase.initializeApp(
          options: _firebaseOptionsForCurrentPlatform(),
        );
      } catch (_) {}
      try {
        await FirebaseMessaging.instance.setAutoInitEnabled(true);
      } catch (_) {}
      await Future<void>.delayed(const Duration(seconds: 1));
      await _refreshNativeDiagnostics();
      _updateDiagnostics('recovery:done');
    } finally {
      _isFisRecoveryInProgress = false;
    }
  }

  Future<void> _refreshNativeDiagnostics() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      final raw = await _firebaseInstallationsChannel
          .invokeMethod<Object?>('getPlayServicesStatus');
      if (raw is Map) {
        final data = Map<Object?, Object?>.from(raw);
        _playServicesNativeStatus = (data['statusName'] ?? '').toString();
        _packageName = (data['packageName'] ?? '').toString();
      }
    } catch (error) {
      _playServicesNativeStatus = 'native_status_error';
      _lastTokenError = _mergeErrors(_lastTokenError, 'play_services_status:$error');
    }
    try {
      final installationId = await _firebaseInstallationsChannel
          .invokeMethod<String>('getInstallationId');
      _installationId = installationId?.trim() ?? '';
    } catch (error) {
      _lastTokenError = _mergeErrors(_lastTokenError, 'installation_id:$error');
    }
  }

  void _updateDiagnostics(String step, {String? token}) {
    _lastStep = step;
    final tokenPrefix = token == null || token.isEmpty
        ? ''
        : token.substring(0, token.length < 16 ? token.length : 16);
    final installationPrefix = _installationId.isEmpty
        ? ''
        : _installationId.substring(
            0,
            _installationId.length < 16 ? _installationId.length : 16,
          );
    final parts = <String>[
      'step=$step',
      'actor=$actorProfile',
      'app=$_appVersion',
      'platform=${Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'other')}',
      'play=$_playServicesState',
      if (_playServicesNativeStatus.isNotEmpty) 'playNative=$_playServicesNativeStatus',
      if (_packageName.isNotEmpty) 'pkg=$_packageName',
      'project=famillytodo-2758f',
      'appId=1:223906415067:android:68a62bb31cc4471895a7fe',
      'sender=223906415067',
      if (installationPrefix.isNotEmpty) 'fis=$installationPrefix',
      if (tokenPrefix.isNotEmpty) 'token=$tokenPrefix',
      if (_lastTokenError.isNotEmpty)
        'err=${_lastTokenError.substring(0, _lastTokenError.length < 220 ? _lastTokenError.length : 220)}',
    ];
    _diagnosticsText = parts.join('\n');
    onDiagnosticsChanged(_diagnosticsText);
  }

  String _mergeErrors(String left, String right) {
    final a = left.trim();
    final b = right.trim();
    if (a.isEmpty) {
      return b;
    }
    if (b.isEmpty || a.contains(b)) {
      return a;
    }
    return '$a | $b';
  }

  Future<void> _registerToken(String token) async {
    await api.registerDeviceToken(
      actorProfile: actorProfile,
      token: token,
      platform:
          Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'other'),
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
    if (!_shouldSendStatus(
      tokenStatus: tokenStatus,
      token: token,
      lastError: lastError,
    )) {
      return;
    }
    final errorText = (lastError ?? _lastTokenError).trim();
    try {
      await api.reportDeviceStatus(
        actorProfile: actorProfile,
        platform:
            Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'other'),
        appVersion: _appVersion,
        tokenStatus: tokenStatus,
        playServices: _playServicesState,
        token: token,
        lastError: _buildReportedError(errorText),
      );
      _rememberStatus(
        tokenStatus: tokenStatus,
        token: token,
        lastError: lastError,
      );
    } catch (_) {
      // Diagnostics must never break app behavior.
    }
  }

  bool _shouldSendStatus({
    required String tokenStatus,
    String? token,
    String? lastError,
  }) {
    final now = DateTime.now();
    final errorText = (lastError ?? _lastTokenError).trim();
    final tokenHash = token == null || token.isEmpty
        ? ''
        : token.substring(0, token.length < 12 ? token.length : 12);
    final key =
        '$tokenStatus|$_playServicesState|$tokenHash|${errorText.substring(0, errorText.length < 80 ? errorText.length : 80)}';

    if (_lastStatusReportedKey.isEmpty || _lastStatusReportedKey != key) {
      return true;
    }

    final lastAt = _lastStatusReportedAt;
    if (lastAt == null) {
      return true;
    }

    final minGap = tokenStatus == 'active'
        ? const Duration(minutes: 5)
        : const Duration(minutes: 2);
    return now.difference(lastAt) >= minGap;
  }

  void _rememberStatus({
    required String tokenStatus,
    String? token,
    String? lastError,
  }) {
    final errorText = (lastError ?? _lastTokenError).trim();
    final tokenHash = token == null || token.isEmpty
        ? ''
        : token.substring(0, token.length < 12 ? token.length : 12);
    _lastStatusReportedKey =
        '$tokenStatus|$_playServicesState|$tokenHash|${errorText.substring(0, errorText.length < 80 ? errorText.length : 80)}';
    _lastStatusReportedAt = DateTime.now();
  }

  String _buildReportedError(String errorText) {
    final parts = <String>[
      errorText,
      'step=$_lastStep',
      if (_playServicesNativeStatus.isNotEmpty) 'play_native=$_playServicesNativeStatus',
      if (_packageName.isNotEmpty) 'package=$_packageName',
      if (_installationId.isNotEmpty)
        'fis=${_installationId.substring(0, _installationId.length < 24 ? _installationId.length : 24)}',
    ].where((part) => part.trim().isNotEmpty).toList();
    final merged = parts.join(' | ');
    return merged.length <= 500 ? merged : merged.substring(0, 500);
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
          AndroidFlutterLocalNotificationsPlugin>()
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

  throw UnsupportedError(
      'Firebase options are not configured for this platform');
}
