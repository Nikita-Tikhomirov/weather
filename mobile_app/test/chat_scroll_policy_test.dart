import 'package:family_todo_mobile/features/chat/chat_scroll_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatScrollPolicy', () {
    test('auto-scrolls for new own message even when user is not at bottom',
        () {
      final decision = ChatScrollPolicy.shouldAutoScrollOnNewLastMessage(
        wasNearBottom: false,
        newestFromOwner: true,
      );

      expect(decision, isTrue);
    });

    test('auto-scrolls for incoming message only when user is near bottom', () {
      expect(
        ChatScrollPolicy.shouldAutoScrollOnNewLastMessage(
          wasNearBottom: true,
          newestFromOwner: false,
        ),
        isTrue,
      );
      expect(
        ChatScrollPolicy.shouldAutoScrollOnNewLastMessage(
          wasNearBottom: false,
          newestFromOwner: false,
        ),
        isFalse,
      );
    });

    test('preserves visual offset when older messages are prepended', () {
      final offset = ChatScrollPolicy.offsetAfterPrepend(
        oldMaxExtent: 1200,
        oldOffset: 80,
        newMaxExtent: 1520,
        minExtent: 0,
        maxExtent: 1520,
      );

      expect(offset, 400);
    });

    test('clamps preserved offset into scroll bounds', () {
      final offset = ChatScrollPolicy.offsetAfterPrepend(
        oldMaxExtent: 1200,
        oldOffset: 1100,
        newMaxExtent: 2000,
        minExtent: 0,
        maxExtent: 1500,
      );

      expect(offset, 1500);
    });
  });
}
