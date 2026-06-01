import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/task_domain_service.dart';
import '../domain/task_draft.dart';
import '../models/family_group.dart';
import '../models/task_item.dart';
import '../models/task_project.dart';
import '../repositories/task_repository.dart';
import '../services/desktop_process_host_service.dart';
import '../services/local_db.dart';
import '../services/project_selection_storage.dart';
import 'desktop_state.dart';

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

class TaskSaveResult {
  const TaskSaveResult.success(this.task) : error = null;
  const TaskSaveResult.failure(this.error) : task = null;

  final TaskItem? task;
  final String? error;

  bool get isSuccess => error == null;
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
  TaskStore({
    required this.repository,
    required this.domainService,
    ProjectSelectionStorage? projectSelectionStorage,
  }) : projectSelectionStorage = projectSelectionStorage ??
            const SharedPreferencesProjectSelectionStorage();

  final TaskRepository repository;
  final TaskDomainService domainService;
  final ProjectSelectionStorage projectSelectionStorage;
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
    'archive': <TaskItem>[],
  });
  final ValueNotifier<List<TaskItem>> tasksForSelectedDate =
      ValueNotifier<List<TaskItem>>(const <TaskItem>[]);
  final ValueNotifier<List<TaskItem>> allTasksView =
      ValueNotifier<List<TaskItem>>(const <TaskItem>[]);
  // ── Projects & Family Groups ──
  final ValueNotifier<String> currentProjectId = ValueNotifier<String>('');
  final ValueNotifier<List<TaskProject>> projects =
      ValueNotifier<List<TaskProject>>(const <TaskProject>[]);
  final ValueNotifier<List<FamilyGroup>> familyGroups =
      ValueNotifier<List<FamilyGroup>>(const <FamilyGroup>[]);
  final ValueNotifier<Map<String, List<String>>> projectGroupMap =
      ValueNotifier<Map<String, List<String>>>(const <String, List<String>>{});

  // ── Desktop state (theme / voice / logs) extracted ──
  final DesktopState desktop = DesktopState();

  // Backward-compatible getters — existing UI code uses these directly.
  ValueNotifier<String> get themeMode => desktop.themeMode;
  ValueNotifier<String> get themeScheme => desktop.themeScheme;
  ValueNotifier<List<String>> get availableSchemes => desktop.availableSchemes;
  ValueNotifier<Map<String, String>> get desktopThemeTokens =>
      desktop.themeTokens;
  ValueNotifier<DesktopHostState> get voiceHostState => desktop.voiceHostState;
  ValueNotifier<List<String>> get desktopLogEntries => desktop.logEntries;

  bool get isAdult => true; // Any registered user has full permissions

  Future<void> initialize({
    required String initialOwner,
    DateTime? initialDate,
  }) async {
    loading.value = true;
    owner.value = initialOwner;
    selectedDate.value = initialDate ?? DateTime.now();
    await repository.bindActor(initialOwner);
    await refreshLocal();
    await refreshProjectsAndGroups();
    await _restoreLastProjectSelection();
    loading.value = false;
  }

  Future<void> switchOwner(String profile) async {
    if (profile == owner.value) {
      return;
    }
    loading.value = true;
    owner.value = profile;
    searchQuery.value = '';
    selectionMode.value = false;
    selectedTaskIds.value = <String>{};
    _lastUndoAction = null;
    canUndo.value = false;
    await repository.bindActor(profile);
    await refreshLocal();
    await refreshProjectsAndGroups();
    await _restoreLastProjectSelection();
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
    await refreshProjectsAndGroups();
  }

  // ── Project & group management ──────────────────────────────────────

  Future<void> refreshProjectsAndGroups() async {
    try {
      final projList = await repository.readProjects();
      final grpList = await repository.readFamilyGroups();
      final pgMap = await repository.readProjectGroupMap();
      projects.value = projList;
      familyGroups.value = grpList;
      projectGroupMap.value = pgMap;
      await _ensureValidProjectSelection(projList);
    } catch (_) {}
  }

  void setCurrentProject(String projectId) {
    if (currentProjectId.value == projectId) return;
    currentProjectId.value = projectId;
    if (projectId.trim().isEmpty) {
      unawaited(projectSelectionStorage.clearLastProjectId(owner.value));
    } else {
      unawaited(
        projectSelectionStorage.saveLastProjectId(owner.value, projectId),
      );
    }
    _recomputeAllSlices();
  }

  Future<void> _restoreLastProjectSelection() async {
    await _ensureValidProjectSelection(projects.value);
  }

  Future<void> _ensureValidProjectSelection(
    List<TaskProject> projectList,
  ) async {
    if (projectList.isEmpty) {
      if (currentProjectId.value.isNotEmpty) {
        currentProjectId.value = '';
        _recomputeAllSlices();
      }
      await projectSelectionStorage.clearLastProjectId(owner.value);
      return;
    }

    final currentId = currentProjectId.value;
    if (currentId.isNotEmpty &&
        projectList.any((project) => project.id == currentId)) {
      return;
    }

    final savedProjectId =
        await projectSelectionStorage.readLastProjectId(owner.value);
    final savedExists = savedProjectId.isNotEmpty &&
        projectList.any((project) => project.id == savedProjectId);
    final nextProjectId = savedExists ? savedProjectId : projectList.first.id;

    if (currentProjectId.value != nextProjectId) {
      currentProjectId.value = nextProjectId;
      _recomputeAllSlices();
    }
    if (savedProjectId != nextProjectId) {
      await projectSelectionStorage.saveLastProjectId(
        owner.value,
        nextProjectId,
      );
    }
  }

  Future<String> createProject(String name, String description) async {
    return createProjectWithGroups(name, description, const <String>[]);
  }

  Future<String> createProjectWithGroups(
    String name,
    String description,
    List<String> groupIds,
  ) async {
    final api = repository.api;
    final project = await api.createProject(
      actorProfile: owner.value,
      name: name,
      description: description,
    );
    if (groupIds.isNotEmpty) {
      await api.setProjectGroups(
        actorProfile: owner.value,
        projectId: project.id,
        groupIds: groupIds,
      );
    }
    // Persist immediately so the UI sees the new project without waiting for sync
    await repository.db.upsertProjectLocal(project);
    await repository.db.setProjectGroupsLocal(project.id, groupIds);
    await refreshProjectsAndGroups();
    return project.id;
  }

  Future<void> editProject(
    String id,
    String name,
    String description,
    List<String> groupIds,
  ) async {
    final api = repository.api;
    await api.updateProject(
      actorProfile: owner.value,
      id: id,
      name: name,
      description: description,
      groupIds: groupIds,
    );
    // Update local DB immediately
    await repository.db.upsertProjectLocal(
      TaskProject(
        id: id,
        name: name,
        description: description,
        ownerKey: owner.value,
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
      ),
    );
    // Update project-group mapping locally
    await repository.db.setProjectGroupsLocal(id, groupIds);
    await refreshProjectsAndGroups();
  }

  Future<void> deleteProject(String id) async {
    await repository.api.deleteProject(
      actorProfile: owner.value,
      id: id,
    );
    if (currentProjectId.value == id) {
      currentProjectId.value = '';
    }
    await repository.db.deleteProjectLocal(id);
    await refreshProjectsAndGroups();
  }

  Future<String> createFamilyGroup(String name, List<String> members) async {
    final group = await repository.api.createFamilyGroup(
      actorProfile: owner.value,
      name: name,
      members: members,
    );
    await repository.db.upsertFamilyGroupLocal(group);
    await refreshProjectsAndGroups();
    return group.id;
  }

  Future<void> editFamilyGroup(
    String id,
    String name,
    List<String> members,
  ) async {
    await repository.api.updateFamilyGroup(
      actorProfile: owner.value,
      id: id,
      name: name,
      members: members,
    );
    final existing = familyGroups.value.cast<FamilyGroup?>().firstWhere(
          (item) => item?.id == id,
          orElse: () => null,
        );
    await repository.db.upsertFamilyGroupLocal(
      FamilyGroup(
        id: id,
        name: name,
        members: members,
        ownerKey: existing?.ownerKey ?? owner.value,
        createdAt: existing?.createdAt ?? '',
        updatedAt: DateTime.now().toIso8601String(),
      ),
    );
    await refreshProjectsAndGroups();
  }

  Future<void> deleteFamilyGroup(String id) async {
    await repository.api.deleteFamilyGroup(
      actorProfile: owner.value,
      id: id,
    );
    await repository.db.deleteFamilyGroupLocal(id);
    await refreshProjectsAndGroups();
  }

  /// Members of all groups assigned to the current project
  List<String> get currentProjectGroupMembers {
    if (currentProjectId.value.isEmpty) return [];
    final gids = projectGroupMap.value[currentProjectId.value] ?? [];
    final members = <String>{};
    for (final gid in gids) {
      final group = familyGroups.value.cast<FamilyGroup?>().firstWhere(
            (g) => g?.id == gid,
            orElse: () => null,
          );
      if (group != null) {
        members.addAll(group.members);
      }
    }
    return members.toList()..sort();
  }

  Future<String?> saveDraft({
    required TaskDraft draft,
    TaskItem? existing,
  }) async {
    final result = await saveDraftWithResult(
      draft: draft,
      existing: existing,
    );
    return result.error;
  }

  Future<TaskSaveResult> saveDraftWithResult({
    required TaskDraft draft,
    TaskItem? existing,
    bool rememberUndo = true,
  }) async {
    final error = domainService.validateDraft(
      draft: draft,
      actorProfile: owner.value,
      projectOwnerKey: _projectOwnerKey(draft.projectId),
      projectGroupMembers: _projectGroupMembers(draft.projectId),
    );
    if (error != null) {
      return TaskSaveResult.failure(error);
    }

    final task = domainService.materializeTask(
      draft: draft,
      actorProfile: owner.value,
      now: DateTime.now(),
      existing: existing,
    );
    await repository.upsert(task);
    if (rememberUndo) {
      if (existing == null) {
        _rememberUndo(_UndoDeleteTask(task));
      } else {
        _rememberUndo(_UndoRestoreTask(existing));
      }
    }
    await refreshLocal();
    return TaskSaveResult.success(task);
  }

  Future<void> move(TaskItem item, WorkflowStatus nextStatus) async {
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
    final nextStatus = item.workflowStatus == WorkflowStatus.done
        ? WorkflowStatus.todo
        : WorkflowStatus.done;
    await move(item, nextStatus);
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
    final taskIds = _kanbanSource().map((task) => task.id).toSet();
    final trimmed = selectedTaskIds.value.where(taskIds.contains).toSet();
    if (trimmed.length != selectedTaskIds.value.length) {
      selectedTaskIds.value = trimmed;
    }
  }

  void _recomputeAllSlices() {
    allTasksView.value = List<TaskItem>.from(_allTasks);
    _recomputeDashboardOnly();
    _recomputeKanbanOnly();
    _recomputeDateSlicesOnly();
  }

  void setDesktopTheme({
    required String mode,
    required String scheme,
    required List<String> schemes,
    required Map<String, String> tokens,
  }) {
    desktop.setTheme(
      mode: mode,
      scheme: scheme,
      schemes: schemes,
      tokens: tokens,
    );
  }

  void setVoiceHostState(DesktopHostState state) {
    desktop.setVoiceHost(state);
  }

  void appendDesktopLog(String entry) {
    desktop.appendLog(entry);
  }

  void _recomputeDashboardOnly() {
    final dateKey = _dateKey(selectedDate.value);
    final visibleTasks = _visibleTasks();
    final today =
        visibleTasks.where((task) => task.dueDate == dateKey).toList();
    final doneToday = today
        .where((task) => task.workflowStatus == WorkflowStatus.done)
        .length;
    final familyToday = today.where((task) => task.isFamily).length;
    final overdue = visibleTasks
        .where(
          (task) =>
              task.dueDate.compareTo(dateKey) < 0 &&
              task.workflowStatus != WorkflowStatus.done,
        )
        .length;
    final upcoming = visibleTasks.toList()
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

  List<TaskItem> _visibleTasks() {
    final myGroups = _myGroupIds();
    return _allTasks
        .where(
          (task) => domainService.isVisibleToActor(
            task: task,
            actorProfile: owner.value,
            actorGroupIds: myGroups,
            currentProjectId: currentProjectId.value,
          ),
        )
        .toList();
  }

  /// Returns tasks visible in kanban — user sees assigned tasks and group tasks.
  List<TaskItem> _kanbanSource() {
    final query = searchQuery.value;
    final tasks = _visibleTasks();
    if (query.isEmpty) {
      return tasks;
    }
    return tasks.where((task) {
      return task.title.toLowerCase().contains(query) ||
          task.details.toLowerCase().contains(query) ||
          task.tags.any((tag) => tag.toLowerCase().contains(query));
    }).toList();
  }

  /// Set of group IDs where the current user is a member.
  Set<String> _myGroupIds() {
    final ids = <String>{};
    for (final group in familyGroups.value) {
      if (group.members.contains(owner.value)) {
        ids.add(group.id);
      }
    }
    return ids;
  }

  String _projectOwnerKey(String projectId) {
    if (projectId.isEmpty) {
      return '';
    }
    final project = projects.value.cast<TaskProject?>().firstWhere(
          (item) => item?.id == projectId,
          orElse: () => null,
        );
    return project?.ownerKey ?? '';
  }

  Map<String, List<String>> _projectGroupMembers(String projectId) {
    if (projectId.isEmpty) {
      return const {};
    }
    final allowedGroupIds = projectGroupMap.value[projectId] ?? const [];
    final out = <String, List<String>>{};
    for (final group in familyGroups.value) {
      if (allowedGroupIds.contains(group.id)) {
        out[group.id] = List<String>.from(group.members);
      }
    }
    return out;
  }

  void _recomputeKanbanOnly() {
    final kanbanTasks = _kanbanSource()
      ..sort(
        (a, b) =>
            ('${a.dueDate} ${a.time}').compareTo('${b.dueDate} ${b.time}'),
      );

    final visibleIds = kanbanTasks.map((task) => task.id).toSet();
    final trimmed = selectedTaskIds.value.where(visibleIds.contains).toSet();
    if (trimmed.length != selectedTaskIds.value.length) {
      selectedTaskIds.value = trimmed;
    }

    personalByStatus.value = <String, List<TaskItem>>{
      WorkflowStatus.todo.name: kanbanTasks
          .where((task) => task.workflowStatus == WorkflowStatus.todo)
          .toList(),
      WorkflowStatus.in_progress.name: kanbanTasks
          .where((task) => task.workflowStatus == WorkflowStatus.in_progress)
          .toList(),
      WorkflowStatus.in_review.name: kanbanTasks
          .where((task) => task.workflowStatus == WorkflowStatus.in_review)
          .toList(),
      WorkflowStatus.done.name: kanbanTasks
          .where((task) => task.workflowStatus == WorkflowStatus.done)
          .toList(),
      WorkflowStatus.archive.name: kanbanTasks
          .where((task) => task.workflowStatus == WorkflowStatus.archive)
          .toList(),
    };
  }

  void _recomputeDateSlicesOnly() {
    final dateKey = _dateKey(selectedDate.value);
    tasksForSelectedDate.value = _visibleTasks()
        .where(
          (task) => task.dueDate == dateKey,
        )
        .toList()
      ..sort(
        (a, b) =>
            ('${a.dueDate} ${a.time}').compareTo('${b.dueDate} ${b.time}'),
      );
    _recomputeDashboardOnly();
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
    selectionMode.dispose();
    selectedTaskIds.dispose();
    canUndo.dispose();
    dashboard.dispose();
    personalByStatus.dispose();
    tasksForSelectedDate.dispose();
    allTasksView.dispose();
    currentProjectId.dispose();
    projects.dispose();
    familyGroups.dispose();
    projectGroupMap.dispose();
    desktop.dispose();
  }
}
