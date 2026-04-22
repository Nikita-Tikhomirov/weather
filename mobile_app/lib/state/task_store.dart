import 'package:flutter/foundation.dart';

import '../domain/task_domain_service.dart';
import '../domain/task_draft.dart';
import '../models/task_item.dart';
import '../repositories/task_repository.dart';
import '../services/desktop_process_host_service.dart';

class DashboardVm {
  const DashboardVm({
    required this.todayKey,
    required this.todayTotal,
    required this.doneToday,
    required this.familyToday,
    required this.overdue,
    required this.upcoming,
  });

  final String todayKey;
  final int todayTotal;
  final int doneToday;
  final int familyToday;
  final int overdue;
  final List<TaskItem> upcoming;
}

abstract class _UndoAction {
  Future<void> apply(TaskRepository repository);
}

class _UndoDeleteTask extends _UndoAction {
  _UndoDeleteTask(this.createdTask);

  final TaskItem createdTask;

  @override
  Future<void> apply(TaskRepository repository) async {
    await repository.delete(createdTask);
  }
}

class _UndoRestoreTask extends _UndoAction {
  _UndoRestoreTask(this.previousTask);

  final TaskItem previousTask;

  @override
  Future<void> apply(TaskRepository repository) async {
    await repository.upsert(previousTask);
  }
}

class _UndoRestoreTasks extends _UndoAction {
  _UndoRestoreTasks(this.previousTasks);

  final List<TaskItem> previousTasks;

  @override
  Future<void> apply(TaskRepository repository) async {
    for (final task in previousTasks) {
      await repository.upsert(task);
    }
  }
}

class TaskStore {
  TaskStore({required this.repository, required this.domainService});

  final TaskRepository repository;
  final TaskDomainService domainService;
  final List<TaskItem> _allTasks = <TaskItem>[];

  _UndoAction? _lastUndoAction;
  bool _muteUndo = false;

  final ValueNotifier<bool> loading = ValueNotifier<bool>(true);
  final ValueNotifier<String> owner = ValueNotifier<String>('nik');
  final ValueNotifier<DateTime> selectedDate = ValueNotifier<DateTime>(
    DateTime.now(),
  );
  final ValueNotifier<int> pageIndex = ValueNotifier<int>(0);
  final ValueNotifier<String> searchQuery = ValueNotifier<String>('');
  final ValueNotifier<String> tasksDateFilter = ValueNotifier<String>('');
  final ValueNotifier<String> familyFilter = ValueNotifier<String>('upcoming');
  final ValueNotifier<bool> selectionMode = ValueNotifier<bool>(false);
  final ValueNotifier<Set<String>> selectedTaskIds = ValueNotifier<Set<String>>(
    <String>{},
  );
  final ValueNotifier<bool> canUndo = ValueNotifier<bool>(false);

  final ValueNotifier<DashboardVm> dashboard = ValueNotifier<DashboardVm>(
    const DashboardVm(
      todayKey: '',
      todayTotal: 0,
      doneToday: 0,
      familyToday: 0,
      overdue: 0,
      upcoming: <TaskItem>[],
    ),
  );
  final ValueNotifier<Map<String, List<TaskItem>>> personalByStatus =
      ValueNotifier<Map<String, List<TaskItem>>>(const {
    'todo': <TaskItem>[],
    'in_progress': <TaskItem>[],
    'in_review': <TaskItem>[],
    'done': <TaskItem>[],
  });
  final ValueNotifier<List<TaskItem>> tasksForSelectedDate =
      ValueNotifier<List<TaskItem>>(const <TaskItem>[]);
  final ValueNotifier<List<TaskItem>> familyTasksView =
      ValueNotifier<List<TaskItem>>(const <TaskItem>[]);
  final ValueNotifier<List<TaskItem>> allTasksView =
      ValueNotifier<List<TaskItem>>(
    const <TaskItem>[],
  );
  final ValueNotifier<String> themeMode = ValueNotifier<String>('light');
  final ValueNotifier<String> themeScheme = ValueNotifier<String>('Ocean');
  final ValueNotifier<List<String>> availableSchemes =
      ValueNotifier<List<String>>(const ['Ocean', 'Slate', 'Forest']);
  final ValueNotifier<Map<String, String>> desktopThemeTokens =
      ValueNotifier<Map<String, String>>(const <String, String>{});
  final ValueNotifier<DesktopHostState> voiceHostState =
      ValueNotifier<DesktopHostState>(
    const DesktopHostState(
      status: DesktopHostStatus.stopped,
      lastMessage: 'voice stopped',
    ),
  );
  final ValueNotifier<DesktopHostState> botHostState =
      ValueNotifier<DesktopHostState>(
    const DesktopHostState(
      status: DesktopHostStatus.stopped,
      lastMessage: 'bot stopped',
    ),
  );
  final ValueNotifier<List<String>> desktopLogEntries =
      ValueNotifier<List<String>>(
    const <String>[],
  );

