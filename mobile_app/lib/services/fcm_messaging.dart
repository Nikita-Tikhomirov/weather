part of 'fcm_service.dart';

// ── Background entry point (must remain top-level) ──────────────

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(
    RemoteMessage message) async {
  try {
    final dir = Directory.systemTemp;
    final file =
        File('${dir.path}/family_todo_pending_push.json');
    await file.writeAsString(jsonEncode(message.data));
  } catch (_) {}

  try {
    await Firebase.initializeApp(
        options: _firebaseOptionsForCurrentPlatform());
  } catch (_) {
    return;
  }
  await _ensureNotificationChannel();
  if (isChatMessageData(message.data)) {
    await _showChatNotificationFromData(
      message.data,
      title: message.notification?.title,
      body: message.notification?.body,
    );
  }
}

// ── Messaging extension on FcmService ───────────────────────────

extension FcmServiceMessaging on FcmService {
  // ── Init sub-steps ────────────────────────────────────────────

  Future<Map<String, dynamic>?> _readPendingPushFile() async {
    try {
      final file = File(
          '${Directory.systemTemp.path}/family_todo_pending_push.json');
      // ignore: avoid_slow_async_io
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

  void _handleFirebaseInitFailed(
      Map<String, dynamic>? prefsPayload) {
    _updateDiagnostics('initialize:firebase_init_failed');
    _reportStatus(tokenStatus: 'firebase_init_failed');
    if (prefsPayload != null) {
      _updateDiagnostics(
          'push:delivering_despite_firebase_failure');
      onOpenPush(prefsPayload);
    }
  }

  Future<void> _setupTokenAndLoops(
      FirebaseMessaging messaging) async {
    final registered = await _registerTokenWithRetry(messaging);
    if (!registered) {
      await _reportStatus(tokenStatus: 'token_unavailable');
    }
    _startTokenRefreshLoop(messaging);
    _startDiagnosticsLoop();
  }

  Future<void> _setupStreamSubscriptions(
      FirebaseMessaging messaging) async {
    _tokenRefreshSub =
        messaging.onTokenRefresh.listen((newToken) async {
      if (newToken.isEmpty) return;
      final registered = await _registerToken(newToken);
      if (registered) {
        await _reportStatus(
            tokenStatus: 'active',
            token: newToken,
            lastError: '');
      }
    });

    _onMessageSub = FirebaseMessaging.onMessage
        .listen((RemoteMessage msg) async {
      final ck =
          (msg.data['conversation_key'] ?? '').toString().trim();

      if (isChatMessageData(msg.data) &&
          shouldSuppressChatNotification != null &&
          shouldSuppressChatNotification!(ck)) {
        return;
      }

      final title = msg.notification?.title ??
          (msg.data['title'] ?? 'Задачи').toString();
      final body = msg.notification?.body ??
          (msg.data['body'] ?? 'Появились новые изменения')
              .toString();
      await _showForegroundNotification(
          title: title, body: body, data: msg.data);
      onForegroundText('$title: $body');
    });

    _onOpenSub = FirebaseMessaging.onMessageOpenedApp
        .listen((msg) async {
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
        final payload = response!.payload!;
        final data =
            _decodeNotificationPayload(payload);
        if (data != null) {
          _updateDiagnostics('push:local_launch');
          await onOpenPush(data);
          handledExplicitLaunch = true;
        }
      }
    }
    if (prefsPayload != null && !handledExplicitLaunch) {
      _updateDiagnostics('push:prefs_payload_cleaned');
      try {
        final file = File(
            '${Directory.systemTemp.path}/family_todo_pending_push.json');
        // ignore: avoid_slow_async_io
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
  }

  // ── Token management ────────────────────────────────────────────

  Future<bool> _registerTokenWithRetry(
      FirebaseMessaging messaging) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      _updateDiagnostics('token:attempt_${attempt + 1}');
      final token =
          await _tryFetchToken(FirebaseMessaging.instance);
      if (token != null && token.isNotEmpty) {
        final registered = await _registerToken(token);
        if (!registered) {
          await Future<void>.delayed(
              const Duration(seconds: 1));
          continue;
        }
        await _reportStatus(
            tokenStatus: 'active',
            token: token,
            lastError: '');
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
    _tokenRefreshTimer = Timer.periodic(
        const Duration(seconds: 30), (_) async {
      final token =
          await _tryFetchToken(FirebaseMessaging.instance);
      if (token == null || token.isEmpty) {
        if (_isFisAuthError(_lastTokenError)) {
          await _recoverFromFisAuthError();
        }
        await _reportStatus(
            tokenStatus: 'token_unavailable');
        return;
      }
      if (token == _lastRegisteredToken) {
        await _reportStatus(
            tokenStatus: 'active',
            token: token,
            lastError: '');
        _updateDiagnostics('token:active_cached',
            token: token);
        await _recoverIfServerRejectedToken(token);
        return;
      }
      final registered = await _registerToken(token);
      if (registered) {
        await _reportStatus(
            tokenStatus: 'active',
            token: token,
            lastError: '');
      }
    });
  }

  Future<String?> _tryFetchToken(
      FirebaseMessaging messaging) async {
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
      _playServicesState =
          _detectPlayServicesState(errorText);
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
        platform: Platform.isAndroid
            ? 'android'
            : (Platform.isIOS ? 'ios' : 'other'),
        appVersion: _appVersion,
        playServices: _playServicesState,
        tokenStatus: 'active',
        lastError: '',
      );
      _lastRegisteredToken = token;
      if (result.shouldResetToken) {
        _lastTokenError =
            'server_rejected_stale_fcm_token:${result.previousTokenStatus}';
        _updateDiagnostics('token:server_reset_required',
            token: token);
        _lastRegisteredToken = '';
        return false;
      }
      return true;
    } catch (error) {
      _lastTokenError = 'register_failed:$error';
      _updateDiagnostics('token:register_failed',
          token: token);
      await _reportStatus(
          tokenStatus: 'register_failed', token: token);
      return false;
    }
  }

  Future<void> _recoverIfServerRejectedToken(
    String? token, {
    PushDeviceStatus? serverStatus,
  }) async {
    final currentToken = token?.trim() ?? '';
    if (currentToken.isEmpty) {
      return;
    }
    final status = serverStatus ??
        await api.pushDeviceStatus(
            actorProfile: actorProfile);
    if (status.effectiveTokenStatus != 'unregistered' &&
        status.effectiveTokenStatus != 'missing') {
      return;
    }

    final now = DateTime.now();
    final last = _lastServerTokenRecoveryAt;
    if (last != null &&
        now.difference(last) < const Duration(minutes: 2)) {
      return;
    }
    _lastServerTokenRecoveryAt = now;
    _lastRegisteredToken = '';
    _lastTokenError =
        'server_effective_${status.effectiveTokenStatus}';
    _updateDiagnostics('token:auto_recovery_start',
        token: currentToken);

    final newToken =
        await _tryFetchToken(FirebaseMessaging.instance);
    if (newToken != null && newToken.isNotEmpty) {
      final registered = await _registerToken(newToken);
      if (registered) {
        await _reportStatus(
            tokenStatus: 'active', token: newToken);
        _updateDiagnostics(
            'token:auto_recovery_registered',
            token: newToken);
      }
    }
  }

  // ── FIS auth error recovery ────────────────────────────────────

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

  Future<void> _recoverFromFisAuthError(
      {bool force = false}) async {
    if (_isFisRecoveryInProgress) {
      return;
    }
    final now = DateTime.now();
    final last = _lastFisRecoveryAt;
    if (!force &&
        last != null &&
        now.difference(last) <
            const Duration(minutes: 3)) return;

    _isFisRecoveryInProgress = true;
    _lastFisRecoveryAt = now;
    try {
      _updateDiagnostics('recovery:start');
      try {
        if (Firebase.apps.isNotEmpty) {
          await Firebase.app().delete();
        }
      } catch (_) {}
      await Future<void>.delayed(
          const Duration(milliseconds: 500));
      try {
        await Firebase.initializeApp(
            options:
                _firebaseOptionsForCurrentPlatform());
      } catch (_) {}
      await Future<void>.delayed(
          const Duration(seconds: 1));
      await _refreshNativeDiagnostics();
      _updateDiagnostics('recovery:done');
    } finally {
      _isFisRecoveryInProgress = false;
    }
  }

  Future<void> _hardResetToken() async {
    if (_isFisRecoveryInProgress) return;
    _isFisRecoveryInProgress = true;
    try {
      _updateDiagnostics('hard_reset:start');
      final messaging = FirebaseMessaging.instance;
      try {
        await messaging.setAutoInitEnabled(false);
      } catch (_) {}
      try {
        await messaging.deleteToken();
      } catch (_) {}
      try {
        await _firebaseInstallationsChannel
            .invokeMethod<bool>('deleteInstallation');
      } catch (_) {}
      await Future<void>.delayed(
          const Duration(milliseconds: 500));
      try {
        if (Firebase.apps.isNotEmpty) {
          await Firebase.app().delete();
        }
      } catch (_) {}
      await Future<void>.delayed(
          const Duration(milliseconds: 500));
      try {
        await Firebase.initializeApp(
            options:
                _firebaseOptionsForCurrentPlatform());
      } catch (_) {}
      try {
        await FirebaseMessaging.instance
            .setAutoInitEnabled(true);
      } catch (_) {}
      await Future<void>.delayed(
          const Duration(seconds: 1));
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
        await Firebase.initializeApp(
            options:
                _firebaseOptionsForCurrentPlatform());
        return true;
      } catch (_) {
        _lastTokenError = 'firebase_init_failed';
        return false;
      }
    }
  }
}

// ── Top-level helper (no instance fields) ───────────────────────

FirebaseOptions _firebaseOptionsForCurrentPlatform() {
  if (Platform.isAndroid) {
    const appId = String.fromEnvironment('FIREBASE_APP_ID');
    const projectId =
        String.fromEnvironment('FIREBASE_PROJECT_ID');
    const senderId = String.fromEnvironment(
        'FIREBASE_MESSAGING_SENDER_ID');
    const apiKey =
        String.fromEnvironment('FIREBASE_API_KEY');
    const storageBucket =
        String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
    return const FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: senderId,
      projectId: projectId,
      storageBucket: storageBucket,
    );
  }
  return const FirebaseOptions(
    apiKey: '',
    appId: '',
    messagingSenderId: '',
    projectId: '',
  );
}

// ── Helpers reused by notifications (top-level) ─────────────────

Map<String, dynamic>? _decodeNotificationPayload(String raw) {
  try {
    return jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}
