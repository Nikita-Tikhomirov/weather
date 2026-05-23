part of 'home_page.dart';

// ───────────────────────────────────────────────────────────────
// FCM / push-notification handling extracted from _HomePageState.
// ───────────────────────────────────────────────────────────────

extension _PushHandlerExtension on _HomePageState {
  /// Wait for the messenger tab to fully render after switching to it.
  /// Replaces a single [WidgetsBinding.instance.endOfFrame] which is
  /// insufficient on slower devices where the widget tree needs more
  /// time to build.
  Future<void> _waitForMessengerTab() async {
    // Let one frame pass so the tab switch is reflected in the widget tree.
    await WidgetsBinding.instance.endOfFrame;
    // Extra buffer for complex builds (chat list, contacts, etc.).
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  /// Process a push payload that arrived before init completed,
  /// or was saved to a temp file by the background handler.
  Future<void> _processPendingPush(TaskStore store) async {
    var pending = _pendingPushData;

    // Also check temp file for payload saved by background handler.
    // This is a safety net in case FcmService.initialize() didn't
    // process it.
    if (pending == null) {
      try {
        final file = File(
            '${Directory.systemTemp.path}/family_todo_pending_push.json');
        if (await file.exists()) {
          final raw = await file.readAsString();
          if (raw.isNotEmpty) {
            try {
              final decoded =
                  Map<String, dynamic>.from(jsonDecode(raw) as Map);
              pending = decoded;
              await file.delete();
              debugPrint(
                  '[FCM push] _init found pending in temp file');
            } catch (_) {
      // silently ignored — non-critical operation
    }
          }
        }
      } catch (_) {
      // silently ignored — non-critical operation
    }
    }

    if (pending == null) return;

    final eventId = (pending['event_id'] ?? '').toString();
    if (eventId.isNotEmpty && _lastProcessedPushEventId == eventId) {
      debugPrint('[FCM push] _init skipping duplicate event $eventId');
      _pendingPushData = null;
      return;
    }
    _lastProcessedPushEventId = eventId;
    debugPrint(
        '[FCM push] _init processing pending: entity=${pending['entity']} conv=${pending['conversation_key']}');
    _pendingPushData = null;
    await _safeSyncDelta(store, showErrors: false);
    final pushType = (pending['type'] ?? pending['entity'] ?? '').toString();
    final conversationKey = (pending['conversation_key'] ?? '').trim();
    if (pushType == 'task_reminder' ||
        pushType == 'todo_update' ||
        (pending['entity'] ?? '') == 'task' ||
        (pending['entity'] ?? '') == 'family_task') {
      store.setPage(1);
    } else if ((pending['entity'] ?? '') == 'chat_message' &&
        conversationKey.isNotEmpty &&
        !isProjectConversation(conversationKey)) {
      _pushAlreadyRouted = true;
      store.setPage(4);
      await _waitForMessengerTab();
      if (mounted) {
        await _openConversation(store, conversationKey);
      }
    } else if (pushType == 'call_incoming') {
      final sessionId = (pending['session_id'] ?? '').toString();
      final callType = (pending['call_type'] ?? 'audio').toString();
      final callerProfile = (pending['caller_profile'] ?? '').toString();
      if (sessionId.isNotEmpty) {
        _callService?.notifyIncomingCall(CallSession(
          sessionId: sessionId,
          callerProfile: callerProfile,
          calleeProfile: store.owner.value,
          conversationKey: conversationKey,
          callType: callType,
          status: 'ringing',
          createdAt: DateTime.now().toIso8601String(),
        ));
      }
    } else {
      await _refreshActiveConversation(store, useNetwork: true, quiet: true);
    }
  }

  void _bindFcm({required ApiClient api, required String owner}) {
    _fcm?.dispose();
    if (mounted) {
      _fcmDiagnostics.value = 'FCM: binding actor=$owner';
    }
    _fcm = FcmService(
      api: api,
      actorProfile: owner,
      onForegroundText: (_) {
        // No snackbar — only system notification is shown
      },
      onDiagnosticsChanged: (text) {
        debugPrint('FCM diagnostics: $text');
        if (!mounted) {
          return;
        }
        _fcmDiagnostics.value = text;
      },
      shouldSuppressChatNotification: (conversationKey) {
        // Suppress foreground notification only when the user is
        // already in the messenger tab viewing that exact conversation.
        final store = _store;
        if (store == null) return false;
        return store.pageIndex.value == 4 &&
            _activeConversationKey == conversationKey;
      },
      onOpenPush: (data) async {
        final store = _store;
        debugPrint(
            '[FCM push] onOpenPush: entity=${data['entity']} conv=${data['conversation_key']} store=${store != null}');
        if (store == null) {
          // Store for later processing once initialization completes
          debugPrint('[FCM push] store is null, saving to _pendingPushData');
          _pendingPushData = Map<String, dynamic>.from(data);
          return;
        }
        final eventId = (data['event_id'] ?? '').toString();
        if (eventId.isNotEmpty && _lastProcessedPushEventId == eventId) {
          debugPrint('[FCM push] skipping duplicate event $eventId');
          return;
        }
        _lastProcessedPushEventId = eventId;
        await _safeSyncDelta(store, showErrors: false);

        final pushType = (data['type'] ?? data['entity'] ?? '').toString();
        final conversationKey = (data['conversation_key'] ?? '').trim();

        // Task-related notifications -> go to tasks tab
        if (pushType == 'task_reminder' ||
            pushType == 'todo_update' ||
            (data['entity'] ?? '') == 'task' ||
            (data['entity'] ?? '') == 'family_task') {
          debugPrint('[FCM push] routing to tasks tab');
          store.setPage(1); // Switch to Tasks tab
          return;
        }

        // Chat messages -> go to messenger
        if ((data['entity'] ?? '') == 'chat_message' &&
            conversationKey.isNotEmpty &&
            !isProjectConversation(conversationKey)) {
          debugPrint(
              '[FCM push] routing to messenger -> _openConversation($conversationKey)');
          _pushAlreadyRouted = true;
          store.setPage(4); // Switch to Messenger tab
          await _waitForMessengerTab();
          if (mounted) {
            await _openConversation(store, conversationKey);
          }
          return;
        }

        // Incoming call -> show call screen
        if (pushType == 'call_incoming') {
          final sessionId = (data['session_id'] ?? '').toString();
          final callType = (data['call_type'] ?? 'audio').toString();
          final callerProfile = (data['caller_profile'] ?? '').toString();
          if (sessionId.isNotEmpty && mounted) {
            final session = CallSession(
              sessionId: sessionId,
              callerProfile: callerProfile,
              calleeProfile: (store.owner.value),
              conversationKey: conversationKey,
              callType: callType,
              status: 'ringing',
              createdAt: DateTime.now().toIso8601String(),
            );
            _callService?.notifyIncomingCall(session);
          }
          return;
        }

        // Call ended remotely
        if (pushType == 'call_accepted' || pushType == 'call_rejected') {
          return;
        }

        // Default: just refresh
        await _refreshActiveConversation(store, useNetwork: true, quiet: true);
      },
    );
    _fcm!.initialize().catchError((error, stackTrace) {
      debugPrint('FCM initialization failed: $error');
      debugPrint('$stackTrace');
    });
  }

  void _showFcmDiagnosticsDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return ValueListenableBuilder<String>(
          valueListenable: _fcmDiagnostics,
          builder: (context, text, _) {
            return AlertDialog(
              title: const Text('FCM диагностика'),
              content: SingleChildScrollView(
                child: SelectableText(text),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    _fcmDiagnostics.value =
                        'FCM: обновляю диагностику...';
                    await _fcm?.refreshDiagnostics();
                  },
                  child: const Text('Обновить'),
                ),
                TextButton(
                  onPressed: () async {
                    _fcmDiagnostics.value =
                        'FCM: сбрасываю токен...';
                    await _fcm
                        ?.refreshDiagnostics(forceResetToken: true);
                  },
                  child: const Text('Сбросить токен'),
                ),
                TextButton(
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(),
                  child: const Text('Закрыть'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
