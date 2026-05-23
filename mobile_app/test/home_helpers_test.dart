import 'package:flutter_test/flutter_test.dart';
import 'package:family_todo_mobile/features/home/home_helpers.dart';
import 'package:family_todo_mobile/models/chat_models.dart';

void main() {
  group('isChatMessageData', () {
    test('returns true for chat_message entity with conversation_key', () {
      expect(
        isChatMessageData({
          'entity': 'chat_message',
          'conversation_key': 'dm:nik:misha',
        }),
        isTrue,
      );
    });

    test('returns true when type is chat_message', () {
      expect(
        isChatMessageData({
          'type': 'chat_message',
          'conversation_key': 'dm:a:b',
        }),
        isTrue,
      );
    });

    test('returns false for task entity', () {
      expect(
        isChatMessageData({
          'entity': 'task',
          'conversation_key': 'dm:nik:misha',
        }),
        isFalse,
      );
    });

    test('returns false for call_incoming type', () {
      expect(
        isChatMessageData({
          'type': 'call_incoming',
          'conversation_key': 'dm:a:b',
        }),
        isFalse,
      );
    });

    test('returns false when conversation_key is empty', () {
      expect(
        isChatMessageData({
          'entity': 'chat_message',
          'conversation_key': '   ',
        }),
        isFalse,
      );
    });

    test('returns false when conversation_key is missing', () {
      expect(
        isChatMessageData({
          'entity': 'chat_message',
        }),
        isFalse,
      );
    });

    test('returns false for empty data', () {
      expect(isChatMessageData({}), isFalse);
    });

    test('returns false for task_reminder type', () {
      expect(
        isChatMessageData({
          'type': 'task_reminder',
          'conversation_key': 'dm:a:b',
        }),
        isFalse,
      );
    });
  });

  group('isProjectConversation', () {
    test('returns true for project: prefix', () {
      expect(isProjectConversation('project:tudushka'), isTrue);
      expect(isProjectConversation('project:cifra'), isTrue);
    });

    test('returns false for non-project keys', () {
      expect(isProjectConversation('dm:nik:misha'), isFalse);
      expect(isProjectConversation('group:common'), isFalse);
      expect(isProjectConversation(''), isFalse);
    });

    test('returns false for keys containing project elsewhere', () {
      expect(isProjectConversation('someproject:test'), isFalse);
    });
  });

  group('dateKey', () {
    test('formats date as YYYY-MM-DD', () {
      expect(dateKey(DateTime(2025, 1, 5)), '2025-01-05');
      expect(dateKey(DateTime(2025, 12, 31)), '2025-12-31');
      expect(dateKey(DateTime(2025, 10, 1)), '2025-10-01');
    });

    test('pads single-digit months and days', () {
      expect(dateKey(DateTime(2025, 3, 7)), '2025-03-07');
      expect(dateKey(DateTime(2025, 11, 9)), '2025-11-09');
    });
  });

  group('contactLabel', () {
    test('returns display name when available', () {
      final contact = ChatContact(
        profileKey: 'nik',
        displayName: 'Никита',
        phone: '+79991112233',
        conversationKey: 'dm:misha:nik',
      );
      expect(contactLabel(contact), 'Никита');
    });

    test('returns phone when display name is empty', () {
      final contact = ChatContact(
        profileKey: 'misha',
        displayName: '   ',
        phone: '+79991112244',
        conversationKey: 'dm:misha:nik',
      );
      expect(contactLabel(contact), '+79991112244');
    });

    test('returns profile key as fallback', () {
      final contact = ChatContact(
        profileKey: 'unknown',
        displayName: '',
        phone: '',
        conversationKey: '',
      );
      expect(contactLabel(contact), 'unknown');
    });
  });

  group('canonicalConversationKey', () {
    test('keeps first two segments for keys with >2 parts', () {
      expect(canonicalConversationKey('dm:nik:misha'), 'dm:nik');
      expect(canonicalConversationKey('group:common:extra'), 'group:common');
    });

    test('returns unchanged for keys with 2 or fewer parts', () {
      expect(canonicalConversationKey('group:common'), 'group:common');
      expect(canonicalConversationKey('project:test'), 'project:test');
      expect(canonicalConversationKey('dm:nik'), 'dm:nik');
    });

    test('trims whitespace', () {
      expect(canonicalConversationKey('  dm:nik  '), 'dm:nik');
    });
  });

  group('sameMessages', () {
    ChatMessage makeMsg(String id, {String? editedAt, String? deletedAt}) =>
        ChatMessage(
          id: id,
          conversationKey: 'test',
          senderProfile: 'nik',
          messageType: 'text',
          text: 'hello',
          createdAt: '2025-01-01T00:00:00',
          editedAt: editedAt,
          deletedAt: deletedAt,
        );

    test('returns true for identical lists', () {
      final a = [makeMsg('1'), makeMsg('2')];
      final b = [makeMsg('1'), makeMsg('2')];
      expect(sameMessages(a, b), isTrue);
    });

    test('returns false for different ids', () {
      final a = [makeMsg('1')];
      final b = [makeMsg('2')];
      expect(sameMessages(a, b), isFalse);
    });

    test('returns false for different editedAt', () {
      final a = [makeMsg('1', editedAt: '2025-01-01')];
      final b = [makeMsg('1', editedAt: '2025-01-02')];
      expect(sameMessages(a, b), isFalse);
    });

    test('returns false for different deletedAt', () {
      final a = [makeMsg('1', deletedAt: null)];
      final b = [makeMsg('1', deletedAt: '2025-01-01')];
      expect(sameMessages(a, b), isFalse);
    });

    test('returns false for different lengths', () {
      final a = [makeMsg('1')];
      final b = [makeMsg('1'), makeMsg('2')];
      expect(sameMessages(a, b), isFalse);
    });

    test('returns true for both empty', () {
      expect(sameMessages([], []), isTrue);
    });
  });

  group('guessMimeType', () {
    test('recognizes common image types', () {
      expect(guessMimeType('photo.jpg'), 'image/jpeg');
      expect(guessMimeType('photo.jpeg'), 'image/jpeg');
      expect(guessMimeType('icon.png'), 'image/png');
      expect(guessMimeType('anim.gif'), 'image/gif');
      expect(guessMimeType('icon.webp'), 'image/webp');
      expect(guessMimeType('icon.bmp'), 'image/bmp');
    });

    test('recognizes video types', () {
      expect(guessMimeType('video.mp4'), 'video/mp4');
      expect(guessMimeType('clip.webm'), 'video/webm');
      expect(guessMimeType('clip.mov'), 'video/quicktime');
    });

    test('recognizes document types', () {
      expect(guessMimeType('doc.pdf'), 'application/pdf');
      expect(guessMimeType('file.txt'), 'text/plain');
    });

    test('returns octet-stream for unknown extensions', () {
      expect(guessMimeType('file.xyz'), 'application/octet-stream');
    });

    test('handles uppercase extensions', () {
      expect(guessMimeType('PHOTO.JPG'), 'image/jpeg');
      expect(guessMimeType('VIDEO.MP4'), 'video/mp4');
    });
  });
}
