import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, File, Directory;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';

import '../app/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/home/home_helpers.dart'
    show isChatMessageData, isIncomingCallData;
import 'api_client.dart';

part 'fcm_messaging.dart';
part 'fcm_notifications.dart';
part 'fcm_diagnostics.dart';

// ── Constants ──────────────────────────────────────────────────

class FcmNotificationMessages {
  const FcmNotificationMessages._();

  static const channelName = 'Notifications';
  static const channelDescription =
      'Push notifications for tasks and reminders';
  static const openAction = 'Open';
  static const markReadAction = 'Mark as read';
  static const messageTitle = 'Message';
  static const newMessageBody = 'New message';
  static const tasksTitle = 'Tasks';
  static const taskUpdateBody = 'New updates are available';
}

const _notificationChannelId = 'family_updates';
const _notificationChannelName = FcmNotificationMessages.channelName;
const _notificationChannelDescription =
    FcmNotificationMessages.channelDescription;
const _appVersion =
    String.fromEnvironment('APP_VERSION', defaultValue: '0.1.6');
const _markReadActionId = 'chat_mark_read';
const _openChatActionId = 'chat_open';
const _defaultApiBaseUrl = AppConfig.apiBaseUrl;
const _defaultApiKey = AppConfig.apiKey;

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();
final StreamController<Map<String, dynamic>> _notificationOpenEvents =
    StreamController<Map<String, dynamic>>.broadcast();
const MethodChannel _firebaseInstallationsChannel =
    MethodChannel('family_todo_mobile/firebase_installations');
const MethodChannel _nativePushChannel =
    MethodChannel('family_todo_mobile/push_intents');

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
    _nativePushChannel.setMethodCallHandler((call) async {
      if (call.method != 'onPushOpened') return;
      final args = call.arguments;
      if (args is Map) {
        await onOpenPush(Map<String, dynamic>.from(args));
      }
    });
    try {
      await _nativePushChannel.invokeMethod<bool>('ready');
    } catch (_) {
      _updateDiagnostics('push:native_channel_error');
    }

    await _ensureNotificationChannel();

    final permission = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
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
      messaging,
      capturedMsg,
      capturedLaunch,
      prefsPayload,
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
    _notificationOpenEvents.close();
  }

  /// Public diagnostics entry point.
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
      _lastTokenError =
          _mergeErrors(_lastTokenError, 'manual_get_token:$error');
    }

    _updateDiagnostics(
      forceResetToken ? 'manual:reset_done' : 'manual:refresh',
      token: token,
    );

    try {
      final server = await api.pushDeviceStatus(actorProfile: actorProfile);
      await _recoverIfServerRejectedToken(token, serverStatus: server);
      final firstToken = server.tokens.isNotEmpty ? server.tokens.first : null;
      _diagnosticsText = [
        _diagnosticsText,
        '',
        'server_effective=${server.effectiveTokenStatus.isEmpty ? 'unknown' : server.effectiveTokenStatus}',
        'server_active_tokens=${server.activeTokenCount}',
        if (server.status.isNotEmpty)
          'server_status=${server.status['token_status'] ?? ''} updated=${server.status['updated_at'] ?? ''}',
        if (firstToken != null)
          'server_last_token=${firstToken['token_status'] ?? ''} active=${firstToken['is_active'] ?? false} seen=${firstToken['last_seen_at'] ?? ''}',
        if (firstToken != null &&
            (firstToken['last_error'] ?? '').toString().isNotEmpty)
          'server_error=${firstToken['last_error']}',
      ].join('\n');
      onDiagnosticsChanged(_diagnosticsText);
    } catch (error) {
      _diagnosticsText =
          [_diagnosticsText, '', 'server_status_error=$error'].join('\n');
      onDiagnosticsChanged(_diagnosticsText);
    }

    return _diagnosticsText;
  }
}
