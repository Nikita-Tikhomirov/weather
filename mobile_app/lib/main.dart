import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'domain/task_draft.dart';
import 'domain/task_domain_service.dart';
import 'models/task_item.dart';
import 'repositories/task_repository.dart';
import 'services/api_client.dart';
import 'services/fcm_service.dart';
import 'services/local_db.dart';
import 'state/task_store.dart';

const kProfileLabels = {
  'nik': 'Ник',
  'nastya': 'Настя',
  'misha': 'Миша',
  'arisha': 'Ариша',
  'family': 'Семья',
};

const kWorkflowLabels = {
  'todo': 'К выполнению',
  'in_progress': 'В работе',
  'in_review': 'На проверке',
  'done': 'Выполнено',
};

String profileLabel(String key) => kProfileLabels[key] ?? key;
String workflowLabel(String key) => kWorkflowLabels[key] ?? key;

void main() {
  runApp(const FamilyTodoApp());
}

class FamilyTodoApp extends StatelessWidget {
  const FamilyTodoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Семейные задачи',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF118AB2)),
        scaffoldBackgroundColor: const Color(0xFFF7FAFC),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _profiles = ['nik', 'nastya', 'misha', 'arisha'];

  TaskStore? _store;
  FcmService? _fcm;
  Timer? _deltaSyncTimer;
  Timer? _fullSyncTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final owner = prefs.getString('actor_profile') ?? 'nik';

