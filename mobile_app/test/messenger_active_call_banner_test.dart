import 'package:family_todo_mobile/features/chat/messenger_page.dart';
import 'package:family_todo_mobile/l10n/app_localizations.dart';
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

  Widget localizedApp(Widget child) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: Scaffold(body: child),
    );
  }

  testWidgets('shows incoming video call banner above contact list',
      (tester) async {
    var opened = false;
    const session = CallSession(
      sessionId: 'call-123',
      callerProfile: 'misha',
      calleeProfile: 'nik',
      conversationKey: 'dm:nik:misha',
      callType: 'video',
      status: 'ringing',
      createdAt: '2026-05-31T10:00:00',
    );

    await tester.pumpWidget(
      localizedApp(
        buildPage(
          activeCallSession: session,
          activeCallState: CallState.ringing,
          onOpenActiveCall: () => opened = true,
        ),
      ),
    );

    expect(find.text('Incoming video call'), findsOneWidget);
    expect(find.text('User misha'), findsOneWidget);

    await tester.tap(find.text('Open'));
    expect(opened, isTrue);
  });

  testWidgets('shows active call banner above open chat', (tester) async {
    var opened = false;
    var ended = false;
    const session = CallSession(
      sessionId: 'call-456',
      callerProfile: 'nik',
      calleeProfile: 'misha',
      conversationKey: 'dm:nik:misha',
      callType: 'audio',
      status: 'active',
      createdAt: '2026-05-31T10:00:00',
    );

    await tester.pumpWidget(
      localizedApp(
        buildPage(
          activeCallSession: session,
          activeCallState: CallState.connected,
          onOpenActiveCall: () => opened = true,
          onEndActiveCall: () => ended = true,
        ),
      ),
    );

    expect(find.text('Ongoing audio call'), findsOneWidget);
    await tester.tap(find.text('Return'));
    expect(opened, isTrue);
    await tester.tap(find.byIcon(Icons.call_end));
    expect(ended, isTrue);
  });
}
