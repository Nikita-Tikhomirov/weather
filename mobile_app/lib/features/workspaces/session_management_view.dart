import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/project_file.dart';
import '../../models/workspace_item.dart';
import '../../models/workspace_session.dart';

class _SessionManagementText {
  const _SessionManagementText(this.l10n);

  final AppLocalizations? l10n;

  String get back => l10n?.back ?? 'Назад';
  String get manageSession => l10n?.manageSession ?? 'Управление сессией';
  String get sessionTab => l10n?.sessionTab ?? 'Сессия';
  String get filesTab => l10n?.filesTab ?? 'Файлы';
  String get commandsTab => l10n?.commandsTab ?? 'Команды';
  String get status => l10n?.sessionStatusLabel ?? 'Статус';
  String get pid => l10n?.sessionPidLabel ?? 'PID';
  String get port => l10n?.sessionPortLabel ?? 'Порт';
  String get events => l10n?.sessionEventsLabel ?? 'Событий';
  String get noValue => l10n?.noValue ?? 'нет';
  String get restartWorker => l10n?.restartWorker ?? 'Перезапустить worker';
  String get stopSession => l10n?.stopSession ?? 'Остановить сессию';
  String get killStuckSession =>
      l10n?.killStuckSession ?? 'Убить зависшую сессию';
  String get restartAction => l10n?.restartAction ?? 'Перезапустить';
  String get stopAction => l10n?.stopAction ?? 'Остановить';
  String get killAction => l10n?.killAction ?? 'Убить';
  String get photo => l10n?.photo ?? 'Фото';
  String get document => l10n?.document ?? 'Документ';
  String get projectRoot => l10n?.projectRoot ?? 'Корень проекта';
  String get upOneLevel => l10n?.upOneLevel ?? 'Наверх';
  String get refreshFiles => l10n?.refreshFiles ?? 'Обновить файлы';
  String get copyFileText => l10n?.copyFileText ?? 'Копировать текст файла';
  String get noFiles => l10n?.noFiles ?? 'Файлов нет';
  String get insertPathInChat => l10n?.insertPathInChat ?? 'Путь в чат';
  String get previewFile => l10n?.previewFile ?? 'Просмотр файла';
  String get codeWhaleModes =>
      l10n?.sessionCodeWhaleModes ?? 'Режимы CodeWhale';
  String get provider => l10n?.provider ?? 'Провайдер';
  String get model => l10n?.model ?? 'Модель';
  String get approvalPolicy => l10n?.approvalPolicy ?? 'Подтверждения';
  String get sandbox => l10n?.sandbox ?? 'Sandbox';
  String get defaultValue => l10n?.defaultValue ?? 'по умолчанию';
  String get autoModeTools => l10n?.autoModeTools ?? 'Авто-режим инструментов';
  String get autoModeToolsTooltip =>
      l10n?.autoModeToolsTooltip ?? 'Автоматически выполнять инструменты';
  String get autoModeToolsSubtitle =>
      l10n?.autoModeToolsSubtitle ?? 'Передает --auto в CodeWhale exec';
  String get commandsLoading =>
      l10n?.codeWhaleCommandsLoading ?? 'Команды CodeWhale загружаются...';
  String get skills => l10n?.skills ?? 'Скиллы';
  String get runSelected => l10n?.runSelected ?? 'Запустить выбранные';
  String get chooseSkills =>
      l10n?.chooseSkills ?? 'Выбери один или несколько навыков';

  String selectedSkillsCount(int count) {
    return l10n?.selectedSkillsCount(count) ?? 'Выбрано: $count';
  }

