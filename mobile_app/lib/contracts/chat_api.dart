import '../models/chat_models.dart';
import '../models/chat_snapshots.dart';
import '../models/device_snapshots.dart';

/// Abstract API surface for chat operations.
abstract class ChatApi {
  Future<ChatBootstrapSnapshot> chatBootstrap({
    required String actorProfile,
  });

  Future<PhoneProfileSession> deviceStart({
    required String phone,
    required String deviceId,
    String displayName = '',
  });

  Future<List<ChatContact>> resolveContacts({
    required String actorProfile,
    required List<String> phones,
  });

  Future<List<ChatContact>> familyMembers({
    required String actorProfile,
  });

  Future<List<ChatContact>> addFamilyMembers({
    required String actorProfile,
    required List<String> profiles,
  });

  Future<ChatMessagesSnapshot> chatFetchMessages({
    required String actorProfile,
    required String conversationKey,
    String? cursor,
    int limit = 50,
  });

  Future<ChatMessage> chatSendMessage({
    required String actorProfile,
    required String conversationKey,
    required String messageType,
    String text = '',
    String? stickerId,
    String? imageUrl,
    Map<String, dynamic>? imageMeta,
    List<ChatAttachment> attachments = const [],
    String? clientMessageId,
  });

  Future<ChatConversation> chatCreateGroup({
    required String actorProfile,
    required String title,
    required List<String> memberProfiles,
  });

  Future<ChatMessage> chatSetReaction({
    required String actorProfile,
    required String messageId,
    required String reaction,
  });

  Future<ChatMessage> chatEditMessage({
    required String actorProfile,
    required String messageId,
    required String text,
  });

  Future<ChatMessage> chatDeleteMessage({
    required String actorProfile,
    required String messageId,
  });

  Future<ChatUploadResult> chatUploadSticker({
    required String actorProfile,
    required List<int> bytes,
    String filename = 'sticker.png',
  });

  Future<ChatUploadResult> chatUploadMedia({
    required String actorProfile,
    required List<int> bytes,
    required String filename,
    void Function(double progress)? onProgress,
  });

  Future<ChatUploadResult> chatUploadDocument({
    required String actorProfile,
    required List<int> bytes,
    required String filename,
    void Function(double progress)? onProgress,
  });

  Future<String> uploadProfileAvatar({
    required String actorProfile,
    required List<int> bytes,
    String filename = 'avatar.jpg',
  });

  Future<void> addGroupMember({
    required String actorProfile,
    required String conversationKey,
    required String profile,
  });

  Future<void> removeGroupMember({
    required String actorProfile,
    required String conversationKey,
    required String profile,
  });

  Future<void> renameGroup({
    required String actorProfile,
    required String conversationKey,
    required String title,
  });

  Future<void> deleteGroup({
    required String actorProfile,
    required String conversationKey,
  });

  Future<void> chatSendTyping({
    required String actorProfile,
    required String conversationKey,
  });

  Future<void> chatMarkRead({
    required String actorProfile,
    required String conversationKey,
  });

  Future<List<StickerPack>> chatStickerPacks();
}
