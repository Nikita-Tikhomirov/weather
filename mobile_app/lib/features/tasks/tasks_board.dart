import 'package:flutter/material.dart';

import '../../app/app_labels.dart';
import '../../l10n/app_localizations.dart';
import '../../models/task_item.dart';
import 'task_card.dart';

class KanbanColumnStyle {
  const KanbanColumnStyle({
    required this.accentColor,
    required this.backgroundColor,
    required this.headerColor,
    required this.titleColor,
    required this.mutedColor,
    required this.borderColor,
    required this.dropColor,
  });

  final Color accentColor;
  final Color backgroundColor;
  final Color headerColor;
  final Color titleColor;
  final Color mutedColor;
  final Color borderColor;
  final Color dropColor;

  static KanbanColumnStyle resolve(ThemeData theme, WorkflowStatus status) {
    final accent = _statusAccent(status);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final baseSurface =
        isDark ? scheme.surfaceContainerLow : scheme.surfaceContainerLowest;
    final background = Color.alphaBlend(
      accent.withValues(alpha: isDark ? 0.10 : 0.06),
      baseSurface,
    );
    final header = Color.alphaBlend(
      accent.withValues(alpha: isDark ? 0.20 : 0.12),
      background,
    );
    final title = isDark ? Colors.white : const Color(0xFF111827);

    return KanbanColumnStyle(
      accentColor: accent,
      backgroundColor: background,
      headerColor: header,
      titleColor: title,
      mutedColor: title.withValues(alpha: isDark ? 0.68 : 0.58),
      borderColor: Color.alphaBlend(
        accent.withValues(alpha: isDark ? 0.32 : 0.22),
        scheme.outlineVariant.withValues(alpha: 0.50),
      ),
      dropColor: Color.alphaBlend(
        accent.withValues(alpha: isDark ? 0.22 : 0.14),
        background,
      ),
    );
  }

  static Color _statusAccent(WorkflowStatus status) {
    switch (status) {
      case WorkflowStatus.todo:
        return const Color(0xFF38BDF8);
      case WorkflowStatus.in_progress:
        return const Color(0xFF34D399);
      case WorkflowStatus.in_review:
        return const Color(0xFFFBBF24);
      case WorkflowStatus.done:
        return const Color(0xFFA78BFA);
      case WorkflowStatus.archive:
        return const Color(0xFF9CA3AF);
    }
  }
}

class TasksBoard extends StatelessWidget {
  const TasksBoard({
    super.key,
    required this.byStatus,
    required this.labelFor,
    this.groupLabel,
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
  final String Function(String groupId)? groupLabel;
  final bool selectionMode;
  final Set<String> selectedIds;
  final void Function(String) onToggleSelect;
  final Future<void> Function(TaskItem, String) onDrop;
  final Future<void> Function(TaskItem) onEdit;
  final Future<void> Function(TaskItem) onDelete;
  final Future<void> Function(TaskItem) onDoneToggle;

  static const _statuses = [
    'todo',
    'in_progress',
    'in_review',
    'done',
    'archive',
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
      children: _statuses.map<Widget>((status) {
        final items = byStatus[status] ?? const <TaskItem>[];
        return _KanbanColumn(
          status: status,
          title: taskWorkflowLabel(context, WorkflowStatus.parse(status)),
          items: items,
          labelFor: labelFor,
          groupLabel: groupLabel,
          selectionMode: selectionMode,
          selectedIds: selectedIds,
          onToggleSelect: onToggleSelect,
          onDrop: (item) => onDrop(item, status),
          onEdit: onEdit,
          onDelete: onDelete,
          onDoneToggle: onDoneToggle,
          margin: const EdgeInsets.only(bottom: 12),
          bodyBuilder: (body) => body,
        );
      }).toList(),
    );
  }
}

String taskWorkflowLabel(BuildContext context, WorkflowStatus status) {
  final l10n = AppLocalizations.of(context);
  switch (status) {
    case WorkflowStatus.todo:
      return l10n?.workflowTodo ?? workflowLabel(status);
    case WorkflowStatus.in_progress:
      return l10n?.workflowInProgress ?? workflowLabel(status);
    case WorkflowStatus.in_review:
      return l10n?.workflowInReview ?? workflowLabel(status);
    case WorkflowStatus.done:
      return l10n?.workflowDone ?? workflowLabel(status);
    case WorkflowStatus.archive:
      return l10n?.workflowArchive ?? workflowLabel(status);
  }
}

String _dropHereLabel(BuildContext context) {
  return AppLocalizations.of(context)?.dropHere ?? 'Отпустить сюда';
}

String _noTasksLabel(BuildContext context) {
  return AppLocalizations.of(context)?.noTasks ?? 'Нет задач';
}

class _KanbanColumn extends StatelessWidget {
  const _KanbanColumn({
    required this.status,
    required this.title,
    required this.items,
    required this.labelFor,
    this.groupLabel,
    required this.selectionMode,
    required this.selectedIds,
    required this.onToggleSelect,
    required this.onDrop,
    required this.onEdit,
    required this.onDelete,
    required this.onDoneToggle,
    required this.bodyBuilder,
    this.margin = EdgeInsets.zero,
  });

