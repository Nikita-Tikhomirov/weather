import '../models/lead_models.dart';

abstract class LeadApi {
  Future<List<LeadItem>> listLeads({required String actorProfile});

  Future<LeadItem> getLead({
    required String actorProfile,
    required int leadId,
  });

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
  });

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
  });

  Future<LeadItem> approveLead({
    required String actorProfile,
    required int leadId,
  });

  Future<LeadItem> rejectLead({
    required String actorProfile,
    required int leadId,
  });

  Future<void> deleteLead({
    required String actorProfile,
    required int leadId,
  });
}
