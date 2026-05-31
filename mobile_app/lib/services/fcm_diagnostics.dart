part of 'fcm_service.dart';

// ── Status reporting (with dedup) ──────────────────────────────

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

// ── Diagnostics ─────────────────────────────────────────────────

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