  bool get isAdult => TaskDomainService.adults.contains(owner.value);

  Future<void> initialize({
    required String initialOwner,
    DateTime? initialDate,
  }) async {
    loading.value = true;
    owner.value = initialOwner;
    selectedDate.value = initialDate ?? DateTime.now();
    await repository.bindActor(initialOwner);
    await refreshLocal();
    loading.value = false;
  }

  Future<void> switchOwner(String profile) async {
    if (profile == owner.value) {
      return;
    }
    loading.value = true;
    owner.value = profile;
    searchQuery.value = '';
    tasksDateFilter.value = '';
    familyFilter.value = 'upcoming';
    selectionMode.value = false;
    selectedTaskIds.value = <String>{};
    _lastUndoAction = null;
    canUndo.value = false;
    await repository.bindActor(profile);
    await refreshLocal();
    loading.value = false;
  }

  void setPage(int index) {
    if (pageIndex.value == index) {
      return;
    }
    pageIndex.value = index;
  }

  void setSelectedDate(DateTime date) {
    selectedDate.value = date;
    _recomputeDateSlicesOnly();
  }

  void setSearchQuery(String value) {
    searchQuery.value = value.trim().toLowerCase();
    _recomputeKanbanOnly();
  }

  void setTasksDateFilter(String value) {
    tasksDateFilter.value = value.trim();
    _recomputeKanbanOnly();
  }

  void clearTasksDateFilter() {
    if (tasksDateFilter.value.isEmpty) {
      return;
    }
    tasksDateFilter.value = '';
    _recomputeKanbanOnly();
  }

  void setFamilyFilter(String value) {
    if (familyFilter.value == value) {
      return;
    }
    familyFilter.value = value;
    _recomputeFamilyOnly();
  }

  void setSelectionMode(bool enabled) {
    selectionMode.value = enabled;
    if (!enabled) {
      selectedTaskIds.value = <String>{};
    }
  }

  void toggleSelectionMode() {
    setSelectionMode(!selectionMode.value);
  }

  void toggleTaskSelection(String taskId) {
    final next = Set<String>.from(selectedTaskIds.value);
    if (next.contains(taskId)) {
      next.remove(taskId);
    } else {
      next.add(taskId);
    }
    selectedTaskIds.value = next;
  }

  Future<void> refreshLocal() async {
    final tasks = await repository.readVisibleTasks();
    _allTasks
      ..clear()
      ..addAll(tasks);
    _trimSelectionToExisting();
    _recomputeAllSlices();
  }

  Future<void> syncDelta() async {
    await repository.syncDelta();
    await refreshLocal();
  }

  Future<void> syncFull() async {
    await repository.syncFull();
    await refreshLocal();
  }

  Future<String?> saveDraft({
    required TaskDraft draft,
    TaskItem? existing,
  }) async {
    final error = domainService.validateDraft(
      draft: draft,
      actorProfile: owner.value,
    );
    if (error != null) {
      return error;
    }

    final task = domainService.materializeTask(
      draft: draft,
      actorProfile: owner.value,
      now: DateTime.now(),
      existing: existing,
    );
    await repository.upsert(task);
    if (existing == null) {
      _rememberUndo(_UndoDeleteTask(task));
    } else {
      _rememberUndo(_UndoRestoreTask(existing));
    }
    await refreshLocal();
    return null;
  }

