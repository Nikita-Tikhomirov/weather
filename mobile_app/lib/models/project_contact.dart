import 'package:flutter/foundation.dart';

@immutable
class ProjectContact {
  const ProjectContact({
    required this.id,
    required this.name,
    required this.path,
    this.icon = 'terminal',
  });

  final String id;
  final String name;
  final String path;
  final String icon;

  factory ProjectContact.fromJson(Map<String, dynamic> json) {
    return ProjectContact(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? json['path'] ?? '').toString(),
      path: (json['path'] ?? '').toString(),
      icon: (json['icon'] ?? 'terminal').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'icon': icon,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProjectContact &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          path == other.path &&
          icon == other.icon;

  @override
  int get hashCode => id.hashCode ^ name.hashCode ^ path.hashCode ^ icon.hashCode;

  ProjectContact copyWith({
    String? id,
    String? name,
    String? path,
    String? icon,
  }) =>
      ProjectContact(
        id: id ?? this.id,
        name: name ?? this.name,
        path: path ?? this.path,
        icon: icon ?? this.icon,
      );
}
