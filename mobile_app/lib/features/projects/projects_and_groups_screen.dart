import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/agent_policy.dart';
import '../../models/chat_models.dart';
import '../../models/family_group.dart';
import '../../models/project_control_models.dart';
import '../../models/task_project.dart';
import '../../models/workspace_item.dart';
import '../../services/codewhale_bridge_service.dart';
import '../../state/task_store.dart';
import 'project_edit_sheet.dart';
import 'family_group_edit_sheet.dart';

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
  String _workspaceBridgeStatus = 'Список workspace ещё не загружен.';

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

  Widget _buildControlCenter(BuildContext context) {
    return ValueListenableBuilder<List<TaskProject>>(
      valueListenable: widget.store.projects,
      builder: (context, projects, _) {
        return ValueListenableBuilder<String>(
          valueListenable: widget.store.currentProjectId,
          builder: (context, currentProjectId, __) {
            final project = projects.cast<TaskProject?>().firstWhere(
                  (item) => item?.id == currentProjectId,
                  orElse: () => projects.isEmpty ? null : projects.first,
                );
            return ValueListenableBuilder<Map<String, List<String>>>(
              valueListenable: widget.store.projectGroupMap,
              builder: (context, pgMap, ___) {
                return ValueListenableBuilder<List<FamilyGroup>>(
                  valueListenable: widget.store.familyGroups,
                  builder: (context, groups, ____) {
                    if (project == null) {
                      return const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Создайте проект, чтобы подключить чат и агента.',
                          ),
                        ),
                      );
                    }
                    final groupIds = pgMap[project.id] ?? const <String>[];
                    final boundGroups = groups
                        .where((group) => groupIds.contains(group.id))
                        .toList();
                    _ensureProjectSnapshot(project.id);
                    final snapshot = _snapshots[project.id];
                    final workspaceId =
                        (snapshot?.primaryWorkspaceId ?? '').trim();
                    final canManageProject = snapshot?.canManageProject ??
                        project.ownerKey ==
                            (widget.actorProfile ?? widget.store.owner.value);
                    final fallbackCanUseWorkspace =
                        widget.accessPolicy.canUseWorkspaces &&
                            _workspaceIsAvailable(workspaceId) &&
                            workspaceId.isNotEmpty;
                    final fallbackCanUseAgent =
                        widget.accessPolicy.canUseAi && fallbackCanUseWorkspace;
                    final canUseAgent =
                        snapshot?.canUseAgent ?? fallbackCanUseAgent;
                    final canUseWorkspace =
                        snapshot?.canUseWorkspace ?? fallbackCanUseWorkspace;
                    final isLoadingSnapshot =
                        _loadingSnapshots.contains(project.id);
                    final workspaceName = _workspaceDisplayLabel(workspaceId);
                    final workspaceLabel = workspaceId.isEmpty
                        ? 'Workspace не выбран'
                        : canUseWorkspace
                            ? 'Workspace: $workspaceName'
                            : 'Workspace: $workspaceName (нет доступа)';
                    final agentBlockedReason = workspaceId.isEmpty
                        ? 'Workspace не выбран'
                        : 'Нет прав на агента';
                    final canPickWorkspace =
                        canManageProject && _availableWorkspaceIds.isNotEmpty;
                    final canUseProjectAgent =
                        canUseAgent && workspaceId.isNotEmpty;

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.hub_outlined,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    project.name,
                                    style:
                                        Theme.of(context).textTheme.titleLarge,
                                  ),
                                ),
                              ],
                            ),
                            if (project.description.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(project.description),
                            ],
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _InfoChip(
                                  icon: Icons.forum_outlined,
                                  label: boundGroups.isEmpty
                                      ? 'Чаты не связаны'
                                      : 'Чатов: ${boundGroups.length}',
                                ),
                                _InfoChip(
                                  icon: Icons.workspaces_outline,
                                  label: isLoadingSnapshot
                                      ? 'Workspace загружается'
                                      : workspaceLabel,
                                ),
                                _InfoChip(
                                  icon: Icons.smart_toy_outlined,
                                  label: canUseProjectAgent
                                      ? 'Агент доступен'
                                      : agentBlockedReason,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _WorkspaceControl(
                              workspaceId: workspaceId,
                              workspaceLabel: workspaceName,
                              isLoading: isLoadingSnapshot,
                              canPick: canPickWorkspace,
                              bridgeConnected: _workspaceBridgeConnected,
                              bridgeStatus: _workspaceBridgeStatus,
                              workspaceCount: _availableWorkspaces.length,
                              onRefresh: widget.loadWorkspacesFromBridge
                                  ? _requestWorkspaceList
                                  : null,
                              onPick: canPickWorkspace
                                  ? () => _pickPrimaryWorkspace(
                                        context,
                                        project,
                                        snapshot,
                                      )
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Связанные чаты',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            if (boundGroups.isEmpty)
                              Text(
                                'Назначьте группу проекту, чтобы появился проектный чат.',
                                style: TextStyle(
                                  color: Theme.of(context).disabledColor,
                                ),
                              )
                            else
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final group in boundGroups)
                                    Chip(
                                      avatar: const Icon(Icons.group, size: 18),
                                      label: Text(group.name),
                                    ),
                                ],
                              ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton.icon(
                                  key: const ValueKey(
                                    'project-control-analyze-chat',
                                  ),
                                  icon: const Icon(Icons.auto_awesome_outlined),
                                  label: const Text('Анализ чата'),
                                  onPressed: canUseProjectAgent &&
                                          boundGroups.isNotEmpty
                                      ? () => _showControlActionHint(context)
                                      : null,
                                ),
                                OutlinedButton.icon(
                                  key: const ValueKey(
                                    'project-control-draft-task',
                                  ),
                                  icon: const Icon(Icons.note_add_outlined),
                                  label: const Text('Черновик задачи'),
                                  onPressed: canUseProjectAgent &&
                                          boundGroups.isNotEmpty
                                      ? () => _showControlActionHint(context)
                                      : null,
                                ),
                                OutlinedButton.icon(
                                  key: const ValueKey(
                                    'project-control-start-agent',
                                  ),
                                  icon: const Icon(Icons.play_arrow_outlined),
                                  label: const Text('Запустить агента'),
                                  onPressed: canUseProjectAgent
                                      ? () => _showControlActionHint(context)
                                      : null,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildProjectsSection(BuildContext context) {
    return ValueListenableBuilder<List<TaskProject>>(
      valueListenable: widget.store.projects,
      builder: (context, projects, _) {
        return ValueListenableBuilder<Map<String, List<String>>>(
          valueListenable: widget.store.projectGroupMap,
          builder: (context, pgMap, _) {
            return ValueListenableBuilder<List<FamilyGroup>>(
              valueListenable: widget.store.familyGroups,
              builder: (context, groups, __) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Проекты',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.add),
                          tooltip: 'Создать проект',
                          onPressed: () => _createProject(context),
                        ),
                      ],
                    ),
                    if (projects.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Проектов пока нет. Нажмите + чтобы создать.',
                          ),
                        ),
                      ),
                    for (final project in projects)
                      _projectTile(context, project, pgMap, groups),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildGroupsSection(BuildContext context) {
    return ValueListenableBuilder<List<FamilyGroup>>(
      valueListenable: widget.store.familyGroups,
      builder: (context, groups, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Группы',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Создать группу',
                  onPressed: () => _createGroup(context),
                ),
              ],
            ),
            if (groups.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Групп пока нет. Нажмите + чтобы создать.'),
                ),
              ),
            for (final group in groups) _groupTile(context, group),
          ],
        );
      },
    );
  }

  Widget _projectTile(
    BuildContext context,
    TaskProject project,
    Map<String, List<String>> pgMap,
    List<FamilyGroup> groups,
  ) {
    final projectGroupIds = pgMap[project.id] ?? [];
    final assignedGroups =
        groups.where((g) => projectGroupIds.contains(g.id)).toList();

    return ValueListenableBuilder<String>(
      valueListenable: widget.store.currentProjectId,
      builder: (context, currentId, _) {
        final isCurrent = currentId == project.id;
        return Card(
          color:
              isCurrent ? Theme.of(context).colorScheme.primaryContainer : null,
          child: ListTile(
            title: Text(project.name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (project.description.isNotEmpty)
                  Text(project.description, maxLines: 1),
                if (assignedGroups.isNotEmpty)
                  Text(
                    'Группы: ${assignedGroups.map((g) => g.name).join(', ')}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
              ],
            ),
            leading: isCurrent
                ? Icon(
                    Icons.check_circle,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : null,
            trailing: PopupMenuButton<String>(
              onSelected: (action) {
                if (action == 'select') {
                  widget.store.setCurrentProject(project.id);
                } else if (action == 'edit') {
                  _editProject(context, project, projectGroupIds);
                } else if (action == 'delete') {
                  _deleteProject(context, project.id);
                }
              },
              itemBuilder: (context) => [
                if (!isCurrent)
                  const PopupMenuItem(
                    value: 'select',
                    child: Text('Выбрать'),
                  ),
                const PopupMenuItem(
                  value: 'edit',
                  child: Text('Редактировать'),
                ),
                const PopupMenuItem(value: 'delete', child: Text('Удалить')),
              ],
            ),
            onTap: () => widget.store.setCurrentProject(project.id),
          ),
        );
      },
    );
  }

  Widget _groupTile(BuildContext context, FamilyGroup group) {
    return Card(
      child: ListTile(
        title: Text(group.name),
        subtitle: Text(
          'Участники: ${group.members.join(', ')}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (action) {
            if (action == 'edit') {
              _editGroup(context, group);
            } else if (action == 'delete') {
              _deleteGroup(context, group.id);
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'edit', child: Text('Редактировать')),
            PopupMenuItem(value: 'delete', child: Text('Удалить')),
          ],
        ),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить проект?'),
        content: const Text('Проект и привязки групп будут удалены.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить группу?'),
        content: const Text('Группа будет удалена из всех проектов.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
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
          setState(() {
            _bridgeWorkspaces = _sortWorkspaces(message.workspaces);
            _workspaceBridgeStatus = _bridgeWorkspaces.isEmpty
                ? 'CodeWhale не вернул workspace.'
                : 'Загружено workspace: ${_bridgeWorkspaces.length}';
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
                              'Основной workspace',
                              style:
                                  Theme.of(sheetContext).textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Обновить список',
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
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Поиск по имени, id или пути',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          setSheetState(() => query = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Найдено: ${filtered.length} из ${_availableWorkspaces.length}. '
                        'Источник: ${_bridgeWorkspaces.isEmpty ? 'права backend' : 'CodeWhale'}',
                        style: Theme.of(sheetContext).textTheme.bodySmall,
                      ),
                      if (currentId.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ListTile(
                          leading: const Icon(Icons.link_off_outlined),
                          title: const Text('Снять привязку'),
                          subtitle: const Text('Агент проекта будет отключён.'),
                          onTap: () => Navigator.of(sheetContext).pop(''),
                        ),
                      ],
                      const SizedBox(height: 8),
                      if (filtered.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text('Workspace не найдены.'),
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
                ? 'Workspace проекта очищен.'
                : 'Workspace проекта сохранён.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Не удалось сохранить workspace проекта.'),
        ),
      );
    }
  }

  void _showControlActionHint(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Откройте связанный групповой чат.')),
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
    final label =
        workspaceId.trim().isEmpty ? 'Выбрать workspace' : 'Сменить workspace';
    final selectedText = workspaceId.trim().isEmpty
        ? 'Workspace не выбран.'
        : 'Выбран: $workspaceLabel';
    final hint = canPick
        ? '$selectedText Доступно: $workspaceCount.'
        : 'Нет доступных workspace для выбора.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isLoading ? 'Загружаю настройку workspace...' : hint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                bridgeConnected ? bridgeStatus : 'CodeWhale: $bridgeStatus',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            IconButton(
              tooltip: 'Обновить workspace',
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
