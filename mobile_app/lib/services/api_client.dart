import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_models.dart';
import '../models/pending_event.dart';
import '../models/task_item.dart';

class PullSnapshot {
  PullSnapshot({
    required this.tasks,
    required this.familyTasks,
    required this.serverTime,
    required this.nextCursor,
    required this.isDelta,
  });

  final List<TaskItem> tasks;
  final List<TaskItem> familyTasks;
  final String serverTime;
  final String nextCursor;
  final bool isDelta;
}

class ChatBootstrapSnapshot {
  ChatBootstrapSnapshot({
    required this.contacts,
    required this.groupConversationKey,
    required this.conversations,
    required this.stickerPacks,
  });

  final List<Map<String, String>> contacts;
  final String groupConversationKey;
  final List<ChatConversation> conversations;
  final List<StickerPack> stickerPacks;
}

class ChatMessagesSnapshot {
  ChatMessagesSnapshot({
    required this.messages,
    required this.nextCursor,
  });

  final List<ChatMessage> messages;
  final String? nextCursor;
}

class ChatUploadResult {
  ChatUploadResult({
    required this.assetUrl,
    required this.imageMeta,
  });

  final String assetUrl;
  final Map<String, dynamic> imageMeta;
}

class ApiClient {
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

  Future<void> registerDeviceToken({
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
    await _postWithFallback(
      paths: const [
        '/devices_register.php',
        '/devices_register.php/',
        '/devices/register/',
        '/devices/register',
      ],
      body: jsonEncode(payload),
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
        .map((row) => {
              'profile_key': (row['profile_key'] ?? '').toString(),
              'conversation_key': (row['conversation_key'] ?? '').toString(),
            })
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
    return ChatMessagesSnapshot(messages: messages, nextCursor: nextCursor);
  }

  Future<ChatMessage> chatSendMessage({
    required String actorProfile,
    required String conversationKey,
    required String messageType,
    String text = '',
    String? stickerId,
    String? imageUrl,
    Map<String, dynamic>? imageMeta,
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

  Future<ChatUploadResult> chatUploadSticker({
    required String actorProfile,
    required List<int> bytes,
    String filename = 'sticker.png',
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

    final response = await request.send();
    final text = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Sticker upload failed: ${response.statusCode} $text');
    }

    final body = jsonDecode(text) as Map<String, dynamic>;
    return ChatUploadResult(
      assetUrl: (body['asset_url'] ?? '').toString(),
      imageMeta:
          (body['image_meta'] as Map?)?.cast<String, dynamic>() ?? const {},
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
}
