import '../models/device_snapshots.dart';
import '../models/pending_event.dart';
import '../models/sync_snapshots.dart';

/// Abstract API surface for backend sync operations.
///
/// Implementations send HTTP requests to the PHP/Laravel backend.
/// A mock implementation can be injected in tests to verify sync logic
/// without a running server.
abstract class SyncApi {
  /// Push a batch of pending events to the server.
  Future<void> push({
    required String actorProfile,
    required List<PendingEvent> events,
    String source = 'mobile',
  });

  /// Pull a snapshot (full or delta) from the server since [since].
  Future<PullSnapshot> pull({
    required String since,
    bool changesMode = false,
    String? cursor,
  });

  /// Register or refresh an FCM device token for [actorProfile].
  Future<DeviceTokenRegistration> registerDeviceToken({
    required String actorProfile,
    required String token,
    required String platform,
    required String appVersion,
    String? deviceId,
    String playServices = 'unknown',
    String tokenStatus = 'active',
    String lastError = '',
  });

  /// Report device push status to the server (diagnostics).
  Future<void> reportDeviceStatus({
    required String actorProfile,
    required String platform,
    required String appVersion,
    required String tokenStatus,
    required String playServices,
    String? token,
    String? deviceId,
    String? lastError,
  });

  /// Query server-side push-device status for [actorProfile].
  Future<PushDeviceStatus> pushDeviceStatus({
    required String actorProfile,
  });

  /// Deactivate a device token (logout / uninstall).
  Future<void> unregisterDeviceToken({
    required String actorProfile,
    required String token,
  });

  /// Set the actor profile used for server-side filtering on pull.
  void setActorProfileForPull(String actorProfile);
}
