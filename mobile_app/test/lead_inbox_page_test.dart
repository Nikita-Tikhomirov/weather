import 'package:family_todo_mobile/contracts/lead_api.dart';
import 'package:family_todo_mobile/features/leads/lead_inbox_page.dart';
import 'package:family_todo_mobile/models/lead_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('edits and approves a Kwork lead from its card', (tester) async {
    final api = _FakeLeadApi();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: LeadInboxPage(api: api, actorProfile: 'nikita'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Заказы'), findsOneWidget);
    expect(find.text('Сверстать лендинг'), findsOneWidget);
    expect(find.textContaining('2 откл.'), findsOneWidget);

    await tester.tap(find.text('Сверстать лендинг'));
    await tester.pumpAndSettle();
    expect(api.getCalls, 1);
    expect(find.text('Открыть заказ на Kwork'), findsOneWidget);
    expect(find.text('Техническое задание'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0),
        'Сделаю адаптивный лендинг и проверю форму.');
    final detailScroll = find
        .descendant(
          of: find.byType(DraggableScrollableSheet),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Сохранить изменения'),
      300,
      scrollable: detailScroll,
    );
    await tester.tap(find.text('Сохранить изменения'));
    await tester.pumpAndSettle();

    expect(api.editCalls, 1);
    await tester.scrollUntilVisible(
      find.text('Одобрить и отправить с ПК'),
      300,
      scrollable: detailScroll,
    );
    await tester.tap(find.text('Одобрить и отправить с ПК'));
    await tester.pumpAndSettle();
    expect(api.approveCalls, 1);
  });

  testWidgets('creates and deletes a lead card', (tester) async {
    final api = _FakeLeadApi();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: LeadInboxPage(api: api, actorProfile: 'nikita'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Ручной заказ');
    await tester.tap(find.byIcon(Icons.save_outlined));
    await tester.pumpAndSettle();
    expect(api.createCalls, 1);

    await tester.tap(find.text('Сверстать лендинг'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();
    expect(api.deleteCalls, 1);
  });

  testWidgets('shows controls for the Kwork monitor', (tester) async {
    final api = _FakeLeadApi();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: LeadInboxPage(api: api, actorProfile: 'nikita'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Сканировать сейчас'), findsOneWidget);
    expect(find.text('Старт'), findsOneWidget);
    expect(find.text('Стоп'), findsOneWidget);
  });

  testWidgets(
      'approval saves edited reply fields before queuing the Kwork send',
      (tester) async {
    final api = _FakeLeadApi();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: LeadInboxPage(api: api, actorProfile: 'nikita'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Сверстать лендинг'));
    await tester.pumpAndSettle();
    final detailScroll = find
        .descendant(
          of: find.byType(DraggableScrollableSheet),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Текст отклика',
      ),
      300,
      scrollable: detailScroll,
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Текст отклика',
      ),
      'Сделаю адаптивный лендинг и проверю форму перед сдачей.',
    );
    await tester.scrollUntilVisible(
      find.text('Одобрить и отправить с ПК'),
      300,
      scrollable: detailScroll,
    );
    await tester.tap(find.text('Одобрить и отправить с ПК'));
    await tester.pumpAndSettle();

    expect(api.editCalls, 1);
    expect(api.approveCalls, 1);
    expect(api.lastSavedReply, contains('перед сдачей'));
  });
}

class _FakeLeadApi implements LeadApi {
  int getCalls = 0;
  int createCalls = 0;
  int deleteCalls = 0;
  int editCalls = 0;
  int approveCalls = 0;
  String lastSavedReply = '';

  LeadItem _lead = _leadItem();

  @override
  Future<LeadMonitor> getMonitor({required String actorProfile}) async =>
      const LeadMonitor(
        desiredState: 'stopped',
        scanRequested: false,
        executorId: null,
        lastSeenAt: null,
        lastScanStartedAt: null,
        lastScanFinishedAt: null,
        lastError: '',
      );

  @override
  Future<LeadMonitor> controlMonitor({
    required String actorProfile,
    required String command,
  }) async =>
      LeadMonitor(
        desiredState: command == 'stop' ? 'stopped' : 'running',
        scanRequested: command != 'stop',
        executorId: null,
        lastSeenAt: null,
        lastScanStartedAt: null,
        lastScanFinishedAt: null,
        lastError: '',
      );

  @override
  Future<LeadItem> createLead({
    required String actorProfile,
    required String title,
    String sourceUrl = '',
    String rawBrief = '',
    String summary = '',
    String draftReply = '',
    String proposalTitle = '',
    int? proposalPriceRub,
    int? proposalDays,
  }) async {
    createCalls++;
    return _lead;
  }

  @override
  Future<void> deleteLead({
    required String actorProfile,
    required int leadId,
  }) async {
    deleteCalls++;
  }

  @override
  Future<LeadItem> approveLead({
    required String actorProfile,
    required int leadId,
  }) async {
    approveCalls++;
    _lead = _lead.copyWith(status: 'approved');
    return _lead;
  }

  @override
  Future<LeadItem> editLead({
    required String actorProfile,
    required int leadId,
    required String draftReply,
    required String proposalTitle,
    String? title,
    String? sourceUrl,
    String? rawBrief,
    String? summary,
    int? proposalPriceRub,
    int? proposalDays,
  }) async {
    editCalls++;
    lastSavedReply = draftReply;
    _lead = _lead.copyWith(
      draftReply: draftReply,
      proposalTitle: proposalTitle,
      proposalPriceRub: proposalPriceRub,
      proposalDays: proposalDays,
      status: 'edited',
    );
    return _lead;
  }

  @override
  Future<LeadItem> getLead({
    required String actorProfile,
    required int leadId,
  }) async {
    getCalls++;
    return _lead;
  }

  @override
  Future<List<LeadItem>> listLeads({required String actorProfile}) async =>
      [_lead];

  @override
  Future<LeadItem> rejectLead({
    required String actorProfile,
    required int leadId,
  }) async =>
      _lead.copyWith(status: 'rejected');
}

LeadItem _leadItem() => const LeadItem(
      id: 1,
      externalKey: 'kwork:81',
      ownerProfile: 'nikita',
      source: 'kwork',
      sourceUrl: 'https://kwork.ru/projects/81',
      title: 'Сверстать лендинг',
      rawBrief: 'Нужна адаптивная страница с формой.',
      summary: 'Подходит для короткого web-проекта.',
      attachmentReport: 'ТЗ.pdf: прочитан',
      draftReply: 'Здравствуйте!',
      proposalTitle: 'Верстка лендинга',
      proposalPriceRub: 5000,
      proposalDays: 3,
      offerCount: 2,
      status: 'new',
      lastError: '',
      version: 1,
      createdAt: '2026-07-18T12:00:00',
      updatedAt: '2026-07-18T12:00:00',
    );
