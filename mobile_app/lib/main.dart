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
      title: 'Family ToDo',
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
  int _tabIndex = 0;

  static const _profiles = ['nik', 'nastya', 'misha', 'arisha'];
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
      baseUrl: const String.fromEnvironment('API_BASE_URL', defaultValue: 'https://example.com'),
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
          SnackBar(
            content: Text(text),
            action: SnackBarAction(
              label: 'Обновить',
              onPressed: () async {
                await _safeSync(showErrors: true);
              },
            ),
          ),
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
      includeAll: _isAdult,
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
    final participantsCtl =
        TextEditingController(text: (existing?.participants ?? const []).join(', '));
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
                      existing == null ? 'Новая задача' : 'Редактировать задачу',
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
                        DropdownMenuItem(value: 'low', child: Text('Low')),
                        DropdownMenuItem(value: 'medium', child: Text('Medium')),
                        DropdownMenuItem(value: 'high', child: Text('High')),
                      ],
                      onChanged: (v) => setModalState(() => priority = v ?? 'medium'),
                    ),
                    DropdownButtonFormField<String>(
                      value: status,
                      decoration: const InputDecoration(labelText: 'Статус'),
                      items: const [
                        DropdownMenuItem(value: 'todo', child: Text('Todo')),
                        DropdownMenuItem(value: 'in_progress', child: Text('In progress')),
                        DropdownMenuItem(value: 'in_review', child: Text('In review')),
                        DropdownMenuItem(value: 'done', child: Text('Done')),
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
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'Участники (через запятую)',
                        ),
                        controller: participantsCtl,
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
                              final participants = participantsCtl.text
                                  .split(',')
                                  .map((e) => e.trim())
                                  .where((e) => e.isNotEmpty)
                                  .toList();
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
                                        participants: participants,
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
                                participants: participants,
                                durationMinutes: int.tryParse(durationCtl.text.trim()) ?? 0,
                                updatedAt: now,
                                version: (existing?.version ?? 0) + 1,
                              );

                              await _sync!.enqueueUpsert(task);
                              await _refreshLocal();
                              if (mounted) {
                                Navigator.pop(context);
                              }
                              await _safeSync();
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
    await _safeSync();
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
    await _safeSync();
  }

  List<TaskItem> get _dateTasks =>
      _allTasks.where((t) => _isSameDate(t.dueDate, _selectedDate)).toList();

  @override
  Widget build(BuildContext context) {
    final selectedKey = _dateKey(_selectedDate);
    final byStatus = {
      for (final s in _statuses)
        s: _dateTasks.where((t) => !t.isFamily && t.workflowStatus == s).toList(),
    };
    final familyTasks = _dateTasks.where((t) => t.isFamily).toList();
    final personalVisible = _dateTasks.where((t) => !t.isFamily).toList();

    return DefaultTabController(
      length: 2,
      initialIndex: _tabIndex,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Family ToDo • $selectedKey'),
          actions: [
            PopupMenuButton<String>(
              initialValue: _owner,
              onSelected: (value) async => _switchProfile(value),
              itemBuilder: (context) => _profiles
                  .map((profile) => PopupMenuItem<String>(
                        value: profile,
                        child: Text(profile),
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
          bottom: TabBar(
            onTap: (i) => setState(() => _tabIndex = i),
            tabs: const [
              Tab(text: 'Задачи'),
              Tab(text: 'Семья'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openTaskEditor(forceFamily: _tabIndex == 1),
          icon: const Icon(Icons.add),
          label: Text(_tabIndex == 1 ? 'Сем. задача' : 'Задача'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _TasksBoard(
                    byStatus: byStatus,
                    onDrop: _move,
                    onEdit: (t) => _openTaskEditor(existing: t),
                    onDelete: _delete,
                    onDoneToggle: _toggleDone,
                  ),
                  _FamilyView(
                    familyTasks: familyTasks,
                    personalTasks: personalVisible,
                    showAllPersonal: _isAdult,
                    onEdit: (t) => _openTaskEditor(existing: t),
                    onDelete: _delete,
                  ),
                ],
              ),
      ),
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
    required this.personalTasks,
    required this.showAllPersonal,
    required this.onEdit,
    required this.onDelete,
  });

  final List<TaskItem> familyTasks;
  final List<TaskItem> personalTasks;
  final bool showAllPersonal;
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
        const SizedBox(height: 16),
        Text(showAllPersonal ? 'Расписания всех' : 'Личные задачи',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (personalTasks.isEmpty)
          const Card(child: ListTile(title: Text('На эту дату задач нет'))),
        for (final item in personalTasks)
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
      if (item.isFamily && item.participants.isNotEmpty) 'Участники: ${item.participants.join(', ')}',
      if (item.isFamily && item.durationMinutes > 0) 'Длительность: ${item.durationMinutes} мин',
      if (item.details.isNotEmpty) item.details,
      'owner: ${item.ownerKey}',
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
              tooltip: 'Done/Undo',
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
