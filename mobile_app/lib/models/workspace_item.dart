enum WorkspaceStatus {
  available,
  missing,
  error,
  unknown,
}

WorkspaceStatus workspaceStatusFromString(String value) {
  switch (value.trim().toLowerCase()) {
    case 'available':
      return WorkspaceStatus.available;
    case 'missing':
      return WorkspaceStatus.missing;
    case 'error':
      return WorkspaceStatus.error;
    default:
      return WorkspaceStatus.unknown;
  }
}

String workspaceStatusToString(WorkspaceStatus status) {
  switch (status) {
    case WorkspaceStatus.available:
      return 'available';
    case WorkspaceStatus.missing:
      return 'missing';
    case WorkspaceStatus.error:
      return 'error';
    case WorkspaceStatus.unknown:
      return 'unknown';
  }
}

class WorkspaceItem {
  const WorkspaceItem({
    required this.id,
    required this.name,
    required this.path,
    required this.status,
    this.createdAt = 0,
    this.updatedAt = 0,
  });

  final String id;
  final String name;
  final String path;
  final WorkspaceStatus status;
  final int createdAt;
  final int updatedAt;

  factory WorkspaceItem.fromJson(Map<String, dynamic> json) {
    return WorkspaceItem(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      path: (json['path'] ?? '').toString(),
      status: workspaceStatusFromString((json['status'] ?? '').toString()),
      createdAt: int.tryParse((json['created_at'] ?? 0).toString()) ?? 0,
      updatedAt: int.tryParse((json['updated_at'] ?? 0).toString()) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'status': workspaceStatusToString(status),
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  bool get isAvailable => status == WorkspaceStatus.available;
}
