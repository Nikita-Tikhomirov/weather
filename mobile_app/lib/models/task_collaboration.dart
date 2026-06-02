import 'dart:convert';

import 'package:flutter/foundation.dart';

@immutable
class TaskAttachment {
  const TaskAttachment({
    required this.id,
    required this.kind,
    required this.filename,
    required this.createdAt,
    this.mimeType = '',
    this.dataBase64 = '',
    this.assetUrl = '',
    this.imageMeta = const {},
    this.caption = '',
    this.authorProfile = '',
    this.sizeBytes = 0,
  });

  final String id;
  final String kind;
  final String filename;
  final String mimeType;
  final String dataBase64;
  final String assetUrl;
  final Map<String, dynamic> imageMeta;
  final String caption;
  final String authorProfile;
  final String createdAt;
  final int sizeBytes;

  bool get isPhoto => kind == 'photo' || kind == 'image';
  bool get isFile => kind == 'file';

  factory TaskAttachment.fromJson(Map<String, dynamic> json) {
    final rawImageMeta = json['image_meta'];
    return TaskAttachment(
      id: (json['id'] ?? '').toString(),
      kind: (json['kind'] ?? 'file').toString(),
      filename: (json['filename'] ?? '').toString(),
      mimeType: (json['mime_type'] ?? '').toString(),
      dataBase64: (json['data_base64'] ?? json['dataBase64'] ?? '').toString(),
      assetUrl: (json['asset_url'] ?? json['image_url'] ?? '').toString(),
      imageMeta: rawImageMeta is Map
          ? Map<String, dynamic>.from(rawImageMeta)
          : const <String, dynamic>{},
      caption: (json['caption'] ?? '').toString(),
      authorProfile: (json['author_profile'] ?? '').toString(),
      createdAt: (json['created_at'] ?? '').toString(),
      sizeBytes: int.tryParse((json['size_bytes'] ?? 0).toString()) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'kind': kind,
      'filename': filename,
      'mime_type': mimeType,
      'data_base64': dataBase64,
      'asset_url': assetUrl,
      'image_meta': imageMeta,
      'caption': caption,
      'author_profile': authorProfile,
      'created_at': createdAt,
      'size_bytes': sizeBytes,
    };
  }

