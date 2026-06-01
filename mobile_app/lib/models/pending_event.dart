import 'package:flutter/foundation.dart';

@immutable
class PendingEvent {
  const PendingEvent({
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

  Map<String, dynamic> toJson() {
    return {
      'event_id': eventId,
      'entity': entity,
      'action': action,
      'payload_json': payloadJson,
      'happened_at': happenedAt,
    };
  }

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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PendingEvent &&
          runtimeType == other.runtimeType &&
          eventId == other.eventId &&
          entity == other.entity &&
          action == other.action &&
          payloadJson == other.payloadJson &&
          happenedAt == other.happenedAt;

  @override
  int get hashCode =>
      eventId.hashCode ^
      entity.hashCode ^
      action.hashCode ^
      payloadJson.hashCode ^
      happenedAt.hashCode;

  PendingEvent copyWith({
    String? eventId,
    String? entity,
    String? action,
    String? payloadJson,
    String? happenedAt,
  }) =>
      PendingEvent(
        eventId: eventId ?? this.eventId,
        entity: entity ?? this.entity,
        action: action ?? this.action,
        payloadJson: payloadJson ?? this.payloadJson,
        happenedAt: happenedAt ?? this.happenedAt,
      );
}
