import 'package:flutter/material.dart';

import '../../models/task_item.dart';
import '../../services/desktop_process_host_service.dart';
import '../../services/desktop_theme_service.dart';
import '../../state/task_store.dart';

/// Standalone desktop shell widget extracted from _HomePageState.
///
/// Receives everything it needs via constructor parameters so it has
/// no dependency on _HomePageState private members.
class DesktopShellWidget extends StatelessWidget {
  const DesktopShellWidget({
    super.key,
    required this.store,
    required this.loading,
    required this.owner,
    required this.selectedDate,
    required this.selectedDateKey,
    required this.desktopLogExpanded,
    required this.desktopMonth,
    required this.onToggleLogExpanded,
    required this.onMonthPrev,
    required this.onMonthNext,
    required this.onMonthToday,
    required this.onSetDesktopThemeMode,
    required this.onSetDesktopThemeScheme,
    required this.onToggleVoiceHost,
    required this.onOpenTaskEditor,
    required this.onSafeSyncFull,
    required this.onSafeSyncDelta,
    required this.onUndo,
    required this.desktopPageContentBuilder,
  });

  final TaskStore store;
  final bool loading;
  final String owner;
  final DateTime selectedDate;
  final String selectedDateKey;

  final bool desktopLogExpanded;
  final DateTime desktopMonth;

  final VoidCallback onToggleLogExpanded;
  final VoidCallback onMonthPrev;
  final VoidCallback onMonthNext;
  final VoidCallback onMonthToday;
  final ValueChanged<String> onSetDesktopThemeMode;
  final ValueChanged<String> onSetDesktopThemeScheme;
  final void Function(TaskStore store, bool value) onToggleVoiceHost;
  final void Function(TaskStore store, {TaskItem? existing}) onOpenTaskEditor;
  final void Function(TaskStore store, {required bool showErrors})
      onSafeSyncFull;
  final void Function(TaskStore store, {required bool showErrors})
      onSafeSyncDelta;
  final void Function(TaskStore store) onUndo;
  final Widget Function(TaskStore store, DateTime selectedDate)
      desktopPageContentBuilder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, String>>(
      valueListenable: store.desktopThemeTokens,
      builder: (context, tokens, _) {
        final bgApp =
            colorFromToken(tokens, 'bg_app', const Color(0xFFF1F5F9));
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
                            'Задачи - $selectedDateKey',
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
                              segments: const [
                                ButtonSegment(
                                    value: 0, label: Text('Задачи')),
                                ButtonSegment(
                                    value: 1, label: Text('Календарь')),
                                ButtonSegment(
                                    value: 2,
                                    label: Text('Мессенджер')),
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
                              segments: const [
                                ButtonSegment(
                                    value: 'light', label: Text('Свет')),
                                ButtonSegment(
                                    value: 'dark', label: Text('Тьма')),
                              ],
                              selected: {mode},
                              onSelectionChanged: (value) =>
                                  onSetDesktopThemeMode(value.first),
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
                                final safeScheme =
                                    schemes.contains(scheme) &&
                                            schemes.isNotEmpty
                                        ? scheme
                                        : (schemes.isEmpty
                                            ? ''
                                            : schemes.first);
                                return DropdownButton<String>(
                                  value:
                                      safeScheme.isEmpty ? null : safeScheme,
                                  hint: const Text('Тема'),
                                  onChanged: (value) {
                                    if (value != null) {
                                      onSetDesktopThemeScheme(value);
                                    }
                                  },
                                  items: schemes
                                      .map(
                                        (item) =>
                                            DropdownMenuItem<String>(
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
                            final enabled = voiceState.status ==
                                DesktopHostStatus.running;
                            return Row(
                              children: [
                                const Text('Голос'),
                                Switch(
                                  value: enabled,
                                  onChanged: (value) =>
                                      onToggleVoiceHost(store, value),
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
                              onPressed: () => onOpenTaskEditor(store),
                              icon: const Icon(Icons.add),
                              label: const Text('Добавить'),
                            );
                          },
                        ),
                        IconButton(
                          tooltip: 'Синхронизация',
                          icon: const Icon(Icons.sync),
                          onPressed: () =>
                              onSafeSyncFull(store, showErrors: true),
                        ),
                        ValueListenableBuilder<bool>(
                          valueListenable: store.canUndo,
                          builder: (context, canUndo, __) {
                            return IconButton(
                              tooltip: 'Отменить',
                              onPressed: canUndo
                                  ? () => onUndo(store)
                                  : null,
                              icon: const Icon(Icons.undo),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: loading
                        ? const Center(
                            child: CircularProgressIndicator())
                        : desktopPageContentBuilder(store, selectedDate),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    height: desktopLogExpanded ? 150 : 44,
                    decoration: BoxDecoration(
                      color: bgPanel,
                      border: Border(
                          top: BorderSide(color: border)),
                    ),
                    child: Column(
                      children: [
                        InkWell(
                          onTap: onToggleLogExpanded,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  desktopLogExpanded
                                      ? Icons
                                          .keyboard_arrow_down
                                      : Icons.keyboard_arrow_up,
                                ),
                                const SizedBox(width: 8),
                                const Text('Desktop logs'),
                              ],
                            ),
                          ),
                        ),
                        if (desktopLogExpanded)
                          Expanded(
                            child:
                                ValueListenableBuilder<List<String>>(
                              valueListenable:
                                  store.desktopLogEntries,
                              builder: (context, logs, __) {
                                return ListView.builder(
                                  reverse: true,
                                  padding:
                                      const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  itemCount: logs.length,
                                  itemBuilder:
                                      (context, index) {
                                    return Text(logs[
                                        logs.length -
                                            1 -
                                            index]);
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

}
