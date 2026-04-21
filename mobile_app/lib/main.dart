import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/task_item.dart';
import 'services/api_client.dart';
import 'services/fcm_service.dart';
import 'services/local_db.dart';
import 'services/sync_service.dart';

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
  late final LocalDb _db;
  late final ApiClient _api;
  SyncService? _sync;
  FcmService? _fcm;

  final _allTasks = <TaskItem>[];
  bool _loading = true;
  String _owner = 'nik';
  DateTime _selectedDate = DateTime.now();
  int _pageIndex = 0;

  static const _profiles = ['nik', 'nastya', 'misha', 'arisha'];
  static const _profileLabels = {
    'nik': 'Ник',
    'nastya': 'Настя',
    'misha': 'Миша',
    'arisha': 'Ариша',
  };
  static const _adults = {'nik', 'nastya'};
  static const _statuses = ['todo', 'in_progress', 'in_review', 'done'];

  bool get _isAdult => _adults.contains(_owner);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _owner = prefs.getString('actor_profile') ?? 'nik';

    _db = await LocalDb.open();
    _api = ApiClient(
      baseUrl: const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'https://familly.nikportfolio.ru/backend_api/public',
      ),
      apiKey: const String.fromEnvironment('API_KEY', defaultValue: 'dev-local-key'),
    );

    await _bindOwner();
    setState(() {
      _loading = false;
    });
  }

  Future<void> _bindOwner() async {
    _sync = SyncService(db: _db, api: _api, actorProfile: _owner);

    await _refreshLocal();
    await _safeSync();

    _fcm = FcmService(
      api: _api,
      actorProfile: _owner,
      onForegroundText: (text) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(text)),
        );
      },
      onOpenPush: () async {
        await _safeSync();
      },
    );

    try {
      await _fcm!.initialize();
    } catch (_) {}
  }

  Future<void> _safeSync({bool showErrors = false}) async {
    if (_sync == null) {
      return;
    }
    try {
      await _sync!.sync();
      await _refreshLocal();
    } catch (e) {
      if (showErrors && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка синхронизации: $e')),
        );
      }
    }
  }

  Future<void> _switchProfile(String profile) async {
    if (profile == _owner) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('actor_profile', profile);

    setState(() {
      _owner = profile;
      _loading = true;
      _allTasks.clear();
    });

    await _bindOwner();

    setState(() {
      _loading = false;
    });
  }

  Future<void> _refreshLocal() async {
    final tasks = await _db.readTasks(
      ownerKey: _owner,
      includeAll: false,
    );
    setState(() {
      _allTasks
        ..clear()
        ..addAll(tasks);
    });
  }

  String _dateKey(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  bool _isSameDate(String dueDate, DateTime d) => dueDate == _dateKey(d);

  Future<void> _openTaskEditor({TaskItem? existing, bool forceFamily = false}) async {
    final titleCtl = TextEditingController(text: existing?.title ?? '');
    final detailsCtl = TextEditingController(text: existing?.details ?? '');
    final durationCtl = TextEditingController(
      text: existing == null ? '' : existing.durationMinutes.toString(),
    );
    final selectedAssignees = <String>{
      ...(existing?.assignees ?? const <String>[]),
    };

    DateTime selected = existing == null
        ? _selectedDate
        : DateTime.tryParse(existing.dueDate) ?? _selectedDate;
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
                                  time = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
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
                      onChanged: (v) => setModalState(() => priority = v ?? 'medium'),
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
                      onChanged: (v) => setModalState(() => status = v ?? 'todo'),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Семейная задача'),
                      value: isFamily,
                      onChanged: forceFamily ? null : (v) => setModalState(() => isFamily = v),
                    ),
                    if (isFamily) ...[
                      TextField(
                        controller: durationCtl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Длительность (мин)'),
                      ),
                      const SizedBox(height: 8),
                      Text('Ответственные', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _profiles.map((profile) {
                          return FilterChip(
                            label: Text(_profileLabels[profile] ?? profile),
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
                              final title = titleCtl.text.trim();
                              if (title.isEmpty || _sync == null) {
                                return;
                              }
                              final now = DateTime.now().toIso8601String();
                              final assignees = selectedAssignees.toList()..sort();
                              if (isFamily && !_isAdult) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Семейные задачи можно создавать только из взрослого профиля (Ник/Настя).',
                                      ),
                                    ),
                                  );
                                }
                                return;
                              }
                              if (isFamily && assignees.isEmpty) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Выберите хотя бы одного ответственного.')),
                                  );
                                }
                                return;
                              }
                              final task = (existing ??
                                      TaskItem(
                                        id: 'm-${DateTime.now().microsecondsSinceEpoch}',
                                        ownerKey: _owner,
                                        isFamily: isFamily,
                                        title: title,
                                        details: detailsCtl.text.trim(),
                                        dueDate: _dateKey(selected),
                                        time: time,
                                        workflowStatus: status,
                                        priority: priority,
                                        tags: const [],
                                        assignees: assignees,
                                        durationMinutes: int.tryParse(durationCtl.text.trim()) ?? 0,
                                        updatedAt: now,
                                        version: 1,
                                      ))
                                  .copyWith(
                                isFamily: isFamily,
                                title: title,
                                details: detailsCtl.text.trim(),
                                dueDate: _dateKey(selected),
                                time: time,
                                workflowStatus: status,
                                priority: priority,
                                assignees: assignees,
                                durationMinutes: int.tryParse(durationCtl.text.trim()) ?? 0,
                                updatedAt: now,
                                version: (existing?.version ?? 0) + 1,
                              );

                              await _sync!.enqueueUpsert(task);
                              await _refreshLocal();
                              if (mounted) {
                                Navigator.pop(context);
                              }
                              await _safeSync(showErrors: true);
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

  Future<void> _move(TaskItem item, String status) async {
    if (_sync == null || item.workflowStatus == status) {
      return;
    }
    final changed = item.copyWith(
      workflowStatus: status,
      updatedAt: DateTime.now().toIso8601String(),
      version: item.version + 1,
    );
    await _sync!.enqueueUpsert(changed);
    await _refreshLocal();
    await _safeSync(showErrors: true);
  }

  Future<void> _toggleDone(TaskItem item) async {
    await _move(item, item.workflowStatus == 'done' ? 'todo' : 'done');
  }

  Future<void> _delete(TaskItem item) async {
    if (_sync == null) {
      return;
    }
    await _sync!.enqueueDelete(
      item.id,
      ownerKey: item.ownerKey,
      isFamily: item.isFamily,
    );
    await _refreshLocal();
    await _safeSync(showErrors: true);
  }

  List<TaskItem> get _dateTasks =>
      _allTasks.where((t) => _isSameDate(t.dueDate, _selectedDate)).toList();

  List<TaskItem> get _familyDateTasks => _dateTasks
      .where((t) => t.isFamily && t.assignees.contains(_owner))
      .toList();

  List<TaskItem> get _personalDateTasks => _dateTasks.where((t) => !t.isFamily).toList();

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final byStatus = {
      for (final s in _statuses)
        s: _personalDateTasks.where((t) => t.workflowStatus == s).toList(),
    };

    switch (_pageIndex) {
      case 0:
        return _DashboardView(
          allTasks: _allTasks,
          selectedDate: _selectedDate,
          onOpenCalendar: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _selectedDate,
              firstDate: DateTime(2024),
              lastDate: DateTime(2035),
            );
            if (picked != null) {
              setState(() => _selectedDate = picked);
            }
          },
        );
      case 1:
        return _TasksBoard(
          byStatus: byStatus,
          onDrop: _move,
          onEdit: (t) => _openTaskEditor(existing: t),
          onDelete: _delete,
          onDoneToggle: _toggleDone,
        );
      case 2:
        return _CalendarView(
          selectedDate: _selectedDate,
          tasksForSelectedDate: _dateTasks,
          onDateChange: (d) => setState(() => _selectedDate = d),
          onEdit: (t) => _openTaskEditor(existing: t),
          onDelete: _delete,
        );
      default:
        return _FamilyView(
          familyTasks: _familyDateTasks,
          onEdit: (t) => _openTaskEditor(existing: t),
          onDelete: _delete,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedKey = _dateKey(_selectedDate);
    return Scaffold(
      appBar: AppBar(
        title: Text('Семейные задачи • $selectedKey'),
        actions: [
          PopupMenuButton<String>(
            initialValue: _owner,
            onSelected: (value) async => _switchProfile(value),
            itemBuilder: (context) => _profiles
                .map((profile) => PopupMenuItem<String>(
                      value: profile,
                      child: Text(_profileLabels[profile] ?? profile),
                    ))
                .toList(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Center(
                child: Text(_owner, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Календарь',
            icon: const Icon(Icons.calendar_month),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2024),
                lastDate: DateTime(2035),
              );
              if (picked != null) {
                setState(() => _selectedDate = picked);
              }
            },
          ),
          IconButton(
            tooltip: 'Синхронизировать',
            icon: const Icon(Icons.sync),
            onPressed: () async => _safeSync(showErrors: true),
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: (_pageIndex == 1 || _pageIndex == 3)
          ? FloatingActionButton.extended(
              onPressed: () => _openTaskEditor(forceFamily: _pageIndex == 3),
              icon: const Icon(Icons.add),
              label: Text(_pageIndex == 3 ? 'Сем. задача' : 'Задача'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _pageIndex,
        onDestinationSelected: (i) => setState(() => _pageIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Дашборд'),
          NavigationDestination(icon: Icon(Icons.view_kanban_outlined), label: 'Задачи'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), label: 'Календарь'),
          NavigationDestination(icon: Icon(Icons.family_restroom_outlined), label: 'Семейные'),
        ],
      ),
    );
  }
}

class _DashboardView extends StatelessWidget {
  const _DashboardView({
    required this.allTasks,
    required this.selectedDate,
    required this.onOpenCalendar,
  });

  final List<TaskItem> allTasks;
  final DateTime selectedDate;
  final Future<void> Function() onOpenCalendar;

  String _dateKey(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  @override
  Widget build(BuildContext context) {
    final todayKey = _dateKey(selectedDate);
    final today = allTasks.where((t) => t.dueDate == todayKey).toList();
    final doneToday = today.where((t) => t.workflowStatus == 'done').length;
    final familyToday = today.where((t) => t.isFamily).length;
    final overdue = allTasks
        .where((t) => t.dueDate.compareTo(todayKey) < 0 && t.workflowStatus != 'done')
        .length;
    final upcoming = allTasks.toList()
      ..sort((a, b) => ('${a.dueDate} ${a.time}').compareTo('${b.dueDate} ${b.time}'));

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricCard(title: 'На дату', value: '${today.length}', hint: todayKey),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricCard(title: 'Сделано', value: '$doneToday', hint: 'Done'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _MetricCard(title: 'Семейных', value: '$familyToday', hint: 'Family'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricCard(title: 'Просрочено', value: '$overdue', hint: 'Overdue'),
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
        for (final t in upcoming.take(8))
          Card(
            child: ListTile(
              title: Text(t.title),
              subtitle: Text('${t.dueDate} ${t.time} • ${t.ownerKey} • ${t.workflowStatus}'),
              trailing: t.isFamily ? const Icon(Icons.family_restroom) : null,
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
    final days = List.generate(10, (i) => start.add(Duration(days: i)));

    return Column(
      children: [
        SizedBox(
          height: 86,
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            scrollDirection: Axis.horizontal,
            itemCount: days.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final d = days[i];
              final isCurrent = d.year == selectedDate.year &&
                  d.month == selectedDate.month &&
                  d.day == selectedDate.day;
              return ChoiceChip(
                selected: isCurrent,
                label: Text('${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}'),
                onSelected: (_) => onDateChange(d),
              );
            },
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              if (tasksForSelectedDate.isEmpty)
                const Card(child: ListTile(title: Text('На выбранную дату задач нет'))),
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
    'todo': 'Todo',
    'in_progress': 'In Progress',
    'in_review': 'In Review',
    'done': 'Done',
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
              onAcceptWithDetails: (d) => onDrop(d.data, status),
              builder: (context, candidate, rejected) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_titles[status]} (${items.length})',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
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
          const Card(child: ListTile(title: Text('На эту дату семейных задач нет'))),
        for (final item in familyTasks)
          _TaskCard(item: item, onEdit: () => onEdit(item), onDelete: () => onDelete(item), onDoneToggle: () async {}),
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
    final subtitle = [
      '${item.dueDate} ${item.time}'.trim(),
      if (item.isFamily && item.assignees.isNotEmpty) 'Ответственные: ${item.assignees.join(', ')}',
      if (item.isFamily && item.durationMinutes > 0) 'Длительность: ${item.durationMinutes} мин',
      if (item.details.isNotEmpty) item.details,
      'Владелец: ${item.ownerKey}',
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
              icon: Icon(item.workflowStatus == 'done' ? Icons.undo : Icons.check_circle),
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
