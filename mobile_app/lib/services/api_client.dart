import 'dart:convert';

import 'package:http/http.dart' as http;

// ignore_for_file: annotate_overrides

import '../contracts/call_api.dart';
import '../contracts/chat_api.dart';
import '../contracts/sync_api.dart';
import '../models/call_models.dart';
import '../models/chat_models.dart';
import '../models/chat_snapshots.dart';
import '../models/device_snapshots.dart';
import '../models/pending_event.dart';
import '../models/sync_snapshots.dart';
import '../models/task_item.dart';

// Re-export for backward compatibility — consumers that import
// api_client.dart still see these types.
export '../models/chat_snapshots.dart';
export '../models/device_snapshots.dart';
export '../models/sync_snapshots.dart';

class ApiClient implements SyncApi, ChatApi, CallApi {
  ApiClient({required this.baseUrl, required this.apiKey});

  final String baseUrl;
  final String apiKey;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-Api-Key': apiKey,
      };

  Future<http.Response> _postWithFallback({
    required List<String> paths,
    required String body,
  }) async {
    Object? lastError;
    for (final path in paths) {
      final uri = Uri.parse('$baseUrl$path');
      try {
        final response = await http.post(uri, headers: _headers, body: body);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response;
        }
        lastError = StateError(
          'POST failed: ${response.statusCode} ${response.body}',
        );
      } catch (err) {
        lastError = err;
      }
    }
    throw StateError('Unable to complete POST request: $lastError');
  }

  Future<http.Response> _getWithFallback({
    required List<String> paths,
    Map<String, String>? query,
  }) async {
    Object? lastError;
    for (final path in paths) {
      final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
      try {
        final response = await http.get(uri, headers: _headers);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response;
        }
        lastError = StateError(
          'GET failed: ${response.statusCode} ${response.body}',
        );
      } catch (err) {
        lastError = err;
      }
    }
    throw StateError('Unable to complete GET request: $lastError');
  }

  Future<void> push({
    required String actorProfile,
    required List<PendingEvent> events,
    String source = 'mobile',
  }) async {
    if (events.isEmpty) {
      return;
    }
    final payload = {
      'actor_profile': actorProfile,
      'source': source,
      'events': events.map((e) {
        return {
          'event_id': e.eventId,
          'entity': e.entity,
          'action': e.action,
          'payload': jsonDecode(e.payloadJson),
          'happened_at': e.happenedAt,
        };
      }).toList(),
    };
    await _postWithFallback(
      paths: const [
        '/sync_push.php',
        '/sync_push.php/',
        '/sync/push/',
        '/sync/push',
      ],
      body: jsonEncode(payload),
    );
  }

  Future<PullSnapshot> pull({
    required String since,
    bool changesMode = false,
    String? cursor,
  }) async {
    final query = <String, String>{'since': since};
    if (changesMode) {
      query['mode'] = 'changes';
      query['cursor'] = (cursor == null || cursor.isEmpty) ? since : cursor;
    }
    if (_actorProfileForPull.isNotEmpty) {
      query['actor_profile'] = _actorProfileForPull;
    }
    final paths = changesMode
        ? const [
            '/sync_changes.php',
            '/sync_changes.php/',
            '/sync_pull.php',
            '/sync_pull.php/',
            '/sync/changes/',
            '/sync/changes',
            '/sync/pull/',
            '/sync/pull',
          ]
        : const [
            '/sync_pull.php',
            '/sync_pull.php/',
            '/sync/pull/',
            '/sync/pull',
          ];
    final response = await _getWithFallback(
      paths: paths,
      query: query,
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final tasks = (body['tasks'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => TaskItem.fromJson(Map<String, dynamic>.from(row)))
        .toList();
    final familyTasks =
        (body['family_tasks'] as List? ?? const []).whereType<Map>().map((row) {
      final source = Map<String, dynamic>.from(row);
      source['owner_key'] = 'family';
      source['is_family'] = true;
      return TaskItem.fromJson(source);
    }).toList();
    final serverTime =
        (body['server_time'] ?? DateTime.now().toIso8601String()).toString();
    final nextCursor = (body['next_cursor'] ?? serverTime).toString();
    final mode = (body['mode'] ?? '').toString();
    return PullSnapshot(
      tasks: tasks,
      familyTasks: familyTasks,
      serverTime: serverTime,
      nextCursor: nextCursor,
      isDelta: mode == 'changes' || changesMode,
    );
  }

  String _actorProfileForPull = '';

  void setActorProfileForPull(String actorProfile) {
    _actorProfileForPull = actorProfile.trim();
  }

  Future<DeviceTokenRegistration> registerDeviceToken({
    required String actorProfile,
    required String token,
    required String platform,
    required String appVersion,
    String? deviceId,
    String playServices = 'unknown',
    String tokenStatus = 'active',
    String lastError = '',
  }) async {
    final payload = {
      'actor_profile': actorProfile,
      'token': token,
      'platform': platform,
      'app_version': appVersion,
      'play_services': playServices,
      'token_status': tokenStatus,
      'last_error': lastError,
      if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
    };
    final response = await _postWithFallback(
      paths: const [
        '/devices_register.php',
        '/devices_register.php/',
        '/devices/register/',
        '/devices/register',
      ],
      body: jsonEncode(payload),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return DeviceTokenRegistration(
      shouldResetToken: body['should_reset_token'] == true,
      previousTokenStatus: (body['previous_token_status'] ?? '').toString(),
    );
  }

  Future<void> reportDeviceStatus({
    required String actorProfile,
    required String platform,
    required String appVersion,
    required String tokenStatus,
    required String playServices,
    String? token,
    String? deviceId,
    String? lastError,
  }) async {
    final payload = {
      'actor_profile': actorProfile,
      'platform': platform,
      'app_version': appVersion,
      'token_status': tokenStatus,
      'play_services': playServices,
      'last_error': lastError ?? '',
      if (token != null && token.isNotEmpty) 'token': token,
      if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
    };
    await _postWithFallback(
      paths: const [
        '/devices_status.php',
        '/devices_status.php/',
        '/devices/status/',
        '/devices/status',
      ],
      body: jsonEncode(payload),
    );
  }

  Future<PushDeviceStatus> pushDeviceStatus({
    required String actorProfile,
  }) async {
    final response = await _getWithFallback(
      paths: const ['/push/device_status', '/push_device_status.php'],
      query: {'actor_profile': actorProfile},
    );
    return PushDeviceStatus.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> unregisterDeviceToken({
    required String actorProfile,
    required String token,
  }) async {
    final payload = {'actor_profile': actorProfile, 'token': token};
    await _postWithFallback(
      paths: const [
        '/devices_unregister.php',
        '/devices_unregister.php/',
        '/devices/unregister/',
        '/devices/unregister',
      ],
      body: jsonEncode(payload),
    );
  }

  Future<ChatBootstrapSnapshot> chatBootstrap({
    required String actorProfile,
  }) async {
    final response = await _getWithFallback(
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

  Future<PhoneProfileSession> deviceStart({
    required String phone,
    required String deviceId,
    String displayName = '',
  }) async {
    final response = await _postWithFallback(
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

  Future<List<ChatContact>> resolveContacts({
    required String actorProfile,
    required List<String> phones,
  }) async {
    final response = await _postWithFallback(
      paths: const ['/contacts/resolve'],
      body: jsonEncode({'actor_profile': actorProfile, 'phones': phones}),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['contacts'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => ChatContact.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<List<ChatContact>> familyMembers({
    required String actorProfile,
  }) async {
    final response = await _getWithFallback(
      paths: const ['/family/members'],
      query: {'actor_profile': actorProfile},
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['members'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => ChatContact.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<List<ChatContact>> addFamilyMembers({
    required String actorProfile,
    required List<String> profiles,
  }) async {
    final response = await _postWithFallback(
      paths: const ['/family/members/add'],
      body: jsonEncode({'actor_profile': actorProfile, 'profiles': profiles}),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['members'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => ChatContact.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

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

    final response = await _getWithFallback(
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

    final response = await _postWithFallback(
      paths: const ['/chat/messages/send'],
      body: jsonEncode(payload),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return ChatMessage.fromJson(
      Map<String, dynamic>.from((body['message'] as Map?) ?? const {}),
    );
  }

  Future<ChatConversation> chatCreateGroup({
    required String actorProfile,
    required String title,
    required List<String> memberProfiles,
  }) async {
    final response = await _postWithFallback(
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

  Future<ChatMessage> chatSetReaction({
    required String actorProfile,
    required String messageId,
    required String reaction,
  }) async {
    final response = await _postWithFallback(
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

  Future<ChatMessage> chatEditMessage({
    required String actorProfile,
    required String messageId,
    required String text,
  }) async {
    final response = await _postWithFallback(
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

  Future<ChatMessage> chatDeleteMessage({
    required String actorProfile,
    required String messageId,
  }) async {
    final response = await _postWithFallback(
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
      throw StateError('Document upload failed: ${streamedResponse.statusCode} $text');
    }

    final body = jsonDecode(text) as Map<String, dynamic>;
    return ChatUploadResult(
      assetUrl: (body['asset_url'] ?? '').toString(),
      imageMeta:
          (body['image_meta'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

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

  Future<void> addGroupMember({
    required String actorProfile,
    required String conversationKey,
    required String profile,
  }) async {
    await _postWithFallback(
      paths: const ['/chat/conversations/members/add'],
      body: jsonEncode({
        'actor_profile': actorProfile,
        'conversation_key': conversationKey,
        'profile': profile,
      }),
    );
  }

  Future<void> removeGroupMember({
    required String actorProfile,
    required String conversationKey,
    required String profile,
  }) async {
    await _postWithFallback(
      paths: const ['/chat/conversations/members/remove'],
      body: jsonEncode({
        'actor_profile': actorProfile,
        'conversation_key': conversationKey,
        'profile': profile,
      }),
    );
  }

  Future<void> renameGroup({
    required String actorProfile,
    required String conversationKey,
    required String title,
  }) async {
    await _postWithFallback(
      paths: const ['/chat/conversations/rename'],
      body: jsonEncode({
        'actor_profile': actorProfile,
        'conversation_key': conversationKey,
        'title': title,
      }),
    );
  }

  Future<void> setGroupAvatar({
    required String actorProfile,
    required String conversationKey,
    required String avatarUrl,
  }) async {
    await _postWithFallback(
      paths: const ['/chat/conversations/avatar'],
      body: jsonEncode({
        'actor_profile': actorProfile,
        'conversation_key': conversationKey,
        'avatar_url': avatarUrl,
      }),
    );
  }

  Future<void> deleteGroup({
    required String actorProfile,
    required String conversationKey,
  }) async {
    await _postWithFallback(
      paths: const ['/chat/conversations/delete'],
      body: jsonEncode({
        'actor_profile': actorProfile,
        'conversation_key': conversationKey,
      }),
    );
  }

  Future<void> chatSendTyping({
    required String actorProfile,
    required String conversationKey,
  }) async {
    await _postWithFallback(
      paths: const ['/chat/typing'],
      body: jsonEncode({
        'actor_profile': actorProfile,
        'conversation_key': conversationKey,
      }),
    );
  }

  Future<void> chatMarkRead({
    required String actorProfile,
    required String conversationKey,
  }) async {
    await _postWithFallback(
      paths: const ['/chat/conversations/read'],
      body: jsonEncode({
        'actor_profile': actorProfile,
        'conversation_key': conversationKey,
      }),
    );
  }

  Future<List<StickerPack>> chatStickerPacks() async {
    final response =
        await _getWithFallback(paths: const ['/chat/stickers/packs']);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['sticker_packs'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => StickerPack.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  // ---- Call (audio/video) ----

  Future<CallSession> callInitiate({
    required String actorProfile,
    required String conversationKey,
    String callType = 'audio',
    String? calleeProfile,
  }) async {
    final response = await _postWithFallback(
      paths: const ['/call/initiate'],
      body: jsonEncode({
        'actor_profile': actorProfile,
        'conversation_key': conversationKey,
        'call_type': callType,
        if (calleeProfile != null) 'callee_profile': calleeProfile,
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return CallSession.fromJson(
      Map<String, dynamic>.from((body['session'] as Map?) ?? const {}),
    );
  }

  Future<CallSession> callAccept({
    required String actorProfile,
    required String sessionId,
  }) async {
    final response = await _postWithFallback(
      paths: const ['/call/accept'],
      body: jsonEncode({
        'actor_profile': actorProfile,
        'session_id': sessionId,
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return CallSession.fromJson(
      Map<String, dynamic>.from((body['session'] as Map?) ?? const {}),
    );
  }

  Future<CallSession> callReject({
    required String actorProfile,
    required String sessionId,
  }) async {
    final response = await _postWithFallback(
      paths: const ['/call/reject'],
      body: jsonEncode({
        'actor_profile': actorProfile,
        'session_id': sessionId,
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return CallSession.fromJson(
      Map<String, dynamic>.from((body['session'] as Map?) ?? const {}),
    );
  }

  Future<CallSession> callEnd({
    required String actorProfile,
    required String sessionId,
  }) async {
    final response = await _postWithFallback(
      paths: const ['/call/end'],
      body: jsonEncode({
        'actor_profile': actorProfile,
        'session_id': sessionId,
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return CallSession.fromJson(
      Map<String, dynamic>.from((body['session'] as Map?) ?? const {}),
    );
  }

  Future<void> callSignal({
    required String actorProfile,
    required String sessionId,
    required String signalType,
    dynamic sdp,
    dynamic candidate,
  }) async {
    await _postWithFallback(
      paths: const ['/call/signal'],
      body: jsonEncode({
        'actor_profile': actorProfile,
        'session_id': sessionId,
        'signal_type': signalType,
        if (sdp != null) 'sdp': sdp is String ? sdp : jsonEncode(sdp),
        if (candidate != null)
          'candidate': candidate is String ? candidate : jsonEncode(candidate),
      }),
    );
  }

  Future<CallSignalsPoll> callPollSignals({
    required String actorProfile,
    required String sessionId,
    String? cursor,
  }) async {
    final query = <String, String>{
      'actor_profile': actorProfile,
      'session_id': sessionId,
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };
    final response = await _getWithFallback(
      paths: const ['/call/signals'],
      query: query,
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final signals = (body['signals'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => CallSignal.fromJson(Map<String, dynamic>.from(row)))
        .toList();
    return CallSignalsPoll(
      signals: signals,
      cursor: (body['cursor'] ?? '0').toString(),
      sessionStatus: (body['session_status'] ?? 'ringing').toString(),
    );
  }

  Future<CallSession?> callCheckIncoming({
    required String actorProfile,
  }) async {
    final response = await _getWithFallback(
      paths: const ['/call/incoming'],
      query: {'actor_profile': actorProfile},
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final incoming = body['incoming_call'];
    if (incoming == null) return null;
    return CallSession.fromJson(Map<String, dynamic>.from(incoming as Map));
  }
}
