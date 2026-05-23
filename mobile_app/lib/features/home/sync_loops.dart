part of 'home_page.dart';

// ───────────────────────────────────────────────────────────────
// Sync-loop management extracted from _HomePageState.
// ───────────────────────────────────────────────────────────────

extension _SyncLoopsExtension on _HomePageState {
  void _startSyncLoops(TaskStore store) {
    _cancelSyncLoops();
    _deltaSyncTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
      await _safeSyncDelta(store, showErrors: false);
    });
    _fullSyncTimer = Timer.periodic(const Duration(minutes: 10), (_) async {
      await _safeSyncFull(store, showErrors: false);
    });
    _retryTimer = Timer.periodic(const Duration(minutes: 2), (_) async {
      _retryPendingMessages(store);
    });
    _incomingCallPollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _pollIncomingCall(store);
    });
    // Also try immediately on startup
    _retryPendingMessages(store);
    _pollIncomingCall(store);
  }

  void _cancelSyncLoops() {
    _deltaSyncTimer?.cancel();
    _deltaSyncTimer = null;
    _fullSyncTimer?.cancel();
    _fullSyncTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _incomingCallPollTimer?.cancel();
    _incomingCallPollTimer = null;
  }

  void _replaceCallService({
    required ApiClient api,
    required String actorProfile,
  }) {
    _callService?.dispose();
    _callService = CallService(api: api, actorProfile: actorProfile)
      ..onIncomingCall = _handleIncomingCall
      ..onCallEnded = () {
        _notifyCallEnded();
      };
  }

  Future<void> _pollIncomingCall(TaskStore store) async {
    final service = _callService;
    if (!mounted ||
        service == null ||
        (service.state != CallState.idle && service.state != CallState.ended)) {
      return;
    }

    try {
      final session = await store.repository.api.callCheckIncoming(
        actorProfile: store.owner.value,
      );
      if (session != null && mounted) {
        service.notifyIncomingCall(session);
      }
    } catch (_) {
      // FCM is primary; polling is a quiet fallback for missed call pushes.
    }
  }

  Future<void> _safeSyncDelta(
    TaskStore store, {
    required bool showErrors,
  }) async {
    try {
      await store.syncDelta();
    } catch (error) {
      if (showErrors && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка синхронизации: $error')));
      }
    }
  }

  Future<void> _safeSyncFull(
    TaskStore store, {
    required bool showErrors,
  }) async {
    try {
      await store.syncFull();
    } catch (error) {
      if (showErrors && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка синхронизации: $error')));
      }
    }
  }


}
