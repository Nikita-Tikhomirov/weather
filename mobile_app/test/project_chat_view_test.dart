import 'package:family_todo_mobile/features/projects/project_chat_view.dart';
import 'package:family_todo_mobile/l10n/app_localizations.dart';
import 'package:family_todo_mobile/models/project_contact.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('uses English project chat fallback controls', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProjectChatView(
            project: const ProjectContact(
              id: 'project-1',
              name: 'Weather',
              path: '/tmp/weather',
            ),
            bridge: null,
            messages: const [],
            chatInputController: controller,
            onBack: () {},
            onRequestBridgeStart: () {},
            onStartNewSession: () {},
            onStopProjectPrompt: () {},
            onOpenBridgeSettings: () {},
            onOpenProjectFiles: () {},
            onReconnect: () {},
            onSendPhotos: () {},
            onSendDocuments: () {},
            onSendMessage: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byTooltip('Start bridge'), findsOneWidget);
    expect(find.byTooltip('New session'), findsOneWidget);
    expect(find.byTooltip('Stop DeepSeek'), findsOneWidget);
    expect(find.byTooltip('Server settings'), findsOneWidget);
    expect(find.byTooltip('Project files'), findsWidgets);
    expect(find.textContaining('Connecting to'), findsOneWidget);
    expect(find.text('Project terminal'), findsOneWidget);
    expect(
      find.text('Send a message to work with the AI assistant in this project'),
      findsOneWidget,
    );
    expect(find.widgetWithText(ElevatedButton, 'Reconnect'), findsOneWidget);
    expect(find.byTooltip('Photo to vision'), findsOneWidget);
    expect(find.byTooltip('Document to vision'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Message'), findsOneWidget);
    expect(find.byTooltip('Send'), findsOneWidget);
  });

  testWidgets('uses localized project chat controls in English',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ProjectChatView(
            project: const ProjectContact(
              id: 'project-1',
              name: 'Weather',
              path: '/tmp/weather',
            ),
            bridge: null,
            messages: const [],
            chatInputController: controller,
            onBack: () {},
            onRequestBridgeStart: () {},
            onStartNewSession: () {},
            onStopProjectPrompt: () {},
            onOpenBridgeSettings: () {},
            onOpenProjectFiles: () {},
            onReconnect: () {},
            onSendPhotos: () {},
            onSendDocuments: () {},
            onSendMessage: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byTooltip('Start bridge'), findsOneWidget);
    expect(find.byTooltip('New session'), findsOneWidget);
    expect(find.byTooltip('Stop DeepSeek'), findsOneWidget);
    expect(find.byTooltip('Server settings'), findsOneWidget);
    expect(find.byTooltip('Project files'), findsWidgets);
    expect(find.textContaining('Connecting to'), findsOneWidget);
    expect(find.text('Project terminal'), findsOneWidget);
    expect(
      find.text('Send a message to work with the AI assistant in this project'),
      findsOneWidget,
    );
    expect(find.widgetWithText(ElevatedButton, 'Reconnect'), findsOneWidget);
    expect(find.byTooltip('Photo to vision'), findsOneWidget);
    expect(find.byTooltip('Document to vision'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Message'), findsOneWidget);
    expect(find.byTooltip('Send'), findsOneWidget);

    expect(find.byTooltip('Запустить bridge'), findsNothing);
    expect(find.text('Терминал проекта'), findsNothing);
    expect(find.byTooltip('Отправить'), findsNothing);
  });
}
