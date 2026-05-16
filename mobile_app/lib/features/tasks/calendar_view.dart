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

class CalendarView extends StatelessWidget {
  const CalendarView({
    super.key,
    required this.selectedDate,
    required this.tasksForSelectedDate,
    required this.labelFor,
    required this.onDateChange,
    required this.onEdit,
    required this.onDelete,
  });

  final DateTime selectedDate;
  final List<TaskItem> tasksForSelectedDate;
  final String Function(String profile) labelFor;
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
