import 'package:flutter/material.dart';

import 'models/task_item.dart';
import 'services/api_client.dart';
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
  late final SyncService _sync;
  final _tasks = <TaskItem>[];
  final _owner = 'nik';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _db = await LocalDb.open();
    _sync = SyncService(
      db: _db,
      api: ApiClient(
        baseUrl: const String.fromEnvironment('API_BASE_URL', defaultValue: 'https://example.com'),
        apiKey: const String.fromEnvironment('API_KEY', defaultValue: ''),
      ),
      actorProfile: _owner,
    );
    await _refreshLocal();
    try {
      await _sync.sync();
      await _refreshLocal();
    } catch (_) {}
    setState(() {
      _loading = false;
    });
  }

  Future<void> _refreshLocal() async {
    final tasks = await _db.readTasks(ownerKey: _owner);
    setState(() {
      _tasks
        ..clear()
        ..addAll(tasks);
    });
  }

  Future<void> _quickAdd() async {
    final now = DateTime.now().toIso8601String();
    final id = 'm-${DateTime.now().microsecondsSinceEpoch}';
    final item = TaskItem(
      id: id,
      ownerKey: _owner,
      isFamily: false,
      title: 'Новая задача',
      details: '',
      dueDate: now.substring(0, 10),
      time: '19:00',
      workflowStatus: 'todo',
      priority: 'medium',
      tags: const [],
      participants: const [],
      durationMinutes: 0,
      updatedAt: now,
      version: 1,
    );
    await _sync.enqueueUpsert(item);
    await _refreshLocal();
  }

  Future<void> _move(TaskItem item, String status) async {
    final changed = item.copyWith(
      workflowStatus: status,
      updatedAt: DateTime.now().toIso8601String(),
      version: item.version + 1,
    );
    await _sync.enqueueUpsert(changed);
    await _refreshLocal();
  }

  @override
  Widget build(BuildContext context) {
    final byStatus = {
      'todo': _tasks.where((t) => t.workflowStatus == 'todo').toList(),
      'in_progress': _tasks.where((t) => t.workflowStatus == 'in_progress').toList(),
      'in_review': _tasks.where((t) => t.workflowStatus == 'in_review').toList(),
      'done': _tasks.where((t) => t.workflowStatus == 'done').toList(),
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Family ToDo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () async {
              await _sync.sync();
              await _refreshLocal();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _quickAdd,
        label: const Text('Добавить'),
        icon: const Icon(Icons.add_task),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _KanbanColumn(
                  title: 'К выполнению',
                  color: const Color(0xFFE3F2FD),
                  items: byStatus['todo']!,
                  onMove: (task) => _move(task, 'in_progress'),
                ),
                _KanbanColumn(
                  title: 'В работе',
                  color: const Color(0xFFE8F5E9),
                  items: byStatus['in_progress']!,
                  onMove: (task) => _move(task, 'in_review'),
                ),
                _KanbanColumn(
                  title: 'На проверке',
                  color: const Color(0xFFFFF3E0),
                  items: byStatus['in_review']!,
                  onMove: (task) => _move(task, 'done'),
                ),
                _KanbanColumn(
                  title: 'Сделано',
                  color: const Color(0xFFEDE7F6),
                  items: byStatus['done']!,
                  onMove: null,
                ),
              ],
            ),
    );
  }
}

class _KanbanColumn extends StatelessWidget {
  const _KanbanColumn({
    required this.title,
    required this.color,
    required this.items,
    required this.onMove,
  });

  final String title;
  final Color color;
  final List<TaskItem> items;
  final void Function(TaskItem task)? onMove;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final item in items)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  title: Text(item.title),
                  subtitle: Text('${item.dueDate} ${item.time}'.trim()),
                  trailing: onMove == null
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.arrow_forward),
                          onPressed: () => onMove!(item),
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

