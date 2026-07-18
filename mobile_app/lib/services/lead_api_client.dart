import 'dart:convert';

import '../contracts/lead_api.dart';
import '../models/lead_models.dart';
import 'http_client_base.dart';

class LeadApiClient extends HttpApiClient implements LeadApi {
  LeadApiClient({required super.baseUrl, required super.apiKey});

  @override
  Future<List<LeadItem>> listLeads({required String actorProfile}) async {
    final body = await getJsonWithFallback(
      paths: const ['/leads'],
      query: {'actor_profile': actorProfile},
    );
    return (body['leads'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => LeadItem.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  @override
  Future<LeadItem> editLead({
    required String actorProfile,
    required int leadId,
    required String draftReply,
    required String proposalTitle,
    int? proposalPriceRub,
    int? proposalDays,
  }) {
    return _postLead('/leads/edit', {
      'actor_profile': actorProfile,
      'lead_id': leadId,
      'draft_reply': draftReply,
      'proposal_title': proposalTitle,
      'proposal_price_rub': proposalPriceRub,
      'proposal_days': proposalDays,
    });
  }

  @override
  Future<LeadItem> approveLead({
    required String actorProfile,
    required int leadId,
  }) => _postLead('/leads/approve', {
        'actor_profile': actorProfile,
        'lead_id': leadId,
      });

  @override
  Future<LeadItem> rejectLead({
    required String actorProfile,
    required int leadId,
  }) => _postLead('/leads/reject', {
        'actor_profile': actorProfile,
        'lead_id': leadId,
      });

  Future<LeadItem> _postLead(String path, Map<String, dynamic> payload) async {
    final body = await postJsonWithFallback(paths: [path], body: jsonEncode(payload));
    return LeadItem.fromJson(
      Map<String, dynamic>.from((body['lead'] as Map?) ?? const {}),
    );
  }
}
