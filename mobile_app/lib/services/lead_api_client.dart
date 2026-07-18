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
  Future<LeadItem> getLead({
    required String actorProfile,
    required int leadId,
  }) async {
    final body = await getJsonWithFallback(
      paths: const ['/leads/show'],
      query: {'actor_profile': actorProfile, 'lead_id': '$leadId'},
    );
    return LeadItem.fromJson(
      Map<String, dynamic>.from((body['lead'] as Map?) ?? const {}),
    );
  }

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
  }) {
    return _postLead('/leads/create', {
      'actor_profile': actorProfile,
      'title': title,
      'source_url': sourceUrl,
      'raw_brief': rawBrief,
      'summary': summary,
      'draft_reply': draftReply,
      'proposal_title': proposalTitle,
      'proposal_price_rub': proposalPriceRub,
      'proposal_days': proposalDays,
    });
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
  }) {
    final payload = <String, dynamic>{
      'actor_profile': actorProfile,
      'lead_id': leadId,
      'draft_reply': draftReply,
      'proposal_title': proposalTitle,
      'proposal_price_rub': proposalPriceRub,
      'proposal_days': proposalDays,
    };
    if (title != null) payload['title'] = title;
    if (sourceUrl != null) payload['source_url'] = sourceUrl;
    if (rawBrief != null) payload['raw_brief'] = rawBrief;
    if (summary != null) payload['summary'] = summary;
    return _postLead('/leads/edit', payload);
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

  @override
  Future<void> deleteLead({
    required String actorProfile,
    required int leadId,
  }) async {
    await postJsonWithFallback(
      paths: const ['/leads/delete'],
      body: jsonEncode({'actor_profile': actorProfile, 'lead_id': leadId}),
    );
  }

  Future<LeadItem> _postLead(String path, Map<String, dynamic> payload) async {
    final body = await postJsonWithFallback(paths: [path], body: jsonEncode(payload));
    return LeadItem.fromJson(
      Map<String, dynamic>.from((body['lead'] as Map?) ?? const {}),
    );
  }
}
