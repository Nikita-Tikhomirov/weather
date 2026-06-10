import 'package:family_todo_mobile/domain/task_domain_service.dart';
import 'package:family_todo_mobile/features/home/desktop_shell_widget.dart';
import 'package:family_todo_mobile/l10n/app_localizations.dart';
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
  testWidgets('desktop shell toolbar uses localized labels', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = TaskStore(
      repository: _FakeTaskRepository(),
      domainService: TaskDomainService(),
    );
    store.availableSchemes.value = const [];
    addTearDown(store.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DesktopShellWidget(
          store: store,
          loading: false,
          owner: 'nik',
          selectedDate: DateTime(2026, 6, 11),
          selectedDateKey: '2026-06-11',
          desktopLogExpanded: false,
          desktopMonth: DateTime(2026, 6),
          onToggleLogExpanded: () {},
          onMonthPrev: () {},
          onMonthNext: () {},
          onMonthToday: () {},
          onSetDesktopThemeMode: (_) {},
          onSetDesktopThemeScheme: (_) {},
          onToggleVoiceHost: (_, __) {},
          onOpenTaskEditor: (_, {existing}) {},
          onSafeSyncFull: (_, {required showErrors}) {},
          onSafeSyncDelta: (_, {required showErrors}) {},
          onUndo: (_) {},
          desktopPageContentBuilder: (_, __) => const SizedBox.shrink(),
        ),
      ),
    );

    expect(find.text('Tasks - 2026-06-11'), findsOneWidget);
    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('Messenger'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Voice'), findsOneWidget);
    expect(find.text('Add Task'), findsOneWidget);
    expect(find.byTooltip('Sync'), findsOneWidget);
    expect(find.byTooltip('Undo'), findsOneWidget);
    expect(find.text('Задачи'), findsNothing);
    expect(find.text('Добавить'), findsNothing);
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
