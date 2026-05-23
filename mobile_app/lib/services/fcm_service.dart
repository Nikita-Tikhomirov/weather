import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, File, Directory;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

// ── Constants ──────────────────────────────────────────────────

const _notificationChannelId = 'family_updates';
const _notificationChannelName = 'Семейные уведомления';
const _notificationChannelDescription =
    'Пуш-уведомления о задачах и напоминаниях';
const _appVersion =
    String.fromEnvironment('APP_VERSION', defaultValue: '0.1.6');
const _markReadActionId = 'chat_mark_read';
const _defaultApiBaseUrl = String.fromEnvironment('API_BASE_URL',
    defaultValue: 'http://31.129.97.211');
const _defaultApiKey =
    String.fromEnvironment('API_KEY', defaultValue: 'dev-local-key');

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();
final StreamController<Map<String, dynamic>> _notificationOpenEvents =
    StreamController<Map<String, dynamic>>.broadcast();
const MethodChannel _firebaseInstallationsChannel =
    MethodChannel('family_todo_mobile/firebase_installations');

// ── Background entry points ────────────────────────────────────

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    final dir = Directory.systemTemp;
    final file = File('${dir.path}/family_todo_pending_push.json');
    await file.writeAsString(jsonEncode(message.data));
  } catch (_) {}

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
  if (_isChatMessageData(message.data)) {
    await _showChatNotificationFromData(
      message.data,
      title: message.notification?.title,
      body: message.notification?.body,
    );
  }
}

@pragma('vm:entry-point')
Future<void> notificationTapBackground(NotificationResponse response) async {
  await _handleNotificationResponse(response);
}

// ── FCM Service ────────────────────────────────────────────────

class FcmService {
  FcmService({
    required this.api,
    required this.actorProfile,
    required this.onForegroundText,
    required this.onDiagnosticsChanged,
    required this.onOpenPush,
    this.shouldSuppressChatNotification,
  });

  // ── Dependencies ───────────────────────────────────────────

  final ApiClient api;
  final String actorProfile;
  final void Function(String text) onForegroundText;
  final void Function(String text) onDiagnosticsChanged;
  final Future<void> Function(Map<String, dynamic> data) onOpenPush;

  /// Optional callback: return true if the foreground notification
  /// for a given conversation should be suppressed (e.g. because
  /// the user is already viewing that chat).
  final bool Function(String conversationKey)? shouldSuppressChatNotification;

  // ── Stream subscriptions ───────────────────────────────────

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onOpenSub;
  StreamSubscription<Map<String, dynamic>>? _localOpenSub;

  // ── Timers ─────────────────────────────────────────────────

  Timer? _tokenRefreshTimer;
  Timer? _diagnosticsTimer;

  // ── Token state ────────────────────────────────────────────

  String _lastRegisteredToken = '';
  String _playServicesState = 'unknown';
  String _lastTokenError = '';
  bool _isFisRecoveryInProgress = false;

  // ── Status reporting (dedup) ───────────────────────────────

  DateTime? _lastStatusReportedAt;
  String _lastStatusReportedKey = '';

  // ── Recovery timestamps ────────────────────────────────────

  DateTime? _lastFisRecoveryAt;
  DateTime? _lastServerTokenRecoveryAt;

  // ── Diagnostics ────────────────────────────────────────────

  String _diagnosticsText = 'FCM: starting';
  String _installationId = '';
  String _packageName = '';
  String _playServicesNativeStatus = '';
  String _lastStep = 'created';

  // ────────────────────────────────────────────────────────────
  // Initialization
  // ────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (!(Platform.isAndroid || Platform.isIOS)) return;

    _updateDiagnostics('initialize:start');
    await _refreshNativeDiagnostics();

    final prefsPayload = await _readPendingPushFile();
    final initialized = await _initializeFirebaseSafely();
    if (!initialized) return _handleFirebaseInitFailed(prefsPayload);

    final messaging = FirebaseMessaging.instance;
    await messaging.setAutoInitEnabled(true);