  Future<void> move(TaskItem item, String nextStatus) async {
    if (item.workflowStatus == nextStatus) {
      return;
    }
    final changed = item.copyWith(
      workflowStatus: nextStatus,
      updatedAt: DateTime.now().toIso8601String(),
      version: item.version + 1,
    );
    await repository.upsert(changed);
    _rememberUndo(_UndoRestoreTask(item));
    await refreshLocal();
  }

  Future<void> moveToDate(TaskItem item, String nextDate) async {
    if (item.dueDate == nextDate) {
      return;
    }
    final changed = item.copyWith(
      dueDate: nextDate,
      updatedAt: DateTime.now().toIso8601String(),
      version: item.version + 1,
    );
    await repository.upsert(changed);
    _rememberUndo(_UndoRestoreTask(item));
    await refreshLocal();
  }

  Future<void> toggleDone(TaskItem item) async {
    await move(item, item.workflowStatus == 'done' ? 'todo' : 'done');
  }

  Future<void> delete(TaskItem item) async {
    await repository.delete(item);
    _rememberUndo(_UndoRestoreTask(item));
    await refreshLocal();
  }

  Future<int> deleteSelectedPersonalTasks() async {
    final selectedIds = selectedTaskIds.value;
    if (selectedIds.isEmpty) {
      return 0;
    }
    final toDelete = _allTasks
        .where((task) => !task.isFamily && selectedIds.contains(task.id))
        .toList();
    if (toDelete.isEmpty) {
      return 0;
    }
    for (final task in toDelete) {
      await repository.delete(task);
    }
    _rememberUndo(_UndoRestoreTasks(toDelete));
    setSelectionMode(false);
    await refreshLocal();
    return toDelete.length;
  }

  Future<bool> undoLastAction() async {
    final action = _lastUndoAction;
    if (action == null) {
      return false;
    }
    _lastUndoAction = null;
    canUndo.value = false;
    _muteUndo = true;
    try {
      await action.apply(repository);
      await refreshLocal();
      return true;
    } finally {
      _muteUndo = false;
    }
  }

  void _rememberUndo(_UndoAction action) {
    if (_muteUndo) {
      return;
    }
    _lastUndoAction = action;
    canUndo.value = true;
  }

  void _trimSelectionToExisting() {
    final existingIds = _allTasks
        .where((task) => !task.isFamily)
        .map((task) => task.id)
        .toSet();
    final trimmed = selectedTaskIds.value.where(existingIds.contains).toSet();
    if (trimmed.length != selectedTaskIds.value.length) {
      selectedTaskIds.value = trimmed;
    }
  }

  void _recomputeAllSlices() {
    allTasksView.value = List<TaskItem>.from(_allTasks);
    _recomputeDashboardOnly();
    _recomputeKanbanOnly();
    _recomputeDateSlicesOnly();
    _recomputeFamilyOnly();
  }

  void setDesktopTheme({
    required String mode,
    required String scheme,
    required List<String> schemes,
    required Map<String, String> tokens,
  }) {
    themeMode.value = mode;
    themeScheme.value = scheme;
    availableSchemes.value = List<String>.from(schemes);
    desktopThemeTokens.value = Map<String, String>.from(tokens);
  }

  void setVoiceHostState(DesktopHostState state) {
    voiceHostState.value = state;
  }

  void setBotHostState(DesktopHostState state) {
    botHostState.value = state;
  }

  void appendDesktopLog(String entry) {
    final next = List<String>.from(desktopLogEntries.value);
    next.add(entry);
    if (next.length > 120) {
      next.removeRange(0, next.length - 120);
    }
    desktopLogEntries.value = next;
  }

