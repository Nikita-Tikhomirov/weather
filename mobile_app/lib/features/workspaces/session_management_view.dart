import 'package:flutter/material.dart';

import '../../models/workspace_item.dart';
import '../../models/workspace_session.dart';

class SessionManagementView extends StatelessWidget {
  const SessionManagementView({
    super.key,
    required this.workspace,
    required this.session,
    required this.onBack,
    required this.onStop,
    required this.onKill,
    required this.onRestart,
  });

  final WorkspaceItem workspace;
  final WorkspaceSession session;
  final VoidCallback onBack;
  final VoidCallback onStop;
  final VoidCallback onKill;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack,
        ),
        title: const Text('Управление сессией'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(session.title, style: textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(workspace.name, style: textTheme.bodyMedium),
          const SizedBox(height: 16),
          _InfoRow(label: 'Статус', value: _statusText(session.status)),
          _InfoRow(label: 'PID', value: session.workerPid?.toString() ?? 'нет'),
          _InfoRow(
            label: 'Порт',
            value: session.workerPort?.toString() ?? 'нет',
          ),
          _InfoRow(label: 'Событий', value: session.lastEventSeq.toString()),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Tooltip(
                message: 'Перезапустить worker',
                child: FilledButton.icon(
                  onPressed: onRestart,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Перезапустить'),
                ),
              ),
              Tooltip(
                message: 'Остановить сессию',
                child: OutlinedButton.icon(
                  onPressed: onStop,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Остановить'),
                ),
              ),
              Tooltip(
                message: 'Убить зависшую сессию',
                child: FilledButton.tonalIcon(
                  onPressed: onKill,
                  icon: const Icon(Icons.power_settings_new),
                  label: const Text('Убить'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _statusText(WorkspaceSessionStatus status) {
    switch (status) {
      case WorkspaceSessionStatus.idle:
        return 'Ожидает';
      case WorkspaceSessionStatus.running:
        return 'Работает';
      case WorkspaceSessionStatus.stopped:
        return 'Остановлена';
      case WorkspaceSessionStatus.killed:
        return 'Убита';
      case WorkspaceSessionStatus.error:
        return 'Ошибка';
      case WorkspaceSessionStatus.unknown:
        return 'Неизвестно';
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
