import 'package:flutter/material.dart';

import '../../domain/task_draft.dart';
import '../../models/chat_models.dart';
import '../../models/task_item.dart';
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
                    initialValue: priority,
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
                    initialValue: status,
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
                    ],
                    onChanged: (value) =>
                        setModalState(() => status = value ?? 'todo'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Семейная задача'),
                    value: isFamily,
                    onChanged: forceFamily
                        ? null
                        : (value) => setModalState(() => isFamily = value),
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
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: knownContacts.map((member) {
                        final profile = member.profileKey;
                        return FilterChip(
                          label: Text(contactLabel(member)),
                          selected: selectedAssignees.contains(profile),
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
