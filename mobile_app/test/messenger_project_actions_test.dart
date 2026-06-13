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

      expect(find.text('Chat analysis'), findsOne);
      expect(find.text('Task draft'), findsOne);
      expect(find.text('Start agent'), findsOne);

      await tester.tap(find.text('Chat analysis'));
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

      expect(find.text('Project chats'), findsOneWidget);
      expect(find.text('Regular groups'), findsOneWidget);
      expect(find.text('Цифра'), findsOneWidget);
      expect(find.text('Команда'), findsOneWidget);

      await tester.tap(find.text('Цифра'));
      await tester.pumpAndSettle();
      expect(openedKey, 'grp:project:project-1');
    });

    testWidgets('uses English fallback labels for contact list',
        (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: Scaffold(
            body: _page(
              controller: controller,
              activeConversationKey: '',
              conversations: const [],
            ),
          ),
        ),
      );

      expect(find.text('Contacts'), findsOneWidget);
      expect(find.byTooltip('Workspaces'), findsOneWidget);
      expect(find.byTooltip('Refresh contacts'), findsOneWidget);
      expect(find.byTooltip('Create group'), findsOneWidget);
      expect(find.text('No registered phone contacts'), findsOneWidget);
      expect(find.text('Контакты'), findsNothing);
      expect(find.byTooltip('Обновить контакты'), findsNothing);
      expect(
        find.text('Нет зарегистрированных контактов из телефона'),
        findsNothing,
      );
    });

    testWidgets('uses localized conversation section labels', (tester) async {
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
              activeConversationKey: '',
              conversations: const [
                ChatConversation(
                  conversationKey: 'grp:project:project-1',
                  kind: 'group',
                  title: 'Weather',
                  members: ['nik', 'nastya'],
                ),
                ChatConversation(
                  conversationKey: 'grp:family:group-1',
                  kind: 'group',
                  title: 'Family',
                  members: ['nik', 'nastya'],
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Project chats'), findsOneWidget);
      expect(find.text('Regular groups'), findsOneWidget);
      expect(find.text('Participants: 2'), findsOneWidget);
      expect(find.text('Проектные чаты'), findsNothing);
      expect(find.text('Обычные группы'), findsNothing);
      expect(find.textContaining('Участники:'), findsNothing);
    });

    testWidgets('uses localized contacts toolbar labels', (tester) async {
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
              activeConversationKey: '',
            ),
          ),
        ),
      );

      expect(find.text('Contacts'), findsOneWidget);
      expect(find.byTooltip('Workspaces'), findsOneWidget);
      expect(find.byTooltip('Refresh contacts'), findsOneWidget);
      expect(find.byTooltip('Create group'), findsOneWidget);
      expect(find.text('Контакты'), findsNothing);
      expect(find.byTooltip('Обновить контакты'), findsNothing);
      expect(find.byTooltip('Создать группу'), findsNothing);
    });

    testWidgets('uses localized empty contacts state', (tester) async {
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
              activeConversationKey: '',
              conversations: const [],
            ),
          ),
        ),
      );

      expect(find.text('No registered phone contacts'), findsOneWidget);
      expect(
        find.text('Нет зарегистрированных контактов из телефона'),
        findsNothing,
      );
    });

    testWidgets('uses localized add-to-family contact tooltip', (tester) async {
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
              activeConversationKey: '',
              contacts: const [
                ChatContact(
                  profileKey: 'nastya',
                  phone: '+10000000000',
                  displayName: 'Nastya',
                  conversationKey: 'dm:nastya',
                ),
              ],
              conversations: const [],
            ),
          ),
        ),
      );

      expect(find.byTooltip('Add to family'), findsOneWidget);
      expect(find.byTooltip('Добавить в семью'), findsNothing);
    });

    testWidgets('uses localized chat header call tooltips', (tester) async {
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
              onCallTap: () {},
              onVideoCallTap: () {},
            ),
          ),
        ),
      );

      expect(find.byTooltip('Contacts'), findsOneWidget);
      expect(find.byTooltip('Audio call'), findsOneWidget);
      expect(find.byTooltip('Video call'), findsOneWidget);
      expect(find.byTooltip('Аудиозвонок'), findsNothing);
      expect(find.byTooltip('Видеозвонок'), findsNothing);
    });

    testWidgets('uses localized typing labels', (tester) async {
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
              typingUsers: const {
                'grp:family:group-1': {'nastya'},
              },
            ),
          ),
        ),
      );

      expect(find.text('nastya is typing...'), findsOneWidget);
      expect(find.textContaining('печатает'), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: Scaffold(
            body: _page(
              controller: controller,
              activeConversationKey: '',
              contacts: const [
                ChatContact(
                  profileKey: 'nastya',
                  displayName: 'Nastya',
                  phone: '+100',
                  conversationKey: 'direct:nastya',
                ),
              ],
              typingUsers: const {
                'direct:nastya': {'nastya'},
              },
            ),
          ),
        ),
      );

      expect(find.text('typing...'), findsOneWidget);
      expect(find.text('печатает...'), findsNothing);
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
  List<ChatContact> contacts = const [],
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
  VoidCallback? onCallTap,
  VoidCallback? onVideoCallTap,
  Map<String, Set<String>> typingUsers = const {},
  void Function(String conversationKey)? onOpenConversation,
}) {
  return MessengerPage(
    conversations: conversations,
    contacts: contacts,
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
    typingUsers: typingUsers,
    onCallTap: onCallTap,
    onVideoCallTap: onVideoCallTap,
    activeProject: activeProject,
    onAnalyzeProjectChat: onAnalyze,
    onDraftProjectTask: activeProject == null ? null : () {},
    onStartProjectAgent: activeProject == null ? null : () {},
    onShowProjectStatus: activeProject == null ? null : () {},
  );
}
