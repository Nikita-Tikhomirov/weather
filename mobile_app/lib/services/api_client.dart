import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/pending_event.dart';
import '../models/task_item.dart';

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

  Future<void> push({
    required String actorProfile,
    required List<PendingEvent> events,
    String source = 'mobile',
  }) async {
    if (events.isEmpty) {
      return;
    }
    final uri = Uri.parse('$baseUrl/sync/push');
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
    final response = await http.post(uri, headers: _headers, body: jsonEncode(payload));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('push failed: ${response.statusCode} ${response.body}');
    }
  }

  Future<(List<TaskItem>, String)> pull({required String since}) async {
    final uri = Uri.parse('$baseUrl/sync/pull?since=$since');
    final response = await http.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('pull failed: ${response.statusCode} ${response.body}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final tasksRaw = body['tasks'] as List? ?? const [];
    final tasks = tasksRaw
        .whereType<Map>()
        .map((row) => TaskItem.fromJson(Map<String, dynamic>.from(row)))
        .toList();
    final serverTime = (body['server_time'] ?? DateTime.now().toIso8601String()).toString();
    return (tasks, serverTime);
  }
}