  String statusText(WorkspaceSessionStatus status) {
    switch (status) {
      case WorkspaceSessionStatus.idle:
        return l10n?.sessionIdleStatus ?? 'Ожидает';
      case WorkspaceSessionStatus.running:
        return l10n?.running ?? 'Работает';
      case WorkspaceSessionStatus.stopped:
        return l10n?.stopped ?? 'Остановлена';
      case WorkspaceSessionStatus.killed:
        return l10n?.killed ?? 'Убита';
      case WorkspaceSessionStatus.error:
        return l10n?.error ?? 'Ошибка';
      case WorkspaceSessionStatus.unknown:
        return l10n?.sessionUnknownStatus ?? 'Неизвестно';
    }
  }
}

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
    final text = _SessionManagementText(AppLocalizations.of(context));
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: text.back,
            icon: const Icon(Icons.arrow_back),
            onPressed: onBack,
          ),
          title: Text(text.manageSession),
          bottom: TabBar(
            tabs: [
              Tab(icon: const Icon(Icons.tune), text: text.sessionTab),
              Tab(icon: const Icon(Icons.folder_open), text: text.filesTab),
              Tab(icon: const Icon(Icons.terminal), text: text.commandsTab),
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
                _InfoRow(
                  label: text.status,
                  value: text.statusText(session.status),
                ),
                _InfoRow(
                  label: text.pid,
                  value: session.workerPid?.toString() ?? text.noValue,
                ),
                _InfoRow(
                  label: text.port,
                  value: session.workerPort?.toString() ?? text.noValue,
                ),
                _InfoRow(
                  label: text.events,
                  value: session.lastEventSeq.toString(),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Tooltip(
                      message: text.restartWorker,
                      child: FilledButton.icon(
                        onPressed: onRestart,
                        icon: const Icon(Icons.restart_alt),
                        label: Text(text.restartAction),
                      ),
                    ),
                    Tooltip(
                      message: text.stopSession,
                      child: OutlinedButton.icon(
                        onPressed: onStop,
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: Text(text.stopAction),
                      ),
                    ),
                    Tooltip(
                      message: text.killStuckSession,
                      child: FilledButton.tonalIcon(
                        onPressed: onKill,
                        icon: const Icon(Icons.power_settings_new),
                        label: Text(text.killAction),
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
                      label: Text(text.photo),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: onSendDocument,
                      icon: const Icon(Icons.description_outlined),
                      label: Text(text.document),
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
    final text = _SessionManagementText(AppLocalizations.of(context));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              IconButton(
                tooltip: text.upOneLevel,
                onPressed:
                    currentPath.isEmpty ? null : () => onOpenPath(parent),
                icon: const Icon(Icons.arrow_upward),
              ),
              Expanded(
                child: SelectableText(
                  currentPath.isEmpty ? text.projectRoot : currentPath,
                  maxLines: 1,
                ),
              ),
              IconButton(
                tooltip: text.refreshFiles,
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
              tooltip: text.copyFileText,
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
                  ? Center(child: Text(text.noFiles))
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
                                tooltip: text.insertPathInChat,
                                onPressed: () => onInsertPath(node.path),
                                icon: const Icon(Icons.link),
                              ),
                              if (!node.isDir)
                                IconButton(
                                  tooltip: text.previewFile,
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
    final text = _SessionManagementText(AppLocalizations.of(context));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          text.codeWhaleModes,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        _ModeDropdown(
          label: text.provider,
          value: _valueOrDefault(session.provider, _providers),
          values: _providers,
          onChanged: (value) => onUpdateSettings(provider: value),
        ),
        const SizedBox(height: 10),
        _ModeDropdown(
          label: text.model,
          value: _valueOrDefault(session.model, _models),
          values: _models,
          onChanged: (value) => onUpdateSettings(model: value),
        ),
        const SizedBox(height: 10),
        _ModeDropdown(
          label: text.approvalPolicy,
          value: _valueOrDefault(session.approvalPolicy, _approvalPolicies),
          values: _approvalPolicies,
          onChanged: (value) => onUpdateSettings(approvalPolicy: value),
        ),
        const SizedBox(height: 10),
        _ModeDropdown(
          label: text.sandbox,
          value: _valueOrDefault(session.sandboxMode, _sandboxModes),
          values: _sandboxModes,
          onChanged: (value) => onUpdateSettings(sandboxMode: value),
        ),
        Tooltip(
          message: text.autoModeToolsTooltip,
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(text.autoModeTools),
            subtitle: Text(text.autoModeToolsSubtitle),
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
    final text = _SessionManagementText(AppLocalizations.of(context));
    return DropdownButtonFormField<String>(
      // ignore: deprecated_member_use
      value: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        for (final item in values)
          DropdownMenuItem(
            value: item,
            child: Text(item.isEmpty ? text.defaultValue : item),
          ),
      ],
      onChanged: (value) => onChanged(value ?? ''),
    );
  }
}

class _CodeWhaleCommandsList extends StatefulWidget {
  const _CodeWhaleCommandsList({
    required this.commands,
    required this.onRunCommand,
  });

  final List<Map<String, dynamic>> commands;
  final void Function(String command) onRunCommand;

  @override
  State<_CodeWhaleCommandsList> createState() => _CodeWhaleCommandsListState();
}

class _CodeWhaleCommandsListState extends State<_CodeWhaleCommandsList> {
  final Set<String> _selectedSkills = <String>{};

  @override
  Widget build(BuildContext context) {
    final text = _SessionManagementText(AppLocalizations.of(context));
    if (widget.commands.isEmpty) {
      return Center(child: Text(text.commandsLoading));
    }
    final skillCommands = widget.commands.where(_isSkillCommand).toList();
    final otherCommands = widget.commands.where((item) {
      return !_isSkillCommand(item);
    }).toList();
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final command in otherCommands) {
      final group = (command['group'] ?? text.commandsTab).toString();
      groups.putIfAbsent(group, () => []).add(command);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (skillCommands.isNotEmpty) ...[
          _SkillsMultiSelect(
            commands: skillCommands,
            selectedValues: _selectedSkills,
            onChanged: _toggleSkill,
            onRunSelected: _runSelectedSkills,
          ),
          const SizedBox(height: 12),
        ],
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
              onTap: () =>
                  widget.onRunCommand((command['value'] ?? '').toString()),
            ),
        ],
      ],
    );
  }

  bool _isSkillCommand(Map<String, dynamic> command) {
    final value = (command['value'] ?? '').toString();
    final group = (command['group'] ?? '').toString().toLowerCase();
    return value.startsWith('/skill') || group == 'навыки' || group == 'skills';
  }

  void _toggleSkill(String value, bool selected) {
    setState(() {
      if (selected) {
        _selectedSkills.add(value);
      } else {
        _selectedSkills.remove(value);
      }
    });
  }

  void _runSelectedSkills() {
    final selected = widget.commands.where((command) {
      return _selectedSkills.contains((command['value'] ?? '').toString());
    }).toList();
    for (final command in selected) {
      widget.onRunCommand((command['value'] ?? '').toString());
    }
    setState(_selectedSkills.clear);
  }
}

