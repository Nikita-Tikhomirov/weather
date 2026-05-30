import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/project_file.dart';
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
    required this.files,
    required this.currentFilePath,
    required this.isFilesLoading,
    required this.filePreviewPath,
    required this.filePreviewText,
    required this.commands,
    required this.onRefreshFiles,
    required this.onOpenFilePath,
    required this.onReadFile,
    required this.onInsertFilePath,
    required this.onSendPhoto,
    required this.onSendDocument,
    required this.onRunCommand,
    required this.onUpdateSettings,
  });

  final WorkspaceItem workspace;
  final WorkspaceSession session;
  final VoidCallback onBack;
  final VoidCallback onStop;
  final VoidCallback onKill;
  final VoidCallback onRestart;
  final List<ProjectFileNode> files;
  final String currentFilePath;
  final bool isFilesLoading;
  final String filePreviewPath;
  final String filePreviewText;
  final List<Map<String, dynamic>> commands;
  final VoidCallback onRefreshFiles;
  final void Function(String path) onOpenFilePath;
  final void Function(String path) onReadFile;
  final void Function(String path) onInsertFilePath;
  final VoidCallback onSendPhoto;
  final VoidCallback onSendDocument;
  final void Function(String command) onRunCommand;
  final void Function({
    String? provider,
    String? model,
    String? approvalPolicy,
    String? sandboxMode,
    bool? autoMode,
  }) onUpdateSettings;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Назад',
            icon: const Icon(Icons.arrow_back),
            onPressed: onBack,
          ),
          title: const Text('Управление сессией'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.tune), text: 'Сессия'),
              Tab(icon: Icon(Icons.folder_open), text: 'Файлы'),
              Tab(icon: Icon(Icons.terminal), text: 'Команды'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text(session.title, style: textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(workspace.name, style: textTheme.bodyMedium),
                const SizedBox(height: 16),
                _InfoRow(label: 'Статус', value: _statusText(session.status)),
                _InfoRow(
                  label: 'PID',
                  value: session.workerPid?.toString() ?? 'нет',
                ),
                _InfoRow(
                  label: 'Порт',
                  value: session.workerPort?.toString() ?? 'нет',
                ),
                _InfoRow(
                  label: 'Событий',
                  value: session.lastEventSeq.toString(),
                ),
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
                const SizedBox(height: 20),
                _SessionModeControls(
                  session: session,
                  onUpdateSettings: onUpdateSettings,
                ),
              ],
            ),
            _SessionFilesTab(
              files: files,
              currentPath: currentFilePath,
              isLoading: isFilesLoading,
              previewPath: filePreviewPath,
              previewText: filePreviewText,
              onRefresh: onRefreshFiles,
              onOpenPath: onOpenFilePath,
              onReadFile: onReadFile,
              onInsertPath: onInsertFilePath,
            ),
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: onSendPhoto,
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('Фото'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: onSendDocument,
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('Документ'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _CodeWhaleCommandsList(
                  commands: commands,
                  onRunCommand: onRunCommand,
                ),
              ],
            ),
          ],
        ),
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

class _SessionFilesTab extends StatelessWidget {
  const _SessionFilesTab({
    required this.files,
    required this.currentPath,
    required this.isLoading,
    required this.previewPath,
    required this.previewText,
    required this.onRefresh,
    required this.onOpenPath,
    required this.onReadFile,
    required this.onInsertPath,
  });

  final List<ProjectFileNode> files;
  final String currentPath;
  final bool isLoading;
  final String previewPath;
  final String previewText;
  final VoidCallback onRefresh;
  final void Function(String path) onOpenPath;
  final void Function(String path) onReadFile;
  final void Function(String path) onInsertPath;

  @override
  Widget build(BuildContext context) {
    final parent = _parentPath(currentPath);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Наверх',
                onPressed:
                    currentPath.isEmpty ? null : () => onOpenPath(parent),
                icon: const Icon(Icons.arrow_upward),
              ),
              Expanded(
                child: SelectableText(
                  currentPath.isEmpty ? 'Корень проекта' : currentPath,
                  maxLines: 1,
                ),
              ),
              IconButton(
                tooltip: 'Обновить файлы',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (previewText.isNotEmpty)
          ExpansionTile(
            initiallyExpanded: true,
            leading: const Icon(Icons.visibility),
            title: Text(previewPath),
            trailing: IconButton(
              tooltip: 'Копировать текст файла',
              icon: const Icon(Icons.copy),
              onPressed: () => Clipboard.setData(
                ClipboardData(text: previewText),
              ),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SelectableText(previewText),
              ),
            ],
          ),
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : files.isEmpty
                  ? const Center(child: Text('Файлов нет'))
                  : ListView.builder(
                      itemCount: files.length,
                      itemBuilder: (context, index) {
                        final node = files[index];
                        return ListTile(
                          leading: Icon(
                            node.isDir
                                ? Icons.folder
                                : Icons.insert_drive_file_outlined,
                          ),
                          title: Text(
                            node.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: node.isDir ? null : Text(node.sizeLabel),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                tooltip: 'Путь в чат',
                                onPressed: () => onInsertPath(node.path),
                                icon: const Icon(Icons.link),
                              ),
                              if (!node.isDir)
                                IconButton(
                                  tooltip: 'Просмотр файла',
                                  onPressed: () => onReadFile(node.path),
                                  icon: const Icon(Icons.visibility),
                                ),
                            ],
                          ),
                          onTap: () {
                            if (node.isDir) {
                              onOpenPath(node.path);
                            } else {
                              onReadFile(node.path);
                            }
                          },
                        );
                      },
                    ),
        ),
      ],
    );
  }

  static String _parentPath(String path) {
    final trimmed = path.endsWith('/') || path.endsWith('\\')
        ? path.substring(0, path.length - 1)
        : path;
    final slash = trimmed.lastIndexOf('/');
    final backslash = trimmed.lastIndexOf('\\');
    final index = slash > backslash ? slash : backslash;
    if (index < 0) {
      return '';
    }
    return trimmed.substring(0, index);
  }
}

