import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/family_group.dart';
import '../../models/task_project.dart';
import '../../state/task_store.dart';

class _ProjectEditSheetText {
  const _ProjectEditSheetText(this.l10n);

  final AppLocalizations? l10n;

  String get newProject => l10n?.newProject ?? 'New project';
  String get editProject => l10n?.editProject ?? 'Edit project';
  String get projectNameLabel => l10n?.projectNameLabel ?? 'Project name';
  String get description => l10n?.description ?? 'Description';
  String get groups => l10n?.groups ?? 'Groups';
  String get cancel => l10n?.cancel ?? 'Cancel';
  String get create => l10n?.create ?? 'Create';
  String get save => l10n?.save ?? 'Save';
  String get projectNameRequired =>
      l10n?.projectNameRequired ?? 'Enter project name';

  String projectSaveFailed(Object error) {
    return l10n?.projectSaveFailed(error.toString()) ?? 'Error: $error';
  }
}

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
  final text = _ProjectEditSheetText(AppLocalizations.of(context));

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
                  bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isCreate ? text.newProject : text.editProject,
                        style: Theme.of(sheetContext).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameCtl,
                        decoration:
                            InputDecoration(labelText: text.projectNameLabel),
                      ),
                      TextField(
                        controller: descCtl,
                        decoration:
                            InputDecoration(labelText: text.description),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      if (groups.isNotEmpty) ...[
                        Text(
                          text.groups,
                          style: Theme.of(sheetContext).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: groups.map((group) {
                            return FilterChip(
                              label: Text(group.name),
                              selected: selectedGroupIds.contains(group.id),
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
                              child: Text(text.cancel),
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
                                    SnackBar(
                                      content: Text(text.projectNameRequired),
                                    ),
                                  );
                                  return;
                                }
                                try {
                                  if (isCreate) {
                                    await store.createProjectWithGroups(
                                      name,
                                      descCtl.text.trim(),
                                      selectedGroupIds.toList(),
                                    );
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
                                } catch (e) {
                                  if (sheetContext.mounted) {
                                    ScaffoldMessenger.of(sheetContext)
                                        .showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          text.projectSaveFailed(
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
        },
      );
    },
  );
}
