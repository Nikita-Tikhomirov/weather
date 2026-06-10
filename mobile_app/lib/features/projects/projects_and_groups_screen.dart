import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/agent_policy.dart';
import '../../models/chat_models.dart';
import '../../models/family_group.dart';
import '../../models/project_control_models.dart';
import '../../models/task_project.dart';
import '../../models/workspace_item.dart';
import '../../services/codewhale_bridge_service.dart';
import '../../services/local_db.dart';
import '../../state/task_store.dart';
import 'project_edit_sheet.dart';
import 'family_group_edit_sheet.dart';

part 'projects_and_groups_sections.dart';

class _ProjectsAndGroupsText {
  const _ProjectsAndGroupsText(this.l10n);

  final AppLocalizations? l10n;

  String get projects => l10n?.projectsSection ?? 'Проекты';
  String get groups => l10n?.groups ?? 'Группы';
  String get createProject => l10n?.createProjectAction ?? 'Создать проект';
  String get createGroup => l10n?.createGroupAction ?? 'Создать группу';
  String get noProjectsYet =>
      l10n?.noProjectsYetAction ??
      'Проектов пока нет. Нажмите + чтобы создать.';
  String get noGroupsYet =>
      l10n?.noGroupsYetAction ?? 'Групп пока нет. Нажмите + чтобы создать.';
  String get projectControlCreateProjectHint =>
      l10n?.projectControlCreateProjectHint ??
      'Создайте проект, чтобы подключить чат и агента.';
  String get projectControlChatsNotLinked =>
      l10n?.projectControlChatsNotLinked ?? 'Чаты не связаны';
  String projectControlChatsCount(int count) =>
      l10n?.projectControlChatsCount(count) ?? 'Чатов: $count';
  String get projectControlWorkspaceNotSelected =>
      l10n?.projectControlWorkspaceNotSelected ?? 'Workspace не выбран';
  String projectControlWorkspaceChip(String label) =>
      l10n?.projectControlWorkspaceChip(label) ?? 'Workspace: $label';
  String projectControlWorkspaceUnavailable(String label) =>
      l10n?.projectControlWorkspaceUnavailable(label) ??
      'Workspace: $label (нет доступа)';
  String get projectControlNoAgentAccess =>
      l10n?.projectControlNoAgentAccess ?? 'Нет прав на агента';
  String get projectControlWorkspaceLoading =>
      l10n?.projectControlWorkspaceLoading ?? 'Workspace загружается';
  String get projectControlAgentAvailable =>
      l10n?.projectControlAgentAvailable ?? 'Агент доступен';
  String get projectControlLinkedChats =>
      l10n?.projectControlLinkedChats ?? 'Связанные чаты';
  String get projectControlAssignGroupForChat =>
      l10n?.projectControlAssignGroupForChat ??
      'Назначьте группу проекту, чтобы появился проектный чат.';
  String get projectControlCreateChat =>
      l10n?.projectControlCreateChat ?? 'Создать проектный чат';
  String get projectControlRefreshChat =>
      l10n?.projectControlRefreshChat ?? 'Обновить проектный чат';
  String get projectControlAnalyzeChat =>
      l10n?.projectControlAnalyzeChat ?? 'Анализ чата';
  String get projectControlDraftTask =>
      l10n?.projectControlDraftTask ?? 'Черновик задачи';
  String get projectControlStartAgent =>
      l10n?.projectControlStartAgent ?? 'Запустить агента';
  String get workspaceBridgeNotLoaded =>
      l10n?.workspaceBridgeNotLoaded ?? 'Список workspace ещё не загружен.';
  String get workspaceBridgeEmpty =>
      l10n?.workspaceBridgeEmpty ?? 'CodeWhale не вернул workspace.';
  String workspaceBridgeLoaded(int count) =>
      l10n?.workspaceBridgeLoaded(count) ?? 'Загружено workspace: $count';
  String get primaryWorkspace => l10n?.primaryWorkspace ?? 'Основной workspace';
  String get refreshWorkspaceList =>
      l10n?.refreshWorkspaceList ?? 'Обновить список';
  String get workspaceSearchHint =>
      l10n?.workspaceSearchHint ?? 'Поиск по имени, id или пути';
  String workspaceFoundSummary({
    required int found,
    required int total,
    required String source,
  }) =>
      l10n?.workspaceFoundSummary(found, total, source) ??
      'Найдено: $found из $total. Источник: $source';
  String get workspaceSourceBackendAccess =>
      l10n?.workspaceSourceBackendAccess ?? 'права backend';
  String get workspaceSourceCodeWhale =>
      l10n?.workspaceSourceCodeWhale ?? 'CodeWhale';
  String get clearWorkspaceBinding =>
      l10n?.clearWorkspaceBinding ?? 'Снять привязку';
  String get projectAgentDisabledAfterClearing =>
      l10n?.projectAgentDisabledAfterClearing ??
      'Агент проекта будет отключён.';
  String get noWorkspacesFound =>
      l10n?.noWorkspacesFound ?? 'Workspace не найдены.';
  String get projectWorkspaceCleared =>
      l10n?.projectWorkspaceCleared ?? 'Workspace проекта очищен.';
  String get projectWorkspaceSaved =>
      l10n?.projectWorkspaceSaved ?? 'Workspace проекта сохранён.';
  String get projectWorkspaceSaveFailed =>
      l10n?.projectWorkspaceSaveFailed ??
      'Не удалось сохранить workspace проекта.';
  String projectChatReady(String title) =>
      l10n?.projectChatReady(title) ?? 'Проектный чат «$title» готов.';
  String projectChatCreateFailed(Object error) =>
      l10n?.projectChatCreateFailed(error) ??
      'Не удалось создать проектный чат: $error';
  String get openProjectChatHint =>
      l10n?.openProjectChatHint ?? 'Откройте проектный чат.';
  String get selectWorkspace => l10n?.selectWorkspace ?? 'Выбрать workspace';
  String get changeWorkspace => l10n?.changeWorkspace ?? 'Сменить workspace';
  String get workspaceNotSelectedSentence =>
      l10n?.workspaceNotSelectedSentence ?? 'Workspace не выбран.';
  String workspaceSelected(String label) =>
      l10n?.workspaceSelected(label) ?? 'Выбран: $label.';
  String workspaceControlAvailable(String selectedText, int count) =>
      l10n?.workspaceControlAvailable(selectedText, count) ??
      '$selectedText Доступно: $count.';
  String get noAvailableWorkspacesToSelect =>
      l10n?.noAvailableWorkspacesToSelect ??
      'Нет доступных workspace для выбора.';
  String get workspaceSettingLoading =>
      l10n?.workspaceSettingLoading ?? 'Загружаю настройку workspace...';
  String get refreshWorkspaces =>
      l10n?.refreshWorkspaces ?? 'Обновить workspace';
  String get selectAction => l10n?.selectAction ?? 'Выбрать';
  String get editAction => l10n?.edit ?? 'Редактировать';
  String get deleteAction => l10n?.delete ?? 'Удалить';
  String get cancelAction => l10n?.cancel ?? 'Отмена';
  String projectGroupsSummary(String groups) =>
      l10n?.projectGroupsSummary(groups) ?? 'Группы: $groups';
  String groupParticipantsSummary(String participants) =>
      l10n?.groupParticipantsSummary(participants) ??
      'Участники: $participants';
  String get deleteProjectTitle =>
      l10n?.deleteProjectTitle ?? 'Удалить проект?';
  String get deleteProjectMessage =>
      l10n?.deleteProjectMessage ?? 'Проект и привязки групп будут удалены.';
  String get deleteGroupTitle => l10n?.deleteGroupTitle ?? 'Удалить группу?';
  String get deleteGroupMessage =>
      l10n?.deleteGroupMessage ?? 'Группа будет удалена из всех проектов.';
}

