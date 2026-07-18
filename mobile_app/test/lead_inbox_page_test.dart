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
    expect(find.text('Открыть заказ на Kwork'), findsOneWidget);
    expect(find.text('Техническое задание'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'Сделаю адаптивный лендинг и проверю форму.');
    final detailScroll = find.descendant(
      of: find.byType(DraggableScrollableSheet),
      matching: find.byType(Scrollable),
    ).first;
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
}

class _FakeLeadApi implements LeadApi {
  int editCalls = 0;
  int approveCalls = 0;

  LeadItem _lead = _leadItem();

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
    int? proposalPriceRub,
    int? proposalDays,
  }) async {
    editCalls++;
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
  Future<List<LeadItem>> listLeads({required String actorProfile}) async => [_lead];

  @override
  Future<LeadItem> rejectLead({
    required String actorProfile,
    required int leadId,
  }) async => _lead.copyWith(status: 'rejected');
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
