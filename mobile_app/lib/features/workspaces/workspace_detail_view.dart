import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/workspace_item.dart';
import '../../models/workspace_session.dart';

class _WorkspaceDetailText {
  const _WorkspaceDetailText(this.l10n);

  final AppLocalizations? l10n;

  String get back => l10n?.back ?? 'Back';
  String get refresh => l10n?.refresh ?? 'Refresh';
  String get createSession => l10n?.createSession ?? 'Create session';
  String get manageSession => l10n?.manageSession ?? 'Manage session';
  String get noSessionsYet => l10n?.noSessionsYet ?? 'No sessions yet';
  String get running => l10n?.running ?? 'Running';
  String get port => l10n?.port ?? 'port';
  String get waitingToStart => l10n?.waitingToStart ?? 'Waiting to start';
  String get stopped => l10n?.stopped ?? 'Stopped';
  String get killed => l10n?.killed ?? 'Killed';
  String get error => l10n?.error ?? 'Error';
  String get unknownStatus => l10n?.unknownStatus ?? 'Unknown status';
}

class WorkspaceDetailView extends StatelessWidget {
  const WorkspaceDetailView({
    super.key,
    required this.workspace,
    required this.sessions,
    required this.onBack,
    required this.onRefresh,
    required this.onCreateSession,
    required this.onOpenSession,
    required this.onManageSession,
  });

  final WorkspaceItem workspace;
  final List<WorkspaceSession> sessions;
  final VoidCallback onBack;
  final VoidCallback onRefresh;
  final VoidCallback onCreateSession;
  final void Function(WorkspaceSession session) onOpenSession;
  final void Function(WorkspaceSession session) onManageSession;

  @override
  Widget build(BuildContext context) {
    final text = _WorkspaceDetailText(AppLocalizations.of(context));
    final visibleSessions = _visibleSessions(sessions);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: text.back,
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack,
        ),
        title: Text(workspace.name),
        actions: [
          IconButton(
            tooltip: text.refresh,
            icon: const Icon(Icons.refresh),
            onPressed: onRefresh,
          ),
          IconButton(
            tooltip: text.createSession,
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: onCreateSession,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              workspace.path,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: visibleSessions.isEmpty
                ? Center(child: Text(text.noSessionsYet))
                : ListView.separated(
                    itemCount: visibleSessions.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final session = visibleSessions[index];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Icon(_sessionIcon(session.status)),
                        ),
                        title: Text(session.title),
                        subtitle: Text(_sessionStatusText(session, text)),
                        trailing: IconButton(
                          tooltip: text.manageSession,
                          icon: const Icon(Icons.tune),
                          onPressed: () => onManageSession(session),
                        ),
                        onTap: () => onOpenSession(session),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  List<WorkspaceSession> _visibleSessions(List<WorkspaceSession> sessions) {
    final result = <WorkspaceSession>[];
    final projectChatByKey = <String, WorkspaceSession>{};
    for (final session in sessions) {
      if (!session.isProjectChatSession) {
        result.add(session);
        continue;
      }
      final key = session.projectChatKey.isEmpty
          ? 'title:${session.title}'
          : session.projectChatKey;
      final existing = projectChatByKey[key];
      if (existing == null || _sessionRank(session) > _sessionRank(existing)) {
        projectChatByKey[key] = session;
      }
    }
    result.addAll(projectChatByKey.values);
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  int _sessionRank(WorkspaceSession session) {
    final statusRank = switch (session.status) {
      WorkspaceSessionStatus.running => 5000000000000,
      WorkspaceSessionStatus.idle => 4000000000000,
      WorkspaceSessionStatus.unknown => 3000000000000,
      WorkspaceSessionStatus.error => 2000000000000,
      WorkspaceSessionStatus.stopped => 1000000000000,
      WorkspaceSessionStatus.killed => 0,
    };
    return statusRank + session.updatedAt;
  }

  IconData _sessionIcon(WorkspaceSessionStatus status) {
    switch (status) {
      case WorkspaceSessionStatus.running:
        return Icons.play_arrow;
      case WorkspaceSessionStatus.stopped:
        return Icons.stop;
      case WorkspaceSessionStatus.killed:
        return Icons.close;
      case WorkspaceSessionStatus.error:
        return Icons.error_outline;
      case WorkspaceSessionStatus.idle:
      case WorkspaceSessionStatus.unknown:
        return Icons.chat_bubble_outline;
    }
  }

  String _sessionStatusText(
    WorkspaceSession session,
    _WorkspaceDetailText text,
  ) {
    final pid = session.workerPid;
    final port = session.workerPort;
    if (session.isRunning && pid != null && port != null) {
      return '${text.running} · PID $pid · ${text.port} $port';
    }
    switch (session.status) {
      case WorkspaceSessionStatus.idle:
        return text.waitingToStart;
      case WorkspaceSessionStatus.running:
        return text.running;
      case WorkspaceSessionStatus.stopped:
        return text.stopped;
      case WorkspaceSessionStatus.killed:
        return text.killed;
      case WorkspaceSessionStatus.error:
        return text.error;
      case WorkspaceSessionStatus.unknown:
        return text.unknownStatus;
    }
  }
}
