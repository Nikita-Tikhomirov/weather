import 'package:flutter/foundation.dart';

@immutable
class TaskProject {
  const TaskProject({
    required this.id,
    required this.name,
    this.description = '',
    this.ownerKey = '',
    this.createdAt = '',
    this.updatedAt = '',
  });

  final String id;
  final String name;
  final String description;
  final String ownerKey;
  final String createdAt;
  final String updatedAt;

  factory TaskProject.fromJson(Map<String, dynamic> json) {
    return TaskProject(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      ownerKey: (json['owner_key'] ?? '').toString(),
      createdAt: (json['created_at'] ?? '').toString(),
      updatedAt: (json['updated_at'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'owner_key': ownerKey,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  Map<String, Object?> toDbRow() => {
        'id': id,
        'name': name,
        'description': description,
        'owner_key': ownerKey,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory TaskProject.fromDbRow(Map<String, Object?> row) => TaskProject(
        id: (row['id'] ?? '').toString(),
        name: (row['name'] ?? '').toString(),
        description: (row['description'] ?? '').toString(),
        ownerKey: (row['owner_key'] ?? '').toString(),
        createdAt: (row['created_at'] ?? '').toString(),
        updatedAt: (row['updated_at'] ?? '').toString(),
      );

  TaskProject copyWith({
    String? name,
    String? description,
    String? ownerKey,
    String? updatedAt,
  }) =>
      TaskProject(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        ownerKey: ownerKey ?? this.ownerKey,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskProject &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          description == other.description &&
          ownerKey == other.ownerKey &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode =>
      id.hashCode ^
      name.hashCode ^
      description.hashCode ^
      ownerKey.hashCode ^
      createdAt.hashCode ^
      updatedAt.hashCode;
}
