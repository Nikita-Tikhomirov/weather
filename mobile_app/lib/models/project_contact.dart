class ProjectContact {
  ProjectContact({
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

  /// Chat conversation key for this project (used in messenger).
  String get conversationKey => 'project:$id';
}
