import 'package:flutter/material.dart';

import '../../app/app_labels.dart';
import '../../models/task_item.dart';
import 'task_card.dart';

const _monthNamesRu = [
  'Январь',
  'Февраль',
  'Март',
  'Апрель',
  'Май',
  'Июнь',
  'Июль',
  'Август',
  'Сентябрь',
  'Октябрь',
  'Ноябрь',
  'Декабрь',
];
const _weekDayNamesRu = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

/// Full-screen month grid calendar for mobile.
/// Shows all tasks in day cells; tap opens a day detail sheet with full task cards.
class CalendarView extends StatelessWidget {
  const CalendarView({
    super.key,
    required this.monthDate,
    required this.selectedDate,
    required this.allTasks,
    required this.labelFor,
    required this.onMonthPrev,
    required this.onMonthNext,
    required this.onGoToday,
    required this.onSelectDate,
    required this.onEdit,
    required this.onDelete,
    required this.onAddForDate,
  });

  final DateTime monthDate;
  final DateTime selectedDate;
  final List<TaskItem> allTasks;
  final String Function(String profile) labelFor;
  final VoidCallback onMonthPrev;
  final VoidCallback onMonthNext;
  final VoidCallback onGoToday;
  final void Function(DateTime) onSelectDate;
  final Future<void> Function(TaskItem) onEdit;
  final Future<void> Function(TaskItem) onDelete;
  final Future<void> Function(DateTime) onAddForDate;

