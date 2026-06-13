import 'dart:async';

import '../state/task_store.dart';
import 'call_service.dart';

String syncErrorMessage(Object error) => 'Sync error: $error';

/// Standalone sync-loop manager extracted from _HomePageState.
///
/// Owns periodic timers for delta sync (8s), full sync (10min),
/// pending-message retry (2min), and incoming call polling (5s).
class SyncLoopService {
  SyncLoopService({
    required this.store,
    this.callService,
    this.onRetryPendingMessages,
    this.onShowSnackBar,
  });

  final TaskStore store;
  CallService? callService;
  final void Function(TaskStore store)? onRetryPendingMessages;
  final void Function(String message)? onShowSnackBar;

  Timer? _deltaSyncTimer;
  Timer? _fullSyncTimer;
  Timer? _retryTimer;
  Timer? _incomingCallPollTimer;
  bool _disposed = false;

  void start() {
    cancel();
    _disposed = false;
    _deltaSyncTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
      await _safeSyncDelta(showErrors: false);
    });
    _fullSyncTimer = Timer.periodic(const Duration(minutes: 10), (_) async {
      await _safeSyncFull(showErrors: false);
    });
    _retryTimer = Timer.periodic(const Duration(minutes: 2), (_) async {
      onRetryPendingMessages?.call(store);
    });
    _incomingCallPollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _pollIncomingCall();
    });
    // Run immediately on startup
    onRetryPendingMessages?.call(store);
    _pollIncomingCall();
  }

  void cancel() {
    _deltaSyncTimer?.cancel();
    _deltaSyncTimer = null;
    _fullSyncTimer?.cancel();
    _fullSyncTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _incomingCallPollTimer?.cancel();
    _incomingCallPollTimer = null;
  }

  void _pollIncomingCall() {
    final service = callService;
    if (_disposed ||
        service == null ||
        (service.state != CallState.idle && service.state != CallState.ended)) {
      return;
    }

    // Fire-and-forget — FCM is primary; polling is a quiet fallback
    store.repository.api
        .callCheckIncoming(actorProfile: store.owner.value)
        .then((session) {
      if (session != null && !_disposed) {
        service.notifyIncomingCall(session);
      }
    }).catchError((_) {
      // FCM is primary; polling is a quiet fallback for missed call pushes.
    });
  }

  Future<void> _safeSyncDelta({required bool showErrors}) async {
    try {
      await store.syncDelta();
    } catch (error) {
      if (showErrors) {
        onShowSnackBar?.call(syncErrorMessage(error));
      }
    }
  }

  Future<void> _safeSyncFull({required bool showErrors}) async {
    try {
      await store.syncFull();
    } catch (error) {
      if (showErrors) {
        onShowSnackBar?.call(syncErrorMessage(error));
      }
    }
  }

  void dispose() {
    _disposed = true;
    cancel();
  }
}
