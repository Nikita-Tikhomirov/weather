import 'package:family_todo_mobile/domain/task_domain_service.dart';
import 'package:family_todo_mobile/models/family_group.dart';
import 'package:family_todo_mobile/models/task_item.dart';
import 'package:family_todo_mobile/models/task_project.dart';
import 'package:family_todo_mobile/repositories/task_repository.dart';
import 'package:family_todo_mobile/services/api_client.dart';
import 'package:family_todo_mobile/services/local_db.dart';
import 'package:family_todo_mobile/services/voice_recorder_service.dart';
import 'package:family_todo_mobile/state/task_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTaskRepository implements TaskRepository {
  @override
  LocalDb get db => throw UnimplementedError();

  @override
  ApiClient get api => throw UnimplementedError();

  @override
  String get actorProfile => 'test_user';

  @override
  Future<void> bindActor(String actorProfile) async {}

  @override
  Future<List<TaskItem>> readVisibleTasks() async => const [];

  @override
  Future<void> syncDelta() async {}

  @override
  Future<void> syncFull() async {}

  @override
  Future<void> upsert(TaskItem task) async {}

  @override
  Future<void> delete(TaskItem task) async {}

  @override
  Future<void> upsertProject(TaskProject project) async {}

  @override
  Future<void> upsertFamilyGroup(FamilyGroup group) async {}

  @override
  Future<List<TaskProject>> readProjects() async => const [];

  @override
  Future<List<FamilyGroup>> readFamilyGroups() async => const [];

  @override
  Future<Map<String, List<String>>> readProjectGroupMap() async => const {};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('uses English default message when microphone permission is denied',
      () async {
    const channel = MethodChannel('family_todo_mobile/voice');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'requestPermission') {
        return false;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final messages = <String>[];
    final service = VoiceRecorderService(
      store: TaskStore(
        repository: _FakeTaskRepository(),
        domainService: TaskDomainService(),
      ),
      onShowSnackBar: messages.add,
    );

    await service.startRecord();

    expect(messages, ['Microphone permission is required']);
  });
}
