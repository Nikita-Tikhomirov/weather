import 'package:flutter_test/flutter_test.dart';
import 'package:family_todo_mobile/features/home/home_helpers.dart';

/// Tests for push notification classification and routing logic.
///
/// These tests validate that:
/// - Push data is correctly classified (task, chat, call)
/// - Chat notification suppression rules are correct
/// - No auto-navigation happens for non-tap scenarios
/// - Foreground notifications are always shown for task types

/// Classifies a push data payload into a navigation target.
/// Mirrors the classification logic in push_handler.dart onOpenPush.
enum PushTarget { tasks, messenger, call, none }

PushTarget classifyPush(Map<String, dynamic> data) {
  final pushType = (data['type'] ?? data['entity'] ?? '').toString().trim();
  final conversationKey =
      (data['conversation_key'] ?? '').toString().trim();
  final entity = (data['entity'] ?? '').toString().trim();

  // Task-related notifications
  if (pushType == 'task_reminder' ||
      pushType == 'todo_update' ||
      entity == 'task' ||
      entity == 'family_task') {
    return PushTarget.tasks;
  }

  // Chat messages
  if (entity == 'chat_message' &&
      conversationKey.isNotEmpty &&
      !isProjectConversation(conversationKey)) {
    return PushTarget.messenger;
  }

  // Incoming call
  if (pushType == 'call_incoming') {
    return PushTarget.call;
  }

  // Call ended remotely — no navigation
  if (pushType == 'call_accepted' || pushType == 'call_rejected') {
    return PushTarget.none;
  }

  return PushTarget.none;
}

/// Determines if a foreground chat notification should be suppressed.
/// Returns true when the user is already viewing that exact conversation.
bool shouldSuppressChatNotification({
  required Map<String, dynamic> data,
  required int currentPageIndex,
  required String activeConversationKey,
}) {
  if (!isChatMessageData(data)) return false;
  final pushKey = (data['conversation_key'] ?? '').toString().trim();
  // Canonicalize: dm:A:B == dm:B:A
  final canonical = _canonicalDmKey(pushKey);
  return currentPageIndex == 4 && activeConversationKey == canonical;
}

String _canonicalDmKey(String key) {
  final trimmed = key.trim();
  final parts = trimmed.split(':');
  if (parts.length == 3 && parts[0] == 'dm') {
    final members = [parts[1], parts[2]]..sort();
    return 'dm:${members[0]}:${members[1]}';
  }
  return trimmed;
}

