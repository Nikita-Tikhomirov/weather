import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/task_item.dart';
import '../tasks/task_card.dart';

class _FamilyViewText {
  const _FamilyViewText(this.l10n);

  final AppLocalizations? l10n;

  String get upcoming => l10n?.filterUpcoming ?? 'Upcoming';
  String get overdue => l10n?.filterOverdue ?? 'Overdue';
  String get done => l10n?.filterDone ?? 'Done';
  String get all => l10n?.filterAll ?? 'All';
  String get familyTasks => l10n?.familyTasks ?? 'Family Tasks';
  String get noTasksForFilter =>
      l10n?.noTasksForFilter ?? 'No tasks match this filter';
}

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
    final text = _FamilyViewText(AppLocalizations.of(context));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'upcoming', label: Text(text.upcoming)),
              ButtonSegment(value: 'overdue', label: Text(text.overdue)),
              ButtonSegment(value: 'done', label: Text(text.done)),
              ButtonSegment(value: 'all', label: Text(text.all)),
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
                text.familyTasks,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (familyTasks.isEmpty)
                Card(
                  child: ListTile(
                    title: Text(text.noTasksForFilter),
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
