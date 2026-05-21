import 'package:family_todo_mobile/services/project_access.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('project chats are visible only for owner phone', () {
    expect(canUseProjectChats('+7 967 981-24-38'), isTrue);
    expect(canUseProjectChats('89679812438'), isTrue);
    expect(canUseProjectChats('+7 920 655-56-44'), isFalse);
    expect(canUseProjectChats(''), isFalse);
  });
}
