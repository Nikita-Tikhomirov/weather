import 'package:family_todo_mobile/app/app_theme.dart';
import 'package:family_todo_mobile/features/tasks/tasks_board.dart';
import 'package:family_todo_mobile/models/task_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const statuses = [WorkflowStatus.todo, WorkflowStatus.in_progress, WorkflowStatus.in_review, WorkflowStatus.done];

  double contrastRatio(Color a, Color b) {
    final l1 = a.computeLuminance();
    final l2 = b.computeLuminance();
    final lighter = l1 > l2 ? l1 : l2;
    final darker = l1 > l2 ? l2 : l1;
    return (lighter + 0.05) / (darker + 0.05);
  }

  test('kanban column titles stay readable in every dark theme', () {
    for (final option in appThemeOptions.where(
      (option) => option.brightness == Brightness.dark,
    )) {
      final theme = buildAppTheme(option);
      for (final status in statuses) {
        final style = KanbanColumnStyle.resolve(theme, status);

        expect(
          contrastRatio(style.titleColor, style.backgroundColor),
          greaterThanOrEqualTo(4.5),
          reason: '${option.name} / $status',
        );
      }
    }
  });
}
