import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/call_models.dart';
import 'api_client.dart';
import 'fcm_service.dart';

/// The action to take for a pending push payload.
enum PendingPushAction {
  /// No pending push — nothing to do.
  none,

  /// Push data is present but was not opened by the user;
  /// the notification was already shown by the system.
  /// Only sync silently — no auto-navigation.
  routePassivePush,

  /// Push was explicitly opened by the user (tap on notification).
  /// Navigate to the relevant tab/conversation.
  routeOpenedPush,
}

enum IncomingCallPushAction { show, accept }

typedef IncomingCallHandler = void Function(
  CallSession session,
  IncomingCallPushAction action,
);

/// Standalone push-notification handler extracted from _HomePageState.
///
/// Manages FCM binding, pending push processing, dedup, and navigation
/// routing for push payloads.
class PushNotificationHandler {
  PushNotificationHandler({
    required this.api,
    required this.owner,
    this.onDiagnosticsChanged,
    this.onShowSnackBar,
    this.onShowDiagnosticsDialog,
    this.onNavigateToTasks,
    this.onNavigateToMessenger,
    this.onNavigateToLeads,
    this.onOpenConversation,
    this.onIncomingCall,
    this.onSyncDelta,
    this.onRefreshActiveConversation,
    this.getActiveConversationKey,
    this.getIsProjectConversation,
    this.getPageIndex,
    this.shouldSuppressChatNotification,
  });

  final ApiClient api;
  final String owner;

  final void Function(String text)? onDiagnosticsChanged;
  final void Function(String message)? onShowSnackBar;
  final void Function()? onShowDiagnosticsDialog;
  final void Function()? onNavigateToTasks;
  final void Function()? onNavigateToMessenger;
  final Future<void> Function()? onNavigateToLeads;
  final Future<void> Function(String conversationKey)? onOpenConversation;
  final IncomingCallHandler? onIncomingCall;
  final Future<void> Function({required bool showErrors})? onSyncDelta;
  final Future<void> Function({required bool useNetwork, required bool quiet})?
      onRefreshActiveConversation;
  final String Function()? getActiveConversationKey;
  final bool Function(String conversationKey)? getIsProjectConversation;
  final int Function()? getPageIndex;
  final bool Function(String conversationKey)? shouldSuppressChatNotification;

  FcmService? _fcm;
  final ValueNotifier<String> diagnostics =
      ValueNotifier('FCM: not initialized');

  // Pending push that arrived before init completed.
  Map<String, dynamic>? pendingPushData;
  bool pendingPushWasOpened = false;
  String _lastProcessedPushEventId = '';

  void bindFcm() {
    _fcm?.dispose();
    diagnostics.value = 'FCM: binding actor=$owner';
    _fcm = FcmService(
      api: api,
      actorProfile: owner,
      onForegroundText: (_) {
        // No snackbar — only system notification is shown
      },
      onDiagnosticsChanged: (text) {
        debugPrint('FCM diagnostics: $text');
        diagnostics.value = text;
        onDiagnosticsChanged?.call(text);
      },
      shouldSuppressChatNotification: (conversationKey) {
        final suppress = shouldSuppressChatNotification;
        if (suppress == null) return false;
        return suppress(conversationKey);
      },
      onOpenPush: (data) async {
        debugPrint(
          '[FCM push] onOpenPush: entity=${data['entity']} conv=${data['conversation_key']}',
        );
        pendingPushData = Map<String, dynamic>.from(data);
        pendingPushWasOpened = true;
        await processPendingPush();
      },
    );
    _fcm!.initialize().catchError((error, stackTrace) {
      debugPrint('FCM initialization failed: $error');
      debugPrint('$stackTrace');
    });
  }

  /// Determine the action for a pending push payload.
  PendingPushAction pendingPushAction({
    required Map<String, dynamic> data,
    required bool wasOpenedByUser,
  }) {
    if (data.isEmpty) return PendingPushAction.none;
    return wasOpenedByUser
        ? PendingPushAction.routeOpenedPush
        : PendingPushAction.routePassivePush;
  }

