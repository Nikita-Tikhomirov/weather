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

  Future<void> _ensureProjectChat(
    BuildContext context,
    TaskProject project,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
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
        SnackBar(content: Text('Проектный чат «${conversation.title}» готов.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось создать проектный чат: $error')),
      );
    }
  }

  void _showControlActionHint(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Откройте проектный чат.')),
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
