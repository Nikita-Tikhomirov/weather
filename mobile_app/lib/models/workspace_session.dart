enum WorkspaceSessionStatus {
  idle,
  running,
  stopped,
  killed,
  error,
  unknown,
}

WorkspaceSessionStatus workspaceSessionStatusFromString(String value) {
  switch (value.trim().toLowerCase()) {
    case 'idle':
      return WorkspaceSessionStatus.idle;
    case 'running':
      return WorkspaceSessionStatus.running;
    case 'stopped':
      return WorkspaceSessionStatus.stopped;
    case 'killed':
      return WorkspaceSessionStatus.killed;
    case 'error':
      return WorkspaceSessionStatus.error;
    default:
      return WorkspaceSessionStatus.unknown;
  }
}

String workspaceSessionStatusToString(WorkspaceSessionStatus status) {
  switch (status) {
    case WorkspaceSessionStatus.idle:
      return 'idle';
    case WorkspaceSessionStatus.running:
      return 'running';
    case WorkspaceSessionStatus.stopped:
      return 'stopped';
    case WorkspaceSessionStatus.killed:
      return 'killed';
    case WorkspaceSessionStatus.error:
      return 'error';
    case WorkspaceSessionStatus.unknown:
      return 'unknown';
  }
}

class WorkspaceSession {
  const WorkspaceSession({
    required this.id,
    required this.workspaceId,
    required this.title,
    required this.status,
    this.workerPid,
    this.workerPort,
    this.createdAt = 0,
    this.updatedAt = 0,
    this.lastEventSeq = 0,
  });

  final String id;
  final String workspaceId;
  final String title;
  final WorkspaceSessionStatus status;
  final int? workerPid;
  final int? workerPort;
  final int createdAt;
  final int updatedAt;
  final int lastEventSeq;

  factory WorkspaceSession.fromJson(Map<String, dynamic> json) {
    return WorkspaceSession(
      id: (json['id'] ?? '').toString(),
      workspaceId: (json['workspace_id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      status: workspaceSessionStatusFromString(
        (json['status'] ?? '').toString(),
      ),
      workerPid: _nullableInt(json['worker_pid']),
      workerPort: _nullableInt(json['worker_port']),
      createdAt: int.tryParse((json['created_at'] ?? 0).toString()) ?? 0,
      updatedAt: int.tryParse((json['updated_at'] ?? 0).toString()) ?? 0,
      lastEventSeq: int.tryParse((json['last_event_seq'] ?? 0).toString()) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'workspace_id': workspaceId,
      'title': title,
      'status': workspaceSessionStatusToString(status),
      'worker_pid': workerPid,
      'worker_port': workerPort,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'last_event_seq': lastEventSeq,
    };
  }

  bool get isRunning => status == WorkspaceSessionStatus.running;

  static int? _nullableInt(Object? value) {
    if (value == null) {
      return null;
    }
    final text = value.toString();
    if (text.isEmpty || text == 'null') {
      return null;
    }
    return int.tryParse(text);
  }
}