  /// Process a push payload that arrived before init completed,
  /// or was saved to a temp file by the background handler.
  Future<void> processPendingPush() async {
    var pending = pendingPushData;
    var pendingWasOpened = pendingPushWasOpened;

    // Check temp file for payload saved by background handler.
    if (pending == null) {
      try {
        final file =
            File('${Directory.systemTemp.path}/family_todo_pending_push.json');
        // ignore: avoid_slow_async_io
        if (await file.exists()) {
          final raw = await file.readAsString();
          if (raw.isNotEmpty) {
            try {
              final decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
              pending = decoded;
              pendingWasOpened = false;
              await file.delete();
              debugPrint('[FCM push] found pending in temp file');
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
      debugPrint('[FCM push] skipping duplicate event $eventId');
      pendingPushData = null;
      pendingPushWasOpened = false;
      return;
    }
    debugPrint(
      '[FCM push] processing pending: entity=${pending['entity']} conv=${pending['conversation_key']}',
    );
    pendingPushData = null;
    pendingPushWasOpened = false;

    if (_isIncomingCallPush(pending) ||
        pendingPushAction(
              data: pending,
              wasOpenedByUser: pendingWasOpened,
            ) ==
            PendingPushAction.routeOpenedPush) {
      await handleOpenedPush(pending);
    } else {
      _lastProcessedPushEventId = eventId;
      await onSyncDelta?.call(showErrors: false);
    }
    // Clean up temp file
    try {
      final file =
          File('${Directory.systemTemp.path}/family_todo_pending_push.json');
      // ignore: avoid_slow_async_io
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // non-critical
    }
  }

  Future<void> handleOpenedPush(Map<String, dynamic> data) async {
    final eventId = (data['event_id'] ?? '').toString();
    if (eventId.isNotEmpty && _lastProcessedPushEventId == eventId) {
      debugPrint('[FCM push] skipping duplicate event $eventId');
      return;
    }
    _lastProcessedPushEventId = eventId;

    final pushType = (data['type'] ?? data['entity'] ?? '').toString();
    final conversationKey = (data['conversation_key'] ?? '').toString().trim();

    // Incoming calls must surface immediately; sync can catch up in background.
    if (pushType == 'call_incoming') {
      unawaited(onSyncDelta?.call(showErrors: false) ?? Future<void>.value());
      final sessionId = (data['session_id'] ?? '').toString();
      final callType = (data['call_type'] ?? 'audio').toString();
      final callerProfile = (data['caller_profile'] ?? '').toString();
      if (sessionId.isNotEmpty) {
        final session = CallSession(
          sessionId: sessionId,
          callerProfile: callerProfile,
          calleeProfile: owner,
          conversationKey: conversationKey,
          callType: callType,
          status: 'ringing',
          createdAt: DateTime.now().toIso8601String(),
        );
        onIncomingCall?.call(session, _incomingCallAction(data));
      }
      return;
    }

    await onSyncDelta?.call(showErrors: false);

    if (pushType == 'kwork_lead') {
      await onNavigateToLeads?.call();
      return;
    }

    // Task-related notifications → go to tasks tab
    if (pushType == 'task_reminder' ||
        pushType == 'todo_update' ||
        (data['entity'] ?? '') == 'task' ||
        (data['entity'] ?? '') == 'family_task') {
      debugPrint('[FCM push] routing to tasks tab');
      onNavigateToTasks?.call();
      return;
    }

    // Chat messages → go to messenger
    if ((data['entity'] ?? '') == 'chat_message' &&
        conversationKey.isNotEmpty &&
        !(getIsProjectConversation?.call(conversationKey) ?? false)) {
      debugPrint(
        '[FCM push] routing to messenger -> _openConversation($conversationKey)',
      );
      onNavigateToMessenger?.call();
      await onOpenConversation?.call(conversationKey);
      return;
    }

    // Call ended remotely — nothing to do
    if (pushType == 'call_accepted' || pushType == 'call_rejected') {
      return;
    }

    // Default: just refresh
    await onRefreshActiveConversation?.call(useNetwork: true, quiet: true);
  }

  void showDiagnosticsDialog() {
    onShowDiagnosticsDialog?.call();
  }

  Future<void> refreshDiagnostics({bool forceResetToken = false}) async {
    await _fcm?.refreshDiagnostics(forceResetToken: forceResetToken);
  }

  void dispose() {
    _fcm?.dispose();
    _fcm = null;
  }

  bool _isIncomingCallPush(Map<String, dynamic> data) {
    final pushType = (data['type'] ?? data['entity'] ?? '').toString().trim();
    return pushType == 'call_incoming' &&
        (data['session_id'] ?? '').toString().trim().isNotEmpty;
  }

  IncomingCallPushAction _incomingCallAction(Map<String, dynamic> data) {
    final action = (data['call_action'] ??
            data['native_call_action'] ??
            data['push_call_action'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();
    return action == 'accept'
        ? IncomingCallPushAction.accept
        : IncomingCallPushAction.show;
  }
}