  TaskAttachment copyWith({
    String? id,
    String? kind,
    String? filename,
    String? mimeType,
    String? dataBase64,
    String? assetUrl,
    Map<String, dynamic>? imageMeta,
    String? caption,
    String? authorProfile,
    String? createdAt,
    int? sizeBytes,
  }) {
    return TaskAttachment(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      filename: filename ?? this.filename,
      mimeType: mimeType ?? this.mimeType,
      dataBase64: dataBase64 ?? this.dataBase64,
      assetUrl: assetUrl ?? this.assetUrl,
      imageMeta: imageMeta ?? this.imageMeta,
      caption: caption ?? this.caption,
      authorProfile: authorProfile ?? this.authorProfile,
      createdAt: createdAt ?? this.createdAt,
      sizeBytes: sizeBytes ?? this.sizeBytes,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskAttachment &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          kind == other.kind &&
          filename == other.filename &&
          mimeType == other.mimeType &&
          dataBase64 == other.dataBase64 &&
          assetUrl == other.assetUrl &&
          mapEquals(imageMeta, other.imageMeta) &&
          caption == other.caption &&
          authorProfile == other.authorProfile &&
          createdAt == other.createdAt &&
          sizeBytes == other.sizeBytes;

  @override
  int get hashCode => Object.hash(
        id,
        kind,
        filename,
        mimeType,
        dataBase64,
        assetUrl,
        Object.hashAll(
          imageMeta.entries.map((entry) => Object.hash(entry.key, entry.value)),
        ),
        caption,
        authorProfile,
        createdAt,
        sizeBytes,
      );
}

@immutable
class TaskComment {
  const TaskComment({
    required this.id,
    required this.authorProfile,
    required this.text,
    required this.createdAt,
    this.attachmentIds = const [],
  });

  final String id;
  final String authorProfile;
  final String text;
  final String createdAt;
  final List<String> attachmentIds;

  factory TaskComment.fromJson(Map<String, dynamic> json) {
    return TaskComment(
      id: (json['id'] ?? '').toString(),
      authorProfile: (json['author_profile'] ?? '').toString(),
      text: (json['text'] ?? '').toString(),
      createdAt: (json['created_at'] ?? '').toString(),
      attachmentIds: _decodeStringList(json['attachment_ids']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'author_profile': authorProfile,
      'text': text,
      'created_at': createdAt,
      'attachment_ids': attachmentIds,
    };
  }

  TaskComment copyWith({
    String? id,
    String? authorProfile,
    String? text,
    String? createdAt,
    List<String>? attachmentIds,
  }) {
    return TaskComment(
      id: id ?? this.id,
      authorProfile: authorProfile ?? this.authorProfile,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      attachmentIds: attachmentIds ?? this.attachmentIds,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskComment &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          authorProfile == other.authorProfile &&
          text == other.text &&
          createdAt == other.createdAt &&
          listEquals(attachmentIds, other.attachmentIds);

  @override
  int get hashCode => Object.hash(
        id,
        authorProfile,
        text,
        createdAt,
        Object.hashAll(attachmentIds),
      );
}

@immutable
class TaskChecklistItem {
  const TaskChecklistItem({
    required this.id,
    required this.text,
    required this.createdAt,
    this.done = false,
    this.createdBy = '',
    this.completedBy = '',
    this.completedAt = '',
  });

  final String id;
  final String text;
  final bool done;
  final String createdBy;
  final String createdAt;
  final String completedBy;
  final String completedAt;

  factory TaskChecklistItem.fromJson(Map<String, dynamic> json) {
    return TaskChecklistItem(
      id: (json['id'] ?? '').toString(),
      text: (json['text'] ?? '').toString(),
      done: json['done'] == true || json['done'] == 1,
      createdBy: (json['created_by'] ?? '').toString(),
      createdAt: (json['created_at'] ?? '').toString(),
      completedBy: (json['completed_by'] ?? '').toString(),
      completedAt: (json['completed_at'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'done': done,
      'created_by': createdBy,
      'created_at': createdAt,
      'completed_by': completedBy,
      'completed_at': completedAt,
    };
  }

  TaskChecklistItem copyWith({
    String? id,
    String? text,
    bool? done,
    String? createdBy,
    String? createdAt,
    String? completedBy,
    String? completedAt,
  }) {
    return TaskChecklistItem(
      id: id ?? this.id,
      text: text ?? this.text,
      done: done ?? this.done,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      completedBy: completedBy ?? this.completedBy,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskChecklistItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          text == other.text &&
          done == other.done &&
          createdBy == other.createdBy &&
          createdAt == other.createdAt &&
          completedBy == other.completedBy &&
          completedAt == other.completedAt;

  @override
  int get hashCode => Object.hash(
        id,
        text,
        done,
        createdBy,
        createdAt,
        completedBy,
        completedAt,
      );
}

@immutable
class TaskChecklist {
  const TaskChecklist({
    required this.id,
    required this.title,
    required this.createdAt,
    this.createdBy = '',
    this.items = const [],
  });

  final String id;
  final String title;
  final String createdBy;
  final String createdAt;
  final List<TaskChecklistItem> items;

  int get doneCount => items.where((item) => item.done).length;
  int get totalCount => items.length;
  double get progress => totalCount == 0 ? 0 : doneCount / totalCount;

  factory TaskChecklist.fromJson(Map<String, dynamic> json) {
    return TaskChecklist(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      createdBy: (json['created_by'] ?? '').toString(),
      createdAt: (json['created_at'] ?? '').toString(),
      items: _decodeMapList(json['items'])
          .map(TaskChecklistItem.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'created_by': createdBy,
      'created_at': createdAt,
      'items': items.map((item) => item.toJson()).toList(),
    };
  }

  TaskChecklist copyWith({
    String? id,
    String? title,
    String? createdBy,
    String? createdAt,
    List<TaskChecklistItem>? items,
  }) {
    return TaskChecklist(
      id: id ?? this.id,
      title: title ?? this.title,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      items: items ?? this.items,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskChecklist &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          createdBy == other.createdBy &&
          createdAt == other.createdAt &&
          listEquals(items, other.items);

  @override
  int get hashCode => Object.hash(
        id,
        title,
        createdBy,
        createdAt,
        Object.hashAll(items),
      );
}

@immutable
class TaskActivityEntry {
  const TaskActivityEntry({
    required this.id,
    required this.type,
    required this.actorProfile,
    required this.text,
    required this.createdAt,
    this.targetId = '',
  });

  final String id;
  final String type;
  final String actorProfile;
  final String text;
  final String createdAt;
  final String targetId;

  factory TaskActivityEntry.fromJson(Map<String, dynamic> json) {
    return TaskActivityEntry(
      id: (json['id'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      actorProfile: (json['actor_profile'] ?? '').toString(),
      text: (json['text'] ?? '').toString(),
      createdAt: (json['created_at'] ?? '').toString(),
      targetId: (json['target_id'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'actor_profile': actorProfile,
      'text': text,
      'created_at': createdAt,
      'target_id': targetId,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskActivityEntry &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          type == other.type &&
          actorProfile == other.actorProfile &&
          text == other.text &&
          createdAt == other.createdAt &&
          targetId == other.targetId;

  @override
  int get hashCode => Object.hash(
        id,
        type,
        actorProfile,
        text,
        createdAt,
        targetId,
      );
}

@immutable
class TaskCollaboration {
  const TaskCollaboration({
    this.comments = const [],
    this.attachments = const [],
    this.checklists = const [],
    this.activity = const [],
  });

  final List<TaskComment> comments;
  final List<TaskAttachment> attachments;
  final List<TaskChecklist> checklists;
  final List<TaskActivityEntry> activity;

  bool get isEmpty =>
      comments.isEmpty &&
      attachments.isEmpty &&
      checklists.isEmpty &&
      activity.isEmpty;

  int get commentCount => comments.length;
  int get attachmentCount => attachments.length;
  int get checklistTotalCount =>
      checklists.fold(0, (sum, checklist) => sum + checklist.totalCount);
  int get checklistDoneCount =>
      checklists.fold(0, (sum, checklist) => sum + checklist.doneCount);

  factory TaskCollaboration.fromJson(Object? raw) {
    final map = _decodeMap(raw);
    if (map.isEmpty) {
      return const TaskCollaboration();
    }
    return TaskCollaboration(
      comments:
          _decodeMapList(map['comments']).map(TaskComment.fromJson).toList(),
      attachments: _decodeMapList(map['attachments'])
          .map(TaskAttachment.fromJson)
          .toList(),
      checklists: _decodeMapList(map['checklists'])
          .map(TaskChecklist.fromJson)
          .toList(),
      activity: _decodeMapList(map['activity'])
          .map(TaskActivityEntry.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'comments': comments.map((item) => item.toJson()).toList(),
      'attachments': attachments.map((item) => item.toJson()).toList(),
      'checklists': checklists.map((item) => item.toJson()).toList(),
      'activity': activity.map((item) => item.toJson()).toList(),
    };
  }

  String toJsonString() => jsonEncode(toJson());

  TaskCollaboration copyWith({
    List<TaskComment>? comments,
    List<TaskAttachment>? attachments,
    List<TaskChecklist>? checklists,
    List<TaskActivityEntry>? activity,
  }) {
    return TaskCollaboration(
      comments: comments ?? this.comments,
      attachments: attachments ?? this.attachments,
      checklists: checklists ?? this.checklists,
      activity: activity ?? this.activity,
    );
  }

  List<TaskAttachment> attachmentsFor(TaskComment comment) {
    final ids = comment.attachmentIds.toSet();
    return attachments.where((item) => ids.contains(item.id)).toList();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskCollaboration &&
          runtimeType == other.runtimeType &&
          listEquals(comments, other.comments) &&
          listEquals(attachments, other.attachments) &&
          listEquals(checklists, other.checklists) &&
          listEquals(activity, other.activity);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(comments),
        Object.hashAll(attachments),
        Object.hashAll(checklists),
        Object.hashAll(activity),
      );
}

Map<String, dynamic> _decodeMap(Object? raw) {
  if (raw is Map) {
    return Map<String, dynamic>.from(raw);
  }
  if (raw is String && raw.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return const {};
    }
  }
  return const {};
}

List<Map<String, dynamic>> _decodeMapList(Object? raw) {
  if (raw is! List) {
    return const [];
  }
  return raw.whereType<Map>().map(Map<String, dynamic>.from).toList();
}

List<String> _decodeStringList(Object? raw) {
  if (raw is! List) {
    return const [];
  }
  return raw
      .map((item) => item.toString())
      .where((item) => item.isNotEmpty)
      .toList();
}
