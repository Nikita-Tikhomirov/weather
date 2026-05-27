/// Central configuration for the Family Todo mobile app.
///
/// All values come from `--dart-define` environment variables set at build
/// time, with safe defaults for local development.  No secrets, URLs, or
/// credentials may be hardcoded outside this file.
class AppConfig {
  AppConfig._();

  // ── Backend API ──────────────────────────────────────────────

  /// Base URL of the sync/chat/call HTTP API (without trailing slash).
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://31.129.97.211',
  );

  /// API key for backend authentication.
  static const String apiKey = String.fromEnvironment(
    'API_KEY',
    defaultValue: 'dev-local-key',
  );

  // ── TURN / STUN (WebRTC) ─────────────────────────────────────

  /// Comma-separated TURN server URLs.
  /// Format: turn:host:port?transport=udp,turn:host:port?transport=tcp
  static const String turnUrls = String.fromEnvironment(
    'TURN_URLS',
    defaultValue:
        'turn:31.129.97.211:3478?transport=udp,turn:31.129.97.211:3478?transport=tcp',
  );

  /// TURN server username (long-term credential mechanism).
  static const String turnUsername = String.fromEnvironment(
    'TURN_USERNAME',
    defaultValue: 'family',
  );

  /// TURN server credential (long-term credential mechanism).
  /// WARNING: The default value is a public development key.
  /// Set TURN_CREDENTIAL via --dart-define in production builds.
  static const String turnCredential = String.fromEnvironment(
    'TURN_CREDENTIAL',
    defaultValue: 'dev-turn-credential',
  );

  // ── STUN servers ─────────────────────────────────────────────

  static const List<String> stunUrls = [
    'stun:stun.l.google.com:19302',
    'stun:stun1.l.google.com:19302',
  ];

  // ── Project Bridge ───────────────────────────────────────────

  /// Default project-bridge host:port (used when SharedPreferences
  /// does not contain a saved value).
  static const String bridgeDefaultHost = '31.129.97.211:9877';

  // ── SharedPreferences keys ───────────────────────────────────

  static const String prefActorProfile = 'actor_profile';
  static const String prefDisplayName = 'profile_display_name';
  static const String prefPhone = 'profile_phone';
  static const String prefBridgeHost = 'bridge_host';
  static const String prefAvatarPrefix = 'avatar_';
}
