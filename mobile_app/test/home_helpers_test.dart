import 'package:flutter_test/flutter_test.dart';
import 'package:family_todo_mobile/features/home/home_helpers.dart';
import 'package:family_todo_mobile/models/chat_models.dart';

void main() {
  group('isChatMessageData', () {
    test('returns true for chat_message entity with conversation_key', () {
      expect(
        isChatMessageData({
          'entity': 'chat_message',
          'conversation_key': 'dm:u_001:u_042',
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
          'conversation_key': 'dm:u_001:u_042',
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
    test('detects retired project chat prefix', () {
      expect(isProjectConversation('project:tudushka'), isTrue);
      expect(isProjectConversation('project:cifra'), isTrue);
    });

    test('returns false for non-project keys', () {
      expect(isProjectConversation('dm:u_001:u_042'), isFalse);
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
      const contact = ChatContact(
        profileKey: 'u_001',
        displayName: 'Никита',
        phone: '+79991112233',
        conversationKey: 'dm:u_001:u_042',
      );
      expect(contactLabel(contact), 'Никита');
    });

    test('returns phone when display name is empty', () {
      const contact = ChatContact(
        profileKey: 'u_042',
        displayName: '   ',
        phone: '+79991112244',
        conversationKey: 'dm:u_001:u_042',
      );
      expect(contactLabel(contact), '+79991112244');
    });

    test('returns profile key as fallback', () {
      const contact = ChatContact(
        profileKey: 'unknown',
        displayName: '',
        phone: '',
        conversationKey: '',
      );
      expect(contactLabel(contact), 'unknown');
    });
  });

  group('canonicalConversationKey', () {
    test('keeps both direct chat members and normalizes their order', () {
      expect(canonicalConversationKey('dm:u_042:u_001'), 'dm:u_001:u_042');
      expect(canonicalConversationKey('dm:u_001:u_042'), 'dm:u_001:u_042');
    });

    test('keeps first two segments for non-direct keys with >2 parts', () {
      expect(canonicalConversationKey('group:common:extra'), 'group:common');
    });

    test('returns unchanged for keys with 2 or fewer parts', () {
      expect(canonicalConversationKey('group:common'), 'group:common');
      expect(canonicalConversationKey('project:test'), 'project:test');
      expect(canonicalConversationKey('dm:u_001'), 'dm:u_001');
    });

    test('trims whitespace', () {
      expect(canonicalConversationKey('  dm:u_001  '), 'dm:u_001');
    });
  });

  group('sameMessages', () {
    ChatMessage makeMsg(String id, {String? editedAt, String? deletedAt}) =>
        ChatMessage(
          id: id,
          conversationKey: 'test',
          senderProfile: 'u_001',
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

  group('primaryChatMediaUrl', () {
    test('uses voice imageUrl when server returns legacy voice payload', () {
      const message = ChatMessage(
        id: 'voice-1',
        conversationKey: 'dm:nik:misha',
        senderProfile: 'nik',
        messageType: 'voice',
        text: 'Голосовое сообщение',
        imageUrl: '/chat/media/voice-1',
        createdAt: '2026-05-31T12:00:00',
      );

      expect(primaryChatMediaUrl(message), '/chat/media/voice-1');
    });

    test('prefers attachment URL over legacy imageUrl', () {
      const message = ChatMessage(
        id: 'voice-2',
        conversationKey: 'dm:nik:misha',
        senderProfile: 'nik',
        messageType: 'voice',
        text: 'Голосовое сообщение',
        imageUrl: '/chat/media/legacy',
        createdAt: '2026-05-31T12:00:00',
        attachments: [
          ChatAttachment(
            kind: 'voice',
            assetUrl: '/chat/media/attached',
            imageMeta: {'duration_ms': 1200},
            sortOrder: 0,
          ),
        ],
      );

      expect(primaryChatMediaUrl(message), '/chat/media/attached');
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