  @override
  Widget build(BuildContext context) {
    final monthGrid = _buildMonthGrid(monthDate);
    final byDate = <String, List<TaskItem>>{};
    for (final task in allTasks) {
      byDate.putIfAbsent(task.dueDate, () => <TaskItem>[]).add(task);
    }

    return Column(
      children: [
        // ── Month header ──
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              IconButton(
                onPressed: onMonthPrev,
                icon: const Icon(Icons.chevron_left),
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Text(
                  '${_monthNamesRu[monthDate.month - 1]} ${monthDate.year}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              IconButton(
                onPressed: onMonthNext,
                icon: const Icon(Icons.chevron_right),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: onGoToday,
                child: const Text('Сегодня'),
              ),
            ],
          ),
        ),
        // ── Weekday header ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              for (final label in _weekDayNamesRu)
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // ── Month grid (scrollable if many weeks) ──
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 3,
              mainAxisSpacing: 3,
              childAspectRatio: 0.80,
            ),
            itemCount: monthGrid.length,
            itemBuilder: (context, index) {
              final day = monthGrid[index];
              final dateKey = _dateKey(day);
              final dayTasks = byDate[dateKey] ?? const <TaskItem>[];
              final isCurrentMonth = day.month == monthDate.month;
              final isToday = _isSameDay(day, DateTime.now());
              final isSelected = _isSameDay(day, selectedDate);

              return _DayCell(
                day: day.day,
                isCurrentMonth: isCurrentMonth,
                isToday: isToday,
                isSelected: isSelected,
                tasks: dayTasks,
                onTap: () => onSelectDate(day),
                onLongPress: () => _openDaySheet(
                  context, day, dayTasks, onEdit, onDelete, onAddForDate, labelFor,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _openDaySheet(
    BuildContext context,
    DateTime day,
    List<TaskItem> tasks,
    Future<void> Function(TaskItem) onEdit,
    Future<void> Function(TaskItem) onDelete,
    Future<void> Function(DateTime) onAddForDate,
    String Function(String) labelFor,
  ) {
    final title =
        '${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}.${day.year}';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          onAddForDate(day);
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Добавить'),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: tasks.isEmpty
                      ? Center(
                          child: Text(
                            'На эту дату задач нет',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: tasks.length,
                          itemBuilder: (context, index) {
                            final task = tasks[index];
                            return TaskCard(
                              item: task,
                              labelFor: labelFor,
                              onEdit: () {
                                Navigator.of(sheetContext).pop();
                                onEdit(task);
                              },
                              onDelete: () {
                                Navigator.of(sheetContext).pop();
                                onDelete(task);
                              },
                              onDoneToggle: () async {},
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static List<DateTime> _buildMonthGrid(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    final lastDay = DateTime(month.year, month.month + 1, 0);
    // Monday = 1, Sunday = 7; weekday is 1-7
    final startOffset = (firstDay.weekday - 1) % 7; // how many days to prepend
    final grid = <DateTime>[];
    for (var i = startOffset; i > 0; i--) {
      grid.add(firstDay.subtract(Duration(days: i)));
    }
    for (var d = 1; d <= lastDay.day; d++) {
      grid.add(DateTime(month.year, month.month, d));
    }
    // Fill remaining cells to complete last week
    while (grid.length % 7 != 0) {
      grid.add(grid.last.add(const Duration(days: 1)));
    }
    return grid;
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static String _dateKey(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}

/// Single day cell in the month grid.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isCurrentMonth,
    required this.isToday,
    required this.isSelected,
    required this.tasks,
    required this.onTap,
    required this.onLongPress,
  });

  final int day;
  final bool isCurrentMonth;
  final bool isToday;
  final bool isSelected;
  final List<TaskItem> tasks;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    Color bgColor;
    if (isSelected) {
      bgColor = colors.primaryContainer;
    } else if (isToday) {
      bgColor = colors.primaryContainer.withValues(alpha: 0.35);
    } else if (!isCurrentMonth) {
      bgColor = colors.surfaceContainerLowest;
    } else {
      bgColor = colors.surface;
    }

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isToday
                ? colors.primary.withValues(alpha: 0.5)
                : colors.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        padding: const EdgeInsets.all(3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Day number
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: isToday
                  ? BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                    )
                  : null,
              child: Text(
                '$day',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                  color: isToday
                      ? colors.onPrimary
                      : isCurrentMonth
                          ? colors.onSurface
                          : colors.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            // Task indicators (compact dots with title snippets)
            if (tasks.isNotEmpty)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final task in tasks.take(3))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 1),
                          child: Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: _statusDot(task.workflowStatus),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  task.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: colors.onSurface.withValues(alpha: 0.7),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (tasks.length > 3)
                        Text(
                          '+${tasks.length - 3}',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: colors.primary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static Color _statusDot(String status) {
    switch (status) {
      case 'todo':
        return const Color(0xFF38BDF8);
      case 'in_progress':
        return const Color(0xFF34D399);
      case 'in_review':
        return const Color(0xFFFBBF24);
      case 'done':
        return const Color(0xFFA78BFA);
      case 'archive':
        return const Color(0xFF9CA3AF);
      default:
        return const Color(0xFF94A3B8);
    }
  }
}


// ── Desktop calendar (unchanged, adapted) ─────────────────────────────────

class DesktopCalendarView extends StatelessWidget {
  const DesktopCalendarView({
    super.key,
    required this.month,
    required this.selectedDate,
    required this.allTasks,
    required this.monthGrid,
    required this.onGoPrevMonth,
    required this.onGoNextMonth,
    required this.onGoToday,
    required this.onSelectDate,
    required this.onDropToDay,
    required this.onDropToStatus,
    required this.onOpenEditor,
    required this.onDelete,
    required this.onAddForDate,
  });

  final DateTime month;
  final DateTime selectedDate;
  final List<TaskItem> allTasks;
  final List<DateTime> monthGrid;
  final VoidCallback onGoPrevMonth;
  final VoidCallback onGoNextMonth;
  final VoidCallback onGoToday;
  final void Function(DateTime) onSelectDate;
  final Future<void> Function(TaskItem, DateTime) onDropToDay;
  final Future<void> Function(TaskItem, String) onDropToStatus;
  final Future<void> Function(DateTime, TaskItem) onOpenEditor;
  final Future<void> Function(TaskItem) onDelete;
  final Future<void> Function(DateTime) onAddForDate;

  static const _statusTitles = {
    'todo': 'К выполнению',
    'in_progress': 'В работе',
    'in_review': 'На проверке',
    'done': 'Выполнено',
    'archive': 'Архив',
  };

  @override
  Widget build(BuildContext context) {
    final byDate = <String, List<TaskItem>>{};
    for (final task in allTasks) {
      byDate.putIfAbsent(task.dueDate, () => <TaskItem>[]).add(task);
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onGoPrevMonth,
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                '${_monthNamesRu[month.month - 1]} ${month.year}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              IconButton(
                onPressed: onGoNextMonth,
                icon: const Icon(Icons.chevron_right),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                  onPressed: onGoToday, child: const Text('Сегодня')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final label in _weekDayNamesRu)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ),
            ],
          ),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.14,
              ),
              itemCount: monthGrid.length,
              itemBuilder: (context, index) {
                final day = monthGrid[index];
                final key =
                    '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
                final dayTasks = byDate[key] ?? const <TaskItem>[];
                final isCurrentMonth = day.month == month.month;
                final isSelected = day.year == selectedDate.year &&
                    day.month == selectedDate.month &&
                    day.day == selectedDate.day;
                final visible = dayTasks.take(3).toList();
                final overflow = dayTasks.length - visible.length;
                return DragTarget<TaskItem>(
                  onAcceptWithDetails: (details) =>
                      onDropToDay(details.data, day),
                  builder: (context, _, __) {
                    return InkWell(
                      onTap: () => onSelectDate(day),
                      onDoubleTap: () async {
                        await _openDayPopup(context, day, dayTasks);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFEAF2FF)
                              : const Color(0xFFFFFFFF),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isCurrentMonth
                                ? const Color(0xFFD9E2EF)
                                : const Color(0xFFEDEFF3),
                          ),
                        ),
                        padding: const EdgeInsets.all(6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${day.day}',
                              style: TextStyle(
                                color: isCurrentMonth
                                    ? const Color(0xFF111827)
                                    : const Color(0xFF9CA3AF),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            for (final item in visible)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: LongPressDraggable<TaskItem>(
                                  data: item,
                                  feedback: Material(
                                    color: Colors.transparent,
                                    child: Chip(label: Text(item.title)),
                                  ),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFDBEAFE),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                                ),
                              ),
                            if (overflow > 0)
                              TextButton(
                                onPressed: () =>
                                    _openDayPopup(context, day, dayTasks),
                                child: Text('+$overflow еще'),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 58,
            child: Row(
              children: _statusTitles.keys.map((status) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: DragTarget<TaskItem>(
                      onAcceptWithDetails: (details) =>
                          onDropToStatus(details.data, status),
                      builder: (context, _, __) {
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFFD9E2EF)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(_statusTitles[status]!),
                          ),
                        );
                      },
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openDayPopup(
    BuildContext context,
    DateTime day,
    List<TaskItem> dayTasks,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            '${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}.${day.year}',
          ),
          content: SizedBox(
            width: 520,
            child: dayTasks.isEmpty
                ? const Text('На эту дату задач нет')
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final task in dayTasks)
                        ListTile(
                          dense: true,
                          title: Text(task.title),
                          subtitle: Text(
                            '${task.time} · ${workflowLabel(task.workflowStatus)}',
                          ),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                onPressed: () => onOpenEditor(day, task),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                onPressed: () => onDelete(task),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Закрыть'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await onAddForDate(day);
              },
              icon: const Icon(Icons.add),
              label: const Text('Добавить'),
            ),
          ],
        );
      },
    );
  }
}
