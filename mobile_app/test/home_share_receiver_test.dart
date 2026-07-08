import 'dart:async';

import 'package:family_todo_mobile/domain/task_domain_service.dart';
import 'package:family_todo_mobile/features/home/home_share_receiver.dart';
import 'package:family_todo_mobile/l10n/app_localizations.dart';
import 'package:family_todo_mobile/models/chat_models.dart';
import 'package:family_todo_mobile/models/family_group.dart';
import 'package:family_todo_mobile/models/task_item.dart';
import 'package:family_todo_mobile/models/task_project.dart';
import 'package:family_todo_mobile/repositories/task_repository.dart';
import 'package:family_todo_mobile/services/api_client.dart';
import 'package:family_todo_mobile/services/local_db.dart';
import 'package:family_todo_mobile/state/task_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('share receiver dialog uses localized labels', (tester) async {
    const channel = MethodChannel('family_todo_mobile/share');
    final store = TaskStore(
      repository: _FakeTaskRepository(),
      domainService: TaskDomainService(),
    );
    store.owner.value = 'nik';
    addTearDown(store.dispose);

    late BuildContext receiverContext;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Builder(
          builder: (context) {
            receiverContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    HomeShareReceiver(store: store).initShareReceiver(
      context: receiverContext,
      getAllContacts: (_) => const [
        ChatContact(
          profileKey: 'mia',
          displayName: 'Mia',
          phone: '',
          conversationKey: 'dm:mia:nik',
        ),
      ],
      setActiveConversation: (_) {},
      refreshConversation: (
        _,
        __, {
        required quiet,
        required useNetwork,
      }) async {},
    );

    unawaited(
      _simulateIncomingShare(
        tester,
        channel,
        const <String, Object?>{'text': 'hello'},
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(find.text('Share text'), findsOneWidget);
    expect(find.text('Mia'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Поделиться текстом'), findsNothing);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    unawaited(
      _simulateIncomingShare(
        tester,
        channel,
        const <String, Object?>{
          'imageUris': <String>['/tmp/missing.jpg'],
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(find.text('Share photo'), findsOneWidget);
    expect(find.text('Поделиться фото'), findsNothing);
  });

  testWidgets('share receiver dialog falls back to English labels',
      (tester) async {
    const channel = MethodChannel('family_todo_mobile/share');
    final store = TaskStore(
      repository: _FakeTaskRepository(),
      domainService: TaskDomainService(),
    );
    store.owner.value = 'nik';
    addTearDown(store.dispose);

    late BuildContext receiverContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Builder(
          builder: (context) {
            receiverContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    HomeShareReceiver(store: store).initShareReceiver(
      context: receiverContext,
      getAllContacts: (_) => const [
        ChatContact(
          profileKey: 'mia',
          displayName: 'Mia',
          phone: '',
          conversationKey: 'dm:mia:nik',
        ),
      ],
      setActiveConversation: (_) {},
      refreshConversation: (
        _,
        __, {
        required quiet,
        required useNetwork,
      }) async {},
    );

    unawaited(
      _simulateIncomingShare(
        tester,
        channel,
        const <String, Object?>{'text': 'hello'},
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(find.text('Share text'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Поделиться текстом'), findsNothing);
    expect(find.text('Отмена'), findsNothing);
  });

  testWidgets('share receiver confirms after selected contact receives content',
      (tester) async {
    const channel = MethodChannel('family_todo_mobile/share');
    final repository = _FakeTaskRepository();
    final store = TaskStore(
      repository: repository,
      domainService: TaskDomainService(),
    );
    store.owner.value = 'nik';
    addTearDown(store.dispose);

    late BuildContext receiverContext;
    var activeConversation = '';
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              receiverContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    HomeShareReceiver(store: store).initShareReceiver(
      context: receiverContext,
      getAllContacts: (_) => const [
        ChatContact(
          profileKey: 'mia',
          displayName: 'Mia',
          phone: '',
          conversationKey: 'dm:mia:nik',
        ),
      ],
      setActiveConversation: (key) => activeConversation = key,
      refreshConversation: (
        _,
        __, {
        required quiet,
        required useNetwork,
      }) async {},
    );

    unawaited(
      _simulateIncomingShare(
        tester,
        channel,
        const <String, Object?>{'text': 'hello'},
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mia'));
    await tester.pumpAndSettle();

    expect(repository.fakeApi.sentTexts, ['hello']);
    expect(activeConversation, 'dm:mia:nik');
    expect(find.text('Forwarded to Mia'), findsOneWidget);
  });
}

Future<void> _simulateIncomingShare(
  WidgetTester tester,
  MethodChannel channel,
  Map<String, Object?> arguments,
) {
  final codec = channel.codec as StandardMethodCodec;
  final data = codec.encodeMethodCall(
    MethodCall('onShareReceived', arguments),
  );
  return tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    channel.name,
    data,
    (_) {},
  );
}

class _FakeTaskRepository implements TaskRepository {
  final _FakeApiClient fakeApi = _FakeApiClient();

  @override
  LocalDb get db => throw UnimplementedError();

  @override
  ApiClient get api => fakeApi;

  @override
  String get actorProfile => 'nik';

  @override
  Future<void> bindActor(String actorProfile) async {}

  @override
  Future<void> delete(TaskItem task) async {}

  @override
  Future<List<FamilyGroup>> readFamilyGroups() async => const [];

  @override
  Future<Map<String, List<String>>> readProjectGroupMap() async => const {};

  @override
  Future<List<TaskProject>> readProjects() async => const [];

  @override
  Future<List<TaskItem>> readVisibleTasks() async => const [];

  @override
  Future<void> syncDelta() async {}

  @override
  Future<void> syncFull() async {}

  @override
  Future<void> upsert(TaskItem task) async {}

  @override
  Future<void> upsertFamilyGroup(FamilyGroup group) async {}

  @override
  Future<void> upsertProject(TaskProject project) async {}
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super(baseUrl: 'http://localhost', apiKey: 'test');

  final sentTexts = <String>[];

  @override
  Future<ChatMessage> chatSendMessage({
    required String actorProfile,
    required String conversationKey,
    required String messageType,
    String text = '',
    String? stickerId,
    String? imageUrl,
    Map<String, dynamic>? imageMeta,
    List<ChatAttachment> attachments = const [],
    String? clientMessageId,
  }) async {
    sentTexts.add(text);
    return ChatMessage(
      id: 'msg-${sentTexts.length}',
      conversationKey: conversationKey,
      senderProfile: actorProfile,
      messageType: messageType,
      text: text,
      createdAt: '2026-07-08T12:00:00Z',
      attachments: attachments,
    );
  }

  @override
  Future<void> chatMarkRead({
    required String actorProfile,
    required String conversationKey,
  }) async {}
}