    // Capture notification launch details BEFORE _ensureNotificationChannel,
    // because _localNotifications.initialize() clears them.
    RemoteMessage? capturedMsg;
    NotificationAppLaunchDetails? capturedLaunch;
    try {
      capturedMsg = await messaging.getInitialMessage();
    } catch (_) {
      _updateDiagnostics('push:getInitialMessage_error');
    }
    try {
      capturedLaunch =
          await _localNotifications.getNotificationAppLaunchDetails();
    } catch (_) {
      _updateDiagnostics('push:getLaunchDetails_error');
    }

    // Set up local open listener before notification channel init
    _localOpenSub = _notificationOpenEvents.stream.listen((data) async {
      await onOpenPush(data);
    });

    await _ensureNotificationChannel();

    final permission = await messaging.requestPermission(
      alert: true, badge: true, sound: true,
    );
    _updateDiagnostics('permission:${permission.authorizationStatus.name}');

    if (permission.authorizationStatus == AuthorizationStatus.denied) {
      _reportStatus(tokenStatus: 'permission_denied');
      return;
    }

    // 1. Set up stream subscriptions BEFORE token registration
    //    so we never miss a token refresh or incoming message.
    await _setupStreamSubscriptions(messaging);

    // 2. Register token and start periodic loops.
    await _setupTokenAndLoops(messaging);

