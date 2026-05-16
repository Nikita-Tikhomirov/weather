import 'package:flutter/material.dart';

import '../../models/task_item.dart';
import '../tasks/task_card.dart';

class FamilyView extends StatelessWidget {
  const FamilyView({
    super.key,
    required this.familyTasks,
    required this.familyFilter,
    required this.labelFor,
    required this.onFilterChanged,
    required this.onEdit,
    required this.onDelete,
  });

  final List<TaskItem> familyTasks;
  final String familyFilter;
  final String Function(String profile) labelFor;
  final void Function(String) onFilterChanged;
  final Future<void> Function(TaskItem) onEdit;
  final Future<void> Function(TaskItem) onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'upcoming', label: Text('Предстоящие')),
              ButtonSegment(value: 'overdue', label: Text('Просроченные')),
              ButtonSegment(value: 'done', label: Text('Выполненные')),
              ButtonSegment(value: 'all', label: Text('Все')),
            ],
            selected: <String>{familyFilter},
            onSelectionChanged: (values) => onFilterChanged(values.first),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text(
                'Семейные задачи',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (familyTasks.isEmpty)
                const Card(
                  child: ListTile(
                    title: Text('Под выбранный фильтр задач нет'),
                  ),
                ),
              for (final item in familyTasks)
                TaskCard(
                  item: item,
                  labelFor: labelFor,
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
