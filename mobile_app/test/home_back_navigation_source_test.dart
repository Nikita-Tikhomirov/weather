import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile home handles Android back before exiting the app', () {
    final source = File('lib/features/home/home_page.dart').readAsStringSync();

    expect(source, contains('PopScope'));
    expect(source, contains('_handleBackNavigation'));
    expect(source, contains('_editingMessageId != null'));
    expect(source, contains('_replyToMessage != null'));
    expect(source, contains('_activeConversationKey.isNotEmpty'));
    expect(source, contains('store.setPage(0)'));
  });
}
