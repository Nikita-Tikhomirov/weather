import 'package:family_todo_mobile/services/sync_loop_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('syncErrorMessage uses English diagnostic text', () {
    expect(syncErrorMessage('network'), 'Sync error: network');
  });
}
