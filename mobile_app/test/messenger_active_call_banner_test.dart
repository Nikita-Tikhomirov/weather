import 'package:family_todo_mobile/features/chat/messenger_page.dart';
import 'package:family_todo_mobile/models/call_models.dart';
import 'package:family_todo_mobile/models/chat_models.dart';
import 'package:family_todo_mobile/services/call_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MessengerPage buildPage({
    required CallSession activeCallSession,
    required CallState activeCallState,
    required VoidCallback onOpenActiveCall,
    VoidCallback? onEndActiveCall,
  }) {
    return MessengerPage(
      conversations: const <ChatConversation>[],
      contacts: const <ChatContact>[],
      messages: const <ChatMessage>[],
      activeConversationKey: '',
      owner: 'nik',
      compact: true,
      chatInputController: TextEditingController(),
      replyToMessage: null,
      editingMessageId: null,
      isRecording: false,
      conversationLabel: (conversation, actor) => conversation.title,
      contactLabel: (contact) => contact.profileKey,
      chatMessageText: (message) => message.text,
      profileLabel: (profile) => 'User $profile',
      stickerAssetFor: (_) => '',
      imageUrlFor: (_) => '',
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
      activeCallSession: activeCallSession,
      activeCallState: activeCallState,
      onOpenActiveCall: onOpenActiveCall,
      onEndActiveCall: onEndActiveCall,
    );
  }

  testWidgets('shows incoming video call banner above contact list',
      (tester) async {
    var opened = false;
    final session = CallSession(
      sessionId: 'call-123',
      callerProfile: 'misha',
      calleeProfile: 'nik',
      conversationKey: 'dm:nik:misha',
      callType: 'video',
      status: 'ringing',
      createdAt: '2026-05-31T10:00:00',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: buildPage(
            activeCallSession: session,
            activeCallState: CallState.ringing,
            onOpenActiveCall: () => opened = true,
          ),
        ),
      ),
    );

    expect(find.text('Входящий видеозвонок'), findsOneWidget);
    expect(find.text('User misha'), findsOneWidget);

    await tester.tap(find.text('Открыть'));
    expect(opened, isTrue);
  });

  testWidgets('shows active call banner above open chat', (tester) async {
    var opened = false;
    var ended = false;
    final session = CallSession(
      sessionId: 'call-456',
      callerProfile: 'nik',
      calleeProfile: 'misha',
      conversationKey: 'dm:nik:misha',
      callType: 'audio',
      status: 'active',
      createdAt: '2026-05-31T10:00:00',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: buildPage(
            activeCallSession: session,
            activeCallState: CallState.connected,
            onOpenActiveCall: () => opened = true,
            onEndActiveCall: () => ended = true,
          ),
        ),
      ),
    );

    expect(find.text('Идет аудиозвонок'), findsOneWidget);
    await tester.tap(find.text('Вернуться'));
    expect(opened, isTrue);
    await tester.tap(find.byIcon(Icons.call_end));
    expect(ended, isTrue);
  });
}
