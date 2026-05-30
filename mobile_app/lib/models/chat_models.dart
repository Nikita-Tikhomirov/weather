import 'package:flutter/foundation.dart';

@immutable
class ChatConversation {
  ChatConversation({
    required this.conversationKey,
    required this.kind,
    required this.title,
    required this.members,
    this.avatarUrl,
  });

  final String conversationKey;
  final String kind;
  final String title;
  final List<String> members;
  final String? avatarUrl;

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
      avatarUrl: json['avatar_url']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'conversation_key': conversationKey,
      'kind': kind,
      'title': title,
      'members': members,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatConversation &&
          runtimeType == other.runtimeType &&
          conversationKey == other.conversationKey &&
          kind == other.kind &&
          title == other.title &&
          listEquals(members, other.members) &&
          avatarUrl == other.avatarUrl;

  @override
  int get hashCode => Object.hash(
        conversationKey,
        kind,
        title,
        Object.hashAll(members),
        avatarUrl,
      );

  ChatConversation copyWith({
    String? conversationKey,
    String? kind,
    String? title,
    List<String>? members,
    String? avatarUrl,
  }) {
    return ChatConversation(
      conversationKey: conversationKey ?? this.conversationKey,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      members: members ?? this.members,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }
}

@immutable
class ChatContact {
  ChatContact({
    required this.profileKey,
    required this.displayName,
    required this.phone,
    required this.conversationKey,
    this.avatarUrl,
  });

  final String profileKey;
  final String displayName;
  final String phone;
  final String conversationKey;
  final String? avatarUrl;