  final String status;
  final String title;
  final List<TaskItem> items;
  final String Function(String profile) labelFor;
  final String Function(String groupId)? groupLabel;
  final bool selectionMode;
  final Set<String> selectedIds;
  final void Function(String) onToggleSelect;
  final Future<void> Function(TaskItem) onDrop;
  final Future<void> Function(TaskItem) onEdit;
  final Future<void> Function(TaskItem) onDelete;
  final Future<void> Function(TaskItem) onDoneToggle;
  final Widget Function(Widget) bodyBuilder;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final style = KanbanColumnStyle.resolve(
      Theme.of(context),
      WorkflowStatus.parse(status),
    );

    return Container(
      margin: margin,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: style.backgroundColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: style.borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha:
                  Theme.of(context).brightness == Brightness.dark ? 0.20 : 0.06,
            ),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: DragTarget<TaskItem>(
        onAcceptWithDetails: (details) => onDrop(details.data),
        builder: (context, candidate, rejected) {
          final isHovering = candidate.isNotEmpty;
          return Column(
            children: [
              _KanbanColumnHeader(
                title: title,
                count: items.length,
                status: status,
                style: style,
              ),
              bodyBuilder(
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  padding: EdgeInsets.all(isHovering ? 8 : 0),
                  decoration: BoxDecoration(
                    color: isHovering ? style.dropColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color:
                          isHovering ? style.accentColor : Colors.transparent,
                      width: 1.4,
                    ),
                  ),
                  child: items.isEmpty
                      ? _EmptyKanbanColumn(
                          style: style,
                          isHovering: isHovering,
                        )
                      : Column(
                          children: [
                            if (isHovering) _DropHint(style: style),
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
                                      groupLabel: groupLabel,
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
                                  groupLabel: groupLabel,
                                  selectionMode: selectionMode,
                                  selected: selectedIds.contains(item.id),
                                  onSelectionToggle: () =>
                                      onToggleSelect(item.id),
                                  onEdit: () => onEdit(item),
                                  onDelete: () => onDelete(item),
                                  onDoneToggle: () => onDoneToggle(item),
                                ),
                              ),
                          ],
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _KanbanColumnHeader extends StatelessWidget {
  const _KanbanColumnHeader({
    required this.title,
    required this.count,
    required this.status,
    required this.style,
  });

  final String title;
  final int count;
  final String status;
  final KanbanColumnStyle style;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: style.headerColor,
        border: Border(
          bottom: BorderSide(color: style.borderColor),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: style.accentColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _statusIcon(status),
              color: style.accentColor,
              size: 19,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: style.titleColor,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            constraints: const BoxConstraints(minWidth: 34),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: style.accentColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: style.accentColor.withValues(alpha: 0.34),
              ),
            ),
            child: Text(
              '$count',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: style.titleColor,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static IconData _statusIcon(String status) {
    switch (status) {
      case 'todo':
        return Icons.radio_button_unchecked;
      case 'in_progress':
        return Icons.bolt_outlined;
      case 'in_review':
        return Icons.rate_review_outlined;
      case 'done':
        return Icons.task_alt;
      case 'archive':
        return Icons.archive_outlined;
      default:
        return Icons.view_kanban_outlined;
    }
  }
}

class _EmptyKanbanColumn extends StatelessWidget {
  const _EmptyKanbanColumn({
    required this.style,
    required this.isHovering,
  });

  final KanbanColumnStyle style;
  final bool isHovering;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 78,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isHovering ? Icons.add_circle_outline : Icons.inbox_outlined,
              size: 20,
              color: style.mutedColor,
            ),
            const SizedBox(width: 8),
            Text(
              isHovering ? _dropHereLabel(context) : _noTasksLabel(context),
              style: TextStyle(
                color: style.mutedColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DropHint extends StatelessWidget {
  const _DropHint({required this.style});

  final KanbanColumnStyle style;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: style.accentColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: style.accentColor.withValues(alpha: 0.55),
        ),
      ),
      child: Center(
        child: Icon(Icons.add, color: style.accentColor),
      ),
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

  static const _statuses = [
    'todo',
    'in_progress',
    'in_review',
    'done',
    'archive',
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: SizedBox(
            width: 5 * 340,
            height: constraints.maxHeight,
            child: Row(
              children: _statuses.map<Widget>((status) {
                final items = byStatus[status] ?? const <TaskItem>[];
                return SizedBox(
                  width: 330,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: _KanbanColumn(
                      status: status,
                      title:
                          taskWorkflowLabel(ctx, WorkflowStatus.parse(status)),
                      items: items,
                      labelFor: labelFor,
                      selectionMode: selectionMode,
                      selectedIds: selectedIds,
                      onToggleSelect: onToggleSelect,
                      onDrop: (item) => onDropStatus(item, status),
                      onEdit: onEdit,
                      onDelete: onDelete,
                      onDoneToggle: onDoneToggle,
                      bodyBuilder: (body) => Expanded(
                        child: SingleChildScrollView(child: body),
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
