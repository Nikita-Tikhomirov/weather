import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:family_todo_mobile/models/agent_policy.dart';
import 'package:family_todo_mobile/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Agent API client', () {
    late HttpServer server;
    late ApiClient client;
    final requests = <Map<String, dynamic>>[];

    setUp(() async {
      requests.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      unawaited(
        server.forEach((request) async {
          final bodyText = await utf8.decoder.bind(request).join();
          final decodedBody = bodyText.trim().isEmpty
              ? <String, dynamic>{}
              : Map<String, dynamic>.from(jsonDecode(bodyText) as Map);
          requests.add({
            'method': request.method,
            'path': request.uri.path,
            'query': request.uri.queryParameters,
            'body': decodedBody,
          });

          Object payload;
          switch (request.uri.path) {
            case '/me/access':
              payload = {
                'ok': true,
                'access': {
                  'phone': '79679812438',
                  'profile_key': 'nik',
                  'roles': ['messenger_user', 'superadmin'],
                  'capabilities': [
                    'messenger.use',
                    'workspaces.use',
                    'tasks.manage_agent',
                    'ai.use',
                    'admin.audit',
                  ],
                  'is_superadmin': true,
                },
              };
              break;
            case '/agent/ticket':
              payload = {
                'ok': true,
                'policy_ticket': 'signed-ticket',
                'policy': {
                  'allowed': true,
                  'mode': 'executor',
                  'mode_label': 'Исполнитель',
                  'workspace_id': 'weather',
                  'task_id': 'task-1',
                  'plugins': ['task_context', 'task_write', 'workspace_write'],
                  'allowed_commands': ['session_create', 'session_send'],
                  'reason': '',
                },
              };
              break;
            case '/agent/context':
              payload = {
                'ok': true,
                'context': {
                  'task': {
                    'id': 'task-1',
                    'title': 'Починить синхронизацию',
                    'workflow_status': 'todo',
                  },
                  'comments': [
                    {'text': 'Падает после push'},
                  ],
                  'checklists': [],
                  'agent_sessions': [],
                },
              };
              break;
            case '/agent/events':
              payload = {
                'ok': true,
                'event': {'type': 'agent_session_started'},
              };
              break;
            case '/admin/workspace-access':
              payload = {
                'ok': true,
                'access': [
                  {
                    'workspace_id': 'weather',
                    'profile_key': 'dev',
                    'role': 'agent_operator',
                    'revoked_at': '',
                  },
                ],
              };
              break;
            case '/admin/workspace-access/grant':
              payload = {
                'ok': true,
                'grant': {
                  'workspace_id': decodedBody['workspace_id'],
                  'profile_key': decodedBody['profile_key'],
                  'role': decodedBody['role'],
                  'revoked_at': '',
                },
              };
              break;
            case '/admin/workspace-access/revoke':
              payload = {'ok': true};
              break;
            default:
              request.response.statusCode = 404;
              payload = {'ok': false, 'error': 'not found'};
          }

          request.response
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(payload));
          await request.response.close();
        }),
      );
      client = ApiClient(
        baseUrl: 'http://${server.address.host}:${server.port}',
        apiKey: 'test-key',
      );
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('fetches access, ticket, context and records events', () async {
      final access = await client.fetchAccessPolicy(
        actorProfile: 'nik-local',
        phone: '+7 967 981-24-38',
      );
      expect(access.isSuperadmin, isTrue);
      expect(access.canUseMessenger, isTrue);
      expect(access.canUseWorkspaces, isTrue);
      expect(access.canUseAi, isTrue);

      final ticket = await client.requestAgentTicket(
        actorProfile: 'nik-local',
        actorPhone: '+7 967 981-24-38',
        taskId: 'task-1',
        taskType: 'feature',
        workspaceId: 'weather',
        requestedMode: 'executor',
      );
      expect(ticket.policyTicket, 'signed-ticket');
      expect(ticket.policy.canStartAgentChat, isTrue);

      final context = await client.fetchAgentContext(
        actorProfile: 'nik-local',
        actorPhone: '+7 967 981-24-38',
        taskId: 'task-1',
        workspaceId: 'weather',
      );
      expect(context.taskTitle, 'Починить синхронизацию');
      expect(context.toPrompt(), contains('Починить синхронизацию'));
      expect(context.toPrompt(), contains('Падает после push'));

      await client.recordAgentEvent(
        actorProfile: 'nik-local',
        actorPhone: '+7 967 981-24-38',
        taskId: 'task-1',
        workspaceId: 'weather',
        agentSessionId: 'agent-session-1',
        eventType: 'agent_session_started',
        payload: {'session_id': 'session-1'},
      );

      expect(requests.map((item) => item['path']), [
        '/me/access',
        '/agent/ticket',
        '/agent/context',
        '/agent/events',
      ]);
      expect(requests.first['query']['phone'], '+7 967 981-24-38');
      expect(requests[1]['body']['actor_phone'], '+7 967 981-24-38');
      expect(requests[2]['body']['actor_phone'], '+7 967 981-24-38');
      final eventRequest = requests.last;
      expect(eventRequest['body']['actor_phone'], '+7 967 981-24-38');
      expect(eventRequest['body']['agent_session_id'], 'agent-session-1');
      expect(eventRequest['body']['payload']['session_id'], 'session-1');
    });

    test('decodes messenger-only access as workspace disabled', () {
      final access = UserAccessPolicy.fromJson(const {
        'phone': '79000000000',
        'roles': ['messenger_user'],
        'capabilities': ['messenger.use'],
        'is_superadmin': false,
      });

      expect(access.canUseMessenger, isTrue);
      expect(access.canUseTaskManager, isFalse);
      expect(access.canUseWorkspaces, isFalse);
      expect(access.canUseAi, isFalse);
    });

    test('manages workspace access for superadmin panel', () async {
      final grants = await client.listWorkspaceAccess(
        actorProfile: 'nik-local',
        actorPhone: '+7 967 981-24-38',
      );
      expect(grants.single.workspaceId, 'weather');
      expect(grants.single.profileKey, 'dev');
      expect(grants.single.role, 'agent_operator');

      final grant = await client.grantWorkspaceAccess(
        actorProfile: 'nik-local',
        actorPhone: '+7 967 981-24-38',
        profileKey: 'qa',
        workspaceId: 'weather',
        role: 'workspace_user',
      );
      expect(grant.profileKey, 'qa');
      expect(grant.workspaceId, 'weather');

      await client.revokeWorkspaceAccess(
        actorProfile: 'nik-local',
        actorPhone: '+7 967 981-24-38',
        profileKey: 'qa',
        workspaceId: 'weather',
      );

      expect(requests.map((item) => item['path']).toList().sublist(0, 3), [
        '/admin/workspace-access',
        '/admin/workspace-access/grant',
        '/admin/workspace-access/revoke',
      ]);
      expect(requests[0]['query']['phone'], '+7 967 981-24-38');
      expect(requests[1]['body']['actor_phone'], '+7 967 981-24-38');
      expect(requests[2]['body']['actor_phone'], '+7 967 981-24-38');
    });
  });
}
