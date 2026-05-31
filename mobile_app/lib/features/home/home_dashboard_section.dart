part of 'home_page.dart';

// ───────────────────────────────────────────────────────────────
// Dashboard section extracted from _HomePageState.
// Contains task page, calendar page, and project selector builders.
// ───────────────────────────────────────────────────────────────

extension _DashboardSection on _HomePageState {
  // ── Task management pages ──

  Widget buildTasksPage(TaskStore store) {
    return Column(
      children: [
        // Project selector bar
        buildProjectSelector(store),
        // Kanban board
        Expanded(
          child: ValueListenableBuilder<Map<String, List<TaskItem>>>(
            valueListenable: store.personalByStatus,
            builder: (context, byStatus, _) {
              return TasksBoard(
                byStatus: byStatus,
                labelFor: _profileLabel,
                groupLabel: _groupLabel,
                selectionMode: false,
                selectedIds: const <String>{},
                onToggleSelect: (_) {},
                onDrop: (item, status) async {
                  await store.move(item, WorkflowStatus.parse(status));
                  await _safeSyncDelta(store, showErrors: true);
                },
                onEdit: (task) => _openTaskEditor(store, existing: task),
                onDelete: (task) async {
                  await store.delete(task);
                  await _safeSyncDelta(store, showErrors: true);
                },
                onDoneToggle: (task) async {
                  await store.toggleDone(task);
                  await _safeSyncDelta(store, showErrors: true);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget buildProjectSelector(TaskStore store) {
    return ValueListenableBuilder<List<TaskProject>>(
      valueListenable: store.projects,
      builder: (context, projects, _) {
        return ValueListenableBuilder<String>(
          valueListenable: store.currentProjectId,
          builder: (context, currentId, _) {
            final currentProject = projects.cast<TaskProject?>().firstWhere(
                  (p) => p?.id == currentId,
                  orElse: () => null,
                );
            final projectName = currentProject?.name ?? 'Все задачи';
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Row(
                children: [
                  Icon(Icons.folder_outlined,
                      size: 18, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: currentId.isEmpty ? null : currentId,
                        isExpanded: true,
                        hint: Text(projectName,
                            style: Theme.of(context).textTheme.titleSmall),
                        items: [
                          for (final p in projects)
                            DropdownMenuItem<String>(
                              value: p.id,
                              child: Text(p.name),
                            ),
                        ],
                        onChanged: (value) {
                          store.setCurrentProject(value ?? '');
                        },
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings, size: 20),
                    tooltip: 'Управление проектами и группами',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ProjectsAndGroupsScreen(
                            store: store,
                            contacts: _allKnownContacts(store),
                            contactLabel: (c) => c.displayName.isNotEmpty
                                ? c.displayName
                                : c.profileKey,
                            actorProfile: store.owner.value,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget buildCalendarPage(TaskStore store) {
    return Column(
      children: [
        buildProjectSelector(store),
        Expanded(
          child: ValueListenableBuilder<List<TaskItem>>(
            valueListenable: store.allTasksView,
            builder: (context, allTasks, _) {
              return ValueListenableBuilder<String>(
                valueListenable: store.currentProjectId,
                builder: (context, currentProjectId, _) {
                  return ValueListenableBuilder<DateTime>(
                    valueListenable: store.selectedDate,
                    builder: (context, selectedDate, _) {
                      // Filter tasks by current project
                      final filteredTasks = currentProjectId.isEmpty
                          ? allTasks
                          : allTasks
                              .where((t) => t.projectId == currentProjectId)
                              .toList();

                      return CalendarView(
                        monthDate: _calendarMonth,
                        selectedDate: selectedDate,
                        allTasks: filteredTasks,
                        labelFor: _profileLabel,
                        onMonthPrev: _goCalendarMonthPrev,
                        onMonthNext: _goCalendarMonthNext,
                        onGoToday: _goCalendarMonthToday,
                        onDayTap: (day, dayTasks) {
                          _openDayTasksScreen(store, day, dayTasks);
                        },
                        onEdit: (task) =>
                            _openTaskEditor(store, existing: task),
                        onDelete: (task) async {
                          await store.delete(task);
                          await _safeSyncDelta(store, showErrors: true);
                        },
                        onAddForDate: (date) async {
                          store.setSelectedDate(date);
                          await _openTaskEditor(store);
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void openDayTasksScreen(
      TaskStore store, DateTime day, List<TaskItem> dayTasks) {
    store.setSelectedDate(day);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DayTasksPage(
          day: day,
          tasks: dayTasks,
          labelFor: _profileLabel,
          onEdit: (task) async {
            Navigator.of(context).pop();
            _openTaskEditor(store, existing: task);
          },
          onDelete: (task) async {
            final navigator = Navigator.of(context);
            await store.delete(task);
            await _safeSyncDelta(store, showErrors: true);
            if (mounted) {
              navigator.pop();
            }
          },
          onAddForDate: (date) async {
            store.setSelectedDate(date);
            Navigator.of(context).pop();
            await _openTaskEditor(store);
          },
        ),
      ),
    );
  }
}
