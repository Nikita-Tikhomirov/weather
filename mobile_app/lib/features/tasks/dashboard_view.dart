import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../state/task_store.dart';
import 'tasks_board.dart';

class _DashboardText {
  const _DashboardText(this.l10n);

  final AppLocalizations? l10n;

  String get onDate => l10n?.dashboardOnDate ?? 'На дату';
  String get done => l10n?.dashboardDone ?? 'Сделано';
  String get doneHint => l10n?.workflowDone ?? 'Выполнено';
  String get family => l10n?.dashboardFamily ?? 'Семейных';
  String get familyHint => l10n?.dashboardFamilyHint ?? 'Семейные';
  String get overdue => l10n?.dashboardOverdue ?? 'Просрочено';
  String get overdueHint => l10n?.dashboardOverdueHint ?? 'Просрочка';
  String get selectDate => l10n?.selectDate ?? 'Выбрать дату';
  String get upcomingTasks => l10n?.upcomingTasks ?? 'Ближайшие задачи';
}

class DashboardView extends StatelessWidget {
  const DashboardView({
    super.key,
    required this.vm,
    required this.labelFor,
    required this.onOpenCalendar,
  });

  final DashboardVm vm;
  final String Function(String profile) labelFor;
  final Future<void> Function() onOpenCalendar;

  @override
  Widget build(BuildContext context) {
    final text = _DashboardText(AppLocalizations.of(context));
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            Expanded(
              child: MetricCard(
                title: text.onDate,
                value: '${vm.todayTotal}',
                hint: vm.todayKey,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: MetricCard(
                title: text.done,
                value: '${vm.doneToday}',
                hint: text.doneHint,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: MetricCard(
                title: text.family,
                value: '${vm.familyToday}',
                hint: text.familyHint,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: MetricCard(
                title: text.overdue,
                value: '${vm.overdue}',
                hint: text.overdueHint,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onOpenCalendar,
          icon: const Icon(Icons.calendar_month),
          label: Text(text.selectDate),
        ),
        const SizedBox(height: 12),
        Text(text.upcomingTasks, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final task in vm.upcoming)
          Card(
            child: ListTile(
              title: Text(task.title),
              subtitle: Text(
                '${task.dueDate} ${task.time} - ${labelFor(task.ownerKey)} - ${taskWorkflowLabel(context, task.workflowStatus)}',
              ),
              trailing:
                  task.isFamily ? const Icon(Icons.family_restroom) : null,
            ),
          ),
      ],
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
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
