import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Workflow status of a task.
enum WorkflowStatus {
  todo,
  in_progress,
  in_review,
  done,
  archive;

  static WorkflowStatus parse(String? value) {
    if (value == null || value.isEmpty) return WorkflowStatus.todo;
    return WorkflowStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => WorkflowStatus.todo,
    );
  }
}

/// Task priority level.
enum Priority {
  low,
  medium,
  high;

  static Priority parse(String? value) {
    if (value == null || value.isEmpty) return Priority.medium;
    return Priority.values.firstWhere(
      (e) => e.name == value,
      orElse: () => Priority.medium,
    );
  }
}

/// A single task item used throughout the app.
///
/// Fields [workflowStatus] and [priority] are typed enums
/// ([WorkflowStatus] / [Priority]) for compile-time safety.
/// Serialization uses `.name` which is backward compatible
/// with the previous string-based format.
@immutable
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
    required this.reminderOffsetsMinutes,
    required this.durationMinutes,
    required this.updatedAt,
    required this.version,
    this.projectId = '',
    this.groupId = '',
  });

  final String id;
  final String ownerKey;
  final bool isFamily;
  final String title;
  final String projectId;
  final String groupId;
  final String details;
  final String dueDate;
  final String time;
  final WorkflowStatus workflowStatus;
  final Priority priority;
  final List<String> tags;
  final List<String> assignees;
  final List<int> reminderOffsetsMinutes;

  final int durationMinutes;
  final String updatedAt;
  final int version;

  factory TaskItem.fromJson(Map<String, dynamic> json) {
    return TaskItem(
      id: (json['id'] ?? '').toString(),
      ownerKey: (json['owner_key'] ?? '').toString(),
      isFamily: json['is_family'] == true || json['is_family'] == 1,
      projectId: (json['project_id'] ?? '').toString(),
      groupId: (json['group_id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      details: (json['details'] ?? '').toString(),
      dueDate: (json['due_date'] ?? '').toString(),
      time: (json['time'] ?? '').toString(),
      workflowStatus: WorkflowStatus.parse(
        (json['workflow_status'] ?? '').toString(),
      ),
      priority: Priority.parse((json['priority'] ?? '').toString()),
      tags: (json['tags'] is List)
          ? (json['tags'] as List).map((v) => v.toString()).toList()
          : const [],
      assignees: (json['assignees'] is List)
          ? (json['assignees'] as List).map((v) => v.toString()).toList()
          : (json['participants'] is List)
              ? (json['participants'] as List).map((v) => v.toString()).toList()
              : const [],
      reminderOffsetsMinutes: _normalizeReminderOffsets(
        (json['reminder_offsets_minutes'] is List)
            ? (json['reminder_offsets_minutes'] as List)
            : const [],
      ),
      durationMinutes:
          int.tryParse((json['duration_minutes'] ?? 0).toString()) ?? 0,
      updatedAt: (json['updated_at'] ?? '').toString(),
      version: int.tryParse((json['version'] ?? 1).toString()) ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'owner_key': ownerKey,
      'is_family': isFamily,
      'project_id': projectId,
      'group_id': groupId,
      'title': title,
      'details': details,
      'due_date': dueDate,
      'time': time,
      'workflow_status': workflowStatus.name,
      'priority': priority.name,
      'tags': tags,
      'assignees': assignees,
      'participants': assignees,
      'reminder_offsets_minutes': reminderOffsetsMinutes,
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
      'project_id': projectId,
      'group_id': groupId,
      'title': title,
      'details': details,
      'due_date': dueDate,
      'time': time,
      'workflow_status': workflowStatus.name,
      'priority': priority.name,
      'tags_json': jsonEncode(tags),
      'participants_json': jsonEncode(assignees),
      'reminder_offsets_json': jsonEncode(reminderOffsetsMinutes),
      'duration_minutes': durationMinutes,
      'created_at': updatedAt,
      'updated_at': updatedAt,
      'version': version,
    };
  }

  factory TaskItem.fromDbRow(Map<String, Object?> row) {
    return TaskItem(
      id: (row['id'] ?? '').toString(),
      ownerKey: (row['owner_key'] ?? '').toString(),
      isFamily: (row['is_family'] ?? 0).toString() == '1',
      projectId: (row['project_id'] ?? '').toString(),
      groupId: (row['group_id'] ?? '').toString(),
      title: (row['title'] ?? '').toString(),
      details: (row['details'] ?? '').toString(),
      dueDate: (row['due_date'] ?? '').toString(),
      time: (row['time'] ?? '').toString(),
      workflowStatus: WorkflowStatus.parse(
        (row['workflow_status'] ?? '').toString(),
      ),
      priority: Priority.parse((row['priority'] ?? '').toString()),
      tags: _decodeStringList(row['tags_json']),
      assignees: _decodeStringList(row['participants_json']),
      reminderOffsetsMinutes: _normalizeReminderOffsets(
        _decodeDynamicList(row['reminder_offsets_json']),
      ),
      durationMinutes:
          int.tryParse((row['duration_minutes'] ?? 0).toString()) ?? 0,
      updatedAt: (row['updated_at'] ?? '').toString(),
      version: int.tryParse((row['version'] ?? 1).toString()) ?? 1,
    );
  }

  TaskItem copyWith({
    String? ownerKey,
    bool? isFamily,
    String? projectId,
    String? groupId,
    String? title,
    String? details,
    String? dueDate,
    String? time,
    WorkflowStatus? workflowStatus,
    Priority? priority,
    List<String>? tags,
    List<String>? assignees,
    List<int>? reminderOffsetsMinutes,
    int? durationMinutes,
    String? updatedAt,
    int? version,
  }) {
    return TaskItem(
      id: id,
      ownerKey: ownerKey ?? this.ownerKey,
      isFamily: isFamily ?? this.isFamily,
      projectId: projectId ?? this.projectId,
      groupId: groupId ?? this.groupId,
      title: title ?? this.title,
      details: details ?? this.details,
      dueDate: dueDate ?? this.dueDate,
      time: time ?? this.time,
      workflowStatus: workflowStatus ?? this.workflowStatus,
      priority: priority ?? this.priority,
      tags: tags ?? this.tags,
      assignees: assignees ?? this.assignees,
      reminderOffsetsMinutes:
          reminderOffsetsMinutes ?? this.reminderOffsetsMinutes,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          ownerKey == other.ownerKey &&
          isFamily == other.isFamily &&
          title == other.title &&
          projectId == other.projectId &&
          groupId == other.groupId &&
          details == other.details &&
          dueDate == other.dueDate &&
          time == other.time &&
          workflowStatus == other.workflowStatus &&
          priority == other.priority &&
          listEquals(tags, other.tags) &&
          listEquals(assignees, other.assignees) &&
          listEquals(reminderOffsetsMinutes, other.reminderOffsetsMinutes) &&
          durationMinutes == other.durationMinutes &&
          updatedAt == other.updatedAt &&
          version == other.version;

  @override
  int get hashCode => Object.hash(
        id,
        ownerKey,
        isFamily,
        title,
        projectId,
        groupId,
        details,
        dueDate,
        time,
        workflowStatus,
        priority,
        Object.hashAll(tags),
        Object.hashAll(assignees),
        Object.hashAll(reminderOffsetsMinutes),
        durationMinutes,
        updatedAt,
        version,
      );
}

List<String> _decodeStringList(Object? raw) {
  if (raw == null) {
    return const [];
  }
  try {
    final parsed = jsonDecode(raw.toString());
    if (parsed is List) {
      return parsed.map((e) => e.toString()).toList();
    }
  } catch (e, st) {
    debugPrint('[task_item] _decodeStringList error: $e\n$st');
  }
  return const [];
}

List<dynamic> _decodeDynamicList(Object? raw) {
  if (raw == null) {
    return const [];
  }
  try {
    final parsed = jsonDecode(raw.toString());
    if (parsed is List) {
      return parsed;
    }
  } catch (e, st) {
    debugPrint('[task_item] _decodeDynamicList error: $e\n$st');
  }
  return const [];
}

List<int> _normalizeReminderOffsets(List<dynamic> raw) {
  const allowed = {1440, 720, 180, 120, 60, 30, 15, 5};
  final out = <int>[];
  for (final item in raw) {
    final value = int.tryParse(item.toString());
    if (value == null || !allowed.contains(value)) {
      continue;
    }
    if (!out.contains(value)) {
      out.add(value);
    }
  }
  out.sort((a, b) => b.compareTo(a));
  return out;
}