  void _recomputeDashboardOnly() {
    final dateKey = _dateKey(selectedDate.value);
    final today = _allTasks.where((task) => task.dueDate == dateKey).toList();
    final doneToday =
        today.where((task) => task.workflowStatus == 'done').length;
    final familyToday = today.where((task) => task.isFamily).length;
    final overdue = _allTasks
        .where(
          (task) =>
              task.dueDate.compareTo(dateKey) < 0 &&
              task.workflowStatus != 'done',
        )
        .length;
    final upcoming = _allTasks.toList()
      ..sort(
        (a, b) =>
            ('${a.dueDate} ${a.time}').compareTo('${b.dueDate} ${b.time}'),
      );
    dashboard.value = DashboardVm(
      todayKey: dateKey,
      todayTotal: today.length,
      doneToday: doneToday,
      familyToday: familyToday,
      overdue: overdue,
      upcoming: upcoming.take(8).toList(),
    );
  }

  void _recomputeKanbanOnly() {
    final filterDate = tasksDateFilter.value.isNotEmpty
        ? tasksDateFilter.value
        : _dateKey(selectedDate.value);
    final query = searchQuery.value;
    final personalTasks = _allTasks
        .where((task) => !task.isFamily && task.dueDate == filterDate)
        .where((task) {
      if (query.isEmpty) {
        return true;
      }
      final haystack =
          '${task.title} ${task.details} ${task.dueDate} ${task.time}'
              .toLowerCase();
      return haystack.contains(query);
    }).toList();

    final visibleIds = personalTasks.map((task) => task.id).toSet();
    final trimmed = selectedTaskIds.value.where(visibleIds.contains).toSet();
    if (trimmed.length != selectedTaskIds.value.length) {
      selectedTaskIds.value = trimmed;
    }

    personalByStatus.value = <String, List<TaskItem>>{
      'todo':
          personalTasks.where((task) => task.workflowStatus == 'todo').toList(),
      'in_progress': personalTasks
          .where((task) => task.workflowStatus == 'in_progress')
          .toList(),
      'in_review': personalTasks
          .where((task) => task.workflowStatus == 'in_review')
          .toList(),
      'done':
          personalTasks.where((task) => task.workflowStatus == 'done').toList(),
    };
  }

  void _recomputeDateSlicesOnly() {
    final dateKey = _dateKey(selectedDate.value);
    tasksForSelectedDate.value =
        _allTasks.where((task) => task.dueDate == dateKey).toList();
    _recomputeDashboardOnly();
  }

  void _recomputeFamilyOnly() {
    final mode = familyFilter.value;
    final todayKey = _dateKey(DateTime.now());
    final source = _allTasks
        .where(
          (task) => task.isFamily && task.assignees.contains(owner.value),
        )
        .toList()
      ..sort(
        (a, b) =>
            ('${a.dueDate} ${a.time}').compareTo('${b.dueDate} ${b.time}'),
      );
    List<TaskItem> filtered;
    if (mode == 'done') {
      filtered = source.where((task) => task.workflowStatus == 'done').toList();
    } else if (mode == 'overdue') {
      filtered = source
          .where(
            (task) =>
                task.dueDate.compareTo(todayKey) < 0 &&
                task.workflowStatus != 'done',
          )
          .toList();
    } else if (mode == 'all') {
      filtered = source;
    } else {
      filtered = source
          .where(
            (task) =>
                task.dueDate.compareTo(todayKey) >= 0 &&
                task.workflowStatus != 'done',
          )
          .toList();
    }
    familyTasksView.value = filtered;
  }

  String _dateKey(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  void dispose() {
    loading.dispose();
    owner.dispose();
    selectedDate.dispose();
    pageIndex.dispose();
    searchQuery.dispose();
    tasksDateFilter.dispose();
    familyFilter.dispose();
    selectionMode.dispose();
    selectedTaskIds.dispose();
    canUndo.dispose();
    dashboard.dispose();
    personalByStatus.dispose();
    tasksForSelectedDate.dispose();
    familyTasksView.dispose();
    allTasksView.dispose();
    themeMode.dispose();
    themeScheme.dispose();
    availableSchemes.dispose();
    desktopThemeTokens.dispose();
    voiceHostState.dispose();
    botHostState.dispose();
    desktopLogEntries.dispose();
  }
}
