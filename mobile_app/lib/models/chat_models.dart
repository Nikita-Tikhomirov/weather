class ChatConversation {
  ChatConversation({
    required this.conversationKey,
    required this.kind,
    required this.title,
    required this.members,
  });

  final String conversationKey;
  final String kind;
  final String title;
  final List<String> members;

  factory ChatConversation.fromJson(Map<String, dynamic> json) {
    final rawMembers = (json['members'] as List? ?? const [])
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList();
    return ChatConversation(
      conversationKey: (json['conversation_key'] ?? '').toString(),
      kind: (json['kind'] ?? 'direct').toString(),
      title: (json['title'] ?? '').toString(),
      members: rawMembers,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'conversation_key': conversationKey,
      'kind': kind,
      'title': title,
      'members': members,
    };
  }
}

class ChatContact {
  ChatContact({
    required this.profileKey,
    required this.displayName,
    required this.phone,
    required this.conversationKey,
  });

  final String profileKey;
  final String displayName;
  final String phone;
  final String conversationKey;

  factory ChatContact.fromJson(Map<String, dynamic> json) {
    return ChatContact(
      profileKey: (json['profile_key'] ?? '').toString(),
      displayName: (json['display_name'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      conversationKey: (json['conversation_key'] ?? '').toString(),
    );
  }
}

class ChatAttachment {
  ChatAttachment({
    required this.kind,
    required this.assetUrl,
    required this.imageMeta,
    required this.sortOrder,
  });

  final String kind;
  final String assetUrl;
  final Map<String, dynamic> imageMeta;
  final int sortOrder;

  factory ChatAttachment.fromJson(Map<String, dynamic> json) {
    return ChatAttachment(
      kind: (json['kind'] ?? 'image').toString(),
      assetUrl: (json['asset_url'] ?? json['image_url'] ?? '').toString(),
      imageMeta:
          (json['image_meta'] as Map?)?.cast<String, dynamic>() ?? const {},
      sortOrder: int.tryParse((json['sort_order'] ?? 0).toString()) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'kind': kind,
      'asset_url': assetUrl,
      'image_meta': imageMeta,
      'sort_order': sortOrder,
    };
  }
}

class ChatReaction {
  ChatReaction({required this.reaction, required this.count});

  final String reaction;
  final int count;

  factory ChatReaction.fromJson(Map<String, dynamic> json) {
    return ChatReaction(
      reaction: (json['reaction'] ?? '').toString(),
      count: int.tryParse((json['count'] ?? 0).toString()) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {'reaction': reaction, 'count': count};
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.conversationKey,
    required this.senderProfile,
    required this.messageType,
    required this.text,
    required this.createdAt,
    this.stickerId,
    this.imageUrl,
    this.imageMeta = const {},
    this.attachments = const [],
    this.reactions = const [],
    this.myReaction,
    this.clientMessageId,
    this.editedAt,
    this.deletedAt,
  });

  final String id;
  final String conversationKey;
  final String senderProfile;
  final String messageType;
  final String text;
  final String createdAt;
  final String? stickerId;
  final String? imageUrl;
  final Map<String, dynamic> imageMeta;
  final List<ChatAttachment> attachments;
  final List<ChatReaction> reactions;
  final String? myReaction;
  final String? clientMessageId;
  final String? editedAt;
  final String? deletedAt;

  bool get isDeleted => deletedAt != null && deletedAt!.isNotEmpty;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawImageMeta = json['image_meta'];
    final imageMeta = rawImageMeta is Map
        ? Map<String, dynamic>.from(rawImageMeta)
        : const <String, dynamic>{};
    final attachments = (json['attachments'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => ChatAttachment.fromJson(Map<String, dynamic>.from(row)))
        .toList();
    final reactions = (json['reactions'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => ChatReaction.fromJson(Map<String, dynamic>.from(row)))
        .toList();
    return ChatMessage(
      id: (json['id'] ?? '').toString(),
      conversationKey: (json['conversation_key'] ?? '').toString(),
      senderProfile: (json['sender_profile'] ?? '').toString(),
      messageType: (json['message_type'] ?? 'text').toString(),
      text: (json['text'] ?? '').toString(),
      createdAt: (json['created_at'] ?? '').toString(),
      stickerId: json['sticker_id']?.toString(),
      imageUrl: json['image_url']?.toString(),
      imageMeta: imageMeta,
      attachments: attachments,
      reactions: reactions,
      myReaction: json['my_reaction']?.toString(),
      clientMessageId: json['client_message_id']?.toString(),
      editedAt: json['edited_at']?.toString(),
      deletedAt: json['deleted_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversation_key': conversationKey,
      'sender_profile': senderProfile,
      'message_type': messageType,
      'text': text,
      'sticker_id': stickerId,
      'image_url': imageUrl,
      'image_meta': imageMeta,
      'attachments': attachments.map((item) => item.toJson()).toList(),
      'reactions': reactions.map((item) => item.toJson()).toList(),
      'my_reaction': myReaction,
      'client_message_id': clientMessageId,
      'created_at': createdAt,
      'edited_at': editedAt,
      'deleted_at': deletedAt,
      'is_deleted': isDeleted,
    };
  }
}

class StickerItem {
  StickerItem({
    required this.stickerId,
    required this.title,
    required this.assetUrl,
    required this.sortOrder,
  });

  final String stickerId;
  final String title;
  final String assetUrl;
  final int sortOrder;

  factory StickerItem.fromJson(Map<String, dynamic> json) {
    return StickerItem(
      stickerId: (json['sticker_id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      assetUrl: (json['asset_url'] ?? '').toString(),
      sortOrder: (json['sort_order'] ?? 0) is int
          ? json['sort_order'] as int
          : int.tryParse((json['sort_order'] ?? '0').toString()) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sticker_id': stickerId,
      'title': title,
      'asset_url': assetUrl,
      'sort_order': sortOrder,
    };
  }
}

class StickerPack {
  StickerPack({
    required this.packKey,
    required this.title,
    required this.items,
  });

  final String packKey;
  final String title;
  final List<StickerItem> items;

  factory StickerPack.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => StickerItem.fromJson(Map<String, dynamic>.from(row)))
        .toList();

    return StickerPack(
      packKey: (json['pack_key'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      items: rawItems,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pack_key': packKey,
      'title': title,
      'items': items.map((item) => item.toJson()).toList(),
    };
  }
}
