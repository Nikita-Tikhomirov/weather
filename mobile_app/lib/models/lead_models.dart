class LeadItem {
  const LeadItem({
    required this.id,
    required this.externalKey,
    required this.ownerProfile,
    required this.source,
    required this.sourceUrl,
    required this.title,
    required this.rawBrief,
    required this.summary,
    required this.attachmentReport,
    required this.draftReply,
    required this.proposalTitle,
    required this.proposalPriceRub,
    required this.proposalDays,
    required this.buyerDesiredBudgetRub,
    required this.kworkMaxPriceRub,
    required this.offerCount,
    required this.status,
    required this.lastError,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String externalKey;
  final String ownerProfile;
  final String source;
  final String sourceUrl;
  final String title;
  final String rawBrief;
  final String summary;
  final String attachmentReport;
  final String draftReply;
  final String proposalTitle;
  final int? proposalPriceRub;
  final int? proposalDays;
  final int? buyerDesiredBudgetRub;
  final int? kworkMaxPriceRub;
  final int? offerCount;
  final String status;
  final String lastError;
  final int version;
  final String createdAt;
  final String updatedAt;

  bool get canEdit => {'new', 'edited', 'failed'}.contains(status);
  bool get canApprove => canEdit;
  bool get canReject => !{'sending', 'sent', 'rejected'}.contains(status);

  LeadItem copyWith({
    String? draftReply,
    String? proposalTitle,
    int? proposalPriceRub,
    int? proposalDays,
    String? status,
    int? version,
  }) {
    return LeadItem(
      id: id,
      externalKey: externalKey,
      ownerProfile: ownerProfile,
      source: source,
      sourceUrl: sourceUrl,
      title: title,
      rawBrief: rawBrief,
      summary: summary,
      attachmentReport: attachmentReport,
      draftReply: draftReply ?? this.draftReply,
      proposalTitle: proposalTitle ?? this.proposalTitle,
      proposalPriceRub: proposalPriceRub ?? this.proposalPriceRub,
      proposalDays: proposalDays ?? this.proposalDays,
      buyerDesiredBudgetRub: buyerDesiredBudgetRub,
      kworkMaxPriceRub: kworkMaxPriceRub,
      offerCount: offerCount,
      status: status ?? this.status,
      lastError: lastError,
      version: version ?? this.version,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  factory LeadItem.fromJson(Map<String, dynamic> json) {
    int? integer(Object? value) =>
        value is num ? value.toInt() : int.tryParse('$value');
    return LeadItem(
      id: integer(json['id']) ?? 0,
      externalKey: '${json['external_key'] ?? ''}',
      ownerProfile: '${json['owner_profile'] ?? ''}',
      source: '${json['source'] ?? 'kwork'}',
      sourceUrl: '${json['source_url'] ?? ''}',
      title: '${json['title'] ?? ''}',
      rawBrief: '${json['raw_brief'] ?? ''}',
      summary: '${json['summary'] ?? ''}',
      attachmentReport: '${json['attachment_report'] ?? ''}',
      draftReply: '${json['draft_reply'] ?? ''}',
      proposalTitle: '${json['proposal_title'] ?? ''}',
      proposalPriceRub: integer(json['proposal_price_rub']),
      proposalDays: integer(json['proposal_days']),
      buyerDesiredBudgetRub: integer(json['buyer_desired_budget_rub']),
      kworkMaxPriceRub: integer(json['kwork_max_price_rub']),
      offerCount: integer(json['offer_count']),
      status: '${json['status'] ?? 'new'}',
      lastError: '${json['last_error'] ?? ''}',
      version: integer(json['version']) ?? 1,
      createdAt: '${json['created_at'] ?? ''}',
      updatedAt: '${json['updated_at'] ?? ''}',
    );
  }
}

class LeadMonitor {
  const LeadMonitor({
    required this.desiredState,
    required this.scanRequested,
    required this.executorId,
    required this.lastSeenAt,
    required this.lastScanStartedAt,
    required this.lastScanFinishedAt,
    required this.lastError,
  });

  final String desiredState;
  final bool scanRequested;
  final String? executorId;
  final String? lastSeenAt;
  final String? lastScanStartedAt;
  final String? lastScanFinishedAt;
  final String lastError;

  bool get isRunning => desiredState == 'running';

  factory LeadMonitor.fromJson(Map<String, dynamic> json) {
    String? nullableText(Object? value) {
      final text = '$value'.trim();
      return text.isEmpty || text == 'null' ? null : text;
    }

    return LeadMonitor(
      desiredState: '${json['desired_state'] ?? 'stopped'}',
      scanRequested: json['scan_requested'] == true,
      executorId: nullableText(json['executor_id']),
      lastSeenAt: nullableText(json['last_seen_at']),
      lastScanStartedAt: nullableText(json['last_scan_started_at']),
      lastScanFinishedAt: nullableText(json['last_scan_finished_at']),
      lastError: '${json['last_error'] ?? ''}',
    );
  }
}