    // 3. Process any pending push payloads (launch / temp file).
    await _processLaunchPayloads(
      messaging, capturedMsg, capturedLaunch, prefsPayload,
    );
  }

  void dispose() {
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = null;
    _diagnosticsTimer?.cancel();
    _diagnosticsTimer = null;
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    _onMessageSub?.cancel();
    _onMessageSub = null;
    _onOpenSub?.cancel();
    _onOpenSub = null;
    _localOpenSub?.cancel();
    _localOpenSub = null;
  }

  // ────────────────────────────────────────────────────────────
  // Init sub-steps
  // ────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _readPendingPushFile() async {
    try {
      final file =
          File('${Directory.systemTemp.path}/family_todo_pending_push.json');
      if (await file.exists()) {
        final raw = await file.readAsString();
        if (raw.isNotEmpty) {
          _updateDiagnostics('push:file_payload_found');
          return _decodeNotificationPayload(raw);
        }
      }
    } catch (_) {
      _updateDiagnostics('push:file_payload_error');
    }
    return null;
  }

  void _handleFirebaseInitFailed(Map<String, dynamic>? prefsPayload) {
    _updateDiagnostics('initialize:firebase_init_failed');
    _reportStatus(tokenStatus: 'firebase_init_failed');
    if (prefsPayload != null) {
      _updateDiagnostics('push:delivering_despite_firebase_failure');
      onOpenPush(prefsPayload);
    }
  }

  Future<void> _setupTokenAndLoops(FirebaseMessaging messaging) async {
    final registered = await _registerTokenWithRetry(messaging);
    if (!registered) {
      await _reportStatus(tokenStatus: 'token_unavailable');
    }
    _startTokenRefreshLoop(messaging);
    _startDiagnosticsLoop();
  }

  Future<void> _setupStreamSubscriptions(FirebaseMessaging messaging) async {
    _tokenRefreshSub = messaging.onTokenRefresh.listen((newToken) async {
      if (newToken.isEmpty) return;
      final registered = await _registerToken(newToken);
      if (registered) {
        await _reportStatus(tokenStatus: 'active', token: newToken, lastError: '');
      }
    });

    _onMessageSub =
        FirebaseMessaging.onMessage.listen((RemoteMessage msg) async {
      try {
        final conversationKey =
            (msg.data['conversation_key'] ?? '').toString().trim();
        final isChatMessage = _isChatMessageData(msg.data);

        // Suppress foreground notification if user is already viewing
        // the relevant chat conversation.
        final suppressed = isChatMessage &&
            shouldSuppressChatNotification != null &&
            shouldSuppressChatNotification!(conversationKey);

        if (!suppressed) {
          // For chat messages in foreground, only show the notification.
          // Navigation to the conversation happens on explicit tap
          // via _handleNotificationResponse -> _notificationOpenEvents.
          if (!isChatMessage) {
            await onOpenPush(msg.data);
          }
        }

        final title = msg.notification?.title ??
            (msg.data['title'] ?? 'Семейные задачи').toString();
        final body = msg.notification?.body ??
            (msg.data['body'] ?? 'Появились новые изменения').toString();

        if (!suppressed) {
          await _showForegroundNotification(
              title: title, body: body, data: msg.data);
        }
        onForegroundText('$title: $body');
      } catch (error, stack) {
        debugPrint(
            '[FCM onMessage] unhandled error: $error\n$stack');
        // Still try to show a fallback notification
        try {
          await _showForegroundNotification(
            title: 'Семейные задачи',
            body: 'Новое уведомление',
            data: msg.data,
          );
        } catch (_) {}
      }
    });

    _onOpenSub = FirebaseMessaging.onMessageOpenedApp.listen((msg) async {
      await onOpenPush(msg.data);
    });
  }

  Future<void> _processLaunchPayloads(
    FirebaseMessaging messaging,
    RemoteMessage? capturedMsg,
    NotificationAppLaunchDetails? capturedLaunch,
    Map<String, dynamic>? prefsPayload,
  ) async {
    var handledExplicitLaunch = false;
    if (capturedMsg != null) {
      _updateDiagnostics('push:initial_message');
      await onOpenPush(capturedMsg.data);
      handledExplicitLaunch = true;
    }
    if (capturedLaunch?.didNotificationLaunchApp == true) {
      final response = capturedLaunch?.notificationResponse;
      if (response?.payload != null) {
        final data = _decodeNotificationPayload(response!.payload);
        if (data != null) {
          _updateDiagnostics('push:local_launch');
          await onOpenPush(data);
          handledExplicitLaunch = true;
        }
      }
    }
    if (prefsPayload != null && !handledExplicitLaunch) {
      _updateDiagnostics('push:prefs_payload');
      await onOpenPush(prefsPayload);
      try {
        final file = File('${Directory.systemTemp.path}/family_todo_pending_push.json');
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  // ────────────────────────────────────────────────────────────
  // Token management
  // ────────────────────────────────────────────────────────────

  Future<bool> _registerTokenWithRetry(FirebaseMessaging messaging) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      _updateDiagnostics('token:attempt_${attempt + 1}');
      final token = await _tryFetchToken(FirebaseMessaging.instance);
      if (token != null && token.isNotEmpty) {
        final registered = await _registerToken(token);
        if (!registered) {
          await Future<void>.delayed(const Duration(seconds: 1));
          continue;
        }
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
        if (_isFisAuthError(_lastTokenError)) await _recoverFromFisAuthError();
        await _reportStatus(tokenStatus: 'token_unavailable');
        return;
      }
      if (token == _lastRegisteredToken) {
        await _reportStatus(tokenStatus: 'active', token: token, lastError: '');
        _updateDiagnostics('token:active_cached', token: token);
        await _recoverIfServerRejectedToken(token);
        return;
      }
      final registered = await _registerToken(token);
      if (registered) {
        await _reportStatus(tokenStatus: 'active', token: token, lastError: '');
      }
    });
  }

  Future<String?> _tryFetchToken(FirebaseMessaging messaging) async {
    try {
      _updateDiagnostics('token:getToken');
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) _playServicesState = 'available';
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

  Future<bool> _registerToken(String token) async {
    try {
      final result = await api.registerDeviceToken(
        actorProfile: actorProfile,
        token: token,
        platform: Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'other'),
        appVersion: _appVersion,
        playServices: _playServicesState,
        tokenStatus: 'active',
        lastError: '',
      );
      _lastRegisteredToken = token;
      if (result.shouldResetToken) {
        _lastTokenError = 'server_rejected_stale_fcm_token:${result.previousTokenStatus}';
        _updateDiagnostics('token:server_reset_required', token: token);
        _lastRegisteredToken = '';
        // Don't destroy the token — just clear local state and
        // let the next getToken() call provide a fresh one.
        return false;
      }
      return true;
    } catch (error) {
      _lastTokenError = 'register_failed:$error';
      _updateDiagnostics('token:register_failed', token: token);
      await _reportStatus(tokenStatus: 'register_failed', token: token);
      return false;
    }
  }

  Future<void> _recoverIfServerRejectedToken(
    String? token, {PushDeviceStatus? serverStatus,}
  ) async {
    final currentToken = token?.trim() ?? '';
    if (currentToken.isEmpty) return;
    final status = serverStatus ?? await api.pushDeviceStatus(actorProfile: actorProfile);
    if (status.effectiveTokenStatus != 'unregistered' &&
        status.effectiveTokenStatus != 'missing') return;

    final now = DateTime.now();
    final last = _lastServerTokenRecoveryAt;
    if (last != null && now.difference(last) < const Duration(minutes: 2)) return;
    _lastServerTokenRecoveryAt = now;
    _lastRegisteredToken = '';
    _lastTokenError = 'server_effective_${status.effectiveTokenStatus}';
    _updateDiagnostics('token:auto_recovery_start', token: currentToken);

    // Just re-fetch token without destroying the Firebase installation.
    final newToken = await _tryFetchToken(FirebaseMessaging.instance);
    if (newToken != null && newToken.isNotEmpty) {
      final registered = await _registerToken(newToken);
      if (registered) {
        await _reportStatus(tokenStatus: 'active', token: newToken);
        _updateDiagnostics('token:auto_recovery_registered', token: newToken);
      }
    }
  }

  // ────────────────────────────────────────────────────────────
  // Status reporting (with dedup)
  // ────────────────────────────────────────────────────────────

  Future<void> _reportStatus({
    required String tokenStatus, String? token, String? lastError,
  }) async {
    final key = _statusKey(tokenStatus: tokenStatus, token: token, lastError: lastError);
    if (key == _lastStatusReportedKey) {
      final lastAt = _lastStatusReportedAt;
      if (lastAt != null) {
        final minGap = tokenStatus == 'active'
            ? const Duration(minutes: 5) : const Duration(minutes: 2);
        if (DateTime.now().difference(lastAt) < minGap) return;
      }
    }

    final errorText = (lastError ?? _lastTokenError).trim();
    try {
      await api.reportDeviceStatus(
        actorProfile: actorProfile,
        platform: Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'other'),
        appVersion: _appVersion,
        tokenStatus: tokenStatus,
        playServices: _playServicesState,
        token: token,
        lastError: _buildReportedError(errorText),
      );
      _lastStatusReportedKey = key;
      _lastStatusReportedAt = DateTime.now();
    } catch (_) {
      // Diagnostics must never break app behavior.
    }
  }

  String _statusKey({required String tokenStatus, String? token, String? lastError}) {
    final errorText = (lastError ?? _lastTokenError).trim();
    final maxError = errorText.length < 80 ? errorText.length : 80;
    final tokenPart = token == null || token.isEmpty
        ? ''
        : token.substring(0, token.length < 12 ? token.length : 12);
    return '$tokenStatus|$_playServicesState|$tokenPart|${errorText.substring(0, maxError)}';
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

  // ────────────────────────────────────────────────────────────
  // FIS auth error recovery
  // ────────────────────────────────────────────────────────────

  bool _isFisAuthError(String text) {
    final lower = text.toLowerCase();
    return lower.contains('fis_auth_error') ||
        lower.contains('firebaseinstallations') ||
        lower.contains('auth_error');
  }

  String _detectPlayServicesState(String errorText) {
    final lower = errorText.toLowerCase();
    if (lower.contains('fis_auth_error')) return 'fis_auth_error';
    if (lower.contains('service_not_available') ||
        lower.contains('google play services')) return 'unavailable_or_restricted';
    return 'unknown_or_network';
  }

  /// Soft recovery: reinitialize Firebase app without destroying
  /// the current FCM token.  Calling deleteToken/deleteInstallation
  /// immediately invalidates the token on Firebase servers, causing
  /// every queued server push to fail with NOT_FOUND.
  Future<void> _recoverFromFisAuthError({bool force = false}) async {
    if (_isFisRecoveryInProgress) return;
    final now = DateTime.now();
    final last = _lastFisRecoveryAt;
    if (!force && last != null && now.difference(last) < const Duration(minutes: 3)) return;

    _isFisRecoveryInProgress = true;
    _lastFisRecoveryAt = now;
    try {
      _updateDiagnostics('recovery:start');
      try { if (Firebase.apps.isNotEmpty) await Firebase.app().delete(); } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 500));
      try { await Firebase.initializeApp(options: _firebaseOptionsForCurrentPlatform()); } catch (_) {}
      await Future<void>.delayed(const Duration(seconds: 1));
      await _refreshNativeDiagnostics();
      _updateDiagnostics('recovery:done');
    } finally {
      _isFisRecoveryInProgress = false;
    }
  }

  /// Hard reset: destroy token + installation, then reinitialize.
  /// Only used for explicit manual reset (diagnostics button).
  Future<void> _hardResetToken() async {
    if (_isFisRecoveryInProgress) return;
    _isFisRecoveryInProgress = true;
    try {
      _updateDiagnostics('hard_reset:start');
      final messaging = FirebaseMessaging.instance;
      try { await messaging.setAutoInitEnabled(false); } catch (_) {}
      try { await messaging.deleteToken(); } catch (_) {}
      try { await _firebaseInstallationsChannel.invokeMethod<bool>('deleteInstallation'); } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 500));
      try { if (Firebase.apps.isNotEmpty) await Firebase.app().delete(); } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 500));
      try { await Firebase.initializeApp(options: _firebaseOptionsForCurrentPlatform()); } catch (_) {}
      try { await FirebaseMessaging.instance.setAutoInitEnabled(true); } catch (_) {}
      await Future<void>.delayed(const Duration(seconds: 1));
      await _refreshNativeDiagnostics();
      _updateDiagnostics('hard_reset:done');
    } finally {
      _isFisRecoveryInProgress = false;
    }
  }

  Future<bool> _initializeFirebaseSafely() async {
    try {
      if (Firebase.apps.isNotEmpty) return true;
      await Firebase.initializeApp();
      return true;
    } catch (_) {
      try {
        if (Firebase.apps.isNotEmpty) return true;
        await Firebase.initializeApp(options: _firebaseOptionsForCurrentPlatform());
        return true;
      } catch (_) {
        _lastTokenError = 'firebase_init_failed';
        return false;
      }
    }
  }

  // ────────────────────────────────────────────────────────────
  // Diagnostics
  // ────────────────────────────────────────────────────────────

  void _startDiagnosticsLoop() {
    _diagnosticsTimer?.cancel();
    _diagnosticsTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      await refreshDiagnostics();
    });
  }

  Future<void> _refreshNativeDiagnostics() async {
    if (!Platform.isAndroid) return;
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
        ? '' : token.substring(0, token.length < 16 ? token.length : 16);
    final installationPrefix = _installationId.isEmpty
        ? '' : _installationId.substring(0, _installationId.length < 16 ? _installationId.length : 16);
    final parts = <String>[
      'step=$step', 'actor=$actorProfile', 'app=$_appVersion',
      'platform=${Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'other')}',
      'play=$_playServicesState',
      if (_playServicesNativeStatus.isNotEmpty) 'playNative=$_playServicesNativeStatus',
      if (_packageName.isNotEmpty) 'pkg=$_packageName',
      'project=famillytodo-2758f', 'appId=1:223906415067:android:68a62bb31cc4471895a7fe',
      'sender=223906415067',
      if (installationPrefix.isNotEmpty) 'fis=$installationPrefix',
      if (tokenPrefix.isNotEmpty) 'token=$tokenPrefix',
      'diagAt=${DateTime.now().toIso8601String()}',
      if (_lastTokenError.isNotEmpty)
        'err=${_lastTokenError.substring(0, _lastTokenError.length < 220 ? _lastTokenError.length : 220)}',
    ];
    _diagnosticsText = parts.join('\n');
    onDiagnosticsChanged(_diagnosticsText);
  }

  String _mergeErrors(String left, String right) {
    final a = left.trim(), b = right.trim();
    if (a.isEmpty) return b;
    if (b.isEmpty || a.contains(b)) return a;
    return '$a | $b';
  }

  Future<String> refreshDiagnostics({bool forceResetToken = false}) async {
    if (forceResetToken) {
      _lastRegisteredToken = '';
      _lastTokenError = 'manual_token_reset';
      await _hardResetToken();
    }

    String? token;
    try {
      await _refreshNativeDiagnostics();
      token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) _playServicesState = 'available';
    } catch (error) {
      _lastTokenError = _mergeErrors(_lastTokenError, 'manual_get_token:$error');
    }

    _updateDiagnostics(forceResetToken ? 'manual:reset_done' : 'manual:refresh', token: token);

    try {
      final server = await api.pushDeviceStatus(actorProfile: actorProfile);
      await _recoverIfServerRejectedToken(token, serverStatus: server);
      final firstToken = server.tokens.isNotEmpty ? server.tokens.first : null;
      _diagnosticsText = [
        _diagnosticsText, '',
        'server_effective=${server.effectiveTokenStatus.isEmpty ? 'unknown' : server.effectiveTokenStatus}',
        'server_active_tokens=${server.activeTokenCount}',
        if (server.status.isNotEmpty)
          'server_status=${server.status['token_status'] ?? ''} updated=${server.status['updated_at'] ?? ''}',
        if (firstToken != null)
          'server_last_token=${firstToken['token_status'] ?? ''} active=${firstToken['is_active'] ?? false} seen=${firstToken['last_seen_at'] ?? ''}',
        if (firstToken != null && (firstToken['last_error'] ?? '').toString().isNotEmpty)
          'server_error=${firstToken['last_error']}',
      ].join('\n');
      onDiagnosticsChanged(_diagnosticsText);
    } catch (error) {
      _diagnosticsText = [_diagnosticsText, '', 'server_status_error=$error'].join('\n');
      onDiagnosticsChanged(_diagnosticsText);
    }

    return _diagnosticsText;
  }

  // ────────────────────────────────────────────────────────────
  // Notification display
  // ────────────────────────────────────────────────────────────

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
        actions: _isChatMessageData(data)
            ? const [AndroidNotificationAction(_markReadActionId, 'Пометить прочитанным',
                cancelNotification: true, showsUserInterface: false)]
            : null,
      ),
    );
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title, body, details, payload: payload,
    );
  }
}

