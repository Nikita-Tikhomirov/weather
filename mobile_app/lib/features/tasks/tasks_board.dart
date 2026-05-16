import 'package:flutter/material.dart';

import '../../models/task_item.dart';
import 'task_card.dart';

class TasksBoard extends StatelessWidget {
  const TasksBoard({
    super.key,
    required this.byStatus,
    required this.labelFor,
    required this.selectionMode,
    required this.selectedIds,
    required this.onToggleSelect,
    required this.onDrop,
    required this.onEdit,
    required this.onDelete,
    required this.onDoneToggle,
  });

  final Map<String, List<TaskItem>> byStatus;
  final String Function(String profile) labelFor;
  final bool selectionMode;
  final Set<String> selectedIds;
  final void Function(String) onToggleSelect;
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
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
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
                            width: 260,
                            child: TaskCard(
                              item: item,
                              labelFor: labelFor,
                              onEdit: () async {},
                              onDelete: () async {},
                              onDoneToggle: () async {},
                            ),
                          ),
                        ),
                        childWhenDragging: const SizedBox.shrink(),
                        child: TaskCard(
                          item: item,
                          labelFor: labelFor,
                          selectionMode: selectionMode,
                          selected: selectedIds.contains(item.id),
                          onSelectionToggle: () => onToggleSelect(item.id),
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

class DesktopTasksBoard extends StatelessWidget {
  const DesktopTasksBoard({
    super.key,
    required this.byStatus,
    required this.labelFor,
    required this.selectionMode,
    required this.selectedIds,
    required this.onToggleSelect,
    required this.onDropStatus,
    required this.onEdit,
    required this.onDelete,
    required this.onDoneToggle,
  });

  final Map<String, List<TaskItem>> byStatus;
  final String Function(String profile) labelFor;
  final bool selectionMode;
  final Set<String> selectedIds;
  final void Function(String) onToggleSelect;
  final Future<void> Function(TaskItem, String) onDropStatus;
  final Future<void> Function(TaskItem) onEdit;
  final Future<void> Function(TaskItem) onDelete;
  final Future<void> Function(TaskItem) onDoneToggle;

  static const _titles = {
    'todo': 'К выполнению',
    'in_progress': 'В работе',
    'in_review': 'На проверке',
    'done': 'Выполнено',
  };

  static Color _columnColor(String status) {
    switch (status) {
      case 'todo':
        return const Color(0xFF3B82F6);
      case 'in_progress':
        return const Color(0xFFF59E0B);
      case 'in_review':
        return const Color(0xFF8B5CF6);
      case 'done':
        return const Color(0xFF10B981);
      default:
        return const Color(0xFF6B7280);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: SizedBox(
            width: 4 * 340,
            height: constraints.maxHeight,
            child: Row(
              children: _titles.keys.map((status) {
                final items = byStatus[status] ?? const <TaskItem>[];
                final colColor = _columnColor(status);
                return SizedBox(
                  width: 330,
                  child: Card(
                    margin: const EdgeInsets.only(right: 10),
                    elevation: 0,
                    color: Theme.of(ctx).colorScheme.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: colColor.withAlpha(25),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: colColor, width: 1),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${_titles[status]} (${items.length})',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: colColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: DragTarget<TaskItem>(
                              onAcceptWithDetails: (details) =>
                                  onDropStatus(details.data, status),
                              builder: (dragCtx, candidateData, rejectedData) {
                                final isHovering = candidateData.isNotEmpty;
                                if (items.isEmpty && !isHovering) {
                                  return Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.inbox_outlined,
                                              size: 32,
                                              color: colColor.withAlpha(100)),
                                          const SizedBox(height: 8),
                                          Text('Нет задач',
                                              style: TextStyle(
                                                  color: Theme.of(dragCtx)
                                                      .colorScheme
                                                      .onSurface
                                                      .withValues(alpha: 0.4))),
                                        ],
                                      ),
                                    ),
                                  );
                                }
                                return ListView(
                                  children: [
                                    if (isHovering)
                                      Container(
                                        height: 60,
                                        margin:
                                            const EdgeInsets.only(bottom: 8),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                              color: colColor,
                                              width: 2,
                                              strokeAlign:
                                                  BorderSide.strokeAlignInside),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          color: colColor.withAlpha(15),
                                        ),
                                        child: Center(
                                            child: Icon(Icons.add,
                                                color: colColor)),
                                      ),
                                    for (final item in items)
                                      LongPressDraggable<TaskItem>(
                                        data: item,
                                        feedback: Material(
                                          color: Colors.transparent,
                                          child: SizedBox(
                                            width: 280,
                                            child: TaskCard(
                                              item: item,
                                              labelFor: labelFor,
                                              onEdit: () async {},
                                              onDelete: () async {},
                                              onDoneToggle: () async {},
                                            ),
                                          ),
                                        ),
                                        childWhenDragging:
                                            const SizedBox.shrink(),
                                        child: TaskCard(
                                          item: item,
                                          labelFor: labelFor,
                                          selectionMode: selectionMode,
                                          selected:
                                              selectedIds.contains(item.id),
                                          onSelectionToggle: () =>
                                              onToggleSelect(item.id),
                                          onEdit: () => onEdit(item),
                                          onDelete: () => onDelete(item),
                                          onDoneToggle: () =>
                                              onDoneToggle(item),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}
