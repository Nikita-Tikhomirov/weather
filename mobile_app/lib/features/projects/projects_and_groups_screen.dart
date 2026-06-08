import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/agent_policy.dart';
import '../../models/chat_models.dart';
import '../../models/family_group.dart';
import '../../models/project_control_models.dart';
import '../../models/task_project.dart';
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
  });

  final TaskStore store;
  final List<ChatContact> contacts;
  final String Function(ChatContact) contactLabel;
  final String? actorProfile;
  final UserAccessPolicy accessPolicy;

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
                    final canUseAgent = (snapshot?.canUseAgent ?? false) ||
                        (widget.accessPolicy.canUseAi &&
                            widget.accessPolicy.canUseWorkspaces &&
                            _workspaceIsAvailable(workspaceId) &&
                            workspaceId.isNotEmpty);
                    final canUseWorkspace =
                        (snapshot?.canUseWorkspace ?? false) ||
                            (widget.accessPolicy.canUseWorkspaces &&
                                _workspaceIsAvailable(workspaceId) &&
                                workspaceId.isNotEmpty);
                    final isLoadingSnapshot =
                        _loadingSnapshots.contains(project.id);
                    final workspaceLabel = workspaceId.isEmpty
                        ? 'Workspace не выбран'
                        : canUseWorkspace
                            ? 'Workspace: $workspaceId'
                            : 'Workspace: $workspaceId (нет доступа)';
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
                              isLoading: isLoadingSnapshot,
                              canPick: canPickWorkspace,
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

  List<String> get _availableWorkspaceIds => widget.accessPolicy.workspaces
      .map((item) => (item['workspace_id'] ?? '').toString().trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);

  bool _workspaceIsAvailable(String workspaceId) {
    final id = workspaceId.trim();
    return id.isNotEmpty && _availableWorkspaceIds.contains(id);
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
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) {
        final currentId = (snapshot?.primaryWorkspaceId ?? '').trim();
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Основной workspace',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
              ),
              if (currentId.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.link_off_outlined),
                  title: const Text('Снять привязку'),
                  onTap: () => Navigator.of(sheetContext).pop(''),
                ),
              for (final workspaceId in _availableWorkspaceIds)
                ListTile(
                  leading: Icon(
                    workspaceId == currentId
                        ? Icons.check_circle
                        : Icons.workspaces_outline,
                  ),
                  title: Text(workspaceId),
                  onTap: () => Navigator.of(sheetContext).pop(workspaceId),
                ),
            ],
          ),
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
    required this.isLoading,
    required this.canPick,
    required this.onPick,
  });

  final String workspaceId;
  final bool isLoading;
  final bool canPick;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final label =
        workspaceId.trim().isEmpty ? 'Выбрать workspace' : 'Сменить workspace';
    final hint = canPick
        ? 'Свяжите проект с конкретным workspace для агента.'
        : 'Нет доступных workspace для выбора.';
    return Row(
      children: [
        Expanded(
          child: Text(
            isLoading ? 'Загружаю настройку workspace...' : hint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          key: const ValueKey('project-workspace-picker'),
          icon: const Icon(Icons.account_tree_outlined),
          label: Text(label),
          onPressed: isLoading ? null : onPick,
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
