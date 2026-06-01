import 'package:flutter/foundation.dart';

import 'chat_models.dart';

@immutable
class ChatBootstrapSnapshot {
  const ChatBootstrapSnapshot({
    required this.contacts,
    required this.groupConversationKey,
    required this.conversations,
    required this.stickerPacks,
  });

  final List<ChatContact> contacts;
  final String groupConversationKey;
  final List<ChatConversation> conversations;
  final List<StickerPack> stickerPacks;

  Map<String, dynamic> toJson() {
    return {
      'contacts': contacts.map((c) => c.toJson()).toList(),
      'group_conversation_key': groupConversationKey,
      'conversations': conversations.map((c) => c.toJson()).toList(),
      'sticker_packs': stickerPacks.map((s) => s.toJson()).toList(),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatBootstrapSnapshot &&
          runtimeType == other.runtimeType &&
          listEquals(contacts, other.contacts) &&
          groupConversationKey == other.groupConversationKey &&
          listEquals(conversations, other.conversations) &&
          listEquals(stickerPacks, other.stickerPacks);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(contacts),
        groupConversationKey,
        Object.hashAll(conversations),
        Object.hashAll(stickerPacks),
      );

  ChatBootstrapSnapshot copyWith({
    List<ChatContact>? contacts,
    String? groupConversationKey,
    List<ChatConversation>? conversations,
    List<StickerPack>? stickerPacks,
  }) =>
      ChatBootstrapSnapshot(
        contacts: contacts ?? this.contacts,
        groupConversationKey: groupConversationKey ?? this.groupConversationKey,
        conversations: conversations ?? this.conversations,
        stickerPacks: stickerPacks ?? this.stickerPacks,
      );
}

@immutable
class ChatMessagesSnapshot {
  const ChatMessagesSnapshot({
    required this.messages,
    required this.nextCursor,
    this.typingProfiles = const [],
  });

  final List<ChatMessage> messages;
  final String? nextCursor;
  final List<String> typingProfiles;

  Map<String, dynamic> toJson() {
    return {
      'messages': messages.map((m) => m.toJson()).toList(),
      'next_cursor': nextCursor,
      'typing_profiles': typingProfiles,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessagesSnapshot &&
          runtimeType == other.runtimeType &&
          listEquals(messages, other.messages) &&
          nextCursor == other.nextCursor &&
          listEquals(typingProfiles, other.typingProfiles);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(messages),
        nextCursor,
        Object.hashAll(typingProfiles),
      );

  ChatMessagesSnapshot copyWith({
    List<ChatMessage>? messages,
    String? nextCursor,
    List<String>? typingProfiles,
  }) =>
      ChatMessagesSnapshot(
        messages: messages ?? this.messages,
        nextCursor: nextCursor ?? this.nextCursor,
        typingProfiles: typingProfiles ?? this.typingProfiles,
      );
}

@immutable
class ChatUploadResult {
  const ChatUploadResult({
    required this.assetUrl,
    required this.imageMeta,
  });

  final String assetUrl;
  final Map<String, dynamic> imageMeta;

  Map<String, dynamic> toJson() {
    return {
      'asset_url': assetUrl,
      'image_meta': imageMeta,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatUploadResult &&
          runtimeType == other.runtimeType &&
          assetUrl == other.assetUrl &&
          mapEquals(imageMeta, other.imageMeta);

  @override
  int get hashCode => Object.hash(
        assetUrl,
        Object.hashAll(
          imageMeta.entries.map((e) => Object.hash(e.key, e.value)),
        ),
      );

  ChatUploadResult copyWith({
    String? assetUrl,
    Map<String, dynamic>? imageMeta,
  }) =>
      ChatUploadResult(
        assetUrl: assetUrl ?? this.assetUrl,
        imageMeta: imageMeta ?? this.imageMeta,
      );
}
