import 'dart:convert';

import '../contracts/sync_api.dart';
import '../models/agent_policy.dart';
import '../models/device_snapshots.dart';
import '../models/family_group.dart';
import '../models/pending_event.dart';
import '../models/sync_snapshots.dart';
import '../models/task_item.dart';
import '../models/task_project.dart';
import 'http_client_base.dart';

class SyncApiClient extends HttpApiClient implements SyncApi {
  SyncApiClient({required super.baseUrl, required super.apiKey});

  @override
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
    await postWithFallback(
      paths: const [
        '/sync_push.php',
        '/sync_push.php/',
        '/sync/push/',
        '/sync/push',
      ],
      body: jsonEncode(payload),
    );
  }

  @override
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
    final body = await getJsonWithFallback(
      paths: paths,
      query: query,
    );
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
    final projects = (body['projects'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => TaskProject.fromJson(Map<String, dynamic>.from(row)))
        .toList();
    final familyGroups = (body['family_groups'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => FamilyGroup.fromJson(Map<String, dynamic>.from(row)))
        .toList();
    final projectGroupMap = <String, List<String>>{};
    final rawPg = body['project_groups'];
    if (rawPg is Map) {
      for (final entry in rawPg.entries) {
        final pid = entry.key.toString();
        final gids = (entry.value is List)
            ? (entry.value as List).map((v) => v.toString()).toList()
            : <String>[];
        projectGroupMap[pid] = gids;
      }
    }
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
      projects: projects,
      familyGroups: familyGroups,
      projectGroupMap: projectGroupMap,
    );
  }

  String _actorProfileForPull = '';

  @override
  void setActorProfileForPull(String actorProfile) {
    _actorProfileForPull = actorProfile.trim();
  }

  @override
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
    final body = await postJsonWithFallback(
      paths: const [
        '/devices_register.php',
        '/devices_register.php/',
        '/devices/register/',
        '/devices/register',
      ],
      body: jsonEncode(payload),
    );
    return DeviceTokenRegistration(
      shouldResetToken: body['should_reset_token'] == true,
      previousTokenStatus: (body['previous_token_status'] ?? '').toString(),
    );
  }

  @override
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
    await postWithFallback(
      paths: const [
        '/devices_status.php',
        '/devices_status.php/',
        '/devices/status/',
        '/devices/status',
      ],
      body: jsonEncode(payload),
    );
  }

  @override
  Future<PushDeviceStatus> pushDeviceStatus({
    required String actorProfile,
  }) async {
    final body = await getJsonWithFallback(
      paths: const ['/push/device_status', '/push_device_status.php'],
      query: {'actor_profile': actorProfile},
    );
    return PushDeviceStatus.fromJson(body);
  }

  Future<UserAccessPolicy> fetchAccessPolicy({
    String actorProfile = '',
    String phone = '',
  }) async {
    final body = await getJsonWithFallback(
      paths: const ['/me/access', '/me/access/'],
      query: {
        if (actorProfile.trim().isNotEmpty) 'actor_profile': actorProfile,
        if (phone.trim().isNotEmpty) 'phone': phone,
      },
    );
    final raw = body['access'];
    return raw is Map
        ? UserAccessPolicy.fromJson(Map<String, dynamic>.from(raw))
        : const UserAccessPolicy.messengerOnly();
  }

  Future<AgentRunPolicy> requestAgentPolicy({
    required String actorProfile,
    String actorPhone = '',
    required String taskId,
    required String taskType,
    required String workspaceId,
    String requestedMode = '',
    String sessionId = '',
  }) async {
    final body = await postJsonWithFallback(
      paths: const ['/agent/policy', '/agent/policy/'],
      body: jsonEncode(
        _agentPayload(
          actorProfile: actorProfile,
          actorPhone: actorPhone,
          taskId: taskId,
          taskType: taskType,
          workspaceId: workspaceId,
          requestedMode: requestedMode,
          sessionId: sessionId,
        ),
      ),
    );
    final raw = body['policy'];
    return raw is Map
        ? AgentRunPolicy.fromJson(Map<String, dynamic>.from(raw))
        : const AgentRunPolicy.unavailable();
  }

  Future<AgentTicketResult> requestAgentTicket({
    required String actorProfile,
    String actorPhone = '',
    required String taskId,
    required String taskType,
    required String workspaceId,
    String requestedMode = '',
    String sessionId = '',
  }) async {
    final body = await postJsonWithFallback(
      paths: const ['/agent/ticket', '/agent/ticket/'],
      body: jsonEncode(
        _agentPayload(
          actorProfile: actorProfile,
          actorPhone: actorPhone,
          taskId: taskId,
          taskType: taskType,
          workspaceId: workspaceId,
          requestedMode: requestedMode,
          sessionId: sessionId,
        ),
      ),
    );
    return AgentTicketResult.fromJson(body);
  }

  Future<AgentContextPack> fetchAgentContext({
    required String actorProfile,
    String actorPhone = '',
    required String taskId,
    required String workspaceId,
    String taskType = 'feature',
    String requestedMode = '',
  }) async {
    final body = await postJsonWithFallback(
      paths: const ['/agent/context', '/agent/context/'],
      body: jsonEncode(
        _agentPayload(
          actorProfile: actorProfile,
          actorPhone: actorPhone,
          taskId: taskId,
          taskType: taskType,
          workspaceId: workspaceId,
          requestedMode: requestedMode,
        ),
      ),
    );
    final raw = body['context'];
    return raw is Map
        ? AgentContextPack.fromJson(Map<String, dynamic>.from(raw))
        : AgentContextPack.fromJson(const {});
  }

  Future<void> recordAgentSession({
    required String actorProfile,
    String actorPhone = '',
    required String taskId,
    required String workspaceId,
    required String agentSessionId,
    String sessionId = '',
    String title = '',
    String taskType = 'feature',
    String requestedMode = '',
    String status = 'pending',
  }) async {
    await postWithFallback(
      paths: const ['/agent/sessions', '/agent/sessions/'],
      body: jsonEncode({
        ..._agentPayload(
          actorProfile: actorProfile,
          actorPhone: actorPhone,
          taskId: taskId,
          taskType: taskType,
          workspaceId: workspaceId,
          requestedMode: requestedMode,
          sessionId: sessionId,
        ),
        'agent_session_id': agentSessionId,
        'title': title,
        'status': status,
      }),
    );
  }

  Future<void> recordAgentEvent({
    required String actorProfile,
    String actorPhone = '',
    required String taskId,
    required String workspaceId,
    required String agentSessionId,
    required String eventType,
    Map<String, dynamic> payload = const {},
    String taskType = 'feature',
    String requestedMode = '',
  }) async {
    await postWithFallback(
      paths: const ['/agent/events', '/agent/events/'],
      body: jsonEncode({
        ..._agentPayload(
          actorProfile: actorProfile,
          actorPhone: actorPhone,
          taskId: taskId,
          taskType: taskType,
          workspaceId: workspaceId,
          requestedMode: requestedMode,
        ),
        'agent_session_id': agentSessionId,
        'event_type': eventType,
        'payload': payload,
      }),
    );
  }

  Future<List<WorkspaceAccessGrant>> listWorkspaceAccess({
    required String actorProfile,
    String actorPhone = '',
    String workspaceId = '',
  }) async {
    final body = await getJsonWithFallback(
      paths: const ['/admin/workspace-access', '/admin/workspace-access/'],
      query: {
        'actor_profile': actorProfile,
        if (actorPhone.trim().isNotEmpty) 'phone': actorPhone,
        if (workspaceId.trim().isNotEmpty) 'workspace_id': workspaceId,
      },
    );
    return (body['access'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map(
          (row) => WorkspaceAccessGrant.fromJson(
            Map<String, dynamic>.from(row),
          ),
        )
        .toList();
  }

  Future<WorkspaceAccessGrant> grantWorkspaceAccess({
    required String actorProfile,
    String actorPhone = '',
    required String profileKey,
    required String workspaceId,
    String role = 'workspace_user',
  }) async {
    final body = await postJsonWithFallback(
      paths: const [
        '/admin/workspace-access/grant',
        '/admin/workspace-access/grant/',
      ],
      body: jsonEncode({
        'actor_profile': actorProfile,
        if (actorPhone.trim().isNotEmpty) 'actor_phone': actorPhone,
        'profile_key': profileKey,
        'workspace_id': workspaceId,
        'role': role,
      }),
    );
    final raw = body['grant'];
    return raw is Map
        ? WorkspaceAccessGrant.fromJson(Map<String, dynamic>.from(raw))
        : WorkspaceAccessGrant(
            workspaceId: workspaceId,
            profileKey: profileKey,
            role: role,
          );
  }

  Future<void> revokeWorkspaceAccess({
    required String actorProfile,
    String actorPhone = '',
    required String profileKey,
    required String workspaceId,
  }) async {
    await postWithFallback(
      paths: const [
        '/admin/workspace-access/revoke',
        '/admin/workspace-access/revoke/',
      ],
      body: jsonEncode({
        'actor_profile': actorProfile,
        if (actorPhone.trim().isNotEmpty) 'actor_phone': actorPhone,
        'profile_key': profileKey,
        'workspace_id': workspaceId,
      }),
    );
  }

  @override
  Future<void> unregisterDeviceToken({
    required String actorProfile,
    required String token,
  }) async {
    final payload = {'actor_profile': actorProfile, 'token': token};
    await postWithFallback(
      paths: const [
        '/devices_unregister.php',
        '/devices_unregister.php/',
        '/devices/unregister/',
        '/devices/unregister',
      ],
      body: jsonEncode(payload),
    );
  }

  // ---- Projects & Family Groups ----

  Future<List<TaskProject>> listProjects({
    required String actorProfile,
  }) async {
    final body = await getJsonWithFallback(
      paths: const ['/projects', '/projects.php'],
      query: {'actor_profile': actorProfile},
    );
    return (body['projects'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => TaskProject.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<TaskProject> createProject({
    required String actorProfile,
    required String name,
    String description = '',
  }) async {
    final body = await postJsonWithFallback(
      paths: const ['/projects/create', '/projects_create.php'],
      body: jsonEncode({
        'actor_profile': actorProfile,
        'name': name,
        'description': description,
      }),
    );
    return TaskProject.fromJson(
      Map<String, dynamic>.from(body['project'] as Map),
    );
  }

  Future<void> updateProject({
    required String actorProfile,
    required String id,
    required String name,
    String description = '',
    List<String>? groupIds,
  }) async {
    await postWithFallback(
      paths: const ['/projects/update', '/projects_update.php'],
      body: jsonEncode({
        'actor_profile': actorProfile,
        'id': id,
        'name': name,
        'description': description,
        if (groupIds != null) 'group_ids': groupIds,
      }),
    );
  }

  Future<void> deleteProject({
    required String actorProfile,
    required String id,
  }) async {
    await postWithFallback(
      paths: const ['/projects/delete', '/projects_delete.php'],
      body: jsonEncode({'actor_profile': actorProfile, 'id': id}),
    );
  }

  Future<void> setProjectGroups({
    required String actorProfile,
    required String projectId,
    required List<String> groupIds,
  }) async {
    await postWithFallback(
      paths: const ['/projects/set-groups', '/projects_set_groups.php'],
      body: jsonEncode({
        'actor_profile': actorProfile,
        'project_id': projectId,
        'group_ids': groupIds,
      }),
    );
  }

  Future<List<FamilyGroup>> listFamilyGroups({
    required String actorProfile,
  }) async {
    final body = await getJsonWithFallback(
      paths: const ['/family-groups', '/family_groups.php'],
      query: {'actor_profile': actorProfile},
    );
    return (body['groups'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => FamilyGroup.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<Map<String, List<String>>> listProjectGroupMap({
    required String actorProfile,
  }) async {
    final body = await getJsonWithFallback(
      paths: const ['/family-groups', '/family_groups.php'],
      query: {'actor_profile': actorProfile},
    );
    return _decodeProjectGroupMap(body['project_groups']);
  }

  Future<FamilyGroup> createFamilyGroup({
    required String actorProfile,
    required String name,
    required List<String> members,
  }) async {
    final body = await postJsonWithFallback(
      paths: const ['/family-groups/create', '/family_groups_create.php'],
      body: jsonEncode({
        'actor_profile': actorProfile,
        'name': name,
        'members': members,
      }),
    );
    return FamilyGroup.fromJson(
      Map<String, dynamic>.from(body['group'] as Map),
    );
  }

  Future<void> updateFamilyGroup({
    required String actorProfile,
    required String id,
    required String name,
    List<String>? members,
  }) async {
    final payload = <String, dynamic>{
      'actor_profile': actorProfile,
      'id': id,
      'name': name,
    };
    if (members != null) {
      payload['members'] = members;
    }
    await postWithFallback(
      paths: const ['/family-groups/update', '/family_groups_update.php'],
      body: jsonEncode(payload),
    );
  }

  Future<void> deleteFamilyGroup({
    required String actorProfile,
    required String id,
  }) async {
    await postWithFallback(
      paths: const ['/family-groups/delete', '/family_groups_delete.php'],
      body: jsonEncode({'actor_profile': actorProfile, 'id': id}),
    );
  }

  Map<String, List<String>> _decodeProjectGroupMap(Object? raw) {
    final projectGroupMap = <String, List<String>>{};
    if (raw is! Map) {
      return projectGroupMap;
    }
    for (final entry in raw.entries) {
      final projectId = entry.key.toString();
      final groupIds = (entry.value is List)
          ? (entry.value as List).map((value) => value.toString()).toList()
          : <String>[];
      projectGroupMap[projectId] = groupIds;
    }
    return projectGroupMap;
  }

  Map<String, dynamic> _agentPayload({
    required String actorProfile,
    String actorPhone = '',
    required String taskId,
    required String taskType,
    required String workspaceId,
    String requestedMode = '',
    String sessionId = '',
  }) {
    return {
      'actor_profile': actorProfile,
      if (actorPhone.trim().isNotEmpty) 'actor_phone': actorPhone,
      'task_id': taskId,
      'task_type': taskType,
      'workspace_id': workspaceId,
      if (requestedMode.trim().isNotEmpty) 'requested_mode': requestedMode,
      if (sessionId.trim().isNotEmpty) 'session_id': sessionId,
    };
  }
}
