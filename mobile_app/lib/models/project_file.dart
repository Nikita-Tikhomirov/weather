/// A node in a project file tree — either a directory or a file.
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

  /// Human-readable size string.
  String get sizeLabel {
    if (isDir) return '';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Stable sort: directories first, then alphabetical.
  static List<ProjectFileNode> sorted(List<ProjectFileNode> nodes) {
    final copy = List<ProjectFileNode>.from(nodes);
    copy.sort((a, b) {
      if (a.isDir && !b.isDir) return -1;
      if (!a.isDir && b.isDir) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return copy;
  }
}