class ProjectsAndGroupsScreen extends StatefulWidget {
  const ProjectsAndGroupsScreen({
    super.key,
    required this.store,
    this.contacts = const [],
    this.contactLabel = _defaultContactLabel,
    this.actorProfile,
    this.accessPolicy = const UserAccessPolicy.messengerOnly(),
    this.initialWorkspaces = const [],
    this.loadWorkspacesFromBridge = true,
  });

  final TaskStore store;
  final List<ChatContact> contacts;
  final String Function(ChatContact) contactLabel;
  final String? actorProfile;
  final UserAccessPolicy accessPolicy;
  final List<WorkspaceItem> initialWorkspaces;
  final bool loadWorkspacesFromBridge;

  static String _defaultContactLabel(ChatContact c) => c.displayName.isNotEmpty
      ? c.displayName
      : (c.phone.isNotEmpty ? c.phone : c.profileKey);

  @override
  State<ProjectsAndGroupsScreen> createState() =>
      _ProjectsAndGroupsScreenState();
}

class _ProjectsAndGroupsScreenState extends State<ProjectsAndGroupsScreen> {
  final Map<String, ProjectControlSnapshot> _snapshots =
      <String, ProjectControlSnapshot>{};
  final Set<String> _loadingSnapshots = <String>{};
  CodeWhaleBridgeService? _workspaceBridge;
  List<WorkspaceItem> _bridgeWorkspaces = const [];
  bool _workspaceBridgeConnected = false;
  String _workspaceBridgeStatus = '';

