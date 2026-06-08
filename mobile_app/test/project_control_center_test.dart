import 'package:family_todo_mobile/domain/task_domain_service.dart';
import 'package:family_todo_mobile/features/projects/projects_and_groups_screen.dart';
import 'package:family_todo_mobile/models/agent_policy.dart';
import 'package:family_todo_mobile/models/family_group.dart';
import 'package:family_todo_mobile/models/task_item.dart';
import 'package:family_todo_mobile/models/task_project.dart';
import 'package:family_todo_mobile/repositories/task_repository.dart';
import 'package:family_todo_mobile/services/api_client.dart';
import 'package:family_todo_mobile/services/local_db.dart';
import 'package:family_todo_mobile/state/task_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Project Control Center workspace binding', () {
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
  });
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
  final List<String> savedWorkspaceIds = [];

  @override
  Future<ProjectControlSnapshot> fetchProjectControlSnapshot({
    required String actorProfile,
    required String projectId,
    String actorPhone = '',
  }) async {
    return snapshot;
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
