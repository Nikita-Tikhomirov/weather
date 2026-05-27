import 'package:flutter/material.dart';

import '../../domain/task_draft.dart';
import '../../models/chat_models.dart';
import '../../models/family_group.dart';
import '../../models/task_item.dart';
import '../../models/task_project.dart';
import '../../state/task_store.dart';

const _reminderOptions = <int, String>{
  1440: 'За 24 часа',
  720: 'За 12 часов',
  180: 'За 3 часа',
  120: 'За 2 часа',
  60: 'За 1 час',
  30: 'За 30 минут',
  15: 'За 15 минут',
  5: 'За 5 минут',
};

Future<void> showTaskEditorSheet({
  required BuildContext context,
  required TaskStore store,
  required List<ChatContact> knownContacts,
  required String Function(ChatContact contact) contactLabel,
  required String Function(DateTime value) dateKey,
  required Future<void> Function() onSaved,
  TaskItem? existing,
  bool forceFamily = false,
}) async {
  final titleCtl = TextEditingController(text: existing?.title ?? '');
  final detailsCtl = TextEditingController(text: existing?.details ?? '');
  final durationCtl = TextEditingController(
    text: existing == null ? '' : existing.durationMinutes.toString(),
  );
  final selectedAssignees = <String>{
    ...(existing?.assignees ?? const <String>[]),
  };
  DateTime selected = existing == null
      ? store.selectedDate.value
      : DateTime.tryParse(existing.dueDate) ?? store.selectedDate.value;
  String time = existing?.time ?? '19:00';
  String priority = existing?.priority ?? 'medium';
  String status = existing?.workflowStatus ?? 'todo';
  bool isFamily = forceFamily || (existing?.isFamily ?? false);
  String selectedProjectId = existing?.projectId ?? store.currentProjectId.value;
  String selectedGroupId = existing?.groupId ?? '';
  final selectedReminderOffsets = <int>{
    ...(existing?.reminderOffsetsMinutes ?? const <int>[]),
  };

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (sheetContext, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    existing == null ? 'Новая задача' : 'Редактирование задачи',
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleCtl,
                    decoration: const InputDecoration(labelText: 'Название'),
                  ),
                  TextField(
                    controller: detailsCtl,
                    decoration: const InputDecoration(labelText: 'Описание'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_month),
                          label: Text(dateKey(selected)),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: sheetContext,
                              initialDate: selected,
                              firstDate: DateTime(2024),
                              lastDate: DateTime(2035),
                            );
                            if (picked != null) {
                              setModalState(() => selected = picked);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.schedule),
                          label: Text(time),
                          onPressed: () async {
                            final parts = time.split(':');
                            final initial = TimeOfDay(
                              hour: int.tryParse(parts.first) ?? 19,
                              minute: int.tryParse(
                                    parts.length > 1 ? parts[1] : '0',
                                  ) ??
                                  0,
                            );
                            final picked = await showTimePicker(
                              context: sheetContext,
                              initialTime: initial,
                            );
                            if (picked != null) {
                              setModalState(() {
                                time =
                                    '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  DropdownButtonFormField<String>(
                    // ignore: deprecated_member_use
                    value: priority,
                    decoration: const InputDecoration(labelText: 'Приоритет'),
                    items: const [
                      DropdownMenuItem(value: 'low', child: Text('Низкий')),
                      DropdownMenuItem(value: 'medium', child: Text('Средний')),
                      DropdownMenuItem(value: 'high', child: Text('Высокий')),
                    ],
                    onChanged: (value) =>
                        setModalState(() => priority = value ?? 'medium'),
                  ),
                  DropdownButtonFormField<String>(
                    // ignore: deprecated_member_use
                    value: status,
                    decoration: const InputDecoration(labelText: 'Статус'),
                    items: const [
                      DropdownMenuItem(
                        value: 'todo',
                        child: Text('К выполнению'),
                      ),
                      DropdownMenuItem(
                        value: 'in_progress',
                        child: Text('В работе'),
                      ),
                      DropdownMenuItem(
                        value: 'in_review',
                        child: Text('На проверке'),
                      ),
                      DropdownMenuItem(value: 'done', child: Text('Выполнено')),
                      DropdownMenuItem(
                        value: 'archive',
                        child: Text('Архив'),
                      ),
                    ],
                    onChanged: (value) =>
                        setModalState(() => status = value ?? 'todo'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Общая задача'),
                    value: isFamily,
                    onChanged: forceFamily
                        ? null
                        : (value) => setModalState(() => isFamily = value),
                  ),
                  // Project selector
                  ValueListenableBuilder<List<TaskProject>>(
                    valueListenable: store.projects,
                    builder: (context, projectList, _) {
                      if (projectList.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return Column(
                        children: [
                          DropdownButtonFormField<String>(
                            // ignore: deprecated_member_use
                            value: projectList.any(
                                    (p) => p.id == selectedProjectId)
                                ? selectedProjectId
                                : null,
                            decoration: const InputDecoration(
                                labelText: 'Проект'),
                            hint: const Text('Без проекта'),
                            items: [
                              const DropdownMenuItem<String>(
                                value: '',
                                child: Text('Без проекта'),
                              ),
                              for (final p in projectList)
                                DropdownMenuItem<String>(
                                  value: p.id,
                                  child: Text(p.name),
                                ),
                            ],
                            onChanged: (value) {
                              setModalState(() {
                                selectedProjectId = value ?? '';
                                selectedGroupId = '';
                                selectedAssignees.clear();
                              });
                            },
                          ),
                          // Group selector — only show when a project is selected
                          if (selectedProjectId.isNotEmpty)
                            ValueListenableBuilder<
                                Map<String, List<String>>>(
                              valueListenable: store.projectGroupMap,
                              builder: (context, pgMap, _) {
                                return ValueListenableBuilder<
                                    List<FamilyGroup>>(
                                  valueListenable: store.familyGroups,
                                  builder: (context, groups, __) {
                                    final projectGroupIds =
                                        pgMap[selectedProjectId] ?? [];
                                    final projectGroups = groups
                                        .where((g) =>
                                            projectGroupIds.contains(g.id))
                                        .toList();
                                    if (projectGroups.isEmpty) {
                                      return const Padding(
                                        padding: EdgeInsets.only(top: 8),
                                        child: Text(
                                            'У проекта нет групп. Назначьте группы в настройках проекта.'),
                                      );
                                    }
                                    return DropdownButtonFormField<String>(
                                      // ignore: deprecated_member_use
                                      value: projectGroups.any((g) =>
                                              g.id == selectedGroupId)
                                          ? selectedGroupId
                                          : null,
                                      decoration: const InputDecoration(
                                          labelText: 'Группа'),
                                      hint: const Text('Выберите группу'),
                                      items: [
                                        for (final g in projectGroups)
                                          DropdownMenuItem<String>(
                                            value: g.id,
                                            child: Text(g.name),
                                          ),
                                      ],
                                      onChanged: (value) {
                                        setModalState(() {
                                          selectedGroupId = value ?? '';
                                          selectedAssignees.clear();
                                        });
                                      },
                                    );
                                  },
                                );
                              },
                            ),
                        ],
                      );
                    },
                  ),
                  if (isFamily) ...[
                    TextField(
                      controller: durationCtl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Длительность (мин)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Ответственные',
                      style: Theme.of(sheetContext).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    // When a group is selected, show only its members
                    ValueListenableBuilder<List<FamilyGroup>>(
                      valueListenable: store.familyGroups,
                      builder: (context, groups, _) {
                        final selectedGroup = selectedGroupId.isNotEmpty
                            ? groups.cast<FamilyGroup?>().firstWhere(
                                  (g) => g?.id == selectedGroupId,
                                  orElse: () => null,
                                )
                            : null;
                        final groupMembers =
                            selectedGroup?.members ?? <String>[];
                        final assigneeContacts = selectedGroup != null
                            ? knownContacts
                                .where((c) =>
                                    groupMembers.contains(c.profileKey))
                                .toList()
                            : knownContacts;

                        if (selectedGroup != null &&
                            assigneeContacts.isEmpty) {
                          return const Text(
                              'Участники группы не найдены в контактах');
                        }

                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: assigneeContacts.map((member) {
                            final profile = member.profileKey;
                            return FilterChip(
                              label: Text(contactLabel(member)),
                              selected:
                                  selectedAssignees.contains(profile),
                              onSelected: (selected) {
                                setModalState(() {
                                  if (selected) {
                                    selectedAssignees.add(profile);
                                  } else {
                                    selectedAssignees.remove(profile);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Напоминания',
                    style: Theme.of(sheetContext).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _reminderOptions.entries.map((entry) {
                      final offset = entry.key;
                      return FilterChip(
                        label: Text(entry.value),
                        selected: selectedReminderOffsets.contains(offset),
                        onSelected: (selected) {
                          setModalState(() {
                            if (selected) {
                              selectedReminderOffsets.add(offset);
                            } else {
                              selectedReminderOffsets.remove(offset);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          child: const Text('Отмена'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: () async {
                            final draft = TaskDraft(
                              title: titleCtl.text.trim(),
                              details: detailsCtl.text.trim(),
                              dueDate: dateKey(selected),
                              time: time,
                              priority: priority,
                              workflowStatus: status,
                              isFamily: isFamily,
                              assignees: selectedAssignees.toList(),
                              durationMinutes:
                                  int.tryParse(durationCtl.text.trim()) ?? 0,
                              reminderOffsetsMinutes:
                                  selectedReminderOffsets.toList(),
                              projectId: selectedProjectId,
                              groupId: selectedGroupId,
                            );
                            final messenger =
                                ScaffoldMessenger.of(sheetContext);
                            final error = await store.saveDraft(
                              draft: draft,
                              existing: existing,
                            );
                            if (!sheetContext.mounted) {
                              return;
                            }
                            if (error != null) {
                              messenger.showSnackBar(
                                SnackBar(content: Text(error)),
                              );
                              return;
                            }
                            Navigator.of(sheetContext).pop();
                            await onSaved();
                          },
                          child: const Text('Сохранить'),
                        ),
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
}
