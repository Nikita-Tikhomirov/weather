import 'package:family_todo_mobile/features/chat/messenger_page.dart';
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
  });
}

MessengerPage _page({
  required TextEditingController controller,
  TaskProject? activeProject,
  VoidCallback? onAnalyze,
}) {
  return MessengerPage(
    conversations: const [
      ChatConversation(
        conversationKey: 'grp:family:group-1',
        kind: 'group',
        title: 'Команда',
        members: ['nik', 'nastya'],
      ),
    ],
    contacts: const [],
    messages: const [],
    activeConversationKey: 'grp:family:group-1',
    owner: 'nik',
    compact: false,
    chatInputController: controller,
    replyToMessage: null,
    editingMessageId: null,
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
    onOpenConversation: (_) {},
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
