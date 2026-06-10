import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/chat_models.dart';
import '../../models/family_group.dart';
import '../../state/task_store.dart';

class _FamilyGroupEditSheetText {
  const _FamilyGroupEditSheetText(this.l10n);

  final AppLocalizations? l10n;

  String get newGroup => l10n?.newGroup ?? 'Новая группа';
  String get editGroup => l10n?.editGroup ?? 'Редактировать группу';
  String get groupNameLabel => l10n?.groupNameLabel ?? 'Название группы';
  String get participants => l10n?.participants ?? 'Участники';
  String get noContacts =>
      l10n?.noContacts ?? 'Нет контактов. Добавьте контакты в мессенджере.';
  String get cancel => l10n?.cancel ?? 'Отмена';
  String get create => l10n?.create ?? 'Создать';
  String get save => l10n?.save ?? 'Сохранить';
  String get groupNameRequired =>
      l10n?.groupNameRequired ?? 'Введите название группы';
  String get groupMemberRequired =>
      l10n?.groupMemberRequired ?? 'Выберите хотя бы одного участника';

  String groupSaveFailed(Object error) {
    return l10n?.groupSaveFailed(error.toString()) ?? 'Ошибка: $error';
  }
}

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
  final text = _FamilyGroupEditSheetText(AppLocalizations.of(context));

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
                isCreate ? text.newGroup : text.editGroup,
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              // ── TextField manages its own state via controller ──
              TextField(
                controller: nameCtl,
                decoration: InputDecoration(labelText: text.groupNameLabel),
              ),
              const SizedBox(height: 12),
              Text(
                text.participants,
                style: Theme.of(sheetContext).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              if (availableContacts.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(text.noContacts),
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
                      child: Text(text.cancel),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        final name = nameCtl.text.trim();
                        if (name.isEmpty) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            SnackBar(
                              content: Text(text.groupNameRequired),
                            ),
                          );
                          return;
                        }
                        if (selectedMembers.isEmpty) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            SnackBar(
                              content: Text(text.groupMemberRequired),
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
                                  text.groupSaveFailed(
                                    e.toString().replaceFirst(
                                          'Exception: ',
                                          '',
                                        ),
                                  ),
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                      child: Text(isCreate ? text.create : text.save),
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
