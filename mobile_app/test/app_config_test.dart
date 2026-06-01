import 'package:flutter_test/flutter_test.dart';
import 'package:family_todo_mobile/app/app_config.dart';

void main() {
  group('AppConfig', () {
    test('apiBaseUrl has default value', () {
      expect(AppConfig.apiBaseUrl, isNotEmpty);
      expect(AppConfig.apiBaseUrl.startsWith('http'), isTrue);
    });

    test('apiKey has non-empty default', () {
      expect(AppConfig.apiKey, isNotEmpty);
    });

    test('turnCredential uses safe development placeholder', () {
      expect(AppConfig.turnCredential, 'dev-turn-credential');
    });

    test('stunUrls contains google stun servers', () {
      expect(AppConfig.stunUrls, hasLength(2));
      for (final url in AppConfig.stunUrls) {
        expect(url, contains('stun:stun'));
      }
    });

    test('bridgeDefaultHost has expected format host:port', () {
      expect(AppConfig.bridgeDefaultHost, isNotEmpty);
      expect(AppConfig.bridgeDefaultHost, contains(':'));
      final parts = AppConfig.bridgeDefaultHost.split(':');
      expect(parts, hasLength(2));
      expect(parts[0], isNotEmpty);
      expect(parts[1], isNotEmpty);
      expect(int.tryParse(parts[1]), isNotNull);
    });

    test('prefActorProfile is \'actor_profile\'', () {
      expect(AppConfig.prefActorProfile, 'actor_profile');
    });

    test('prefAvatarPrefix ends with underscore', () {
      expect(AppConfig.prefAvatarPrefix, isNotEmpty);
      expect(AppConfig.prefAvatarPrefix.endsWith('_'), isTrue);
    });

    test('all pref keys are unique', () {
      final prefKeys = <String>[
        AppConfig.prefActorProfile,
        AppConfig.prefDisplayName,
        AppConfig.prefPhone,
        AppConfig.prefBridgeHost,
        AppConfig.prefAvatarPrefix,
      ];
      expect(prefKeys.toSet().length, prefKeys.length);
    });
  });
}
