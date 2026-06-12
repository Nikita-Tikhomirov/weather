import 'package:family_todo_mobile/features/home/home_project_status_sheet.dart';
import 'package:family_todo_mobile/l10n/app_localizations.dart';
import 'package:family_todo_mobile/models/task_project.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('uses localized project status labels', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: const Scaffold(
          body: ProjectChatStatusSheet(
            project: TaskProject(id: 'project-1', name: 'Weather'),
            conversationTitle: 'Family',
            members: ['nik', 'misha'],
            workspaceId: '',
            canUseAi: true,
            agentSessionId: 'session-1',
          ),
        ),
      ),
    );

    expect(find.text('Project status'), findsOneWidget);
    expect(find.text('Weather'), findsOneWidget);
    expect(find.text('No description'), findsOneWidget);
    expect(find.text('Family'), findsOneWidget);
    expect(find.text('Participants: nik, misha'), findsOneWidget);
    expect(find.text('Workspace is not selected'), findsOneWidget);
    expect(
      find.text('Select workspace in Project Control Center'),
      findsOneWidget,
    );
    expect(find.text('Active agent session'), findsOneWidget);
    expect(find.text('session-1'), findsOneWidget);
    expect(find.text('Статус проекта'), findsNothing);
    expect(find.text('Описание не задано'), findsNothing);
    expect(find.text('Workspace не выбран'), findsNothing);
  });
}
