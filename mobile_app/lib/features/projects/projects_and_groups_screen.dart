import 'package:flutter/material.dart';

import '../../models/agent_policy.dart';
import '../../models/chat_models.dart';
import '../../models/family_group.dart';
import '../../models/task_project.dart';
import '../../state/task_store.dart';
import 'project_edit_sheet.dart';
import 'family_group_edit_sheet.dart';

class ProjectsAndGroupsScreen extends StatelessWidget {
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
      valueListenable: store.projects,
      builder: (context, projects, _) {
        return ValueListenableBuilder<String>(
          valueListenable: store.currentProjectId,
          builder: (context, currentProjectId, __) {
            final project = projects.cast<TaskProject?>().firstWhere(
                  (item) => item?.id == currentProjectId,
                  orElse: () => projects.isEmpty ? null : projects.first,
                );
            return ValueListenableBuilder<Map<String, List<String>>>(
              valueListenable: store.projectGroupMap,
              builder: (context, pgMap, ___) {
                return ValueListenableBuilder<List<FamilyGroup>>(
                  valueListenable: store.familyGroups,
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
                    final workspaceId = _primaryWorkspaceId(project.id);
                    final canUseAgent = accessPolicy.canUseAi &&
                        accessPolicy.canUseWorkspaces &&
                        workspaceId.isNotEmpty;
                    final agentBlockedReason = workspaceId.isEmpty
                        ? 'Нет доступного workspace'
                        : 'Нет прав на агента';

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
                                  label: workspaceId.isEmpty
                                      ? 'Workspace не выбран'
                                      : 'Workspace: $workspaceId',
                                ),
                                _InfoChip(
                                  icon: Icons.smart_toy_outlined,
                                  label: canUseAgent
                                      ? 'Агент доступен'
                                      : agentBlockedReason,
                                ),
                              ],
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
                                  onPressed: canUseAgent &&
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
                                  onPressed: canUseAgent &&
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
                                  onPressed: canUseAgent
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
      valueListenable: store.projects,
      builder: (context, projects, _) {
        return ValueListenableBuilder<Map<String, List<String>>>(
          valueListenable: store.projectGroupMap,
          builder: (context, pgMap, _) {
            return ValueListenableBuilder<List<FamilyGroup>>(
              valueListenable: store.familyGroups,
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
      valueListenable: store.familyGroups,
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
      valueListenable: store.currentProjectId,
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
                  store.setCurrentProject(project.id);
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
            onTap: () => store.setCurrentProject(project.id),
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
      store: store,
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
      store: store,
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
    await store.deleteProject(id);
  }

  Future<void> _createGroup(BuildContext context) async {
    await showFamilyGroupEditSheet(
      context: context,
      store: store,
      isCreate: true,
      contacts: contacts,
      contactLabel: contactLabel,
      actorProfile: actorProfile,
    );
  }

  Future<void> _editGroup(BuildContext context, FamilyGroup group) async {
    await showFamilyGroupEditSheet(
      context: context,
      store: store,
      isCreate: false,
      group: group,
      contacts: contacts,
      contactLabel: contactLabel,
      actorProfile: actorProfile,
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
    await store.deleteFamilyGroup(id);
  }

  String _primaryWorkspaceId(String projectId) {
    final workspaces = accessPolicy.workspaces
        .map((item) => (item['workspace_id'] ?? '').toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (workspaces.contains(projectId)) {
      return projectId;
    }
    return workspaces.isEmpty ? '' : workspaces.first;
  }

  void _showControlActionHint(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Откройте связанный групповой чат.')),
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
