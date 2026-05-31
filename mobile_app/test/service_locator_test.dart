import 'package:family_todo_mobile/services/service_locator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServiceLocator', () {
    test('singleton instance is consistent', () {
      final a = ServiceLocator.instance;
      final b = ServiceLocator.instance;
      expect(identical(a, b), isTrue);
    });

    test('api is available after init', () async {
      final locator = ServiceLocator.instance;
      await locator.init();

      expect(locator.api, isNotNull);
    });

    test('multiple init calls are safe', () async {
      final locator = ServiceLocator.instance;
      await locator.init();
      await locator.init(); // Should not throw

      expect(locator.api, isNotNull);
    });
  });
}
