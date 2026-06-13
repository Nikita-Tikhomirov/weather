import 'package:family_todo_mobile/domain/task_domain_service.dart';
import 'package:family_todo_mobile/features/projects/family_group_edit_sheet.dart';
import 'package:family_todo_mobile/features/projects/project_edit_sheet.dart';
import 'package:family_todo_mobile/features/projects/projects_and_groups_screen.dart';
import 'package:family_todo_mobile/l10n/app_localizations.dart';
import 'package:family_todo_mobile/models/agent_policy.dart';
import 'package:family_todo_mobile/models/chat_models.dart';
import 'package:family_todo_mobile/models/family_group.dart';
import 'package:family_todo_mobile/models/task_item.dart';
import 'package:family_todo_mobile/models/task_project.dart';
import 'package:family_todo_mobile/models/workspace_item.dart';
import 'package:family_todo_mobile/repositories/task_repository.dart';
import 'package:family_todo_mobile/services/api_client.dart';
import 'package:family_todo_mobile/services/local_db.dart';
import 'package:family_todo_mobile/state/task_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Project Control Center workspace binding', () {
    testWidgets('project edit sheet uses localized labels', (tester) async {
      final repository = _FakeTaskRepository();
      final store = TaskStore(
        repository: repository,
        domainService: TaskDomainService(),
      );
      store.familyGroups.value = const [
        FamilyGroup(id: 'team', name: 'Team', members: ['nik']),
      ];

      await tester.pumpWidget(
        _localizedApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => showProjectEditSheet(
                      context: context,
                      store: store,
                      isCreate: true,
                    ),
                    child: const Text('Open sheet'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open sheet'));
      await tester.pumpAndSettle();

      expect(find.text('New project'), findsOneWidget);
      expect(find.text('Project name'), findsOneWidget);
      expect(find.text('Description'), findsOneWidget);
      expect(find.text('Groups'), findsOneWidget);
      expect(find.text('Team'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Create'), findsOneWidget);

      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text('Enter project name'), findsOneWidget);
    });

    testWidgets('project edit sheet falls back to English labels',
        (tester) async {
      final repository = _FakeTaskRepository();
      final store = TaskStore(
        repository: repository,
        domainService: TaskDomainService(),
      );
      store.familyGroups.value = const [
        FamilyGroup(id: 'team', name: 'Team', members: ['nik']),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => showProjectEditSheet(
                      context: context,
                      store: store,
                      isCreate: true,
                    ),
                    child: const Text('Open sheet'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open sheet'));
      await tester.pumpAndSettle();

      expect(find.text('New project'), findsOneWidget);
      expect(find.text('Project name'), findsOneWidget);
      expect(find.text('Description'), findsOneWidget);
      expect(find.text('Groups'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Create'), findsOneWidget);
      expect(find.text('Новый проект'), findsNothing);
      expect(find.text('Отмена'), findsNothing);

      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text('Enter project name'), findsOneWidget);
    });

    testWidgets('family group edit sheet uses localized labels',
        (tester) async {
      final repository = _FakeTaskRepository();
      final store = TaskStore(
        repository: repository,
        domainService: TaskDomainService(),
      );

      await tester.pumpWidget(
        _localizedApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => showFamilyGroupEditSheet(
                      context: context,
                      store: store,
                      isCreate: true,
                      contacts: const [
                        ChatContact(
                          profileKey: 'nik',
                          displayName: 'Nick',
                          phone: '',
                          conversationKey: 'chat:nik',
                        ),
                      ],
                      contactLabel: (contact) => contact.displayName,
                      actorProfile: 'nik',
                    ),
                    child: const Text('Open group sheet'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open group sheet'));
      await tester.pumpAndSettle();

      expect(find.text('New group'), findsOneWidget);
      expect(find.text('Group name'), findsOneWidget);
      expect(find.text('Participants'), findsOneWidget);
      expect(find.text('Nick'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Create'), findsOneWidget);

      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text('Enter group name'), findsOneWidget);
    });

    testWidgets('projects and groups sections use localized empty states',
        (tester) async {
      final repository = _FakeTaskRepository();
      final store = TaskStore(
        repository: repository,
        domainService: TaskDomainService(),
      );

      await tester.pumpWidget(
        _localizedApp(
          home: ProjectsAndGroupsScreen(
            store: store,
            actorProfile: 'nik',
            loadWorkspacesFromBridge: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Projects'), findsOneWidget);
      expect(find.byTooltip('Create project'), findsOneWidget);
      expect(
        find.text('No projects yet. Press + to create one.'),
        findsOneWidget,
      );
      expect(find.text('Groups'), findsOneWidget);
      expect(find.byTooltip('Create group'), findsOneWidget);
      expect(
        find.text('No groups yet. Press + to create one.'),
        findsOneWidget,
      );
    });

    testWidgets('workspace picker and status use localized labels',
        (tester) async {
      final repository = _FakeTaskRepository();
      final store = TaskStore(
        repository: repository,
        domainService: TaskDomainService(),
      );
      store.owner.value = 'nik';
      store.currentProjectId.value = 'project-1';
      store.projects.value = const [
        TaskProject(id: 'project-1', name: 'Cifra', ownerKey: 'nik'),
      ];
      repository.fakeApi.snapshot = const ProjectControlSnapshot(
        project: TaskProject(id: 'project-1', name: 'Cifra'),
        chatBindings: [],
        automation: ProjectAutomationConfig(
          projectId: 'project-1',
          primaryWorkspaceId: 'workspace-cifra',
        ),
        primaryWorkspaceId: 'workspace-cifra',
        canManageProject: true,
        canUseWorkspace: true,
        canUseAgent: true,
      );

      await tester.pumpWidget(
        _localizedApp(
          home: ProjectsAndGroupsScreen(
            store: store,
            actorProfile: 'nik',
            loadWorkspacesFromBridge: false,
            initialWorkspaces: const [
              WorkspaceItem(
                id: 'workspace-cifra',
                name: 'Cifra Tools',
                path: 'C:/projects/cifra-tools',
                status: WorkspaceStatus.available,
              ),
            ],
            accessPolicy: const UserAccessPolicy(
              phone: '',
              profileKey: 'nik',
              roles: ['workspace_user'],
              capabilities: [
                'messenger.use',
                'projects.view',
                'workspaces.use',
                'ai.use',
              ],
              workspaces: [
                {'workspace_id': 'workspace-cifra'},
              ],
              isSuperadmin: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Workspace: Cifra Tools'), findsOneWidget);
      expect(find.text('Agent available'), findsOneWidget);
      expect(find.text('Selected: Cifra Tools. Available: 1.'), findsOneWidget);
      expect(find.text('Change workspace'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('project-workspace-picker')));
      await tester.pumpAndSettle();

      expect(find.text('Primary workspace'), findsOneWidget);
      expect(find.byTooltip('Refresh workspaces'), findsWidgets);
      expect(find.text('Search by name, id, or path'), findsOneWidget);
      expect(
        find.text('Found: 1 of 1. Source: CodeWhale'),
        findsOneWidget,
      );
      expect(find.text('Clear binding'), findsOneWidget);
      expect(find.text('The project agent will be disabled.'), findsOneWidget);
    });

    testWidgets('project and group menus use localized labels', (tester) async {
      final repository = _FakeTaskRepository();
      final store = TaskStore(
        repository: repository,
        domainService: TaskDomainService(),
      );
      store.owner.value = 'nik';
      store.currentProjectId.value = 'project-2';
      store.projects.value = const [
        TaskProject(id: 'project-1', name: 'Alpha', ownerKey: 'nik'),
        TaskProject(id: 'project-2', name: 'Beta', ownerKey: 'nik'),
      ];
      store.familyGroups.value = const [
        FamilyGroup(id: 'team', name: 'Team', members: ['nik', 'mia']),
      ];
      store.projectGroupMap.value = const {
        'project-1': ['team'],
      };

      Finder popupForTile(String title) {
        final tile = find.ancestor(
          of: find.text(title),
          matching: find.byType(ListTile),
        );
        return find.descendant(
          of: tile,
          matching: find.byType(PopupMenuButton<String>),
        );
      }

      await tester.pumpWidget(
        _localizedApp(
          home: ProjectsAndGroupsScreen(
            store: store,
            actorProfile: 'nik',
            loadWorkspacesFromBridge: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Groups: Team'), findsOneWidget);

      await tester.ensureVisible(find.text('Alpha'));
      await tester.pumpAndSettle();

      await tester.tap(popupForTile('Alpha'));
      await tester.pumpAndSettle();

      expect(find.text('Select'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete project?'), findsOneWidget);
      expect(
        find.text('The project and group links will be deleted.'),
        findsOneWidget,
      );
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();

      expect(find.text('Participants: nik, mia'), findsOneWidget);

      await tester.tap(popupForTile('Team'));
      await tester.pumpAndSettle();

      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete group?'), findsOneWidget);
      expect(
        find.text('The group will be removed from all projects.'),
        findsOneWidget,
      );
    });

    testWidgets('does not auto-select first workspace and saves chosen one',
        (tester) async {
      final repository = _FakeTaskRepository();
      final store = TaskStore(
        repository: repository,
        domainService: TaskDomainService(),
      );
      store.owner.value = 'nik';
      store.currentProjectId.value = 'project-1';
      store.projects.value = const [
        TaskProject(
          id: 'project-1',
          name: 'Stylish house',
          description: 'Магазин laravel',
          ownerKey: 'nik',
        ),
      ];
      store.familyGroups.value = const [
        FamilyGroup(
          id: 'group-1',
          name: 'Я',
          members: ['nik'],
        ),
      ];
      store.projectGroupMap.value = const {
        'project-1': ['group-1'],
      };

      repository.fakeApi.snapshot = const ProjectControlSnapshot(
        project: TaskProject(id: 'project-1', name: 'Stylish house'),
        chatBindings: [],
        automation: ProjectAutomationConfig(projectId: 'project-1'),
        canManageProject: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: ProjectsAndGroupsScreen(
            store: store,
            actorProfile: 'nik',
            accessPolicy: const UserAccessPolicy(
              phone: '',
              profileKey: 'nik',
              roles: ['workspace_user'],
              capabilities: [
                'messenger.use',
                'projects.view',
                'workspaces.use',
                'ai.use',
              ],
              workspaces: [
                {'workspace_id': 'exp76-ru'},
                {'workspace_id': 'stylish-house'},
              ],
              isSuperadmin: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Workspace не выбран'), findsWidgets);
      expect(find.textContaining('Workspace: exp76-ru'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('project-workspace-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('stylish-house').last);
      await tester.pumpAndSettle();

      expect(repository.fakeApi.savedWorkspaceIds, ['stylish-house']);
    });

    testWidgets('shows all CodeWhale workspaces with readable labels',
        (tester) async {
      final repository = _FakeTaskRepository();
      final store = TaskStore(
        repository: repository,
        domainService: TaskDomainService(),
      );
      store.owner.value = 'nik';
      store.currentProjectId.value = 'project-1';
      store.projects.value = const [
        TaskProject(id: 'project-1', name: 'Цифра', ownerKey: 'nik'),
      ];
      repository.fakeApi.snapshot = const ProjectControlSnapshot(
        project: TaskProject(id: 'project-1', name: 'Цифра'),
        chatBindings: [],
        automation: ProjectAutomationConfig(projectId: 'project-1'),
        canManageProject: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: ProjectsAndGroupsScreen(
            store: store,
            actorProfile: 'nik',
            loadWorkspacesFromBridge: false,
            initialWorkspaces: const [
              WorkspaceItem(
                id: 'exp76-ru',
                name: 'Exp76.ru',
                path: 'C:/projects/exp76',
                status: WorkspaceStatus.available,
              ),
              WorkspaceItem(
                id: 'prj-6a188d11473da242626035',
                name: '',
                path: 'C:/projects/stylish-house',
                status: WorkspaceStatus.available,
              ),
              WorkspaceItem(
                id: 'workspace-cifra',
                name: 'Цифра: утилиты',
                path: 'C:/projects/cifra-tools',
                status: WorkspaceStatus.available,
              ),
              WorkspaceItem(
                id: 'workspace-shop',
                name: 'Магазин Laravel',
                path: 'C:/projects/shop-laravel',
                status: WorkspaceStatus.available,
              ),
              WorkspaceItem(
                id: 'workspace-bot',
                name: 'Telegram bot',
                path: 'C:/projects/tg-bot',
                status: WorkspaceStatus.available,
              ),
            ],
            accessPolicy: const UserAccessPolicy(
              phone: '',
              profileKey: 'nik',
              roles: ['workspace_user'],
              capabilities: [
                'messenger.use',
                'projects.view',
                'workspaces.use',
                'ai.use',
              ],
              workspaces: [
                {'workspace_id': 'exp76-ru'},
              ],
              isSuperadmin: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('project-workspace-picker')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Найдено: 5 из 5'), findsOneWidget);
      expect(find.text('Exp76.ru'), findsOneWidget);
      expect(find.text('stylish-house'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'цифра');
      await tester.pumpAndSettle();
      expect(find.text('Цифра: утилиты'), findsOneWidget);
      expect(find.textContaining('C:/projects/cifra-tools'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'telegram');
      await tester.pumpAndSettle();
      expect(find.text('Telegram bot'), findsOneWidget);
    });

    testWidgets('uses backend snapshot permissions for agent actions',
        (tester) async {
      final repository = _FakeTaskRepository();
      final store = TaskStore(
        repository: repository,
        domainService: TaskDomainService(),
      );
      store.owner.value = 'nik';
      store.currentProjectId.value = 'project-1';
      store.projects.value = const [
        TaskProject(id: 'project-1', name: 'Цифра', ownerKey: 'nik'),
      ];
      store.familyGroups.value = const [
        FamilyGroup(id: 'group-1', name: 'Команда', members: ['nik']),
      ];
      store.projectGroupMap.value = const {
        'project-1': ['group-1'],
      };
      repository.fakeApi.snapshot = const ProjectControlSnapshot(
        project: TaskProject(id: 'project-1', name: 'Цифра'),
        chatBindings: [],
        automation: ProjectAutomationConfig(
          projectId: 'project-1',
          primaryWorkspaceId: 'workspace-cifra',
        ),
        primaryWorkspaceId: 'workspace-cifra',
        canManageProject: true,
        canUseAgent: false,
        canUseWorkspace: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: ProjectsAndGroupsScreen(
            store: store,
            actorProfile: 'nik',
            loadWorkspacesFromBridge: false,
            initialWorkspaces: const [
              WorkspaceItem(
                id: 'workspace-cifra',
                name: 'Цифра: утилиты',
                path: 'C:/projects/cifra-tools',
                status: WorkspaceStatus.available,
              ),
            ],
            accessPolicy: const UserAccessPolicy(
              phone: '',
              profileKey: 'nik',
              roles: ['workspace_user'],
              capabilities: [
                'messenger.use',
                'projects.view',
                'workspaces.use',
                'ai.use',
              ],
              workspaces: [],
              isSuperadmin: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Workspace: Цифра: утилиты (нет доступа)'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('project-control-analyze-chat')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('project-control-start-agent')),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('creates project chat from assigned group', (tester) async {
      final repository = _FakeTaskRepository();
      final store = TaskStore(
        repository: repository,
        domainService: TaskDomainService(),
      );
      store.owner.value = 'nik';
      store.currentProjectId.value = 'project-1';
      store.projects.value = const [
        TaskProject(id: 'project-1', name: 'Цифра', ownerKey: 'nik'),
      ];
      store.familyGroups.value = const [
        FamilyGroup(id: 'group-1', name: 'Команда', members: ['nik', 'nastya']),
      ];
      store.projectGroupMap.value = const {
        'project-1': ['group-1'],
      };
      repository.fakeApi.snapshot = const ProjectControlSnapshot(
        project: TaskProject(id: 'project-1', name: 'Цифра'),
        chatBindings: [],
        automation: ProjectAutomationConfig(projectId: 'project-1'),
        canManageProject: true,
      );
      repository.fakeApi.snapshotAfterEnsure = const ProjectControlSnapshot(
        project: TaskProject(id: 'project-1', name: 'Цифра'),
        chatBindings: [
          ProjectChatBinding(
            projectId: 'project-1',
            conversationKey: 'grp:project:project-1',
            groupId: 'group-1',
            source: 'project_group',
            isPrimary: true,
            title: 'Цифра',
            members: ['nik', 'nastya'],
          ),
        ],
        automation: ProjectAutomationConfig(projectId: 'project-1'),
        canManageProject: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: ProjectsAndGroupsScreen(
            store: store,
            actorProfile: 'nik',
            loadWorkspacesFromBridge: false,
            accessPolicy: const UserAccessPolicy(
              phone: '',
              profileKey: 'nik',
              roles: ['workspace_user'],
              capabilities: ['messenger.use', 'projects.view'],
              workspaces: [],
              isSuperadmin: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('project-control-ensure-chat')),
        findsOneWidget,
      );
      await tester
          .tap(find.byKey(const ValueKey('project-control-ensure-chat')));
      await tester.pumpAndSettle();

      expect(repository.fakeApi.ensureChatProjectIds, ['project-1']);
      expect(find.text('Цифра'), findsWidgets);
      expect(find.text('Обновить проектный чат'), findsOneWidget);
    });
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

class _FakeTaskRepository implements TaskRepository {
  final _FakeApiClient fakeApi = _FakeApiClient();

  @override
  LocalDb get db => throw UnimplementedError();

  @override
  ApiClient get api => fakeApi;

  @override
  String get actorProfile => 'nik';

  @override
  Future<void> bindActor(String actorProfile) async {}

  @override
  Future<void> delete(TaskItem task) async {}

  @override
  Future<List<FamilyGroup>> readFamilyGroups() async => const [];

  @override
  Future<Map<String, List<String>>> readProjectGroupMap() async => const {};

  @override
  Future<List<TaskProject>> readProjects() async => const [];

  @override
  Future<List<TaskItem>> readVisibleTasks() async => const [];

  @override
  Future<void> syncDelta() async {}

  @override
  Future<void> syncFull() async {}

  @override
  Future<void> upsert(TaskItem task) async {}

  @override
  Future<void> upsertFamilyGroup(FamilyGroup group) async {}

  @override
  Future<void> upsertProject(TaskProject project) async {}
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super(baseUrl: 'http://localhost', apiKey: 'test');

  ProjectControlSnapshot snapshot = const ProjectControlSnapshot(
    project: TaskProject(id: '', name: ''),
    chatBindings: [],
    automation: ProjectAutomationConfig(projectId: ''),
  );
  ProjectControlSnapshot? snapshotAfterEnsure;
  final List<String> savedWorkspaceIds = [];
  final List<String> ensureChatProjectIds = [];

  @override
  Future<ProjectControlSnapshot> fetchProjectControlSnapshot({
    required String actorProfile,
    required String projectId,
    String actorPhone = '',
  }) async {
    if (snapshotAfterEnsure != null &&
        ensureChatProjectIds.contains(projectId)) {
      return snapshotAfterEnsure!;
    }
    return snapshot;
  }

  @override
  Future<ChatConversation> ensureProjectChat({
    required String actorProfile,
    required String projectId,
  }) async {
    ensureChatProjectIds.add(projectId);
    return const ChatConversation(
      conversationKey: 'grp:project:project-1',
      kind: 'group',
      title: 'Цифра',
      members: ['nik', 'nastya'],
    );
  }

  @override
  Future<ProjectAutomationConfig> updateProjectAutomationConfig({
    required String actorProfile,
    String actorPhone = '',
    required String projectId,
    required String primaryWorkspaceId,
    bool? agentEnabled,
    String? defaultAgentMode,
    int? chatAnalysisMessageLimit,
  }) async {
    savedWorkspaceIds.add(primaryWorkspaceId);
    return ProjectAutomationConfig(
      projectId: projectId,
      primaryWorkspaceId: primaryWorkspaceId,
      agentEnabled: true,
    );
  }
}
