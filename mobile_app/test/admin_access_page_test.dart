import 'package:family_todo_mobile/features/admin/admin_access_page.dart';
import 'package:family_todo_mobile/l10n/app_localizations.dart';
import 'package:family_todo_mobile/models/agent_policy.dart';
import 'package:family_todo_mobile/models/chat_models.dart';
import 'package:family_todo_mobile/models/task_project.dart';
import 'package:family_todo_mobile/models/workspace_item.dart';
import 'package:family_todo_mobile/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('admin page uses localized access labels', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _localizedApp(
        home: AdminAccessPage(
          api: _FakeAdminApiClient(),
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
              displayName: 'Developer',
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

    expect(find.text('Administration'), findsOneWidget);
    expect(find.byTooltip('Refresh'), findsOneWidget);
    expect(find.text('Users: 2'), findsOneWidget);
    expect(find.text('Workspaces: 1'), findsOneWidget);
    expect(find.text('Projects: 1'), findsOneWidget);
    expect(find.text('CodeWhale disabled'), findsOneWidget);
    expect(find.text('New access'), findsOneWidget);
    expect(find.text('Contact from contacts'), findsOneWidget);
    expect(find.text('Workspace'), findsOneWidget);
    expect(find.text('Role'), findsOneWidget);
    expect(find.text('Agent operator'), findsWidgets);
    expect(find.text('Grant access'), findsOneWidget);
    expect(find.text('Granted access'), findsOneWidget);
    expect(find.text('Agent roles'), findsOneWidget);
    expect(find.byTooltip('Revoke access'), findsOneWidget);
  });

  testWidgets('admin page uses English fallback labels without localizations',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _plainApp(
        home: AdminAccessPage(
          api: _EmptyAdminApiClient(),
          actorProfile: '',
          actorPhone: '',
          accessPolicy: const UserAccessPolicy(
            phone: '79679812438',
            profileKey: 'nik',
            roles: ['messenger_user', 'superadmin'],
            capabilities: ['workspaces.grant_access'],
            workspaces: [],
            isSuperadmin: true,
          ),
          contacts: const [],
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

    expect(find.text('Administration'), findsOneWidget);
    expect(find.byTooltip('Refresh'), findsOneWidget);
    expect(find.text('Users: 0'), findsOneWidget);
    expect(find.text('Workspaces: 1'), findsOneWidget);
    expect(find.text('Projects: 1'), findsOneWidget);
    expect(find.text('CodeWhale disabled'), findsOneWidget);
    expect(find.text('New access'), findsOneWidget);
    expect(find.text('Contact from contacts'), findsOneWidget);
    expect(find.text('No contacts found'), findsOneWidget);
    expect(find.text('Workspace'), findsOneWidget);
    expect(find.text('Role'), findsOneWidget);
    expect(find.text('Agent operator'), findsWidgets);
    expect(
      find.text('Can launch agent chats from tasks and run work in them.'),
      findsWidgets,
    );
    expect(find.text('Grant access'), findsOneWidget);
    expect(find.text('Granted access'), findsOneWidget);
    expect(find.text('No active access yet'), findsOneWidget);
    expect(find.text('Agent roles'), findsOneWidget);
    expect(find.text('Workspace member'), findsOneWidget);
    expect(find.text('Workspace administrator'), findsOneWidget);
    expect(find.textContaining(RegExp(r'[А-Яа-яЁё]')), findsNothing);
  });

  testWidgets('admin page grants workspace access only to real workspaces',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final client = _FakeAdminApiClient();

    await tester.pumpWidget(
      _localizedApp(
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

    expect(find.text('Administration'), findsOneWidget);
    expect(find.text('Разработчик'), findsWidgets);
    expect(find.text('System'), findsNothing);
    expect(find.text('Weather'), findsWidgets);
    expect(find.text('Agent operator'), findsWidgets);
    expect(find.text('Плагины'), findsNothing);

    final grantButton = find.widgetWithText(FilledButton, 'Grant access');
    await tester.ensureVisible(grantButton);
    await tester.tap(grantButton);
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Access granted'), findsOneWidget);
    expect(find.text('Доступ выдан'), findsNothing);

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

Widget _localizedApp({required Widget home}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(splashFactory: NoSplash.splashFactory),
    home: home,
  );
}

Widget _plainApp({required Widget home}) {
  return MaterialApp(
    theme: ThemeData(splashFactory: NoSplash.splashFactory),
    home: home,
  );
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

class _EmptyAdminApiClient extends _FakeAdminApiClient {
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
    return const [];
  }
}
