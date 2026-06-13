import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../services/sync_loop_service.dart';
import '../../state/task_store.dart';

/// Manages periodic sync timers previously embedded in _HomePageState.
///
/// Extracted from `sync_loops.dart` as a standalone class so the home page
/// delegates timer lifecycle instead of owning it directly.
class HomeSyncLoops {
  HomeSyncLoops({
    required this.store,
    this.onError,
    this.onCallServiceReplace,
  });

  final TaskStore store;
  final void Function(String message)? onError;
  final void Function()? onCallServiceReplace;

  Timer? _deltaSyncTimer;
  Timer? _fullSyncTimer;
  Timer? _retryTimer;
  Timer? _incomingCallPollTimer;

  void start() {
    cancel();
    _deltaSyncTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
      await _safeSyncDelta(showErrors: false);
    });
    _fullSyncTimer = Timer.periodic(const Duration(minutes: 10), (_) async {
      await _safeSyncFull(showErrors: false);
    });
    _retryTimer = Timer.periodic(const Duration(minutes: 2), (_) async {
      onCallServiceReplace?.call();
    });
    _incomingCallPollTimer =
        Timer.periodic(const Duration(seconds: 5), (_) async {
      await _pollIncomingCall();
    });
    // Also try immediately on startup
    onCallServiceReplace?.call();
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

  void dispose() => cancel();

  Future<void> _safeSyncDelta({required bool showErrors}) async {
    try {
      await store.syncDelta();
    } catch (e, st) {
      debugPrint('[sync] delta error: $e\n$st');
      if (showErrors) {
        onError?.call(syncErrorMessage(e));
      }
    }
  }

  Future<void> _safeSyncFull({required bool showErrors}) async {
    try {
      await store.syncFull();
    } catch (e, st) {
      debugPrint('[sync] full error: $e\n$st');
      if (showErrors) {
        onError?.call(syncErrorMessage(e));
      }
    }
  }

  Future<void> _pollIncomingCall() async {
    // Incoming call polling — delegated to caller via onCallServiceReplace.
    // The actual call polling logic remains in the caller (HomePage)
    // because it depends on CallService state.
  }
}
