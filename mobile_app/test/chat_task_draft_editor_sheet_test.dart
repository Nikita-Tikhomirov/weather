import 'package:family_todo_mobile/features/projects/chat_task_draft_editor_sheet.dart';
import 'package:family_todo_mobile/models/project_control_models.dart';
import 'package:family_todo_mobile/models/task_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('allows full editing before confirming chat task draft',
      (tester) async {
    ChatTaskDraft? confirmed;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: ChatTaskDraftEditorSheet(
            initialDraft: const ChatTaskDraft(
              title: 'Старый заголовок',
              details: 'Старое описание',
              checklist: ['Первый пункт'],
              assignees: ['nik'],
              priority: Priority.medium,
            ),
            onCancel: () {},
            onConfirm: (draft) => confirmed = draft,
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('chat-draft-title-field')),
      'Настроить checkout',
    );
    await tester.enterText(
      find.byKey(const ValueKey('chat-draft-details-field')),
      'Собрать понятный сценарий покупки.',
    );
    await tester.enterText(
      find.byKey(const ValueKey('chat-draft-checklist-field')),
      'Спроектировать форму\nПодключить оплату',
    );
    await tester.enterText(
      find.byKey(const ValueKey('chat-draft-assignees-field')),
      'nik, nastya',
    );
    await tester
        .ensureVisible(find.byKey(const ValueKey('chat-draft-confirm')));
    await tester.tap(find.byKey(const ValueKey('chat-draft-confirm')));

    expect(confirmed, isNotNull);
    expect(confirmed?.title, 'Настроить checkout');
    expect(confirmed?.details, 'Собрать понятный сценарий покупки.');
    expect(confirmed?.checklist, ['Спроектировать форму', 'Подключить оплату']);
    expect(confirmed?.assignees, ['nik', 'nastya']);
    expect(confirmed?.priority, Priority.medium);
  });
}
