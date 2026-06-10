import 'package:family_todo_mobile/features/chat/active_call_banner.dart';
import 'package:family_todo_mobile/l10n/app_localizations.dart';
import 'package:family_todo_mobile/models/call_models.dart';
import 'package:family_todo_mobile/services/call_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const owner = 'nik';

  CallSession session({
    String callType = 'video',
    String caller = 'misha',
    String callee = owner,
  }) {
    return CallSession(
      sessionId: 'call-123',
      callerProfile: caller,
      calleeProfile: callee,
      conversationKey: 'dm:nik:misha',
      callType: callType,
      status: 'ringing',
      createdAt: '2026-05-31T10:00:00',
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

  testWidgets('shows incoming call banner above any app tab', (tester) async {
    var opened = false;
    var accepted = false;
    var ended = false;

    await tester.pumpWidget(
      localizedApp(
        ActiveCallOverlay(
          session: session(),
          state: CallState.ringing,
          owner: owner,
          profileLabel: (profile) => 'User $profile',
          onOpen: () => opened = true,
          onAccept: () => accepted = true,
          onEnd: () => ended = true,
          child: const Center(child: Text('Tasks')),
        ),
      ),
    );

    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('Incoming video call'), findsOneWidget);
    expect(find.text('User misha'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);

    await tester.tap(find.text('Open call screen'));
    expect(opened, isTrue);

    await tester.tap(find.text('Accept'));
    expect(accepted, isTrue);

    await tester.tap(find.text('Decline'));
    expect(ended, isTrue);
  });

  testWidgets('hides banner for ended calls and keeps child visible',
      (tester) async {
    await tester.pumpWidget(
      localizedApp(
        ActiveCallOverlay(
          session: session(),
          state: CallState.ended,
          owner: owner,
          profileLabel: (profile) => profile,
          onOpen: () {},
          onAccept: () {},
          onEnd: () {},
          child: const Center(child: Text('Calendar')),
        ),
      ),
    );

    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('Incoming video call'), findsNothing);
  });

  testWidgets('uses a non-black prompt for incoming audio calls',
      (tester) async {
    await tester.pumpWidget(
      localizedApp(
        ActiveCallOverlay(
          session: session(callType: 'audio'),
          state: CallState.ringing,
          owner: owner,
          profileLabel: (profile) => 'User $profile',
          onOpen: () {},
          onAccept: () {},
          onEnd: () {},
          child: const Center(child: Text('Tasks')),
        ),
      ),
    );

    expect(find.text('Incoming audio call'), findsOneWidget);
    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(IncomingCallPrompt),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.color, isNot(Colors.black));
  });
}
