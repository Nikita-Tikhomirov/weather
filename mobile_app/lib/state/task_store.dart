import 'package:flutter/foundation.dart';

import '../domain/task_domain_service.dart';
import '../domain/task_draft.dart';
import '../models/task_item.dart';
import '../repositories/task_repository.dart';

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

class TaskStore {
  TaskStore({
    required this.repository,
    required this.domainService,
  });

  final TaskRepository repository;
  final TaskDomainService domainService;
  final List<TaskItem> _allTasks = <TaskItem>[];

  final ValueNotifier<bool> loading = ValueNotifier<bool>(true);
  final ValueNotifier<String> owner = ValueNotifier<String>('nik');
  final ValueNotifier<DateTime> selectedDate = ValueNotifier<DateTime>(
    DateTime.now(),
  );
  final ValueNotifier<int> pageIndex = ValueNotifier<int>(0);
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
      ValueNotifier<Map<String, List<TaskItem>>>(
        const {
          'todo': <TaskItem>[],
          'in_progress': <TaskItem>[],
          'in_review': <TaskItem>[],
          'done': <TaskItem>[],
        },
      );
  final ValueNotifier<List<TaskItem>> tasksForSelectedDate =
      ValueNotifier<List<TaskItem>>(const <TaskItem>[]);
  final ValueNotifier<List<TaskItem>> familyTasksForSelectedDate =
      ValueNotifier<List<TaskItem>>(const <TaskItem>[]);

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

  Future<void> refreshLocal() async {
    final tasks = await repository.readVisibleTasks();
    _allTasks
      ..clear()
      ..addAll(tasks);
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
    await refreshLocal();
  }

  Future<void> toggleDone(TaskItem item) async {
    await move(item, item.workflowStatus == 'done' ? 'todo' : 'done');
  }

  Future<void> delete(TaskItem item) async {
    await repository.delete(item);
    await refreshLocal();
  }

  void _recomputeAllSlices() {
    _recomputeDashboardOnly();
    _recomputeKanbanOnly();
    _recomputeDateSlicesOnly();
  }

  void _recomputeDashboardOnly() {
    final dateKey = _dateKey(selectedDate.value);
    final today = _allTasks.where((task) => task.dueDate == dateKey).toList();
    final doneToday = today.where((task) => task.workflowStatus == 'done').length;
    final familyToday = today.where((task) => task.isFamily).length;
    final overdue = _allTasks
        .where(
          (task) => task.dueDate.compareTo(dateKey) < 0 && task.workflowStatus != 'done',
        )
        .length;
    final upcoming = _allTasks.toList()
      ..sort(
        (a, b) => ('${a.dueDate} ${a.time}').compareTo('${b.dueDate} ${b.time}'),
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
    final dateKey = _dateKey(selectedDate.value);
    final personalDateTasks = _allTasks
        .where((task) => !task.isFamily && task.dueDate == dateKey)
        .toList();
    personalByStatus.value = <String, List<TaskItem>>{
      'todo': personalDateTasks.where((task) => task.workflowStatus == 'todo').toList(),
      'in_progress': personalDateTasks
          .where((task) => task.workflowStatus == 'in_progress')
          .toList(),
      'in_review': personalDateTasks.where((task) => task.workflowStatus == 'in_review').toList(),
      'done': personalDateTasks.where((task) => task.workflowStatus == 'done').toList(),
    };
  }

  void _recomputeDateSlicesOnly() {
    final dateKey = _dateKey(selectedDate.value);
    final dayTasks = _allTasks.where((task) => task.dueDate == dateKey).toList();
    tasksForSelectedDate.value = dayTasks;
    familyTasksForSelectedDate.value = dayTasks
        .where((task) => task.isFamily && task.assignees.contains(owner.value))
        .toList();
    _recomputeDashboardOnly();
    _recomputeKanbanOnly();
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
    dashboard.dispose();
    personalByStatus.dispose();
    tasksForSelectedDate.dispose();
    familyTasksForSelectedDate.dispose();
  }
}
