import 'chat_models.dart';

class ChatBootstrapSnapshot {
  ChatBootstrapSnapshot({
    required this.contacts,
    required this.groupConversationKey,
    required this.conversations,
    required this.stickerPacks,
  });

  final List<ChatContact> contacts;
  final String groupConversationKey;
  final List<ChatConversation> conversations;
  final List<StickerPack> stickerPacks;
}

class ChatMessagesSnapshot {
  ChatMessagesSnapshot({
    required this.messages,
    required this.nextCursor,
    this.typingProfiles = const [],
  });

  final List<ChatMessage> messages;
  final String? nextCursor;
  final List<String> typingProfiles;
}

class ChatUploadResult {
  ChatUploadResult({
    required this.assetUrl,
    required this.imageMeta,
  });

  final String assetUrl;
  final Map<String, dynamic> imageMeta;
}
