import 'dart:convert';

import 'package:http/http.dart' as http;

import '../contracts/chat_api.dart';
import '../models/chat_models.dart';
import '../models/chat_snapshots.dart';
import '../models/device_snapshots.dart';
import 'http_client_base.dart';

class ChatApiClient extends HttpApiClient implements ChatApi {
  ChatApiClient({required super.baseUrl, required super.apiKey});

  @override
  Future<ChatBootstrapSnapshot> chatBootstrap({
    required String actorProfile,
  }) async {
    final response = await getWithFallback(
      paths: const ['/chat/bootstrap'],
      query: {'actor_profile': actorProfile},
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    final contacts = (body['contacts'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => ChatContact.fromJson(Map<String, dynamic>.from(row)))
        .toList();

    final conversations = (body['conversations'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => ChatConversation.fromJson(Map<String, dynamic>.from(row)))
        .toList();

    final packs = (body['sticker_packs'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => StickerPack.fromJson(Map<String, dynamic>.from(row)))
        .toList();

    return ChatBootstrapSnapshot(
      contacts: contacts,
      groupConversationKey:
          (body['group'] as Map?)?['conversation_key']?.toString() ??
              'group:common',
      conversations: conversations,
      stickerPacks: packs,
    );
  }

  @override
  Future<PhoneProfileSession> deviceStart({
    required String phone,
    required String deviceId,
    String displayName = '',
  }) async {
    final response = await postWithFallback(
      paths: const ['/auth/device-start'],
      body: jsonEncode({
        'phone': phone,
        'device_id': deviceId,
        'display_name': displayName,
        'platform': 'android',
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final user = Map<String, dynamic>.from((body['user'] as Map?) ?? const {});
    final members = (body['family_members'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => ChatContact.fromJson(Map<String, dynamic>.from(row)))
        .toList();
    return PhoneProfileSession(
      profileKey: (user['profile_key'] ?? '').toString(),
      phone: (user['phone'] ?? '').toString(),
      displayName: (user['display_name'] ?? '').toString(),
      deviceId: (user['device_id'] ?? deviceId).toString(),
      familyMembers: members,
    );
  }

  @override
  Future<List<ChatContact>> resolveContacts({
    required String actorProfile,
    required List<String> phones,
  }) async {
    final response = await postWithFallback(
      paths: const ['/contacts/resolve'],
      body: jsonEncode({'actor_profile': actorProfile, 'phones': phones}),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['contacts'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => ChatContact.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  @override
  Future<List<ChatContact>> familyMembers({
    required String actorProfile,
  }) async {
    final response = await getWithFallback(
      paths: const ['/family/members'],
      query: {'actor_profile': actorProfile},
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['members'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => ChatContact.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  @override
  Future<List<ChatContact>> addFamilyMembers({
    required String actorProfile,
    required List<String> profiles,
  }) async {
    final response = await postWithFallback(
      paths: const ['/family/members/add'],
      body: jsonEncode({'actor_profile': actorProfile, 'profiles': profiles}),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['members'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => ChatContact.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  @override
  Future<ChatMessagesSnapshot> chatFetchMessages({
    required String actorProfile,
    required String conversationKey,
    String? cursor,
    int limit = 50,
  }) async {
    final query = <String, String>{
      'actor_profile': actorProfile,
      'conversation_key': conversationKey,
      'limit': limit.toString(),
    };
    if (cursor != null && cursor.isNotEmpty) {
      query['cursor'] = cursor;
    }

    final response = await getWithFallback(
      paths: const ['/chat/messages'],
      query: query,
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    final messages = (body['messages'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => ChatMessage.fromJson(Map<String, dynamic>.from(row)))
        .toList();

    final nextCursor = body['next_cursor']?.toString();
    final typingProfiles = (body['typing_profiles'] as List? ?? const [])
        .map((item) => item.toString())
        .where((item) => item.trim().isNotEmpty)
        .toList();
    return ChatMessagesSnapshot(
      messages: messages,
      nextCursor: nextCursor,
      typingProfiles: typingProfiles,
    );
  }

  @override
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
  }) async {
    final payload = {
      'actor_profile': actorProfile,
      'conversation_key': conversationKey,
      'message_type': messageType,
      'text': text,
      if (stickerId != null && stickerId.isNotEmpty) 'sticker_id': stickerId,
      if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
      if (imageMeta != null) 'image_meta': imageMeta,
      if (attachments.isNotEmpty)
        'attachments': attachments.map((item) => item.toJson()).toList(),
      if (clientMessageId != null && clientMessageId.isNotEmpty)
        'client_message_id': clientMessageId,
    };

    final response = await postWithFallback(
      paths: const ['/chat/messages/send'],
      body: jsonEncode(payload),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return ChatMessage.fromJson(
      Map<String, dynamic>.from((body['message'] as Map?) ?? const {}),
    );
  }

  @override
  Future<ChatConversation> chatCreateGroup({
    required String actorProfile,
    required String title,
    required List<String> memberProfiles,
  }) async {
    final response = await postWithFallback(
      paths: const ['/chat/conversations'],
      body: jsonEncode({
        'actor_profile': actorProfile,
        'title': title,
        'member_profiles': memberProfiles,
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return ChatConversation.fromJson(
      Map<String, dynamic>.from((body['conversation'] as Map?) ?? const {}),
    );
  }

  @override
  Future<ChatMessage> chatSetReaction({
    required String actorProfile,
    required String messageId,
    required String reaction,
  }) async {
    final response = await postWithFallback(
      paths: const ['/chat/messages/reaction'],
      body: jsonEncode({
        'actor_profile': actorProfile,
        'message_id': messageId,
        'reaction': reaction,
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return ChatMessage.fromJson(
      Map<String, dynamic>.from((body['message'] as Map?) ?? const {}),
    );
  }

  @override
  Future<ChatMessage> chatEditMessage({
    required String actorProfile,
    required String messageId,
    required String text,
  }) async {
    final response = await postWithFallback(
      paths: const ['/chat/messages/edit'],
      body: jsonEncode({
        'actor_profile': actorProfile,
        'message_id': messageId,
        'text': text,
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return ChatMessage.fromJson(
      Map<String, dynamic>.from((body['message'] as Map?) ?? const {}),
    );
  }

  @override
  Future<ChatMessage> chatDeleteMessage({
    required String actorProfile,
    required String messageId,
  }) async {
    final response = await postWithFallback(
      paths: const ['/chat/messages/delete'],
      body: jsonEncode({
        'actor_profile': actorProfile,
        'message_id': messageId,
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return ChatMessage.fromJson(
      Map<String, dynamic>.from((body['message'] as Map?) ?? const {}),
    );
  }

  @override
  Future<ChatUploadResult> chatUploadSticker({
    required String actorProfile,
    required List<int> bytes,
    String filename = 'sticker.png',
  }) async {
    return chatUploadMedia(
      actorProfile: actorProfile,
      bytes: bytes,
      filename: filename,
    );
  }

  @override
  Future<ChatUploadResult> chatUploadMedia({
    required String actorProfile,
    required List<int> bytes,
    required String filename,
    void Function(double progress)? onProgress,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/chat/stickers/upload'),
    );
    request.headers['X-Api-Key'] = apiKey;
    request.fields['actor_profile'] = actorProfile;
    request.files.add(
      http.MultipartFile.fromBytes('image', bytes, filename: filename),
    );

    final streamedResponse = await request.send();
    final totalBytes = streamedResponse.contentLength ?? bytes.length;
    var receivedBytes = 0;
    final chunks = <int>[];

    await for (final chunk in streamedResponse.stream) {
      chunks.addAll(chunk);
      receivedBytes += chunk.length;
      if (onProgress != null && totalBytes > 0) {
        onProgress((receivedBytes / totalBytes).clamp(0.0, 1.0));
      }
    }

    final text = utf8.decode(chunks);
    if (streamedResponse.statusCode < 200 ||
        streamedResponse.statusCode >= 300) {
      throw StateError('Upload failed: ${streamedResponse.statusCode} $text');
    }

    final body = jsonDecode(text) as Map<String, dynamic>;
    return ChatUploadResult(
      assetUrl: (body['asset_url'] ?? '').toString(),
      imageMeta:
          (body['image_meta'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  @override
  Future<ChatUploadResult> chatUploadDocument({
    required String actorProfile,
    required List<int> bytes,
    required String filename,
    void Function(double progress)? onProgress,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/chat/documents/upload'),
    );
    request.headers['X-Api-Key'] = apiKey;
    request.fields['actor_profile'] = actorProfile;
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );

    final streamedResponse = await request.send();
    final totalBytes = streamedResponse.contentLength ?? bytes.length;
    var receivedBytes = 0;
    final chunks = <int>[];

    await for (final chunk in streamedResponse.stream) {
      chunks.addAll(chunk);
      receivedBytes += chunk.length;
      if (onProgress != null && totalBytes > 0) {
        onProgress((receivedBytes / totalBytes).clamp(0.0, 1.0));
      }
    }

    final text = utf8.decode(chunks);
    if (streamedResponse.statusCode < 200 ||
        streamedResponse.statusCode >= 300) {
      throw StateError(
          'Document upload failed: ${streamedResponse.statusCode} $text');
    }

    final body = jsonDecode(text) as Map<String, dynamic>;
    return ChatUploadResult(
      assetUrl: (body['asset_url'] ?? '').toString(),
      imageMeta:
          (body['image_meta'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  @override
  Future<String> uploadProfileAvatar({
    required String actorProfile,
    required List<int> bytes,
    String filename = 'avatar.jpg',
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/profile/avatar'),
    );
    request.headers['X-Api-Key'] = apiKey;
    request.fields['actor_profile'] = actorProfile;
    request.files.add(
      http.MultipartFile.fromBytes('image', bytes, filename: filename),
    );

    final response = await http.Response.fromStream(await request.send());
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
          'Avatar upload failed: ${response.statusCode} ${response.body}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return ((body['user'] as Map?)?['avatar_url'] ?? '').toString();
  }

  @override
  Future<void> addGroupMember({
    required String actorProfile,
    required String conversationKey,
    required String profile,
  }) async {
    await postWithFallback(
      paths: const ['/chat/conversations/members/add'],
      body: jsonEncode({
        'actor_profile': actorProfile,
        'conversation_key': conversationKey,
        'profile': profile,
      }),
    );
  }

  @override
  Future<void> removeGroupMember({
    required String actorProfile,
    required String conversationKey,
    required String profile,
  }) async {
    await postWithFallback(
      paths: const ['/chat/conversations/members/remove'],
      body: jsonEncode({
        'actor_profile': actorProfile,
        'conversation_key': conversationKey,
        'profile': profile,
      }),
    );
  }

  @override
  Future<void> renameGroup({
    required String actorProfile,
    required String conversationKey,
    required String title,
  }) async {
    await postWithFallback(
      paths: const ['/chat/conversations/rename'],
      body: jsonEncode({
        'actor_profile': actorProfile,
        'conversation_key': conversationKey,
        'title': title,
      }),
    );
  }

  @override
  Future<void> setGroupAvatar({
    required String actorProfile,
    required String conversationKey,
    required String avatarUrl,
  }) async {
    await postWithFallback(
      paths: const ['/chat/conversations/avatar'],
      body: jsonEncode({
        'actor_profile': actorProfile,
        'conversation_key': conversationKey,
        'avatar_url': avatarUrl,
      }),
    );
  }

  @override
  Future<void> deleteGroup({
    required String actorProfile,
    required String conversationKey,
  }) async {
    await postWithFallback(
      paths: const ['/chat/conversations/delete'],
      body: jsonEncode({
        'actor_profile': actorProfile,
        'conversation_key': conversationKey,
      }),
    );
  }

  @override
  Future<void> chatSendTyping({
    required String actorProfile,
    required String conversationKey,
  }) async {
    await postWithFallback(
      paths: const ['/chat/typing'],
      body: jsonEncode({
        'actor_profile': actorProfile,
        'conversation_key': conversationKey,
      }),
    );
  }

  @override
  Future<void> chatMarkRead({
    required String actorProfile,
    required String conversationKey,
  }) async {
    await postWithFallback(
      paths: const ['/chat/conversations/read'],
      body: jsonEncode({
        'actor_profile': actorProfile,
        'conversation_key': conversationKey,
      }),
    );
  }

  @override
  Future<List<StickerPack>> chatStickerPacks() async {
    final response =
        await getWithFallback(paths: const ['/chat/stickers/packs']);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['sticker_packs'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => StickerPack.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }
}