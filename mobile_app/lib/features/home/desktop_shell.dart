part of 'home_page.dart';

// ───────────────────────────────────────────────────────────────
// Desktop shell builders extracted from _HomePageState.
// These methods live in a part file so home_page.dart stays
// manageable while retaining access to all private members.
// ───────────────────────────────────────────────────────────────

extension _DesktopShellExtension on _HomePageState {
  Widget _buildDesktopShell({
    required TaskStore store,
    required bool loading,
    required String owner,
    required DateTime selectedDate,
    required String selectedDateKey,
  }) {
    return ValueListenableBuilder<Map<String, String>>(
      valueListenable: store.desktopThemeTokens,
      builder: (context, tokens, _) {
        final labels = DesktopShellLabels(AppLocalizations.of(context));
        final bgApp = colorFromToken(tokens, 'bg_app', const Color(0xFFF1F5F9));
        final bgPanel =
            colorFromToken(tokens, 'bg_panel', const Color(0xFFFFFFFF));
        final textPrimary =
            colorFromToken(tokens, 'text_primary', const Color(0xFF0F172A));
        final border =
            colorFromToken(tokens, 'border', const Color(0xFFE2E8F0));
        return Scaffold(
          body: Container(
            color: bgApp,
            child: SafeArea(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: bgPanel,
                      border: Border(
                        bottom: BorderSide(color: border),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            labels.taskTitle(selectedDateKey),
                            style: TextStyle(
                              color: textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        ValueListenableBuilder<int>(
                          valueListenable: store.pageIndex,
                          builder: (context, page, __) {
                            return SegmentedButton<int>(
                              showSelectedIcon: false,
                              segments: [
                                ButtonSegment(
                                  value: 0,
                                  label: Text(labels.tasks),
                                ),
                                ButtonSegment(
                                  value: 1,
                                  label: Text(labels.calendar),
                                ),
                                ButtonSegment(
                                  value: 2,
                                  label: Text(labels.messenger),
                                ),
                              ],
                              selected: {page},
                              onSelectionChanged: (value) =>
                                  store.setPage(value.first),
                            );
                          },
                        ),
                        const SizedBox(width: 10),
                        ValueListenableBuilder<String>(
                          valueListenable: store.themeMode,
                          builder: (context, mode, __) {
                            return SegmentedButton<String>(
                              showSelectedIcon: false,
                              segments: [
                                ButtonSegment(
                                  value: 'light',
                                  label: Text(labels.light),
                                ),
                                ButtonSegment(
                                  value: 'dark',
                                  label: Text(labels.dark),
                                ),
                              ],
                              selected: {mode},
                              onSelectionChanged: (value) =>
                                  _setDesktopThemeMode(value.first),
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        ValueListenableBuilder<List<String>>(
                          valueListenable: store.availableSchemes,
                          builder: (context, schemes, __) {
                            return ValueListenableBuilder<String>(
                              valueListenable: store.themeScheme,
                              builder: (context, scheme, ___) {
                                final safeScheme = schemes.contains(scheme) &&
                                        schemes.isNotEmpty
                                    ? scheme
                                    : (schemes.isEmpty ? '' : schemes.first);
                                return DropdownButton<String>(
                                  value: safeScheme.isEmpty ? null : safeScheme,
                                  hint: Text(labels.theme),
                                  onChanged: (value) {
                                    if (value != null) {
                                      _setDesktopThemeScheme(value);
                                    }
                                  },
                                  items: schemes
                                      .map(
                                        (item) => DropdownMenuItem<String>(
                                          value: item,
                                          child: Text(item),
                                        ),
                                      )
                                      .toList(),
                                );
                              },
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        ValueListenableBuilder<DesktopHostState>(
                          valueListenable: store.voiceHostState,
                          builder: (context, voiceState, __) {
                            final enabled =
                                voiceState.status == DesktopHostStatus.running;
                            return Row(
                              children: [
                                Text(labels.voice),
                                Switch(
                                  value: enabled,
                                  onChanged: (value) =>
                                      _toggleVoiceHost(store, value),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        ValueListenableBuilder<int>(
                          valueListenable: store.pageIndex,
                          builder: (context, page, __) {
                            return FilledButton.icon(
                              onPressed: () => _openTaskEditor(store),
                              icon: const Icon(Icons.add),
                              label: Text(labels.addTask),
                            );
                          },
                        ),
                        if (_accessPolicy.canManageWorkspaceAccess)
                          IconButton(
                            tooltip: labels.administration,
                            icon: const Icon(
                              Icons.admin_panel_settings_outlined,
                            ),
                            onPressed: _openAdminAccess,
                          ),
                        IconButton(
                          tooltip: labels.sync,
                          icon: const Icon(Icons.sync),
                          onPressed: () =>
                              _safeSyncFull(store, showErrors: true),
                        ),
                        ValueListenableBuilder<bool>(
                          valueListenable: store.canUndo,
                          builder: (context, canUndo, __) {
                            return IconButton(
                              tooltip: labels.undo,
                              onPressed: canUndo
                                  ? () async {
                                      final ok = await store.undoLastAction();
                                      if (ok) {
                                        await _safeSyncDelta(
                                          store,
                                          showErrors: false,
                                        );
                                      }
                                    }
                                  : null,
                              icon: const Icon(Icons.undo),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  ActiveCallBanner(
                    session: _activeCallSession,
                    state: _activeCallState,
                    owner: owner,
                    profileLabel: _profileLabel,
                    onOpen: _openActiveCallScreen,
                    onAccept: _acceptActiveCallFromBanner,
                    onEnd: _endActiveCallFromBanner,
                  ),
                  Expanded(
                    child: loading
                        ? const Center(child: CircularProgressIndicator())
                        : _buildDesktopPageContent(store, selectedDate),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    height: _desktopLogExpanded ? 150 : 48,
                    decoration: BoxDecoration(
                      color: bgPanel,
                      border: Border(top: BorderSide(color: border)),
                    ),
                    child: Column(
                      children: [
                        InkWell(
                          onTap: _toggleDesktopLogExpanded,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _desktopLogExpanded
                                      ? Icons.keyboard_arrow_down
                                      : Icons.keyboard_arrow_up,
                                ),
                                const SizedBox(width: 8),
                                const Text('Desktop logs'),
                              ],
                            ),
                          ),
                        ),
                        if (_desktopLogExpanded)
                          Expanded(
                            child: ValueListenableBuilder<List<String>>(
                              valueListenable: store.desktopLogEntries,
                              builder: (context, logs, __) {
                                return ListView.builder(
                                  reverse: true,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  itemCount: logs.length,
                                  itemBuilder: (context, index) {
                                    return Text(logs[logs.length - 1 - index]);
                                  },
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDesktopPageContent(TaskStore store, DateTime selectedDate) {
    return ValueListenableBuilder<int>(
      valueListenable: store.pageIndex,
      builder: (context, page, _) {
        if (page == 0) {
          return Column(
            children: [
              buildProjectSelector(store),
              Expanded(
                child: ValueListenableBuilder<Map<String, List<TaskItem>>>(
                  valueListenable: store.personalByStatus,
                  builder: (context, byStatus, __) {
                    return DesktopTasksBoard(
                      byStatus: byStatus,
                      labelFor: _profileLabel,
                      selectionMode: false,
                      selectedIds: const <String>{},
                      onToggleSelect: (_) {},
                      onDropStatus: (item, status) async {
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
        if (page == 1) {
          return ValueListenableBuilder<List<TaskItem>>(
            valueListenable: store.allTasksView,
            builder: (context, tasks, __) {
              return DesktopCalendarView(
                month: _desktopMonth,
                selectedDate: selectedDate,
                allTasks: tasks,
                monthGrid: _monthGrid(_desktopMonth),
                onGoPrevMonth: _goDesktopMonthPrev,
                onGoNextMonth: _goDesktopMonthNext,
                onGoToday: _goDesktopMonthToday,
                onSelectDate: (date) => store.setSelectedDate(date),
                onDropToDay: (task, targetDay) =>
                    _moveToDate(store, task, targetDay),
                onDropToStatus: (task, status) async {
                  await store.move(task, WorkflowStatus.parse(status));
                  await _safeSyncDelta(store, showErrors: true);
                },
                onOpenEditor: (day, task) async {
                  store.setSelectedDate(day);
                  await _openTaskEditor(store, existing: task);
                },
                onDelete: (task) async {
                  await store.delete(task);
                  await _safeSyncDelta(store, showErrors: true);
                },
                onAddForDate: (day) async {
                  store.setSelectedDate(day);
                  await _openTaskEditor(store);
                },
              );
            },
          );
        }
        return buildMessengerPage(store, compact: false);
      },
    );
  }
}
