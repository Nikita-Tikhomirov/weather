import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/pending_event.dart';
import '../models/task_item.dart';

class PullSnapshot {
  PullSnapshot({
    required this.tasks,
    required this.familyTasks,
    required this.serverTime,
  });

  final List<TaskItem> tasks;
  final List<TaskItem> familyTasks;
  final String serverTime;
}

class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this.apiKey,
  });

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
        lastError = StateError('post failed: ${response.statusCode} ${response.body}');
      } catch (err) {
        lastError = err;
      }
    }
    throw StateError('$lastError');
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
        lastError = StateError('get failed: ${response.statusCode} ${response.body}');
      } catch (err) {
        lastError = err;
      }
    }
    throw StateError('$lastError');
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

  Future<PullSnapshot> pull({required String since}) async {
    final query = <String, String>{'since': since};
    if (_actorProfileForPull.isNotEmpty) {
      query['actor_profile'] = _actorProfileForPull;
    }
    final response = await _getWithFallback(
      paths: const ['/sync_pull.php', '/sync/pull'],
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
    final serverTime = (body['server_time'] ?? DateTime.now().toIso8601String()).toString();
    return PullSnapshot(tasks: tasks, familyTasks: familyTasks, serverTime: serverTime);
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
    final payload = {
      'actor_profile': actorProfile,
      'token': token,
    };
    await _postWithFallback(
      paths: const ['/devices_unregister.php', '/devices/unregister'],
      body: jsonEncode(payload),
    );
  }
}
