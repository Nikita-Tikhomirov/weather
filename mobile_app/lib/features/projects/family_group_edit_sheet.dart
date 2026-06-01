import 'package:flutter/material.dart';

import '../../models/chat_models.dart';
import '../../models/family_group.dart';
import '../../state/task_store.dart';

Future<void> showFamilyGroupEditSheet({
  required BuildContext context,
  required TaskStore store,
  required bool isCreate,
  FamilyGroup? group,
  required List<ChatContact> contacts,
  required String Function(ChatContact) contactLabel,
  String? actorProfile,
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
      // Ensure the current actor can select themselves
      final selfKey = actorProfile ?? store.owner.value;
      final hasSelf = contacts.any((c) => c.profileKey == selfKey);
      final effectiveContacts = hasSelf
          ? contacts
          : [
              ChatContact(
                profileKey: selfKey,
                displayName: selfKey,
                phone: '',
                conversationKey: '',
              ),
              ...contacts,
            ];
      final availableContacts =
          effectiveContacts.where((c) => c.profileKey.isNotEmpty).toList();

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
              // ── TextField manages its own state via controller ──
              TextField(
                controller: nameCtl,
                decoration: const InputDecoration(labelText: 'Название группы'),
              ),
              const SizedBox(height: 12),
              Text(
                'Участники',
                style: Theme.of(sheetContext).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              if (availableContacts.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child:
                      Text('Нет контактов. Добавьте контакты в мессенджере.'),
                ),
              // ── StatefulBuilder only for FilterChips ──
              StatefulBuilder(
                builder: (_, setModalState) {
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: availableContacts.map((contact) {
                      final profile = contact.profileKey;
                      return FilterChip(
                        label: Text(contactLabel(contact)),
                        selected: selectedMembers.contains(profile),
                        onSelected: (selected) {
                          setModalState(() {
                            if (selected) {
                              selectedMembers.add(profile);
                            } else {
                              selectedMembers.remove(profile);
                            }
                          });
                        },
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 12),
              // ── Save/Cancel outside StatefulBuilder ──
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
                              content: Text('Введите название группы'),
                            ),
                          );
                          return;
                        }
                        if (selectedMembers.isEmpty) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            const SnackBar(
                              content:
                                  Text('Выберите хотя бы одного участника'),
                            ),
                          );
                          return;
                        }
                        try {
                          if (isCreate) {
                            await store.createFamilyGroup(
                              name,
                              selectedMembers.toList(),
                            );
                          } else {
                            await store.editFamilyGroup(
                              group!.id,
                              name,
                              selectedMembers.toList(),
                            );
                          }
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext);
                          }
                        } catch (e) {
                          if (sheetContext.mounted) {
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Ошибка: ${e.toString().replaceFirst("Exception: ", "")}',
                                ),
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
}
