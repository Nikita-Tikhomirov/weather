import 'dart:convert';

import 'package:http/http.dart' as http;

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
          'Ошибка POST: ${response.statusCode} ${response.body}',
        );
      } catch (err) {
        lastError = err;
      }
    }
    throw StateError('Не удалось выполнить POST-запрос: $lastError');
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
          'Ошибка GET: ${response.statusCode} ${response.body}',
        );
      } catch (err) {
        lastError = err;
      }
    }
    throw StateError('Не удалось выполнить GET-запрос: $lastError');
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
      paths: const ['/sync_push.php', '/sync/push'],
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
        ? const ['/sync_changes.php', '/sync/changes', '/sync_pull.php', '/sync/pull']
        : const ['/sync_pull.php', '/sync/pull'];
    final response = await _getWithFallback(
      paths: paths,
      query: query,
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final tasks = (body['tasks'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => TaskItem.fromJson(Map<String, dynamic>.from(row)))
        .toList();
    final familyTasks = (body['family_tasks'] as List? ?? const [])
        .whereType<Map>()
        .map((row) {
          final source = Map<String, dynamic>.from(row);
          source['owner_key'] = 'family';
          source['is_family'] = true;
          return TaskItem.fromJson(source);
        })
        .toList();
    final serverTime = (body['server_time'] ?? DateTime.now().toIso8601String())
        .toString();
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
  }) async {
    final payload = {
      'actor_profile': actorProfile,
      'token': token,
      'platform': platform,
      'app_version': appVersion,
      if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
    };
    await _postWithFallback(
      paths: const ['/devices_register.php', '/devices/register'],
      body: jsonEncode(payload),
    );
  }

  Future<void> unregisterDeviceToken({
    required String actorProfile,
    required String token,
  }) async {
    final payload = {'actor_profile': actorProfile, 'token': token};
    await _postWithFallback(
      paths: const ['/devices_unregister.php', '/devices/unregister'],
      body: jsonEncode(payload),
    );
  }
}