  @override
  void initState() {
    super.initState();
    _bridgeWorkspaces = _sortWorkspaces(widget.initialWorkspaces);
    if (widget.loadWorkspacesFromBridge) {
      _connectWorkspaceBridge();
    }
  }

  @override
  void dispose() {
    _workspaceBridge?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Project Control Center'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _buildControlCenter(context),
          const SizedBox(height: 24),
          _buildProjectsSection(context),
          const SizedBox(height: 24),
          _buildGroupsSection(context),
        ],
      ),
    );
  }

  Future<void> _createProject(BuildContext context) async {
    await showProjectEditSheet(
      context: context,
      store: widget.store,
      isCreate: true,
    );
  }

  Future<void> _editProject(
    BuildContext context,
    TaskProject project,
    List<String> currentGroupIds,
  ) async {
    await showProjectEditSheet(
      context: context,
      store: widget.store,
      isCreate: false,
      project: project,
      initialGroupIds: currentGroupIds,
    );
  }

  Future<void> _deleteProject(BuildContext context, String id) async {
    final text = _ProjectsAndGroupsText(AppLocalizations.of(context));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(text.deleteProjectTitle),
        content: Text(text.deleteProjectMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(text.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(text.deleteAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.store.deleteProject(id);
  }

  Future<void> _createGroup(BuildContext context) async {
    await showFamilyGroupEditSheet(
      context: context,
      store: widget.store,
      isCreate: true,
      contacts: widget.contacts,
      contactLabel: widget.contactLabel,
      actorProfile: widget.actorProfile,
    );
  }

  Future<void> _editGroup(BuildContext context, FamilyGroup group) async {
    await showFamilyGroupEditSheet(
      context: context,
      store: widget.store,
      isCreate: false,
      group: group,
      contacts: widget.contacts,
      contactLabel: widget.contactLabel,
      actorProfile: widget.actorProfile,
    );
  }

  Future<void> _deleteGroup(BuildContext context, String id) async {
    final text = _ProjectsAndGroupsText(AppLocalizations.of(context));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(text.deleteGroupTitle),
        content: Text(text.deleteGroupMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(text.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(text.deleteAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.store.deleteFamilyGroup(id);
  }

  List<WorkspaceItem> get _availableWorkspaces {
    final byId = <String, WorkspaceItem>{};
    for (final workspace in _bridgeWorkspaces) {
      final id = workspace.id.trim();
      if (id.isEmpty) {
        continue;
      }
      byId[id] = workspace;
    }
    for (final raw in widget.accessPolicy.workspaces) {
      final id = (raw['workspace_id'] ?? '').toString().trim();
      if (id.isEmpty || byId.containsKey(id)) {
        continue;
      }
      byId[id] = WorkspaceItem(
        id: id,
        name: id,
        path: '',
        status: WorkspaceStatus.unknown,
      );
    }
    return _sortWorkspaces(byId.values.toList());
  }

  List<String> get _availableWorkspaceIds => _availableWorkspaces
      .map((item) => item.id.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);

  bool _workspaceIsAvailable(String workspaceId) {
    final id = workspaceId.trim();
    return id.isNotEmpty && _availableWorkspaceIds.contains(id);
  }

  ProjectChatBinding? _projectChatBinding(ProjectControlSnapshot? snapshot) {
    final bindings = snapshot?.chatBindings ?? const <ProjectChatBinding>[];
    for (final binding in bindings) {
      if (binding.source == 'project_group' ||
          binding.conversationKey.startsWith('grp:project:')) {
        return binding;
      }
    }
    return null;
  }

  String _workspaceDisplayLabel(String workspaceId) {
    final id = workspaceId.trim();
    if (id.isEmpty) {
      return '';
    }
    final workspace = _workspaceById(id);
    return workspace == null ? id : _workspaceTitle(workspace);
  }

  WorkspaceItem? _workspaceById(String workspaceId) {
    final id = workspaceId.trim();
    if (id.isEmpty) {
      return null;
    }
    for (final workspace in _availableWorkspaces) {
      if (workspace.id.trim() == id) {
        return workspace;
      }
    }
    return null;
  }

  void _connectWorkspaceBridge() {
    final bridge = CodeWhaleBridgeService(
      onMessage: (message) {
        if (!mounted) {
          return;
        }
        if (message.type == 'workspace_list' || message.workspaces.isNotEmpty) {
          final text = _ProjectsAndGroupsText(AppLocalizations.of(context));
          setState(() {
            _bridgeWorkspaces = _sortWorkspaces(message.workspaces);
            _workspaceBridgeStatus = _bridgeWorkspaces.isEmpty
                ? text.workspaceBridgeEmpty
                : text.workspaceBridgeLoaded(_bridgeWorkspaces.length);
          });
        }
      },
      onStatusChange: (connected, status) {
        if (!mounted) {
          return;
        }
        setState(() {
          _workspaceBridgeConnected = connected;
          _workspaceBridgeStatus = status;
        });
        if (connected) {
          _requestWorkspaceList();
        }
      },
    );
    _workspaceBridge = bridge;
    unawaited(
      bridge.connect().then((_) {
        if (mounted) {
          _requestWorkspaceList();
        }
      }),
    );
  }

  void _requestWorkspaceList() {
    _workspaceBridge?.requestWorkspaceList();
  }

  List<WorkspaceItem> _filterWorkspaces(String query) {
    final normalized = query.trim().toLowerCase();
    final workspaces = _availableWorkspaces;
    if (normalized.isEmpty) {
      return workspaces;
    }
    return workspaces.where((workspace) {
      final haystack = [
        _workspaceTitle(workspace),
        workspace.id,
        workspace.name,
        workspace.path,
      ].join(' ').toLowerCase();
      return haystack.contains(normalized);
    }).toList(growable: false);
  }

  static List<WorkspaceItem> _sortWorkspaces(Iterable<WorkspaceItem> items) {
    final result = items.toList(growable: false);
    result.sort((a, b) => _workspaceTitle(a).compareTo(_workspaceTitle(b)));
    return result;
  }

  static String _workspaceTitle(WorkspaceItem workspace) {
    final name = workspace.name.trim();
    final pathSegment = _lastPathSegment(workspace.path).trim();
    if (name.isNotEmpty && !_looksTechnicalId(name)) {
      return name;
    }
    if (pathSegment.isNotEmpty && !_looksTechnicalId(pathSegment)) {
      return pathSegment;
    }
    if (name.isNotEmpty) {
      return name;
    }
    return workspace.id.trim();
  }

  static String _workspaceSubtitle(WorkspaceItem workspace) {
    final parts = <String>[];
    final id = workspace.id.trim();
    final path = workspace.path.trim();
    final title = _workspaceTitle(workspace);
    if (id.isNotEmpty && id != title) {
      parts.add(id);
    }
    if (path.isNotEmpty) {
      parts.add(path);
    }
    return parts.join(' · ');
  }

  static String _lastPathSegment(String path) {
    final parts = path.trim().split(RegExp(r'[\\/]+'));
    if (parts.isEmpty) {
      return path.trim();
    }
    return parts.last.trim();
  }

  static bool _looksTechnicalId(String value) {
    final text = value.trim().toLowerCase();
    if (text.isEmpty) {
      return true;
    }
    return RegExp(r'^prj-[a-f0-9]{12,}$').hasMatch(text) ||
        RegExp(r'^[a-f0-9]{16,}$').hasMatch(text);
  }

  void _ensureProjectSnapshot(String projectId) {
    if (projectId.isEmpty ||
        _snapshots.containsKey(projectId) ||
        _loadingSnapshots.contains(projectId)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_loadProjectSnapshot(projectId));
    });
  }

  Future<void> _loadProjectSnapshot(String projectId) async {
    if (_loadingSnapshots.contains(projectId)) {
      return;
    }
    setState(() => _loadingSnapshots.add(projectId));
    try {
      final snapshot =
          await widget.store.repository.api.fetchProjectControlSnapshot(
        actorProfile: widget.actorProfile ?? widget.store.owner.value,
        projectId: projectId,
      );
      if (!mounted) return;
      setState(() => _snapshots[projectId] = snapshot);
    } catch (_) {
      // The local project/group lists still render; controls stay disabled.
    } finally {
      if (mounted) {
        setState(() => _loadingSnapshots.remove(projectId));
      }
    }
  }

  Future<void> _pickPrimaryWorkspace(
    BuildContext context,
    TaskProject project,
    ProjectControlSnapshot? snapshot,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final text = _ProjectsAndGroupsText(AppLocalizations.of(context));
    var query = '';
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final currentId = (snapshot?.primaryWorkspaceId ?? '').trim();
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final filtered = _filterWorkspaces(query);
            return SafeArea(
              child: DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.78,
                minChildSize: 0.45,
                maxChildSize: 0.92,
                builder: (context, scrollController) {
                  return ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              text.primaryWorkspace,
                              style:
                                  Theme.of(sheetContext).textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            tooltip: text.refreshWorkspaceList,
                            icon: const Icon(Icons.refresh),
                            onPressed: widget.loadWorkspacesFromBridge
                                ? _requestWorkspaceList
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        autofocus: false,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: text.workspaceSearchHint,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          setSheetState(() => query = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        text.workspaceFoundSummary(
                          found: filtered.length,
                          total: _availableWorkspaces.length,
                          source: _bridgeWorkspaces.isEmpty
                              ? text.workspaceSourceBackendAccess
                              : text.workspaceSourceCodeWhale,
                        ),
                        style: Theme.of(sheetContext).textTheme.bodySmall,
                      ),
                      if (currentId.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ListTile(
                          leading: const Icon(Icons.link_off_outlined),
                          title: Text(text.clearWorkspaceBinding),
                          subtitle:
                              Text(text.projectAgentDisabledAfterClearing),
                          onTap: () => Navigator.of(sheetContext).pop(''),
                        ),
                      ],
                      const SizedBox(height: 8),
                      if (filtered.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(text.noWorkspacesFound),
                        )
                      else
                        for (final workspace in filtered)
                          ListTile(
                            leading: Icon(
                              workspace.id == currentId
                                  ? Icons.check_circle
                                  : Icons.workspaces_outline,
                            ),
                            title: Text(_workspaceTitle(workspace)),
                            subtitle: Text(
                              _workspaceSubtitle(workspace),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () =>
                                Navigator.of(sheetContext).pop(workspace.id),
                          ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
    if (selected == null) {
      return;
    }
    try {
      final automation =
          await widget.store.repository.api.updateProjectAutomationConfig(
        actorProfile: widget.actorProfile ?? widget.store.owner.value,
        projectId: project.id,
        primaryWorkspaceId: selected,
      );
      if (!mounted) return;
      final current = _snapshots[project.id] ?? snapshot;
      setState(() {
        _snapshots[project.id] = ProjectControlSnapshot(
          project: current?.project ?? project,
          chatBindings: current?.chatBindings ?? const [],
          automation: automation,
          primaryWorkspaceId: automation.primaryWorkspaceId,
          canManageProject: current?.canManageProject ?? true,
          canUseWorkspace: automation.primaryWorkspaceId.isNotEmpty &&
              widget.accessPolicy.canUseWorkspaces &&
              _workspaceIsAvailable(automation.primaryWorkspaceId),
          canUseAgent: automation.primaryWorkspaceId.isNotEmpty &&
              widget.accessPolicy.canUseWorkspaces &&
              widget.accessPolicy.canUseAi &&
              _workspaceIsAvailable(automation.primaryWorkspaceId),
        );
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            selected.isEmpty
                ? text.projectWorkspaceCleared
                : text.projectWorkspaceSaved,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(text.projectWorkspaceSaveFailed),
        ),
      );
    }
  }

  Future<void> _ensureProjectChat(
    BuildContext context,
    TaskProject project,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final text = _ProjectsAndGroupsText(AppLocalizations.of(context));
    try {
      final actor = widget.actorProfile ?? widget.store.owner.value;
      final conversation = await widget.store.repository.api.ensureProjectChat(
        actorProfile: actor,
        projectId: project.id,
      );
      try {
        await widget.store.repository.db.upsertConversation(conversation);
      } catch (_) {
        // Widget tests can provide a repository without a local DB.
      }
      final snapshot =
          await widget.store.repository.api.fetchProjectControlSnapshot(
        actorProfile: actor,
        projectId: project.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _snapshots[project.id] = snapshot;
      });
      messenger.showSnackBar(
        SnackBar(content: Text(text.projectChatReady(conversation.title))),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text(text.projectChatCreateFailed(error))),
      );
    }
  }

  void _showControlActionHint(BuildContext context) {
    final text = _ProjectsAndGroupsText(AppLocalizations.of(context));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text.openProjectChatHint)),
    );
  }
}

class _WorkspaceControl extends StatelessWidget {
  const _WorkspaceControl({
    required this.workspaceId,
    required this.workspaceLabel,
    required this.isLoading,
    required this.canPick,
    required this.bridgeConnected,
    required this.bridgeStatus,
    required this.workspaceCount,
    required this.onRefresh,
    required this.onPick,
  });

  final String workspaceId;
  final String workspaceLabel;
  final bool isLoading;
  final bool canPick;
  final bool bridgeConnected;
  final String bridgeStatus;
  final int workspaceCount;
  final VoidCallback? onRefresh;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final text = _ProjectsAndGroupsText(AppLocalizations.of(context));
    final label = workspaceId.trim().isEmpty
        ? text.selectWorkspace
        : text.changeWorkspace;
    final selectedText = workspaceId.trim().isEmpty
        ? text.workspaceNotSelectedSentence
        : text.workspaceSelected(workspaceLabel);
    final hint = canPick
        ? text.workspaceControlAvailable(selectedText, workspaceCount)
        : text.noAvailableWorkspacesToSelect;
    final normalizedBridgeStatus = bridgeStatus.trim();
    final displayBridgeStatus = normalizedBridgeStatus.isEmpty
        ? text.workspaceBridgeNotLoaded
        : bridgeStatus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isLoading ? text.workspaceSettingLoading : hint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                bridgeConnected
                    ? displayBridgeStatus
                    : 'CodeWhale: $displayBridgeStatus',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            IconButton(
              tooltip: text.refreshWorkspaces,
              icon: const Icon(Icons.refresh),
              onPressed: onRefresh,
            ),
            const SizedBox(width: 4),
            OutlinedButton.icon(
              key: const ValueKey('project-workspace-picker'),
              icon: const Icon(Icons.account_tree_outlined),
              label: Text(label),
              onPressed: isLoading ? null : onPick,
            ),
          ],
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}
