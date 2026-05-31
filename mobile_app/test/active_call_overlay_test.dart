import 'package:family_todo_mobile/features/chat/active_call_banner.dart';
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

  testWidgets('shows incoming call banner above any app tab', (tester) async {
    var opened = false;
    var accepted = false;
    var ended = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActiveCallOverlay(
            session: session(),
            state: CallState.ringing,
            owner: owner,
            profileLabel: (profile) => 'User $profile',
            onOpen: () => opened = true,
            onAccept: () => accepted = true,
            onEnd: () => ended = true,
            child: const Center(child: Text('Задачи')),
          ),
        ),
      ),
    );

    expect(find.text('Задачи'), findsOneWidget);
    expect(find.text('Входящий видеозвонок'), findsOneWidget);
    expect(find.text('User misha'), findsOneWidget);
    expect(find.text('Принять'), findsOneWidget);
    expect(find.text('Отклонить'), findsOneWidget);

    await tester.tap(find.text('Открыть экран звонка'));
    expect(opened, isTrue);

    await tester.tap(find.text('Принять'));
    expect(accepted, isTrue);

    await tester.tap(find.text('Отклонить'));
    expect(ended, isTrue);
  });

  testWidgets('hides banner for ended calls and keeps child visible',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActiveCallOverlay(
            session: session(),
            state: CallState.ended,
            owner: owner,
            profileLabel: (profile) => profile,
            onOpen: () {},
            onAccept: () {},
            onEnd: () {},
            child: const Center(child: Text('Календарь')),
          ),
        ),
      ),
    );

    expect(find.text('Календарь'), findsOneWidget);
    expect(find.text('Входящий видеозвонок'), findsNothing);
  });

  testWidgets('uses a non-black prompt for incoming audio calls',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActiveCallOverlay(
            session: session(callType: 'audio'),
            state: CallState.ringing,
            owner: owner,
            profileLabel: (profile) => 'User $profile',
            onOpen: () {},
            onAccept: () {},
            onEnd: () {},
            child: const Center(child: Text('Задачи')),
          ),
        ),
      ),
    );

    expect(find.text('Входящий аудиозвонок'), findsOneWidget);
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