class _SkillsMultiSelect extends StatelessWidget {
  const _SkillsMultiSelect({
    required this.commands,
    required this.selectedValues,
    required this.onChanged,
    required this.onRunSelected,
  });

  final List<Map<String, dynamic>> commands;
  final Set<String> selectedValues;
  final void Function(String value, bool selected) onChanged;
  final VoidCallback onRunSelected;

  @override
  Widget build(BuildContext context) {
    final text = _SessionManagementText(AppLocalizations.of(context));
    return ExpansionTile(
      leading: const Icon(Icons.extension_outlined),
      title: Text(text.skills),
      subtitle: Text(
        selectedValues.isEmpty
            ? text.chooseSkills
            : text.selectedSkillsCount(selectedValues.length),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      children: [
        for (final command in commands)
          CheckboxListTile(
            dense: true,
            value: selectedValues.contains(_valueOf(command)),
            title: Text(_labelOf(command)),
            subtitle: Text(_descriptionOf(command)),
            onChanged: (value) => onChanged(_valueOf(command), value == true),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: selectedValues.isEmpty ? null : onRunSelected,
            icon: const Icon(Icons.playlist_play),
            label: Text(text.runSelected),
          ),
        ),
      ],
    );
  }

  String _valueOf(Map<String, dynamic> command) {
    return (command['value'] ?? '').toString();
  }

  String _labelOf(Map<String, dynamic> command) {
    return (command['label'] ?? command['value'] ?? '').toString();
  }

  String _descriptionOf(Map<String, dynamic> command) {
    return (command['description'] ?? '').toString();
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
