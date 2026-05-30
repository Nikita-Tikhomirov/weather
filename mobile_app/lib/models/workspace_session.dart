import 'package:flutter/foundation.dart';

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

int? _nullableInt(Object? value) {
  if (value == null) {
    return null;
  }
  final text = value.toString();
  if (text.isEmpty || text == 'null') {
    return null;
  }
  return int.tryParse(text);
}

@immutable
class WorkspaceSession {
  const WorkspaceSession({
    required this.id,
    required this.workspaceId,
    required this.title,
    required this.status,
    this.workerPid,
    this.workerPort,
    this.provider = '',
    this.model = '',
    this.approvalPolicy = '',
    this.sandboxMode = '',
    this.autoMode = false,
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
  final String provider;
  final String model;
  final String approvalPolicy;
  final String sandboxMode;
  final bool autoMode;
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
      provider: (json['provider'] ?? '').toString(),
      model: (json['model'] ?? '').toString(),
      approvalPolicy: (json['approval_policy'] ?? '').toString(),
      sandboxMode: (json['sandbox_mode'] ?? '').toString(),
      autoMode: json['auto_mode'] == true,
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
      'provider': provider,
      'model': model,
      'approval_policy': approvalPolicy,
      'sandbox_mode': sandboxMode,
      'auto_mode': autoMode,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'last_event_seq': lastEventSeq,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkspaceSession &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          workspaceId == other.workspaceId &&
          title == other.title &&
          status == other.status &&
          workerPid == other.workerPid &&
          workerPort == other.workerPort &&
          provider == other.provider &&
          model == other.model &&
          approvalPolicy == other.approvalPolicy &&
          sandboxMode == other.sandboxMode &&
          autoMode == other.autoMode &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt &&
          lastEventSeq == other.lastEventSeq;

  @override
  int get hashCode =>
      id.hashCode ^
      workspaceId.hashCode ^
      title.hashCode ^
      status.hashCode ^
      workerPid.hashCode ^
      workerPort.hashCode ^
      provider.hashCode ^
      model.hashCode ^
      approvalPolicy.hashCode ^
      sandboxMode.hashCode ^
      autoMode.hashCode ^
      createdAt.hashCode ^
      updatedAt.hashCode ^
      lastEventSeq.hashCode;

  WorkspaceSession copyWith({
    String? id,
    String? workspaceId,
    String? title,
    WorkspaceSessionStatus? status,
    int? workerPid,
    int? workerPort,
    String? provider,
    String? model,
    String? approvalPolicy,
    String? sandboxMode,
    bool? autoMode,
    int? createdAt,
    int? updatedAt,
    int? lastEventSeq,
  }) {
    return WorkspaceSession(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      title: title ?? this.title,
      status: status ?? this.status,
      workerPid: workerPid ?? this.workerPid,
      workerPort: workerPort ?? this.workerPort,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      approvalPolicy: approvalPolicy ?? this.approvalPolicy,
      sandboxMode: sandboxMode ?? this.sandboxMode,
      autoMode: autoMode ?? this.autoMode,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastEventSeq: lastEventSeq ?? this.lastEventSeq,
    );
  }
}