  factory ChatContact.fromJson(Map<String, dynamic> json) {
    return ChatContact(
      profileKey: (json['profile_key'] ?? '').toString(),
      displayName: (json['display_name'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      conversationKey: (json['conversation_key'] ?? '').toString(),
      avatarUrl: json['avatar_url']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'profile_key': profileKey,
      'display_name': displayName,
      'phone': phone,
      'conversation_key': conversationKey,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatContact &&
          runtimeType == other.runtimeType &&
          profileKey == other.profileKey &&
          displayName == other.displayName &&
          phone == other.phone &&
          conversationKey == other.conversationKey &&
          avatarUrl == other.avatarUrl;

  @override
  int get hashCode =>
      profileKey.hashCode ^
      displayName.hashCode ^
      phone.hashCode ^
      conversationKey.hashCode ^
      avatarUrl.hashCode;

  ChatContact copyWith({
    String? profileKey,
    String? displayName,
    String? phone,
    String? conversationKey,
    String? avatarUrl,
  }) {
    return ChatContact(
      profileKey: profileKey ?? this.profileKey,
      displayName: displayName ?? this.displayName,
      phone: phone ?? this.phone,
      conversationKey: conversationKey ?? this.conversationKey,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }
}

@immutable
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
    final rawImageMeta = json['image_meta'];
    final imageMeta = rawImageMeta is Map
        ? Map<String, dynamic>.from(rawImageMeta)
        : const <String, dynamic>{};
    return ChatAttachment(
      kind: (json['kind'] ?? 'image').toString(),
      assetUrl: (json['asset_url'] ?? json['image_url'] ?? '').toString(),
      imageMeta: imageMeta,
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatAttachment &&
          runtimeType == other.runtimeType &&
          kind == other.kind &&
          assetUrl == other.assetUrl &&
          mapEquals(imageMeta, other.imageMeta) &&
          sortOrder == other.sortOrder;

  @override
  int get hashCode => Object.hash(
        kind,
        assetUrl,
        Object.hashAll(imageMeta.entries.map((e) => Object.hash(e.key, e.value))),
        sortOrder,
      );

  ChatAttachment copyWith({
    String? kind,
    String? assetUrl,
    Map<String, dynamic>? imageMeta,
    int? sortOrder,
  }) {
    return ChatAttachment(
      kind: kind ?? this.kind,
      assetUrl: assetUrl ?? this.assetUrl,
      imageMeta: imageMeta ?? this.imageMeta,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}

@immutable
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatReaction &&
          runtimeType == other.runtimeType &&
          reaction == other.reaction &&
          count == other.count;

  @override
  int get hashCode => reaction.hashCode ^ count.hashCode;

  ChatReaction copyWith({
    String? reaction,
    int? count,
  }) {
    return ChatReaction(
      reaction: reaction ?? this.reaction,
      count: count ?? this.count,
    );
  }
}

@immutable
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
    this.isUploading = false,
    this.uploadProgress = 0.0,
    this.deliveryStatus = 'sent',
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

  /// Local-only fields for optimistic uploads
  final bool isUploading;
  final double uploadProgress;

  /// Delivery status: sending, sent, delivered, read, failed
  final String deliveryStatus;

  ChatMessage copyWith({
    String? id,
    String? conversationKey,
    String? senderProfile,
    String? messageType,
    String? text,
    String? createdAt,
    String? stickerId,
    String? imageUrl,
    Map<String, dynamic>? imageMeta,
    List<ChatAttachment>? attachments,
    List<ChatReaction>? reactions,
    String? myReaction,
    String? clientMessageId,
    String? editedAt,
    String? deletedAt,
    bool? isUploading,
    double? uploadProgress,
    String? deliveryStatus,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      conversationKey: conversationKey ?? this.conversationKey,
      senderProfile: senderProfile ?? this.senderProfile,
      messageType: messageType ?? this.messageType,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      stickerId: stickerId ?? this.stickerId,
      imageUrl: imageUrl ?? this.imageUrl,
      imageMeta: imageMeta ?? this.imageMeta,
      attachments: attachments ?? this.attachments,
      reactions: reactions ?? this.reactions,
      myReaction: myReaction ?? this.myReaction,
      clientMessageId: clientMessageId ?? this.clientMessageId,
      editedAt: editedAt ?? this.editedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      isUploading: isUploading ?? this.isUploading,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
    );
  }

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
      isUploading: json['is_uploading'] == true,
      uploadProgress: (json['upload_progress'] as num?)?.toDouble() ?? 0.0,
      deliveryStatus: (json['delivery_status'] ?? 'sent').toString(),
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
      'is_deleted': deletedAt != null && deletedAt!.isNotEmpty,
      'is_uploading': isUploading,
      'upload_progress': uploadProgress,
      'delivery_status': deliveryStatus,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessage &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          conversationKey == other.conversationKey &&
          senderProfile == other.senderProfile &&
          messageType == other.messageType &&
          text == other.text &&
          createdAt == other.createdAt &&
          stickerId == other.stickerId &&
          imageUrl == other.imageUrl &&
          mapEquals(imageMeta, other.imageMeta) &&
          listEquals(attachments, other.attachments) &&
          listEquals(reactions, other.reactions) &&
          myReaction == other.myReaction &&
          clientMessageId == other.clientMessageId &&
          editedAt == other.editedAt &&
          deletedAt == other.deletedAt &&
          isUploading == other.isUploading &&
          uploadProgress == other.uploadProgress &&
          deliveryStatus == other.deliveryStatus;

  @override
  int get hashCode => Object.hash(
        id,
        conversationKey,
        senderProfile,
        messageType,
        text,
        createdAt,
        stickerId,
        imageUrl,
        Object.hashAll(imageMeta.entries.map((e) => Object.hash(e.key, e.value))),
        Object.hashAll(attachments),
        Object.hashAll(reactions),
        myReaction,
        clientMessageId,
        editedAt,
        deletedAt,
        isUploading,
        uploadProgress,
        deliveryStatus,
      );
}

@immutable
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StickerItem &&
          runtimeType == other.runtimeType &&
          stickerId == other.stickerId &&
          title == other.title &&
          assetUrl == other.assetUrl &&
          sortOrder == other.sortOrder;

  @override
  int get hashCode =>
      stickerId.hashCode ^ title.hashCode ^ assetUrl.hashCode ^ sortOrder.hashCode;

  StickerItem copyWith({
    String? stickerId,
    String? title,
    String? assetUrl,
    int? sortOrder,
  }) {
    return StickerItem(
      stickerId: stickerId ?? this.stickerId,
      title: title ?? this.title,
      assetUrl: assetUrl ?? this.assetUrl,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}

@immutable
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StickerPack &&
          runtimeType == other.runtimeType &&
          packKey == other.packKey &&
          title == other.title &&
          listEquals(items, other.items);

  @override
  int get hashCode => Object.hash(
        packKey,
        title,
        Object.hashAll(items),
      );

  StickerPack copyWith({
    String? packKey,
    String? title,
    List<StickerItem>? items,
  }) {
    return StickerPack(
      packKey: packKey ?? this.packKey,
      title: title ?? this.title,
      items: items ?? this.items,
    );
  }
}
