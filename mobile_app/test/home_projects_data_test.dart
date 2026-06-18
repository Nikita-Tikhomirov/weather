import 'package:family_todo_mobile/domain/task_domain_service.dart';
import 'package:family_todo_mobile/features/home/home_projects_data.dart';
import 'package:family_todo_mobile/models/family_group.dart';
import 'package:family_todo_mobile/models/project_contact.dart';
import 'package:family_todo_mobile/models/task_item.dart';
import 'package:family_todo_mobile/models/task_project.dart';
import 'package:family_todo_mobile/repositories/task_repository.dart';
import 'package:family_todo_mobile/services/api_client.dart';
import 'package:family_todo_mobile/services/local_db.dart';
import 'package:family_todo_mobile/state/task_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('openProjectContact uses injected unavailable project chat message',
      () async {
    final errors = <String>[];
    final manager = HomeProjectsDataManager(
      store: TaskStore(
        repository: _FakeTaskRepository(),
        domainService: TaskDomainService(),
      ),
      api: ApiClient(baseUrl: 'http://localhost', apiKey: 'test'),
      owner: 'nik',
      currentProfilePhone: '',
      projectChatsUnavailableMessage: 'Project chats are unavailable',
      onShowError: errors.add,
    );

    await manager.openProjectContact(
      const ProjectContact(
        id: 'weather',
        name: 'Weather',
        path: r'C:\weather',
        icon: 'code',
      ),
    );

    expect(errors, ['Project chats are unavailable']);
  });
}

class _FakeTaskRepository implements TaskRepository {
  @override
  LocalDb get db => throw UnimplementedError();

  @override
  ApiClient get api => throw UnimplementedError();

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
