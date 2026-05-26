import 'package:flutter/material.dart';

import '../../models/family_group.dart';
import '../../state/task_store.dart';

const _knownMembers = ['nik', 'nastya', 'misha', 'arisha'];
const _memberLabels = {
  'nik': 'Ник',
  'nastya': 'Настя',
  'misha': 'Миша',
  'arisha': 'Ариша',
};

Future<void> showFamilyGroupEditSheet({
  required BuildContext context,
  required TaskStore store,
  required bool isCreate,
  FamilyGroup? group,
}) async {
  final nameCtl =
      TextEditingController(text: isCreate ? '' : group?.name ?? '');
  final selectedMembers = <String>{
    ...(isCreate ? const <String>{} : group?.members ?? const <String>[]),
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isCreate ? 'Новая группа' : 'Редактировать группу',
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtl,
                    decoration:
                        const InputDecoration(labelText: 'Название группы'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Участники',
                    style: Theme.of(sheetContext).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _knownMembers.map((member) {
                      return FilterChip(
                        label:
                            Text(_memberLabels[member] ?? member),
                        selected: selectedMembers.contains(member),
                        onSelected: (selected) {
                          setModalState(() {
                            if (selected) {
                              selectedMembers.add(member);
                            } else {
                              selectedMembers.remove(member);
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
                            final name = nameCtl.text.trim();
                            if (name.isEmpty) {
                              ScaffoldMessenger.of(sheetContext).showSnackBar(
                                const SnackBar(
                                    content: Text('Введите название группы')),
                              );
                              return;
                            }
                            if (selectedMembers.isEmpty) {
                              ScaffoldMessenger.of(sheetContext).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('Выберите хотя бы одного участника')),
                              );
                              return;
                            }
                            try {
                              if (isCreate) {
                                await store.createFamilyGroup(
                                    name, selectedMembers.toList());
                              } else {
                                await store.editFamilyGroup(
                                    group!.id, name, selectedMembers.toList());
                              }
                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext);
                              }
                            } catch (e) {
                              if (sheetContext.mounted) {
                                ScaffoldMessenger.of(sheetContext).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        'Ошибка: ${e.toString().replaceFirst("Exception: ", "")}'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          child: Text(isCreate ? 'Создать' : 'Сохранить'),
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
