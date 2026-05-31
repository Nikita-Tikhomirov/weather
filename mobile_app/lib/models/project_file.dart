import 'package:flutter/foundation.dart';

/// A node in a project file tree — either a directory or a file.
@immutable
class ProjectFileNode {
  const ProjectFileNode({
    required this.name,
    required this.path,
    required this.isDir,
    this.size = 0,
    this.children = const [],
  });

  final String name;
  final String path;
  final bool isDir;
  final int size;
  final List<ProjectFileNode> children;

  /// Human-readable file size (e.g. "1.2 MB").
  String get sizeLabel {
    if (isDir) return '';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Sort children: directories first, then alphabetically by name.
  static List<ProjectFileNode> sorted(List<ProjectFileNode> nodes) {
    final list = List<ProjectFileNode>.from(nodes);
    list.sort((a, b) {
      if (a.isDir && !b.isDir) return -1;
      if (!a.isDir && b.isDir) return 1;
      return a.name.compareTo(b.name);
    });
    return list;
  }

  factory ProjectFileNode.fromJson(Map<String, dynamic> json) {
    final rawChildren = (json['children'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ProjectFileNode.fromJson)
        .toList();
    return ProjectFileNode(
      name: (json['name'] ?? '').toString(),
      path: (json['path'] ?? '').toString(),
      isDir: json['is_dir'] == true || json['type'] == 'dir',
      size: int.tryParse((json['size'] ?? 0).toString()) ?? 0,
      children: rawChildren,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'is_dir': isDir,
        'size': size,
        if (children.isNotEmpty)
          'children': children.map((c) => c.toJson()).toList(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProjectFileNode &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          path == other.path &&
          isDir == other.isDir &&
          size == other.size &&
          listEquals(children, other.children);

  @override
  int get hashCode => Object.hash(
        name,
        path,
        isDir,
        size,
        Object.hashAll(children),
      );

  ProjectFileNode copyWith({
    String? name,
    String? path,
    bool? isDir,
    int? size,
    List<ProjectFileNode>? children,
  }) =>
      ProjectFileNode(
        name: name ?? this.name,
        path: path ?? this.path,
        isDir: isDir ?? this.isDir,
        size: size ?? this.size,
        children: children ?? this.children,
      );
}
