import '../models/lead_models.dart';

abstract class LeadApi {
  Future<List<LeadItem>> listLeads({required String actorProfile});

  Future<LeadItem> editLead({
    required String actorProfile,
    required int leadId,
    required String draftReply,
    required String proposalTitle,
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
}
