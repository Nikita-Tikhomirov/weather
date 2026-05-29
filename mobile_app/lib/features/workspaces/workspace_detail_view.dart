import 'package:flutter/material.dart';

import '../../models/workspace_item.dart';
import '../../models/workspace_session.dart';

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
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack,
        ),
        title: Text(workspace.name),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh),
            onPressed: onRefresh,
          ),
          IconButton(
            tooltip: 'Создать сессию',
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
            child: sessions.isEmpty
                ? const Center(child: Text('Сессий пока нет'))
                : ListView.separated(
                    itemCount: sessions.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final session = sessions[index];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Icon(_sessionIcon(session.status)),
                        ),
                        title: Text(session.title),
                        subtitle: Text(_sessionStatusText(session)),
                        trailing: IconButton(
                          tooltip: 'Управление сессией',
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

  String _sessionStatusText(WorkspaceSession session) {
    final pid = session.workerPid;
    final port = session.workerPort;
    if (session.isRunning && pid != null && port != null) {
      return 'Работает · PID $pid · порт $port';
    }
    switch (session.status) {
      case WorkspaceSessionStatus.idle:
        return 'Ожидает запуска';
      case WorkspaceSessionStatus.running:
        return 'Работает';
      case WorkspaceSessionStatus.stopped:
        return 'Остановлена';
      case WorkspaceSessionStatus.killed:
        return 'Убита';
      case WorkspaceSessionStatus.error:
        return 'Ошибка';
      case WorkspaceSessionStatus.unknown:
        return 'Неизвестный статус';
    }
  }
}
