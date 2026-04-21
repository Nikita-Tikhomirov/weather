import 'dart:convert';

class TaskItem {
  TaskItem({
    required this.id,
    required this.ownerKey,
    required this.isFamily,
    required this.title,
    required this.details,
    required this.dueDate,
    required this.time,
    required this.workflowStatus,
    required this.priority,
    required this.tags,
    required this.assignees,
    required this.durationMinutes,
    required this.updatedAt,
    required this.version,
  });

  final String id;
  final String ownerKey;
  final bool isFamily;
  final String title;
  final String details;
  final String dueDate;
  final String time;
  final String workflowStatus;
  final String priority;
  final List<String> tags;
  final List<String> assignees;
  List<String> get participants => assignees;

  final int durationMinutes;
  final String updatedAt;
  final int version;

  factory TaskItem.fromJson(Map<String, dynamic> json) {
    return TaskItem(
      id: (json['id'] ?? '').toString(),
      ownerKey: (json['owner_key'] ?? '').toString(),
      isFamily: json['is_family'] == true || json['is_family'] == 1,
      title: (json['title'] ?? '').toString(),
      details: (json['details'] ?? '').toString(),
      dueDate: (json['due_date'] ?? '').toString(),
      time: (json['time'] ?? '').toString(),
      workflowStatus: (json['workflow_status'] ?? 'todo').toString(),
      priority: (json['priority'] ?? 'medium').toString(),
      tags: (json['tags'] is List)
          ? (json['tags'] as List).map((v) => v.toString()).toList()
          : const [],
      assignees: (json['assignees'] is List)
          ? (json['assignees'] as List).map((v) => v.toString()).toList()
          : (json['participants'] is List)
              ? (json['participants'] as List).map((v) => v.toString()).toList()
              : const [],
      durationMinutes: int.tryParse((json['duration_minutes'] ?? 0).toString()) ?? 0,
      updatedAt: (json['updated_at'] ?? '').toString(),
      version: int.tryParse((json['version'] ?? 1).toString()) ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'owner_key': ownerKey,
      'is_family': isFamily,
      'title': title,
      'details': details,
      'due_date': dueDate,
      'time': time,
      'workflow_status': workflowStatus,
      'priority': priority,
      'tags': tags,
      'assignees': assignees,
      'participants': assignees,
      'duration_minutes': durationMinutes,
      'updated_at': updatedAt,
      'version': version,
    };
  }

  Map<String, Object?> toDbRow() {
    return {
      'id': id,
      'owner_key': ownerKey,
      'is_family': isFamily ? 1 : 0,
      'title': title,
      'details': details,
      'due_date': dueDate,
      'time': time,
      'workflow_status': workflowStatus,
      'priority': priority,
      'tags_json': jsonEncode(tags),
      'participants_json': jsonEncode(assignees),
      'duration_minutes': durationMinutes,
      'updated_at': updatedAt,
      'version': version,
    };
  }

  factory TaskItem.fromDbRow(Map<String, Object?> row) {
    return TaskItem(
      id: (row['id'] ?? '').toString(),
      ownerKey: (row['owner_key'] ?? '').toString(),
      isFamily: (row['is_family'] ?? 0).toString() == '1',
      title: (row['title'] ?? '').toString(),
      details: (row['details'] ?? '').toString(),
      dueDate: (row['due_date'] ?? '').toString(),
      time: (row['time'] ?? '').toString(),
      workflowStatus: (row['workflow_status'] ?? 'todo').toString(),
      priority: (row['priority'] ?? 'medium').toString(),
      tags: _decodeStringList(row['tags_json']),
      assignees: _decodeStringList(row['participants_json']),
      durationMinutes: int.tryParse((row['duration_minutes'] ?? 0).toString()) ?? 0,
      updatedAt: (row['updated_at'] ?? '').toString(),
      version: int.tryParse((row['version'] ?? 1).toString()) ?? 1,
    );
  }

  TaskItem copyWith({
    String? ownerKey,
    bool? isFamily,
    String? title,
    String? details,
    String? dueDate,
    String? time,
    String? workflowStatus,
    String? priority,
    List<String>? tags,
    List<String>? assignees,
    int? durationMinutes,
    String? updatedAt,
    int? version,
  }) {
    return TaskItem(
      id: id,
      ownerKey: ownerKey ?? this.ownerKey,
      isFamily: isFamily ?? this.isFamily,
      title: title ?? this.title,
      details: details ?? this.details,
      dueDate: dueDate ?? this.dueDate,
      time: time ?? this.time,
      workflowStatus: workflowStatus ?? this.workflowStatus,
      priority: priority ?? this.priority,
      tags: tags ?? this.tags,
      assignees: assignees ?? this.assignees,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
    );
  }

  static List<String> _decodeStringList(Object? raw) {
    if (raw == null) {
      return const [];
    }
    try {
      final parsed = jsonDecode(raw.toString());
      if (parsed is List) {
        return parsed.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return const [];
  }
}
