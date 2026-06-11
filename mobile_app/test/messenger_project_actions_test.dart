import 'package:family_todo_mobile/features/chat/messenger_page.dart';
import 'package:family_todo_mobile/l10n/app_localizations.dart';
import 'package:family_todo_mobile/models/chat_models.dart';
import 'package:family_todo_mobile/models/task_project.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Messenger project actions', () {
    testWidgets('shows project chip and agent actions for bound chat',
        (tester) async {
      var analyzed = false;
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: Scaffold(
            body: _page(
              controller: controller,
              activeProject: const TaskProject(
                id: 'project-1',
                name: 'Weather',
              ),
              onAnalyze: () => analyzed = true,
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('messenger-project-chip')), findsOne);
      expect(find.text('Weather'), findsOne);
      await tester
          .tap(find.byKey(const ValueKey('messenger-project-agent-menu')));
      await tester.pumpAndSettle();

      expect(find.text('Анализ чата'), findsOne);
      expect(find.text('Черновик задачи'), findsOne);
      expect(find.text('Запустить агента'), findsOne);

      await tester.tap(find.text('Анализ чата'));
      await tester.pumpAndSettle();
      expect(analyzed, isTrue);
    });

    testWidgets('hides project actions for unbound chat', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: Scaffold(body: _page(controller: controller)),
        ),
      );

      expect(
        find.byKey(const ValueKey('messenger-project-chip')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('messenger-project-agent-menu')),
        findsNothing,
      );
    });

    testWidgets('separates project chats from regular groups', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var openedKey = '';

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: Scaffold(
            body: _page(
              controller: controller,
              activeConversationKey: '',
              conversations: const [
                ChatConversation(
                  conversationKey: 'grp:project:project-1',
                  kind: 'group',
                  title: 'Цифра',
                  members: ['nik', 'nastya'],
                ),
                ChatConversation(
                  conversationKey: 'grp:family:group-1',
                  kind: 'group',
                  title: 'Команда',
                  members: ['nik', 'nastya'],
                ),
              ],
              onOpenConversation: (key) => openedKey = key,
            ),
          ),
        ),
      );

      expect(find.text('Проектные чаты'), findsOneWidget);
      expect(find.text('Обычные группы'), findsOneWidget);
      expect(find.text('Цифра'), findsOneWidget);
      expect(find.text('Команда'), findsOneWidget);

      await tester.tap(find.text('Цифра'));
      await tester.pumpAndSettle();
      expect(openedKey, 'grp:project:project-1');
    });

    testWidgets('uses localized project action labels', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: Scaffold(
            body: _page(
              controller: controller,
              activeProject: const TaskProject(
                id: 'project-1',
                name: 'Weather',
              ),
              onAnalyze: () {},
            ),
          ),
        ),
      );

      await tester
          .tap(find.byKey(const ValueKey('messenger-project-agent-menu')));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Project agent'), findsOneWidget);
      expect(find.text('Chat analysis'), findsOneWidget);
      expect(find.text('Task draft'), findsOneWidget);
      expect(find.text('Start agent'), findsOneWidget);
      expect(find.text('Project status'), findsOneWidget);
      expect(find.text('Анализ чата'), findsNothing);
    });

    testWidgets('uses localized composer reply and edit labels',
        (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: Scaffold(
            body: _page(
              controller: controller,
              replyToMessage: const ChatMessage(
                id: 'message-1',
                conversationKey: 'grp:family:group-1',
                senderProfile: 'nik',
                messageType: 'text',
                text: 'status update',
                createdAt: '2026-06-11T10:00:00Z',
              ),
              editingMessageId: 'message-1',
            ),
          ),
        ),
      );

      expect(find.text('Reply: status update'), findsOneWidget);
      expect(find.text('Editing message'), findsOneWidget);
      expect(find.text('Cancel'), findsNWidgets(2));
      expect(find.textContaining('Ответ'), findsNothing);
      expect(find.text('Редактирование сообщения'), findsNothing);
    });

    testWidgets('uses localized composer input labels and actions',
        (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: Scaffold(
            body: _page(
              controller: controller,
              editingMessageId: 'message-1',
            ),
          ),
        ),
      );

      expect(find.byTooltip('Attachment'), findsOneWidget);
      expect(find.byTooltip('Send'), findsOneWidget);
      expect(find.text('Edit message'), findsOneWidget);
      expect(find.byTooltip('Вложение'), findsNothing);
      expect(find.byTooltip('Отправить'), findsNothing);
      expect(find.text('Изменить сообщение'), findsNothing);
    });
  });
}

MessengerPage _page({
  required TextEditingController controller,
  List<ChatConversation> conversations = const [
    ChatConversation(
      conversationKey: 'grp:family:group-1',
      kind: 'group',
      title: 'Команда',
      members: ['nik', 'nastya'],
    ),
  ],
  String activeConversationKey = 'grp:family:group-1',
  TaskProject? activeProject,
  ChatMessage? replyToMessage,
  String? editingMessageId,
  VoidCallback? onAnalyze,
  void Function(String conversationKey)? onOpenConversation,
}) {
  return MessengerPage(
    conversations: conversations,
    contacts: const [],
    messages: const [],
    activeConversationKey: activeConversationKey,
    owner: 'nik',
    compact: false,
    chatInputController: controller,
    replyToMessage: replyToMessage,
    editingMessageId: editingMessageId,
    isRecording: false,
    conversationLabel: (conversation, actor) => conversation.title,
    contactLabel: (contact) => contact.displayName,
    chatMessageText: (message) => message.text,
    profileLabel: (profile) => profile,
    stickerAssetFor: (message) => '',
    imageUrlFor: (message) => '',
    onRefreshContacts: () {},
    onCreateGroup: () {},
    onAddContactToFamily: (_) {},
    onOpenDirectContact: (_) {},
    onOpenWorkspaces: () {},
    onBackToContacts: () {},
    onOpenConversation: onOpenConversation ?? (_) {},
    onOpenMessageActions: (_) {},
    onImageTap: (_, __) {},
    hasMoreOlderMessages: false,
    loadingOlderMessages: false,
    onLoadOlderMessages: () async {},
    onClearReply: () {},
    onCancelEdit: () {},
    onOpenAttachMenu: () {},
    onStartRecord: () {},
    onStopRecord: () {},
    onSendText: () {},
    onManageGroup: (_) {},
    activeProject: activeProject,
    onAnalyzeProjectChat: onAnalyze,
    onDraftProjectTask: activeProject == null ? null : () {},
    onStartProjectAgent: activeProject == null ? null : () {},
    onShowProjectStatus: activeProject == null ? null : () {},
  );
}