// ── Top-level helpers ──────────────────────────────────────────

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

bool _isChatMessageData(Map<String, dynamic> data) {
  return (data['entity'] ?? data['type'] ?? '').toString() == 'chat_message' &&
      (data['conversation_key'] ?? '').toString().trim().isNotEmpty;
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
      actions: [AndroidNotificationAction(_markReadActionId, 'Пометить прочитанным',
          cancelNotification: true, showsUserInterface: false)],
    ),
  );
  await _localNotifications.show(
    DateTime.now().millisecondsSinceEpoch.remainder(100000),
    notificationTitle, notificationBody, details, payload: jsonEncode(data),
  );
}

Future<void> _handleNotificationResponse(NotificationResponse response) async {
  if (response.actionId == null || response.actionId!.isEmpty) {
    final data = _decodeNotificationPayload(response.payload);
    if (data != null) _notificationOpenEvents.add(data);
    return;
  }
  if (response.actionId != _markReadActionId) return;
  final data = _decodeNotificationPayload(response.payload);
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

Map<String, dynamic>? _decodeNotificationPayload(String? payload) {
  if (payload == null || payload.trim().isEmpty) return null;
  try {
    return Map<String, dynamic>.from(jsonDecode(payload) as Map);
  } catch (_) {
    return null;
  }
}

FirebaseOptions _firebaseOptionsForCurrentPlatform() {
  if (Platform.isAndroid) {
    const appId = String.fromEnvironment('FIREBASE_APP_ID',
        defaultValue: '1:223906415067:android:68a62bb31cc4471895a7fe');
    const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID',
        defaultValue: 'famillytodo-2758f');
    const senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID',
        defaultValue: '223906415067');
    const apiKey = String.fromEnvironment('FIREBASE_API_KEY',
        defaultValue: 'AIzaSyBtO5Nbcb91lk3WViNIHzwYX_5yazfG6K8');
    const storageBucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET',
        defaultValue: 'famillytodo-2758f.firebasestorage.app');
    return const FirebaseOptions(
      apiKey: apiKey, appId: appId, messagingSenderId: senderId,
      projectId: projectId, storageBucket: storageBucket,
    );
  }
  throw UnsupportedError('Firebase options are not configured for this platform');
}
