class PendingEvent {
  PendingEvent({
    required this.eventId,
    required this.entity,
    required this.action,
    required this.payloadJson,
    required this.happenedAt,
  });

  final String eventId;
  final String entity;
  final String action;
  final String payloadJson;
  final String happenedAt;

  Map<String, Object?> toDbRow() {
    return {
      'event_id': eventId,
      'entity': entity,
      'action': action,
      'payload_json': payloadJson,
      'happened_at': happenedAt,
    };
  }

  factory PendingEvent.fromDbRow(Map<String, Object?> row) {
    return PendingEvent(
      eventId: (row['event_id'] ?? '').toString(),
      entity: (row['entity'] ?? '').toString(),
      action: (row['action'] ?? '').toString(),
      payloadJson: (row['payload_json'] ?? '{}').toString(),
      happenedAt: (row['happened_at'] ?? '').toString(),
    );
  }
}

