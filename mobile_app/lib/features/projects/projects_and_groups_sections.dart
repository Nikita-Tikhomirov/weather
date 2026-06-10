part of 'projects_and_groups_screen.dart';

extension _ProjectsAndGroupsSections on _ProjectsAndGroupsScreenState {
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
                    final projectChatBinding = _projectChatBinding(snapshot);
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
                                  if (projectChatBinding != null)
                                    Chip(
                                      avatar: const Icon(
                                        Icons.hub_outlined,
                                        size: 18,
                                      ),
                                      label: Text(
                                        projectChatBinding.displayTitle,
                                      ),
                                    )
                                  else
                                    for (final group in boundGroups)
                                      Chip(
                                        avatar:
                                            const Icon(Icons.group, size: 18),
                                        label: Text(group.name),
                                      ),
                                ],
                              ),
                            if (boundGroups.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                key: const ValueKey(
                                  'project-control-ensure-chat',
                                ),
                                icon: const Icon(Icons.forum_outlined),
                                label: Text(
                                  projectChatBinding == null
                                      ? 'Создать проектный чат'
                                      : 'Обновить проектный чат',
                                ),
                                onPressed: canManageProject &&
                                        !isLoadingSnapshot
                                    ? () => _ensureProjectChat(context, project)
                                    : null,
                              ),
                            ],
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
                                          projectChatBinding != null
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
                                          projectChatBinding != null
                                      ? () => _showControlActionHint(context)
                                      : null,
                                ),
                                OutlinedButton.icon(
                                  key: const ValueKey(
                                    'project-control-start-agent',
                                  ),
                                  icon: const Icon(Icons.play_arrow_outlined),
                                  label: const Text('Запустить агента'),
                                  onPressed: canUseProjectAgent &&
                                          projectChatBinding != null
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
}
