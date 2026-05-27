import 'dart:convert';

import 'package:flutter/foundation.dart';

class FamilyGroup {
  const FamilyGroup({
    required this.id,
    required this.name,
    required this.members,
    this.ownerKey = '',
    this.createdAt = '',
    this.updatedAt = '',
  });

  final String id;
  final String name;
  final List<String> members;
  final String ownerKey;
  final String createdAt;
  final String updatedAt;

  factory FamilyGroup.fromJson(Map<String, dynamic> json) {
    final members = (json['members'] is List)
        ? (json['members'] as List).map((v) => v.toString()).toList()
        : <String>[];
    return FamilyGroup(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      members: members,
      ownerKey: (json['owner_key'] ?? '').toString(),
      createdAt: (json['created_at'] ?? '').toString(),
      updatedAt: (json['updated_at'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'members': members,
        'owner_key': ownerKey,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  Map<String, Object?> toDbRow() => {
        'id': id,
        'name': name,
        'members_json': jsonEncode(members),
        'owner_key': ownerKey,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory FamilyGroup.fromDbRow(Map<String, Object?> row) {
    List<String> members;
    try {
      final raw = (row['members_json'] ?? '').toString();
      members = (jsonDecode(raw) as List).map((e) => e.toString()).toList();
    } catch (e, st) {
      debugPrint('[family_group] JSON decode members error: $e\n$st');
      members = [];
    }
    return FamilyGroup(
      id: (row['id'] ?? '').toString(),
      name: (row['name'] ?? '').toString(),
      members: members,
      ownerKey: (row['owner_key'] ?? '').toString(),
      createdAt: (row['created_at'] ?? '').toString(),
      updatedAt: (row['updated_at'] ?? '').toString(),
    );
  }

  FamilyGroup copyWith({
    String? name,
    List<String>? members,
    String? ownerKey,
    String? updatedAt,
  }) =>
      FamilyGroup(
        id: id,
        name: name ?? this.name,
        members: members ?? List.from(this.members),
        ownerKey: ownerKey ?? this.ownerKey,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
