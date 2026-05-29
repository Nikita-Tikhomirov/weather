import '../../models/chat_models.dart';

/// Pure helper functions extracted from HomePage to reduce file size.
///
/// These functions have no side effects and don't depend on widget state.
/// They can be safely unit-tested in isolation.

/// Legacy project chats are retired; CodeWhale workspaces own project sessions.
bool isProjectConversation(String key) => false;

enum PendingPushAction { syncOnly, routeOpenedPush }

/// Returns true when the FCM data payload represents a chat message
/// (as opposed to a task reminder, call notification, etc.).
bool isChatMessageData(Map<String, dynamic> data) {
  return (data['entity'] ?? data['type'] ?? '').toString() == 'chat_message' &&
      (data['conversation_key'] ?? '').toString().trim().isNotEmpty;
}

/// Pending payloads saved from an explicit notification tap must keep routing
/// after app init; passive background deliveries should only refresh data.
PendingPushAction pendingPushAction({
  required Map<String, dynamic> data,
  required bool wasOpenedByUser,
}) {
  if (!wasOpenedByUser || data.isEmpty) {
    return PendingPushAction.syncOnly;
  }
  return PendingPushAction.routeOpenedPush;
}

/// Formats a [DateTime] as 'YYYY-MM-DD'.
String dateKey(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

/// Returns a display label for a chat contact.
String contactLabel(ChatContact contact) {
  if (contact.displayName.trim().isNotEmpty) {
    return contact.displayName.trim();
  }
  if (contact.phone.trim().isNotEmpty) {
    return contact.phone.trim();
  }
  return contact.profileKey;
}

/// Returns a human-readable label for a conversation.
String conversationLabel(ChatConversation conversation, String actor) {
  if (conversation.kind == 'group' ||
      conversation.conversationKey == 'group:common') {
    if (conversation.title.trim().isNotEmpty) {
      return conversation.title.trim();
    }
    return 'Группа';
  }
  // Direct chat — show the other participant's name.
  final others = conversation.members.where((m) => m != actor).toList();
  if (others.isNotEmpty) {
    return others.first;
  }
  return conversation.conversationKey;
}

/// Returns the display text for a chat message.
String chatMessageText(ChatMessage message) {
  if (message.isDeleted) {
    return 'Сообщение удалено';
  }
  if (message.messageType == 'sticker') {
    return 'Стикер';
  }
  if (message.messageType == 'image') {
    return 'Фото';
  }
  if (message.messageType == 'voice') {
    return 'Голосовое сообщение';
  }
  if (message.messageType == 'document') {
    return 'Документ';
  }
  return message.text;
}

/// Normalises a conversation key by stripping trailing metadata.
String canonicalConversationKey(String key) {
  final trimmed = key.trim();
  final parts = trimmed.split(':');
  if (parts.length == 3 && parts[0] == 'dm') {
    final members = [parts[1], parts[2]]..sort();
    return 'dm:${members[0]}:${members[1]}';
  }
  // Keys like "group:name:extra" keep only first two segments.
  if (parts.length > 2) {
    return '${parts[0]}:${parts[1]}';
  }
  return trimmed;
}

/// Compares two lists of chat messages for equality (by id and editedAt).
bool sameMessages(List<ChatMessage> a, List<ChatMessage> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].id != b[i].id) return false;
    if (a[i].editedAt != b[i].editedAt) return false;
    if (a[i].deletedAt != b[i].deletedAt) return false;
  }
  return true;
}

/// Returns the MIME type for a file based on its extension.
String guessMimeType(String filename) {
  final ext = filename.toLowerCase().split('.').last;
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'bmp':
      return 'image/bmp';
    case 'mp4':
      return 'video/mp4';
    case 'webm':
      return 'video/webm';
    case 'mov':
      return 'video/quicktime';
    case 'pdf':
      return 'application/pdf';
    case 'zip':
      return 'application/zip';
    case 'json':
      return 'application/json';
    case 'txt':
      return 'text/plain';
    default:
      return 'application/octet-stream';
  }
}
