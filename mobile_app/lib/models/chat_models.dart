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
  final String? clientMessageId;
  final String? editedAt;
  final String? deletedAt;

  bool get isDeleted => deletedAt != null && deletedAt!.isNotEmpty;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawImageMeta = json['image_meta'];
    final imageMeta = rawImageMeta is Map
        ? Map<String, dynamic>.from(rawImageMeta)
        : const <String, dynamic>{};
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
