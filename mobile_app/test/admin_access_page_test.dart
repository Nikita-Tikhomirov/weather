import 'package:family_todo_mobile/features/admin/admin_access_page.dart';
import 'package:family_todo_mobile/models/agent_policy.dart';
import 'package:family_todo_mobile/models/chat_models.dart';
import 'package:family_todo_mobile/models/task_project.dart';
import 'package:family_todo_mobile/models/workspace_item.dart';
import 'package:family_todo_mobile/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('admin page grants workspace access only to real workspaces',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final client = _FakeAdminApiClient();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: AdminAccessPage(
          api: client,
          actorProfile: 'nik',
          actorPhone: '+7 967 981-24-38',
          accessPolicy: const UserAccessPolicy(
            phone: '79679812438',
            profileKey: 'nik',
            roles: ['messenger_user', 'superadmin'],
            capabilities: ['workspaces.grant_access'],
            workspaces: [],
            isSuperadmin: true,
          ),
          contacts: const [
            ChatContact(
              profileKey: 'user-dev',
              displayName: 'Разработчик',
              phone: '79000000000',
              conversationKey: 'dm:nik:user-dev',
            ),
          ],
          projects: const [
            TaskProject(id: 'project-system', name: 'System'),
          ],
          initialWorkspaces: const [
            WorkspaceItem(
              id: 'workspace-weather',
              name: 'Weather',
              path: r'C:\weather',
              status: WorkspaceStatus.available,
            ),
          ],
          connectToBridge: false,
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Администрирование'), findsOneWidget);
    expect(find.text('Разработчик'), findsWidgets);
    expect(find.text('System'), findsNothing);
    expect(find.text('Weather'), findsWidgets);
    expect(find.text('Оператор агентов'), findsWidgets);
    expect(find.text('Плагины'), findsNothing);

    final grantButton = find.widgetWithText(FilledButton, 'Выдать доступ');
    await tester.ensureVisible(grantButton);
    await tester.tap(grantButton);
    await tester.pump(const Duration(seconds: 2));

    expect(
      client.requests.map((item) => item['path']),
      contains('/admin/workspace-access/grant'),
    );
    final grant = client.requests.lastWhere(
      (item) => item['path'] == '/admin/workspace-access/grant',
    );
    expect(grant['body']['profile_key'], 'user-dev');
    expect(grant['body']['workspace_id'], 'workspace-weather');
    expect(grant['body']['role'], 'agent_operator');
    expect(grant['body']['actor_phone'], '+7 967 981-24-38');
  });
}

class _FakeAdminApiClient extends ApiClient {
  _FakeAdminApiClient() : super(baseUrl: 'http://localhost', apiKey: 'test');

  final List<Map<String, dynamic>> requests = <Map<String, dynamic>>[];

  @override
  Future<List<WorkspaceAccessGrant>> listWorkspaceAccess({
    required String actorProfile,
    String actorPhone = '',
    String workspaceId = '',
  }) async {
    requests.add({
      'path': '/admin/workspace-access',
      'query': {
        'actor_profile': actorProfile,
        'phone': actorPhone,
        'workspace_id': workspaceId,
      },
    });
    return const [
      WorkspaceAccessGrant(
        workspaceId: 'workspace-weather',
        profileKey: 'user-dev',
        role: 'agent_operator',
      ),
    ];
  }

  @override
  Future<WorkspaceAccessGrant> grantWorkspaceAccess({
    required String actorProfile,
    String actorPhone = '',
    required String profileKey,
    required String workspaceId,
    String role = 'workspace_user',
  }) async {
    requests.add({
      'path': '/admin/workspace-access/grant',
      'body': {
        'actor_profile': actorProfile,
        'actor_phone': actorPhone,
        'profile_key': profileKey,
        'workspace_id': workspaceId,
        'role': role,
      },
    });
    return WorkspaceAccessGrant(
      workspaceId: workspaceId,
      profileKey: profileKey,
      role: role,
    );
  }

  @override
  Future<void> revokeWorkspaceAccess({
    required String actorProfile,
    String actorPhone = '',
    required String profileKey,
    required String workspaceId,
  }) async {
    requests.add({
      'path': '/admin/workspace-access/revoke',
      'body': {
        'actor_profile': actorProfile,
        'actor_phone': actorPhone,
        'profile_key': profileKey,
        'workspace_id': workspaceId,
      },
    });
  }
}