    final db = await LocalDb.open();
    final api = ApiClient(
      baseUrl: const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'https://familly.nikportfolio.ru/backend_api/public',
      ),
      apiKey: const String.fromEnvironment(
        'API_KEY',
        defaultValue: 'dev-local-key',
      ),
    );
    final repository = TaskRepository(db: db, api: api);
    final store = TaskStore(
      repository: repository,
      domainService: TaskDomainService(),
    );
    await store.initialize(initialOwner: owner);
    await _safeSyncFull(store, showErrors: false);
    _bindFcm(api: api, owner: owner);
    _startSyncLoops(store);
    if (!mounted) {
      store.dispose();
      return;
    }
    setState(() {
      _store = store;
    });
  }

  void _bindFcm({
    required ApiClient api,
    required String owner,
  }) {
    _fcm = FcmService(
      api: api,
      actorProfile: owner,
      onForegroundText: (text) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
      },
      onOpenPush: () async {
        final store = _store;
        if (store == null) {
          return;
        }
        await _safeSyncDelta(store, showErrors: false);
      },
    );
    _fcm!.initialize().catchError((_) {});
  }

  void _startSyncLoops(TaskStore store) {
    _cancelSyncLoops();
    _deltaSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      await _safeSyncDelta(store, showErrors: false);
    });
    _fullSyncTimer = Timer.periodic(const Duration(minutes: 10), (_) async {
      await _safeSyncFull(store, showErrors: false);
    });
  }

  void _cancelSyncLoops() {
    _deltaSyncTimer?.cancel();
    _deltaSyncTimer = null;
    _fullSyncTimer?.cancel();
    _fullSyncTimer = null;
  }

  Future<void> _safeSyncDelta(
    TaskStore store, {
    required bool showErrors,
  }) async {
    try {
      await store.syncDelta();
    } catch (error) {
      if (showErrors && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка синхронизации: $error')));
      }
    }
  }

  Future<void> _safeSyncFull(
    TaskStore store, {
    required bool showErrors,
  }) async {
    try {
      await store.syncFull();
    } catch (error) {
      if (showErrors && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка синхронизации: $error')));
      }
    }
  }

  Future<void> _switchProfile(TaskStore store, String profile) async {
    if (profile == store.owner.value) {
      return;
    }
    _cancelSyncLoops();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('actor_profile', profile);
    await store.switchOwner(profile);
    _bindFcm(api: store.repository.api, owner: profile);
    _startSyncLoops(store);
  }

  String _dateKey(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  Future<void> _openTaskEditor(
    TaskStore store, {
    TaskItem? existing,
    bool forceFamily = false,
  }) async {
    final titleCtl = TextEditingController(text: existing?.title ?? '');
    final detailsCtl = TextEditingController(text: existing?.details ?? '');
    final durationCtl = TextEditingController(
      text: existing == null ? '' : existing.durationMinutes.toString(),
    );
    final selectedAssignees = <String>{...(existing?.assignees ?? const <String>[])};
    DateTime selected = existing == null
        ? store.selectedDate.value
        : DateTime.tryParse(existing.dueDate) ?? store.selectedDate.value;
    String time = existing?.time ?? '19:00';
    String priority = existing?.priority ?? 'medium';
    String status = existing?.workflowStatus ?? 'todo';
    bool isFamily = forceFamily || (existing?.isFamily ?? false);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      existing == null ? 'Новая задача' : 'Редактирование задачи',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: titleCtl,
                      decoration: const InputDecoration(labelText: 'Название'),
                    ),
                    TextField(
                      controller: detailsCtl,
                      decoration: const InputDecoration(labelText: 'Описание'),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.calendar_month),
                            label: Text(_dateKey(selected)),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: selected,
                                firstDate: DateTime(2024),
                                lastDate: DateTime(2035),
                              );
                              if (picked != null) {
                                setModalState(() => selected = picked);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.schedule),
                            label: Text(time),
                            onPressed: () async {
                              final parts = time.split(':');
                              final initial = TimeOfDay(
                                hour: int.tryParse(parts.first) ?? 19,
                                minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
                              );
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: initial,
                              );
                              if (picked != null) {
                                setModalState(() {
                                  time =
                                      '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    DropdownButtonFormField<String>(
                      value: priority,
                      decoration: const InputDecoration(labelText: 'Приоритет'),
                      items: const [
                        DropdownMenuItem(value: 'low', child: Text('Низкий')),
                        DropdownMenuItem(value: 'medium', child: Text('Средний')),
                        DropdownMenuItem(value: 'high', child: Text('Высокий')),
                      ],
                      onChanged: (value) => setModalState(() => priority = value ?? 'medium'),
                    ),
                    DropdownButtonFormField<String>(
                      value: status,
                      decoration: const InputDecoration(labelText: 'Статус'),
                      items: const [
                        DropdownMenuItem(value: 'todo', child: Text('К выполнению')),
                        DropdownMenuItem(value: 'in_progress', child: Text('В работе')),
                        DropdownMenuItem(value: 'in_review', child: Text('На проверке')),
                        DropdownMenuItem(value: 'done', child: Text('Выполнено')),
                      ],
                      onChanged: (value) => setModalState(() => status = value ?? 'todo'),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Семейная задача'),
                      value: isFamily,
                      onChanged: forceFamily ? null : (value) => setModalState(() => isFamily = value),
                    ),
                    if (isFamily) ...[
                      TextField(
                        controller: durationCtl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Длительность (мин)'),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Ответственные',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _profiles.map((profile) {
                          return FilterChip(
                            label: Text(profileLabel(profile)),
                            selected: selectedAssignees.contains(profile),
                            onSelected: (selected) {
                              setModalState(() {
                                if (selected) {
                                  selectedAssignees.add(profile);
                                } else {
                                  selectedAssignees.remove(profile);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Отмена'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              final draft = TaskDraft(
                                title: titleCtl.text.trim(),
                                details: detailsCtl.text.trim(),
                                dueDate: _dateKey(selected),
                                time: time,
                                priority: priority,
                                workflowStatus: status,
                                isFamily: isFamily,
                                assignees: selectedAssignees.toList(),
                                durationMinutes: int.tryParse(durationCtl.text.trim()) ?? 0,
                              );
                              final error = await store.saveDraft(
                                draft: draft,
                                existing: existing,
                              );
                              if (error != null && mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(error)),
                                );
                                return;
                              }
                              if (!mounted) {
                                return;
                              }
                              Navigator.pop(context);
                              await _safeSyncDelta(store, showErrors: true);
                            },
                            child: const Text('Сохранить'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    if (store == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return ValueListenableBuilder<bool>(
      valueListenable: store.loading,
      builder: (context, loading, _) {
        return ValueListenableBuilder<String>(
          valueListenable: store.owner,
          builder: (context, owner, __) {
            return ValueListenableBuilder<DateTime>(
              valueListenable: store.selectedDate,
              builder: (context, selectedDate, ___) {
                final selectedDateKey = _dateKey(selectedDate);
                return Scaffold(
                  appBar: AppBar(
                    title: Text('Family tasks - $selectedDateKey'),
                    actions: [
                      PopupMenuButton<String>(
                        initialValue: owner,
                        onSelected: (value) async => _switchProfile(store, value),
                        itemBuilder: (context) => _profiles
                            .map(
                              (profile) => PopupMenuItem<String>(
                                value: profile,
                                child: Text(profileLabel(profile)),
                              ),
                            )
                            .toList(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          child: Center(
                            child: Text(
                              profileLabel(owner),
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Calendar',
                        icon: const Icon(Icons.calendar_month),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime(2024),
                            lastDate: DateTime(2035),
                          );
                          if (picked != null) {
                            store.setSelectedDate(picked);
                          }
                        },
                      ),
                      IconButton(
                        tooltip: 'Sync now',
                        icon: const Icon(Icons.sync),
                        onPressed: () async => _safeSyncFull(store, showErrors: true),
                      ),
                    ],
                  ),
                  body: loading
                      ? const Center(child: CircularProgressIndicator())
                      : ValueListenableBuilder<int>(
                          valueListenable: store.pageIndex,
                          builder: (context, page, ____) {
                            if (page == 0) {
                              return ValueListenableBuilder<DashboardVm>(
                                valueListenable: store.dashboard,
                                builder: (context, vm, _) {
                                  return _DashboardView(
                                    vm: vm,
                                    onOpenCalendar: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: selectedDate,
                                        firstDate: DateTime(2024),
                                        lastDate: DateTime(2035),
                                      );
                                      if (picked != null) {
                                        store.setSelectedDate(picked);
                                      }
                                    },
                                  );
                                },
                              );
                            }
                            if (page == 1) {
                              return ValueListenableBuilder<Map<String, List<TaskItem>>>(
                                valueListenable: store.personalByStatus,
                                builder: (context, byStatus, _) {
                                  return _TasksBoard(
                                    byStatus: byStatus,
                                    onDrop: (item, status) async {
                                      await store.move(item, status);
                                      await _safeSyncDelta(store, showErrors: true);
                                    },
                                    onEdit: (task) => _openTaskEditor(store, existing: task),
                                    onDelete: (task) async {
                                      await store.delete(task);
                                      await _safeSyncDelta(store, showErrors: true);
                                    },
                                    onDoneToggle: (task) async {
                                      await store.toggleDone(task);
                                      await _safeSyncDelta(store, showErrors: true);
                                    },
                                  );
                                },
                              );
                            }
                            if (page == 2) {
                              return ValueListenableBuilder<List<TaskItem>>(
                                valueListenable: store.tasksForSelectedDate,
                                builder: (context, tasks, _) {
                                  return _CalendarView(
                                    selectedDate: selectedDate,
                                    tasksForSelectedDate: tasks,
                                    onDateChange: store.setSelectedDate,
                                    onEdit: (task) => _openTaskEditor(store, existing: task),
                                    onDelete: (task) async {
                                      await store.delete(task);
                                      await _safeSyncDelta(store, showErrors: true);
                                    },
                                  );
                                },
                              );
                            }
                            return ValueListenableBuilder<List<TaskItem>>(
                              valueListenable: store.familyTasksForSelectedDate,
                              builder: (context, tasks, _) {
                                return _FamilyView(
                                  familyTasks: tasks,
                                  onEdit: (task) => _openTaskEditor(store, existing: task),
                                  onDelete: (task) async {
                                    await store.delete(task);
                                    await _safeSyncDelta(store, showErrors: true);
                                  },
                                );
                              },
                            );
                          },
                        ),
                  floatingActionButton: ValueListenableBuilder<int>(
                    valueListenable: store.pageIndex,
                    builder: (context, page, _) {
                      if (page != 1 && page != 3) {
                        return const SizedBox.shrink();
                      }
                      return FloatingActionButton.extended(
                        onPressed: () => _openTaskEditor(
                          store,
                          forceFamily: page == 3,
                        ),
                        icon: const Icon(Icons.add),
                        label: Text(page == 3 ? 'Family task' : 'Task'),
                      );
                    },
                  ),
                  bottomNavigationBar: ValueListenableBuilder<int>(
                    valueListenable: store.pageIndex,
                    builder: (context, page, _) {
                      return NavigationBar(
                        selectedIndex: page,
                        onDestinationSelected: store.setPage,
                        destinations: const [
                          NavigationDestination(
                            icon: Icon(Icons.dashboard_outlined),
                            label: 'Dashboard',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.view_kanban_outlined),
                            label: 'Tasks',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.calendar_month_outlined),
                            label: 'Calendar',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.family_restroom_outlined),
                            label: 'Family',
                          ),
                        ],
                      );
                    },
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _cancelSyncLoops();
    _store?.dispose();
    super.dispose();
  }
}

class _DashboardView extends StatelessWidget {
  const _DashboardView({
    required this.vm,
    required this.onOpenCalendar,
  });

  final DashboardVm vm;
  final Future<void> Function() onOpenCalendar;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: 'На дату',
                value: '${vm.todayTotal}',
                hint: vm.todayKey,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricCard(
                title: 'Сделано',
                value: '${vm.doneToday}',
                hint: 'Выполнено',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: 'Семейных',
                value: '${vm.familyToday}',
                hint: 'Семейные',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricCard(
                title: 'Просрочено',
                value: '${vm.overdue}',
                hint: 'Просрочка',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onOpenCalendar,
          icon: const Icon(Icons.calendar_month),
          label: const Text('Выбрать дату'),
        ),
        const SizedBox(height: 12),
        Text('Ближайшие задачи', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final task in vm.upcoming)
          Card(
            child: ListTile(
              title: Text(task.title),
              subtitle: Text(
                '${task.dueDate} ${task.time} - ${profileLabel(task.ownerKey)} - ${workflowLabel(task.workflowStatus)}',
              ),
              trailing: task.isFamily ? const Icon(Icons.family_restroom) : null,
            ),
          ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.hint,
  });

  final String title;
  final String value;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(hint, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _CalendarView extends StatelessWidget {
  const _CalendarView({
    required this.selectedDate,
    required this.tasksForSelectedDate,
    required this.onDateChange,
    required this.onEdit,
    required this.onDelete,
  });

  final DateTime selectedDate;
  final List<TaskItem> tasksForSelectedDate;
  final void Function(DateTime) onDateChange;
  final Future<void> Function(TaskItem) onEdit;
  final Future<void> Function(TaskItem) onDelete;

  @override
  Widget build(BuildContext context) {
    final start = selectedDate.subtract(const Duration(days: 3));
    final days = List.generate(10, (index) => start.add(Duration(days: index)));

    return Column(
      children: [
        SizedBox(
          height: 86,
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            scrollDirection: Axis.horizontal,
            itemCount: days.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final date = days[index];
              final isCurrent = date.year == selectedDate.year &&
                  date.month == selectedDate.month &&
                  date.day == selectedDate.day;
              return ChoiceChip(
                selected: isCurrent,
                label: Text(
                  '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}',
                ),
                onSelected: (_) => onDateChange(date),
              );
            },
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              if (tasksForSelectedDate.isEmpty)
                const Card(
                  child: ListTile(title: Text('На выбранную дату задач нет')),
                ),
              for (final item in tasksForSelectedDate)
                _TaskCard(
                  item: item,
                  onEdit: () => onEdit(item),
                  onDelete: () => onDelete(item),
                  onDoneToggle: () async {},
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TasksBoard extends StatelessWidget {
  const _TasksBoard({
    required this.byStatus,
    required this.onDrop,
    required this.onEdit,
    required this.onDelete,
    required this.onDoneToggle,
  });

  final Map<String, List<TaskItem>> byStatus;
  final Future<void> Function(TaskItem, String) onDrop;
  final Future<void> Function(TaskItem) onEdit;
  final Future<void> Function(TaskItem) onDelete;
  final Future<void> Function(TaskItem) onDoneToggle;

  static const _titles = {
    'todo': 'К выполнению',
    'in_progress': 'В работе',
    'in_review': 'На проверке',
    'done': 'Выполнено',
  };

  static const _colors = {
    'todo': Color(0xFFE3F2FD),
    'in_progress': Color(0xFFE8F5E9),
    'in_review': Color(0xFFFFF3E0),
    'done': Color(0xFFEDE7F6),
  };

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: _titles.keys.map((status) {
        final items = byStatus[status] ?? const <TaskItem>[];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: _colors[status],
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: DragTarget<TaskItem>(
              onAcceptWithDetails: (details) => onDrop(details.data, status),
              builder: (context, candidate, rejected) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_titles[status]} (${items.length})',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final item in items)
                      LongPressDraggable<TaskItem>(
                        data: item,
                        feedback: Material(
                          color: Colors.transparent,
                          child: SizedBox(
                            width: 250,
                            child: _TaskCard(
                              item: item,
                              onEdit: () async {},
                              onDelete: () async {},
                              onDoneToggle: () async {},
                            ),
                          ),
                        ),
                        childWhenDragging: const SizedBox.shrink(),
                        child: _TaskCard(
                          item: item,
                          onEdit: () => onEdit(item),
                          onDelete: () => onDelete(item),
                          onDoneToggle: () => onDoneToggle(item),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _FamilyView extends StatelessWidget {
  const _FamilyView({
    required this.familyTasks,
    required this.onEdit,
    required this.onDelete,
  });

  final List<TaskItem> familyTasks;
  final Future<void> Function(TaskItem) onEdit;
  final Future<void> Function(TaskItem) onDelete;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('Семейные задачи', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (familyTasks.isEmpty)
          const Card(
            child: ListTile(title: Text('На эту дату семейных задач нет')),
          ),
        for (final item in familyTasks)
          _TaskCard(
            item: item,
            onEdit: () => onEdit(item),
            onDelete: () => onDelete(item),
            onDoneToggle: () async {},
          ),
      ],
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.item,
    required this.onEdit,
    required this.onDelete,
    required this.onDoneToggle,
  });

  final TaskItem item;
  final Future<void> Function() onEdit;
  final Future<void> Function() onDelete;
  final Future<void> Function() onDoneToggle;

  @override
  Widget build(BuildContext context) {
    final assigneeLabels = item.assignees.map(profileLabel).toList();
    final subtitle = [
      '${item.dueDate} ${item.time}'.trim(),
      'Статус: ${workflowLabel(item.workflowStatus)}',
      if (item.isFamily && assigneeLabels.isNotEmpty)
        'Ответственные: ${assigneeLabels.join(', ')}',
      if (item.isFamily && item.durationMinutes > 0)
        'Длительность: ${item.durationMinutes} мин',
      if (item.details.isNotEmpty) item.details,
      'Владелец: ${profileLabel(item.ownerKey)}',
    ].join('\n');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => onEdit(),
        title: Text(item.title),
        subtitle: Text(subtitle),
        isThreeLine: true,
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(
              tooltip: 'Выполнить/отменить',
              icon: Icon(
                item.workflowStatus == 'done' ? Icons.undo : Icons.check_circle,
              ),
              onPressed: () => onDoneToggle(),
            ),
            IconButton(
              tooltip: 'Удалить',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => onDelete(),
            ),
          ],
        ),
      ),
    );
  }
}
