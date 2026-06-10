import 'package:family_todo_mobile/features/tasks/task_editor_text.dart';
import 'package:family_todo_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fallback keeps Russian labels for legacy test harnesses', () {
    const text = TaskEditorText.fallback();

    expect(text.newTask, 'Новая задача');
    expect(text.settingsTab, 'Настройки');
    expect(text.title, 'Название');
  });

  testWidgets('reads English labels from AppLocalizations', (tester) async {
    late TaskEditorText text;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            text = TaskEditorText.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(text.newTask, 'New task');
    expect(text.settingsTab, 'Settings');
    expect(text.title, 'Title');
    expect(text.selectProject, 'Select project');
  });
}
