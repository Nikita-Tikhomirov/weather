import 'package:flutter_test/flutter_test.dart';

import 'package:family_todo_mobile/models/lead_models.dart';

void main() {
  test('LeadItem decodes editable Kwork order card', () {
    final lead = LeadItem.fromJson(const {
      'id': 9,
      'external_key': 'kwork:9',
      'owner_profile': 'phone-79679812438',
      'source': 'kwork',
      'source_url': 'https://kwork.ru/projects/9',
      'title': 'Сверстать страницу',
      'raw_brief': 'Нужен адаптив.',
      'summary': 'Небольшая верстка.',
      'attachment_report': 'PDF прочитан.',
      'draft_reply': 'Сделаю аккуратно.',
      'proposal_title': 'Верстка страницы',
      'proposal_price_rub': 4500,
      'proposal_days': 3,
      'buyer_desired_budget_rub': 2000,
      'kwork_max_price_rub': 6000,
      'offer_count': 2,
      'status': 'new',
      'last_error': '',
      'version': 1,
      'created_at': '2026-07-18T12:00:00',
      'updated_at': '2026-07-18T12:00:00',
    });

    expect(lead.id, 9);
    expect(lead.proposalPriceRub, 4500);
    expect(lead.buyerDesiredBudgetRub, 2000);
    expect(lead.kworkMaxPriceRub, 6000);
    expect(lead.offerCount, 2);
    expect(lead.canEdit, isTrue);
    expect(lead.canApprove, isTrue);
  });
}