class _SessionModeControls extends StatelessWidget {
  const _SessionModeControls({
    required this.session,
    required this.onUpdateSettings,
  });

  static const _providers = [
    '',
    'deepseek',
    'openrouter',
    'openai',
    'nvidia-nim',
    'ollama',
    'moonshot',
    'xiaomi',
  ];
  static const _models = [
    '',
    'deepseek-v4-pro',
    'deepseek-v4-flash',
    'deepseek-coder:1.3b',
    'kimi-k2.6',
  ];
  static const _approvalPolicies = [
    '',
    'on-request',
    'on-failure',
    'never',
    'untrusted',
  ];
  static const _sandboxModes = [
    '',
    'read-only',
    'workspace-write',
    'danger-full-access',
  ];

  final WorkspaceSession session;
  final void Function({
    String? provider,
    String? model,
    String? approvalPolicy,
    String? sandboxMode,
    bool? autoMode,
  }) onUpdateSettings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Режимы CodeWhale',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        _ModeDropdown(
          label: 'Провайдер',
          value: _valueOrDefault(session.provider, _providers),
          values: _providers,
          onChanged: (value) => onUpdateSettings(provider: value),
        ),
        const SizedBox(height: 10),
        _ModeDropdown(
          label: 'Модель',
          value: _valueOrDefault(session.model, _models),
          values: _models,
          onChanged: (value) => onUpdateSettings(model: value),
        ),
        const SizedBox(height: 10),
        _ModeDropdown(
          label: 'Подтверждения',
          value: _valueOrDefault(session.approvalPolicy, _approvalPolicies),
          values: _approvalPolicies,
          onChanged: (value) => onUpdateSettings(approvalPolicy: value),
        ),
        const SizedBox(height: 10),
        _ModeDropdown(
          label: 'Sandbox',
          value: _valueOrDefault(session.sandboxMode, _sandboxModes),
          values: _sandboxModes,
          onChanged: (value) => onUpdateSettings(sandboxMode: value),
        ),
        Tooltip(
          message: 'Автоматически выполнять инструменты',
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Авто-режим инструментов'),
            subtitle: const Text('Передает --auto в CodeWhale exec'),
            value: session.autoMode,
            onChanged: (value) => onUpdateSettings(autoMode: value),
            secondary: const Icon(Icons.auto_fix_high),
            dense: true,
            controlAffinity: ListTileControlAffinity.trailing,
            shape: const RoundedRectangleBorder(),
            tileColor: Colors.transparent,
            hoverColor: Colors.transparent,
            selectedTileColor: Colors.transparent,
            enableFeedback: true,
          ),
        ),
      ],
    );
  }

  static String _valueOrDefault(String value, List<String> values) {
    return values.contains(value) ? value : '';
  }
}

class _ModeDropdown extends StatelessWidget {
  const _ModeDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> values;
  final void Function(String value) onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        for (final item in values)
          DropdownMenuItem(
            value: item,
            child: Text(item.isEmpty ? 'по умолчанию' : item),
          ),
      ],
      onChanged: (value) => onChanged(value ?? ''),
    );
  }
}

class _CodeWhaleCommandsList extends StatelessWidget {
  const _CodeWhaleCommandsList({
    required this.commands,
    required this.onRunCommand,
  });

  final List<Map<String, dynamic>> commands;
  final void Function(String command) onRunCommand;

  @override
  Widget build(BuildContext context) {
    if (commands.isEmpty) {
      return const Center(child: Text('Команды CodeWhale загружаются...'));
    }
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final command in commands) {
      final group = (command['group'] ?? 'Команды').toString();
      groups.putIfAbsent(group, () => []).add(command);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(
              entry.key,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final command in entry.value)
            ListTile(
              leading: const Icon(Icons.chevron_right),
              title:
                  Text((command['label'] ?? command['value'] ?? '').toString()),
              subtitle: Text((command['description'] ?? '').toString()),
              trailing: Text((command['value'] ?? '').toString()),
              onTap: () => onRunCommand((command['value'] ?? '').toString()),
            ),
        ],
      ],
    );
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
