import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../models/call_models.dart';
import '../../services/api_client.dart';
import '../../services/call_service.dart';
import '../../services/fcm_service.dart';
import '../../state/task_store.dart';
import 'home_helpers.dart';

/// Standalone push-notification handler extracted from _HomePageState.
///
/// Manages FCM push processing, de-duplication, and navigation routing.
/// All dependencies are injected via constructor — no access to widget state.
class HomePushHandler {
  HomePushHandler({
    required this.store,
    required this.api,
    required this.owner,
    required this.fcmDiagnostics,
    this.onNavigateToTasks,
    this.onNavigateToChat,
    this.onIncomingCall,
    this.onSyncDelta,
    this.onShowDialog,
  });

  final TaskStore store;
  final ApiClient api;
  final String owner;
  final ValueNotifier<String> fcmDiagnostics;
  final void Function()? onNavigateToTasks;
  final Future<void> Function(String conversationKey)? onNavigateToChat;
  final void Function(CallSession session)? onIncomingCall;
  final Future<void> Function({required bool showErrors})? onSyncDelta;
  final void Function(Widget dialog)? onShowDialog;

  FcmService? fcm;
  CallService? callService;

  Map<String, dynamic>? pendingPushData;
  bool pendingPushWasOpened = false;
  String lastProcessedPushEventId = '';
  bool pushAlreadyRouted = false;

  /// Process a push payload that arrived before init completed,
  /// or was saved to a temp file by the background handler.
  Future<void> processPendingPush() async {
    var pending = pendingPushData;
    var pendingWasOpened = pendingPushWasOpened;

    // Check temp file for payload saved by background handler
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
              debugPrint('[FCM push] init found pending in temp file');
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
    if (eventId.isNotEmpty && lastProcessedPushEventId == eventId) {
      debugPrint('[FCM push] init skipping duplicate event $eventId');
      pendingPushData = null;
      pendingPushWasOpened = false;
      return;
    }
    debugPrint(
        '[FCM push] init processing pending: entity=${pending['entity']} conv=${pending['conversation_key']}');
    pendingPushData = null;
    pendingPushWasOpened = false;

    if (pendingPushAction(
          data: pending,
          wasOpenedByUser: pendingWasOpened,
        ) ==
        PendingPushAction.routeOpenedPush) {
      await handleOpenedPush(pending);
    } else {
      lastProcessedPushEventId = eventId;
      await onSyncDelta?.call(showErrors: false);
    }

    // Clean up temp file if any
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

  /// Handle a push notification that the user explicitly opened.
  Future<void> handleOpenedPush(Map<String, dynamic> data) async {
    final eventId = (data['event_id'] ?? '').toString();
    if (eventId.isNotEmpty && lastProcessedPushEventId == eventId) {
      debugPrint('[FCM push] skipping duplicate event $eventId');
      return;
    }
    lastProcessedPushEventId = eventId;

    final pushType = (data['type'] ?? data['entity'] ?? '').toString();
    final conversationKey = (data['conversation_key'] ?? '').toString().trim();

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
        callService?.notifyIncomingCall(session);
        onIncomingCall?.call(session);
      }
      return;
    }

    await onSyncDelta?.call(showErrors: false);

    // Task-related notifications → go to tasks tab
    if (pushType == 'task_reminder' ||
        pushType == 'todo_update' ||
        (data['entity'] ?? '') == 'task' ||
        (data['entity'] ?? '') == 'family_task') {
      debugPrint('[FCM push] routing to tasks tab');
      store.setPage(1);
      return;
    }

    // Chat messages → go to messenger
    if ((data['entity'] ?? '') == 'chat_message' &&
        conversationKey.isNotEmpty &&
        !isProjectConversation(conversationKey)) {
      debugPrint(
          '[FCM push] routing to messenger → openConversation($conversationKey)');
      pushAlreadyRouted = true;
      store.setPage(4);
      await _waitForMessengerTab();
      await onNavigateToChat?.call(conversationKey);
      return;
    }

    // Call ended remotely — no action
    if (pushType == 'call_accepted' || pushType == 'call_rejected') {
      return;
    }
  }

  /// Create and bind the FCM service.
  void bindFcm() {
    fcm?.dispose();
    fcmDiagnostics.value = 'FCM: binding actor=$owner';
    fcm = FcmService(
      api: api,
      actorProfile: owner,
      onForegroundText: (_) {},
      onDiagnosticsChanged: (text) {
        debugPrint('FCM diagnostics: $text');
        fcmDiagnostics.value = text;
      },
      shouldSuppressChatNotification: (conversationKey) {
        // Canonicalize to match _activeConversationKey (dm:A:B ≡ dm:B:A)
        canonicalConversationKey(conversationKey);
        return store.pageIndex.value == 4;
      },
      onOpenPush: (data) async {
        debugPrint(
            '[FCM push] onOpenPush: entity=${data['entity']} conv=${data['conversation_key']}');
        pendingPushData = Map<String, dynamic>.from(data);
        pendingPushWasOpened = true;
        await handleOpenedPush(data);
      },
    );
    fcm!.initialize().catchError((error, stackTrace) {
      debugPrint('FCM initialization failed: $error');
      debugPrint('$stackTrace');
    });
  }

  void dispose() {
    fcm?.dispose();
  }

  Future<void> _waitForMessengerTab() async {
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
}