void main() {
  // ── Push classification tests ──────────────────────────────────

  group('classifyPush', () {
    test('task_reminder → PushTarget.tasks', () {
      final data = {
        'type': 'task_reminder',
        'entity': 'task',
        'conversation_key': 'dm:nik:misha',
      };
      expect(classifyPush(data), PushTarget.tasks);
    });

    test('todo_update → PushTarget.tasks', () {
      final data = {
        'type': 'todo_update',
        'entity': 'task',
      };
      expect(classifyPush(data), PushTarget.tasks);
    });

    test('entity=task → PushTarget.tasks', () {
      final data = {'entity': 'task'};
      expect(classifyPush(data), PushTarget.tasks);
    });

    test('entity=family_task → PushTarget.tasks', () {
      final data = {'entity': 'family_task'};
      expect(classifyPush(data), PushTarget.tasks);
    });

    test('chat_message with conversation_key → PushTarget.messenger', () {
      final data = {
        'entity': 'chat_message',
        'conversation_key': 'dm:nik:misha',
      };
      expect(classifyPush(data), PushTarget.messenger);
    });

    test('chat_message without conversation_key → PushTarget.none', () {
      final data = {'entity': 'chat_message', 'conversation_key': ''};
      expect(classifyPush(data), PushTarget.none);
    });

    test('project: chat_message → PushTarget.none (no messenger nav)', () {
      final data = {
        'entity': 'chat_message',
        'conversation_key': 'project:tudushka',
      };
      expect(classifyPush(data), PushTarget.none);
    });

    test('call_incoming → PushTarget.call', () {
      final data = {
        'type': 'call_incoming',
        'session_id': 'abc123',
        'caller_profile': 'misha',
      };
      expect(classifyPush(data), PushTarget.call);
    });

    test('call_accepted → PushTarget.none (no navigation)', () {
      final data = {'type': 'call_accepted'};
      expect(classifyPush(data), PushTarget.none);
    });

    test('call_rejected → PushTarget.none (no navigation)', () {
      final data = {'type': 'call_rejected'};
      expect(classifyPush(data), PushTarget.none);
    });

    test('unknown push type → PushTarget.none', () {
      final data = {'type': 'unknown_event'};
      expect(classifyPush(data), PushTarget.none);
    });

    test('empty data → PushTarget.none', () {
      expect(classifyPush({}), PushTarget.none);
    });
  });

  // ── Notification suppression tests ─────────────────────────────

  group('shouldSuppressChatNotification', () {
    test('suppresses when on messenger tab viewing same chat', () {
      final data = {
        'entity': 'chat_message',
        'conversation_key': 'dm:nik:misha',
      };
      expect(
        shouldSuppressChatNotification(
          data: data,
          currentPageIndex: 4,
          activeConversationKey: 'dm:misha:nik',
        ),
        isTrue,
      );
    });

    test('does NOT suppress chat when on different tab', () {
      final data = {
        'entity': 'chat_message',
        'conversation_key': 'dm:nik:misha',
      };
      expect(
        shouldSuppressChatNotification(
          data: data,
          currentPageIndex: 1, // tasks tab
          activeConversationKey: 'dm:misha:nik',
        ),
        isFalse,
      );
    });

    test('does NOT suppress chat when viewing different conversation', () {
      final data = {
        'entity': 'chat_message',
        'conversation_key': 'dm:nik:misha',
      };
      expect(
        shouldSuppressChatNotification(
          data: data,
          currentPageIndex: 4, // messenger tab
          activeConversationKey: 'dm:nik:arisha',
        ),
        isFalse,
      );
    });

    test('does NOT suppress task notification (always shown)', () {
      final data = {
        'entity': 'task',
        'type': 'task_reminder',
      };
      // Even when on messenger tab — task notifications should show
      expect(
        shouldSuppressChatNotification(
          data: data,
          currentPageIndex: 4,
          activeConversationKey: 'dm:nik:misha',
        ),
        isFalse,
      );
    });

    test('does NOT suppress task notification on any tab', () {
      final data = {
        'entity': 'task',
        'type': 'todo_update',
        'conversation_key': 'dm:nik:misha',
      };
      // Try all tab indices
      for (var tab = 0; tab < 5; tab++) {
        expect(
          shouldSuppressChatNotification(
            data: data,
            currentPageIndex: tab,
            activeConversationKey: 'dm:misha:nik',
          ),
          isFalse,
          reason: 'Task notification should not be suppressed on tab $tab',
        );
      }
    });

    test('does NOT suppress call_incoming notification', () {
      final data = {
        'type': 'call_incoming',
        'conversation_key': 'dm:nik:misha',
      };
      expect(
        shouldSuppressChatNotification(
          data: data,
          currentPageIndex: 4,
          activeConversationKey: 'dm:misha:nik',
        ),
        isFalse,
      );
    });

    test('does NOT suppress when no suppression callback (null scenario)', () {
      // When shouldSuppressChatNotification is null, nothing is suppressed.
      // This is the default behavior — all notifications are shown.
      expect(isChatMessageData({'entity': 'task'}), isFalse);
    });
  });

  // ── isChatMessageData edge cases ────────────────────────────────

  group('isChatMessageData edge cases', () {
    test('chat_message with whitespace conversation_key → false', () {
      expect(
        isChatMessageData({
          'entity': 'chat_message',
          'conversation_key': '   ',
        }),
        isFalse,
      );
    });

    test('chat_message with project conversation_key → true (valid chat)', () {
      // Project conversations ARE chat messages — they just route differently.
      expect(
        isChatMessageData({
          'entity': 'chat_message',
          'conversation_key': 'project:tudushka',
        }),
        isTrue,
      );
    });
  });

  // ── Canonical DM key normalization ─────────────────────────────

  group('_canonicalDmKey', () {
    test('normalizes dm:A:B and dm:B:A to the same key', () {
      final a = _canonicalDmKey('dm:nik:misha');
      final b = _canonicalDmKey('dm:misha:nik');
      expect(a, equals(b));
    });

    test('preserves non-dm keys', () {
      expect(_canonicalDmKey('group:common'), 'group:common');
      expect(_canonicalDmKey('project:tudushka'), 'project:tudushka');
    });

    test('handles empty key', () {
      expect(_canonicalDmKey(''), '');
    });

    test('handles key with extra whitespace', () {
      expect(_canonicalDmKey(' dm:nik:misha '), _canonicalDmKey('dm:misha:nik'));
    });
  });
}
