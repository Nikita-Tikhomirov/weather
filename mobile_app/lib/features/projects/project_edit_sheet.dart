import 'package:flutter/material.dart';

import '../../models/family_group.dart';
import '../../models/task_project.dart';
import '../../state/task_store.dart';

Future<void> showProjectEditSheet({
  required BuildContext context,
  required TaskStore store,
  required bool isCreate,
  TaskProject? project,
  List<String>? initialGroupIds,
}) async {
  final nameCtl =
      TextEditingController(text: isCreate ? '' : project?.name ?? '');
  final descCtl =
      TextEditingController(text: isCreate ? '' : project?.description ?? '');
  final selectedGroupIds = <String>{
    ...(initialGroupIds ?? const <String>[]),
  };

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (sheetContext, setModalState) {
          return ValueListenableBuilder<List<FamilyGroup>>(
            valueListenable: store.familyGroups,
            builder: (context, groups, _) {
              return Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 8,
                  bottom:
                      MediaQuery.of(sheetContext).viewInsets.bottom + 16,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isCreate ? 'Новый проект' : 'Редактировать проект',
                        style: Theme.of(sheetContext).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameCtl,
                        decoration:
                            const InputDecoration(labelText: 'Название'),
                      ),
                      TextField(
                        controller: descCtl,
                        decoration:
                            const InputDecoration(labelText: 'Описание'),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      if (groups.isNotEmpty) ...[
                        Text(
                          'Семейные группы',
                          style: Theme.of(sheetContext).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: groups.map((group) {
                            return FilterChip(
                              label: Text(group.name),
                              selected:
                                  selectedGroupIds.contains(group.id),
                              onSelected: (selected) {
                                setModalState(() {
                                  if (selected) {
                                    selectedGroupIds.add(group.id);
                                  } else {
                                    selectedGroupIds.remove(group.id);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ],
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
                                  ScaffoldMessenger.of(sheetContext)
                                      .showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Введите название проекта')),
                                  );
                                  return;
                                }
                                if (isCreate) {
                                  await store.createProject(
                                      name, descCtl.text.trim());
                                } else {
                                  await store.editProject(
                                    project!.id,
                                    name,
                                    descCtl.text.trim(),
                                    selectedGroupIds.toList(),
                                  );
                                }
                                if (sheetContext.mounted) {
                                  Navigator.pop(sheetContext);
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
    },
  );
}
