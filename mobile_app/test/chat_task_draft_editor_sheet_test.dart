import 'package:family_todo_mobile/features/projects/chat_task_draft_editor_sheet.dart';
import 'package:family_todo_mobile/l10n/app_localizations.dart';
import 'package:family_todo_mobile/models/project_control_models.dart';
import 'package:family_todo_mobile/models/task_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget plainApp(Widget child) {
    return MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: Scaffold(body: child),
    );
  }

  Widget localizedApp(Widget child) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: Scaffold(body: child),
    );
  }

  testWidgets('uses English editor fallback labels without delegates',
      (tester) async {
    ChatTaskDraft? confirmed;

    await tester.pumpWidget(
      plainApp(
        ChatTaskDraftEditorSheet(
          initialDraft: const ChatTaskDraft(
            title: '',
            priority: Priority.medium,
          ),
          onCancel: () {},
          onConfirm: (draft) => confirmed = draft,
        ),
      ),
    );

    expect(find.text('Task draft'), findsOneWidget);
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
    expect(find.text('Summary'), findsOneWidget);
    expect(find.text('Checklist'), findsOneWidget);
    expect(find.text('Action items'), findsOneWidget);
    expect(find.text('Decisions'), findsOneWidget);
    expect(find.text('Blockers'), findsOneWidget);
    expect(find.text('Assignees'), findsOneWidget);
    expect(find.text('Sources'), findsOneWidget);
    expect(find.text('Priority'), findsOneWidget);
    expect(find.text('Medium'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Create task'), findsOneWidget);

    await tester
        .ensureVisible(find.byKey(const ValueKey('chat-draft-confirm')));
    await tester.tap(find.byKey(const ValueKey('chat-draft-confirm')));

    expect(confirmed?.title, 'Task from chat');
  });

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

  testWidgets('uses localized editor labels when delegates are available',
      (tester) async {
    await tester.pumpWidget(
      localizedApp(
        ChatTaskDraftEditorSheet(
          initialDraft: const ChatTaskDraft(
            title: '',
            priority: Priority.medium,
          ),
          onCancel: () {},
          onConfirm: (_) {},
        ),
      ),
    );

    expect(find.text('Task draft'), findsOneWidget);
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
    expect(find.text('Summary'), findsOneWidget);
    expect(find.text('Checklist'), findsOneWidget);
    expect(find.text('Action items'), findsOneWidget);
    expect(find.text('Decisions'), findsOneWidget);
    expect(find.text('Blockers'), findsOneWidget);
    expect(find.text('Assignees'), findsOneWidget);
    expect(find.text('Sources'), findsOneWidget);
    expect(find.text('Priority'), findsOneWidget);
    expect(find.text('Medium'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Create task'), findsOneWidget);
  });
}
