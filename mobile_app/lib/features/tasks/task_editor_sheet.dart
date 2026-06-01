import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../domain/task_draft.dart';
import '../../models/chat_models.dart';
import '../../models/family_group.dart';
import '../../models/task_collaboration.dart';
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
}) async {
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => TaskEditorScreen(
        store: store,
        knownContacts: knownContacts,
        contactLabel: contactLabel,
        dateKey: dateKey,
        onSaved: onSaved,
        existing: existing,
      ),
    ),
  );
}

class TaskEditorScreen extends StatefulWidget {
  const TaskEditorScreen({
    super.key,
    required this.store,
    required this.knownContacts,
    required this.contactLabel,
    required this.dateKey,
    required this.onSaved,
    this.existing,
  });

  final TaskStore store;
  final List<ChatContact> knownContacts;
  final String Function(ChatContact contact) contactLabel;
  final String Function(DateTime value) dateKey;
  final Future<void> Function() onSaved;
  final TaskItem? existing;

  @override
  State<TaskEditorScreen> createState() => _TaskEditorScreenState();
}

class _TaskEditorScreenState extends State<TaskEditorScreen> {
  late final TextEditingController _titleCtl;
  late final TextEditingController _detailsCtl;
  late final TextEditingController _durationCtl;
  late final TextEditingController _commentCtl;
  late final TextEditingController _checklistTitleCtl;
  final Map<String, TextEditingController> _checklistItemControllers = {};

  late final List<TaskProject> _projectList;
  late final List<FamilyGroup> _groups;
  late final Map<String, List<String>> _projectGroupMap;
  late final Set<String> _selectedAssignees;
  late final Set<int> _selectedReminderOffsets;
  late DateTime _selectedDate;
  late String _time;
  late Priority _priority;
  late WorkflowStatus _status;
  late String _selectedProjectId;
  late String _selectedGroupId;
  late TaskCollaboration _collaboration;
  final List<TaskAttachment> _pendingAttachments = [];

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _titleCtl = TextEditingController(text: existing?.title ?? '');
    _detailsCtl = TextEditingController(text: existing?.details ?? '');
    _durationCtl = TextEditingController(
      text: existing == null ? '' : existing.durationMinutes.toString(),
    );
    _commentCtl = TextEditingController();
    _checklistTitleCtl = TextEditingController();
    _projectList = List<TaskProject>.from(widget.store.projects.value);
    _groups = List<FamilyGroup>.from(widget.store.familyGroups.value);
    _projectGroupMap = Map<String, List<String>>.from(
      widget.store.projectGroupMap.value,
    );
    _selectedAssignees = <String>{
      ...(existing?.assignees ?? const <String>[]),
    };
    _selectedReminderOffsets = <int>{
      ...(existing?.reminderOffsetsMinutes ?? const <int>[]),
    };
    _selectedDate = existing == null
        ? widget.store.selectedDate.value
        : DateTime.tryParse(existing.dueDate) ??
            widget.store.selectedDate.value;
    _time = existing?.time ?? '19:00';
    _priority = existing?.priority ?? Priority.medium;
    _status = existing?.workflowStatus ?? WorkflowStatus.todo;
    _selectedProjectId =
        existing?.projectId ?? widget.store.currentProjectId.value;
    _selectedGroupId = existing?.groupId ?? '';
    _collaboration = existing?.collaboration ?? const TaskCollaboration();
    _normalizeProjectSelection();
  }

  @override
  void dispose() {
    _titleCtl.dispose();
    _detailsCtl.dispose();
    _durationCtl.dispose();
    _commentCtl.dispose();
    _checklistTitleCtl.dispose();
    for (final controller in _checklistItemControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _canEdit {
    if (widget.existing == null) return true;
    final actor = widget.store.owner.value;
    final task = widget.existing!;
    if (task.assignees.contains(actor)) return true;
    if (_projectOwnerKey(task.projectId) == actor) return true;
    if (task.groupId.isEmpty) return false;
    return _groups.any(
      (group) => group.id == task.groupId && group.members.contains(actor),
    );
  }

  List<FamilyGroup> _groupsForProject(String projectId) {
    final ids = _projectGroupMap[projectId] ?? const <String>[];
    return _groups.where((group) => ids.contains(group.id)).toList();
  }

  void _normalizeProjectSelection() {
    if (_selectedProjectId.isNotEmpty &&
        !_projectList.any((project) => project.id == _selectedProjectId)) {
      _selectedProjectId = '';
    }
    final projectGroups = _groupsForProject(_selectedProjectId);
    if (_selectedProjectId.isEmpty) {
      _selectedGroupId = '';
      return;
    }
    if (!projectGroups.any((group) => group.id == _selectedGroupId)) {
      _selectedGroupId =
          projectGroups.length == 1 ? projectGroups.first.id : '';
    }
    if (_selectedGroupId.isNotEmpty) {
      final members = projectGroups
          .firstWhere((group) => group.id == _selectedGroupId)
          .members
          .toSet();
      _selectedAssignees.removeWhere((assignee) => !members.contains(assignee));
    }
  }

  String _projectOwnerKey(String projectId) {
    if (projectId.isEmpty) return '';
    final project = _projectList.cast<TaskProject?>().firstWhere(
          (item) => item?.id == projectId,
          orElse: () => null,
        );
    return project?.ownerKey ?? '';
  }

  TaskDraft _buildDraft() {
    return TaskDraft(
      title: _titleCtl.text.trim(),
      details: _detailsCtl.text.trim(),
      dueDate: widget.dateKey(_selectedDate),
      time: _time,
      priority: _priority,
      workflowStatus: _status,
      isFamily: true,
      assignees: _selectedAssignees.toList(),
      durationMinutes: int.tryParse(_durationCtl.text.trim()) ?? 0,
      reminderOffsetsMinutes: _selectedReminderOffsets.toList(),
      projectId: _selectedProjectId,
      groupId: _selectedGroupId,
      collaboration: _collaboration,
    );
  }

  Future<void> _save() async {
    if (_saving || !_canEdit) return;
    if (_selectedProjectId.isEmpty) {
      _showSnack('Выберите проект');
      return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final error = await widget.store.saveDraft(
      draft: _buildDraft(),
      existing: widget.existing,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    Navigator.of(context).pop();
    await widget.onSaved();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _newId(String prefix) {
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}';
  }

  TaskActivityEntry _activity({
    required String type,
    required String text,
    String targetId = '',
  }) {
    final now = DateTime.now().toIso8601String();
    return TaskActivityEntry(
      id: _newId('activity'),
      type: type,
      actorProfile: widget.store.owner.value,
      text: text,
      createdAt: now,
      targetId: targetId,
    );
  }

  void _sendComment() {
    if (!_canEdit) return;
    final text = _commentCtl.text.trim();
    if (text.isEmpty && _pendingAttachments.isEmpty) {
      return;
    }
    final now = DateTime.now().toIso8601String();
    final attachments = _pendingAttachments
        .map((item) => item.copyWith(caption: text, createdAt: now))
        .toList();
    final comment = TaskComment(
      id: _newId('comment'),
      authorProfile: widget.store.owner.value,
      text: text,
      createdAt: now,
      attachmentIds: attachments.map((item) => item.id).toList(),
    );
    setState(() {
      _collaboration = _collaboration.copyWith(
        comments: [..._collaboration.comments, comment],
        attachments: [..._collaboration.attachments, ...attachments],
        activity: [
          ..._collaboration.activity,
          _activity(
            type: 'comment_added',
            text: attachments.isEmpty
                ? 'добавил комментарий'
                : 'добавил комментарий с вложением',
            targetId: comment.id,
          ),
        ],
      );
      _pendingAttachments.clear();
      _commentCtl.clear();
    });
  }

  Future<void> _pickPhoto() async {
    if (!_canEdit) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 1600,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _pendingAttachments.add(
        TaskAttachment(
          id: _newId('att'),
          kind: 'photo',
          filename: picked.name,
          mimeType: picked.mimeType ?? 'image/jpeg',
          dataBase64: base64Encode(bytes),
          authorProfile: widget.store.owner.value,
          createdAt: DateTime.now().toIso8601String(),
          sizeBytes: bytes.length,
        ),
      );
    });
  }

  Future<void> _pickFile() async {
    if (!_canEdit) return;
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) {
      if (mounted) _showSnack('Не удалось прочитать файл');
      return;
    }
    if (!mounted) return;
    setState(() {
      _pendingAttachments.add(
        TaskAttachment(
          id: _newId('att'),
          kind: 'file',
          filename: file.name,
          mimeType: 'application/octet-stream',
          dataBase64: base64Encode(bytes),
          authorProfile: widget.store.owner.value,
          createdAt: DateTime.now().toIso8601String(),
          sizeBytes: bytes.length,
        ),
      );
    });
  }

  void _removePendingAttachment(String id) {
    setState(() => _pendingAttachments.removeWhere((item) => item.id == id));
  }

  void _addChecklist() {
    if (!_canEdit) return;
    final title = _checklistTitleCtl.text.trim();
    if (title.isEmpty) return;
    final checklist = TaskChecklist(
      id: _newId('checklist'),
      title: title,
      createdBy: widget.store.owner.value,
      createdAt: DateTime.now().toIso8601String(),
    );
    setState(() {
      _collaboration = _collaboration.copyWith(
        checklists: [..._collaboration.checklists, checklist],
        activity: [
          ..._collaboration.activity,
          _activity(
            type: 'checklist_added',
            text: 'создал чеклист "$title"',
            targetId: checklist.id,
          ),
        ],
      );
      _checklistTitleCtl.clear();
    });
  }

  TextEditingController _itemControllerFor(String checklistId) {
    return _checklistItemControllers.putIfAbsent(
      checklistId,
      TextEditingController.new,
    );
  }

  void _addChecklistItem(String checklistId) {
    if (!_canEdit) return;
    final controller = _itemControllerFor(checklistId);
    final text = controller.text.trim();
    if (text.isEmpty) return;
    final nextChecklists = _collaboration.checklists.map((checklist) {
      if (checklist.id != checklistId) return checklist;
      return checklist.copyWith(
        items: [
          ...checklist.items,
          TaskChecklistItem(
            id: _newId('check-item'),
            text: text,
            createdBy: widget.store.owner.value,
            createdAt: DateTime.now().toIso8601String(),
          ),
        ],
      );
    }).toList();
    setState(() {
      _collaboration = _collaboration.copyWith(
        checklists: nextChecklists,
        activity: [
          ..._collaboration.activity,
          _activity(
            type: 'checklist_item_added',
            text: 'добавил пункт "$text"',
            targetId: checklistId,
          ),
        ],
      );
      controller.clear();
    });
  }

  void _toggleChecklistItem(String checklistId, String itemId, bool done) {
    if (!_canEdit) return;
    final now = DateTime.now().toIso8601String();
    final nextChecklists = _collaboration.checklists.map((checklist) {
      if (checklist.id != checklistId) return checklist;
      return checklist.copyWith(
        items: checklist.items.map((item) {
          if (item.id != itemId) return item;
          return item.copyWith(
            done: done,
            completedBy: done ? widget.store.owner.value : '',
            completedAt: done ? now : '',
          );
        }).toList(),
      );
    }).toList();
    setState(() {
      _collaboration = _collaboration.copyWith(
        checklists: nextChecklists,
        activity: [
          ..._collaboration.activity,
          _activity(
            type: done ? 'checklist_item_done' : 'checklist_item_reopened',
            text: done ? 'закрыл пункт чеклиста' : 'вернул пункт чеклиста',
            targetId: itemId,
          ),
        ],
      );
    });
  }

  void _openPhoto(TaskAttachment attachment) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PhotoViewer(attachment: attachment),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title =
        widget.existing == null ? 'Новая задача' : 'Редактирование задачи';
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.tune), text: 'Настройки'),
              Tab(icon: Icon(Icons.forum_outlined), text: 'Работа'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Сохранить',
              onPressed: _saving || !_canEdit ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
            ),
          ],
        ),
        body: TabBarView(
          children: [
            _buildSettingsTab(),
            _buildWorkTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsTab() {
    final projectGroups = _groupsForProject(_selectedProjectId);
    final selectedGroup = _selectedGroupId.isNotEmpty
        ? projectGroups.cast<FamilyGroup?>().firstWhere(
              (group) => group?.id == _selectedGroupId,
              orElse: () => null,
            )
        : null;
    final selectedGroupMembers = selectedGroup?.members.toSet() ?? const {};
    final assigneeContacts = selectedGroup != null
        ? widget.knownContacts
            .where(
              (contact) => selectedGroupMembers.contains(contact.profileKey),
            )
            .toList()
        : widget.knownContacts
            .where((contact) => contact.profileKey.isNotEmpty)
            .toList();
    final isProjectTask = _selectedProjectId.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        TextField(
          controller: _titleCtl,
          enabled: _canEdit,
          decoration: const InputDecoration(labelText: 'Название'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _projectList.any((p) => p.id == _selectedProjectId)
              ? _selectedProjectId
              : null,
          decoration: const InputDecoration(labelText: 'Проект *'),
          hint: const Text('Выберите проект'),
          items: [
            for (final project in _projectList)
              DropdownMenuItem<String>(
                value: project.id,
                child: Text(project.name),
              ),
          ],
          onChanged: !_canEdit
              ? null
              : (value) {
                  setState(() {
                    _selectedProjectId = value ?? '';
                    _selectedGroupId = '';
                    _selectedAssignees.clear();
                    _normalizeProjectSelection();
                  });
                },
        ),
        if (isProjectTask) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey('task-group-$_selectedProjectId'),
            initialValue:
                projectGroups.any((group) => group.id == _selectedGroupId)
                    ? _selectedGroupId
                    : null,
            decoration: const InputDecoration(labelText: 'Группа'),
            hint: const Text('Выберите группу'),
            items: [
              for (final group in projectGroups)
                DropdownMenuItem<String>(
                  value: group.id,
                  child: Text(group.name),
                ),
            ],
            onChanged: !_canEdit || projectGroups.isEmpty
                ? null
                : (value) {
                    setState(() {
                      _selectedGroupId = value ?? '';
                      final nextGroup = _selectedGroupId.isNotEmpty
                          ? projectGroups.cast<FamilyGroup?>().firstWhere(
                                (group) => group?.id == _selectedGroupId,
                                orElse: () => null,
                              )
                          : null;
                      final members =
                          nextGroup?.members.toSet() ?? const <String>{};
                      if (members.isNotEmpty) {
                        _selectedAssignees.removeWhere(
                          (assignee) => !members.contains(assignee),
                        );
                      } else {
                        _selectedAssignees.clear();
                      }
                    });
                  },
          ),
          if (projectGroups.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('У проекта нет групп.'),
            ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_month),
                label: Text(widget.dateKey(_selectedDate)),
                onPressed: !_canEdit
                    ? null
                    : () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate,
                          firstDate: DateTime(2024),
                          lastDate: DateTime(2035),
                        );
                        if (picked != null) {
                          setState(() => _selectedDate = picked);
                        }
                      },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.schedule),
                label: Text(_time),
                onPressed: !_canEdit
                    ? null
                    : () async {
                        final parts = _time.split(':');
                        final initial = TimeOfDay(
                          hour: int.tryParse(parts.first) ?? 19,
                          minute: int.tryParse(
                                parts.length > 1 ? parts[1] : '0',
                              ) ??
                              0,
                        );
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: initial,
                        );
                        if (picked != null) {
                          setState(() {
                            _time =
                                '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                          });
                        }
                      },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<Priority>(
          initialValue: _priority,
          decoration: const InputDecoration(labelText: 'Приоритет'),
          items: const [
            DropdownMenuItem(value: Priority.low, child: Text('Низкий')),
            DropdownMenuItem(value: Priority.medium, child: Text('Средний')),
            DropdownMenuItem(value: Priority.high, child: Text('Высокий')),
          ],
          onChanged: !_canEdit
              ? null
              : (value) => setState(() => _priority = value ?? Priority.medium),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<WorkflowStatus>(
          initialValue: _status,
          decoration: const InputDecoration(labelText: 'Статус'),
          items: const [
            DropdownMenuItem(
              value: WorkflowStatus.todo,
              child: Text('К выполнению'),
            ),
            DropdownMenuItem(
              value: WorkflowStatus.in_progress,
              child: Text('В работе'),
            ),
            DropdownMenuItem(
              value: WorkflowStatus.in_review,
              child: Text('На проверке'),
            ),
            DropdownMenuItem(
              value: WorkflowStatus.done,
              child: Text('Выполнено'),
            ),
            DropdownMenuItem(
              value: WorkflowStatus.archive,
              child: Text('Архив'),
            ),
          ],
          onChanged: !_canEdit
              ? null
              : (value) =>
                  setState(() => _status = value ?? WorkflowStatus.todo),
        ),
        const SizedBox(height: 16),
        Text('Ответственные', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (isProjectTask && selectedGroup == null)
          const Text('Выберите группу проекта.')
        else if (selectedGroup != null && assigneeContacts.isEmpty)
          const Text('Участники группы не найдены в контактах.')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: assigneeContacts.map((member) {
              final profile = member.profileKey;
              return FilterChip(
                label: Text(widget.contactLabel(member)),
                selected: _selectedAssignees.contains(profile),
                onSelected: !_canEdit
                    ? null
                    : (selected) {
                        setState(() {
                          if (selected) {
                            _selectedAssignees.add(profile);
                          } else {
                            _selectedAssignees.remove(profile);
                          }
                        });
                      },
              );
            }).toList(),
          ),
        const SizedBox(height: 16),
        Text('Напоминания', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _reminderOptions.entries.map((entry) {
            final offset = entry.key;
            return FilterChip(
              label: Text(entry.value),
              selected: _selectedReminderOffsets.contains(offset),
              onSelected: !_canEdit
                  ? null
                  : (selected) {
                      setState(() {
                        if (selected) {
                          _selectedReminderOffsets.add(offset);
                        } else {
                          _selectedReminderOffsets.remove(offset);
                        }
                      });
                    },
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _durationCtl,
          enabled: _canEdit,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Оценка времени (мин)'),
        ),
      ],
    );
  }

  Widget _buildWorkTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        _CollaborationSummary(collaboration: _collaboration),
        const SizedBox(height: 14),
        TextField(
          controller: _detailsCtl,
          enabled: _canEdit,
          minLines: 3,
          maxLines: 7,
          decoration: const InputDecoration(
            labelText: 'Описание',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 18),
        _SectionHeader(
          icon: Icons.forum_outlined,
          title: 'Комментарии',
          trailing: '${_collaboration.commentCount}',
        ),
        const SizedBox(height: 10),
        if (_collaboration.comments.isEmpty)
          const _EmptyLine(
            icon: Icons.chat_bubble_outline,
            text: 'Комментариев нет',
          )
        else
          ..._collaboration.comments.map(
            (comment) => _CommentBubble(
              comment: comment,
              attachments: _collaboration.attachmentsFor(comment),
              owner: widget.store.owner.value,
              labelFor: _profileLabel,
              onPhotoTap: _openPhoto,
            ),
          ),
        const SizedBox(height: 8),
        if (_pendingAttachments.isNotEmpty)
          _PendingAttachments(
            items: _pendingAttachments,
            onRemove: _removePendingAttachment,
          ),
        _CommentComposer(
          controller: _commentCtl,
          enabled: _canEdit,
          onPickPhoto: _pickPhoto,
          onPickFile: _pickFile,
          onSend: _sendComment,
        ),
        const SizedBox(height: 22),
        _SectionHeader(
          icon: Icons.checklist,
          title: 'Чеклисты',
          trailing:
              '${_collaboration.checklistDoneCount}/${_collaboration.checklistTotalCount}',
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _checklistTitleCtl,
                enabled: _canEdit,
                decoration: const InputDecoration(labelText: 'Новый чеклист'),
                onSubmitted: (_) => _addChecklist(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Добавить чеклист',
              onPressed: _canEdit ? _addChecklist : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_collaboration.checklists.isEmpty)
          const _EmptyLine(
            icon: Icons.playlist_add_check,
            text: 'Чеклистов нет',
          )
        else
          ..._collaboration.checklists.map(
            (checklist) => _ChecklistPanel(
              checklist: checklist,
              enabled: _canEdit,
              itemController: _itemControllerFor(checklist.id),
              onAddItem: () => _addChecklistItem(checklist.id),
              onToggleItem: (item, done) =>
                  _toggleChecklistItem(checklist.id, item.id, done),
            ),
          ),
        const SizedBox(height: 22),
        _SectionHeader(
          icon: Icons.history,
          title: 'Активность',
          trailing: '${_collaboration.activity.length}',
        ),
        const SizedBox(height: 10),
        if (_collaboration.activity.isEmpty)
          const _EmptyLine(icon: Icons.bolt_outlined, text: 'Пока пусто')
        else
          ..._collaboration.activity.reversed.take(12).map(
                (entry) => _ActivityRow(
                  entry: entry,
                  labelFor: _profileLabel,
                ),
              ),
      ],
    );
  }

  String _profileLabel(String profile) {
    final contact = widget.knownContacts.cast<ChatContact?>().firstWhere(
          (item) => item?.profileKey == profile,
          orElse: () => null,
        );
    if (contact != null) {
      return widget.contactLabel(contact);
    }
    return profile.isEmpty ? 'Пользователь' : profile;
  }
}

class _CollaborationSummary extends StatelessWidget {
  const _CollaborationSummary({required this.collaboration});

  final TaskCollaboration collaboration;

  @override
  Widget build(BuildContext context) {
    final progress = collaboration.checklistTotalCount == 0
        ? '0/0'
        : '${collaboration.checklistDoneCount}/${collaboration.checklistTotalCount}';
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _MetricChip(
          icon: Icons.chat_bubble_outline,
          text: '${collaboration.commentCount}',
        ),
        _MetricChip(
          icon: Icons.attachment,
          text: '${collaboration.attachmentCount}',
        ),
        _MetricChip(icon: Icons.checklist, text: progress),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(text),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        Text(
          trailing,
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
      ],
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

class _CommentComposer extends StatelessWidget {
  const _CommentComposer({
    required this.controller,
    required this.enabled,
    required this.onPickPhoto,
    required this.onPickFile,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onPickPhoto;
  final VoidCallback onPickFile;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            tooltip: 'Фото',
            onPressed: enabled ? onPickPhoto : null,
            icon: const Icon(Icons.image_outlined),
          ),
          IconButton(
            tooltip: 'Файл',
            onPressed: enabled ? onPickFile : null,
            icon: const Icon(Icons.attach_file),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: 'Комментарий или подпись',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(24)),
                ),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Отправить',
            onPressed: enabled ? onSend : null,
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}

class _PendingAttachments extends StatelessWidget {
  const _PendingAttachments({required this.items, required this.onRemove});

  final List<TaskAttachment> items;
  final void Function(String id) onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: items.map((item) {
          return InputChip(
            avatar: Icon(item.isPhoto ? Icons.image_outlined : Icons.file_copy),
            label: Text(
              item.filename,
              overflow: TextOverflow.ellipsis,
            ),
            onDeleted: () => onRemove(item.id),
          );
        }).toList(),
      ),
    );
  }
}

class _CommentBubble extends StatelessWidget {
  const _CommentBubble({
    required this.comment,
    required this.attachments,
    required this.owner,
    required this.labelFor,
    required this.onPhotoTap,
  });

  final TaskComment comment;
  final List<TaskAttachment> attachments;
  final String owner;
  final String Function(String profile) labelFor;
  final void Function(TaskAttachment attachment) onPhotoTap;

  @override
  Widget build(BuildContext context) {
    final mine = comment.authorProfile == owner;
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: mine ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              labelFor(comment.authorProfile),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: cs.primary,
              ),
            ),
            if (comment.text.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(comment.text),
            ],
            if (attachments.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...attachments.map(
                (attachment) => _AttachmentPreview(
                  attachment: attachment,
                  onPhotoTap: onPhotoTap,
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              _shortDateTime(comment.createdAt),
              style: TextStyle(fontSize: 11, color: cs.outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({
    required this.attachment,
    required this.onPhotoTap,
  });

  final TaskAttachment attachment;
  final void Function(TaskAttachment attachment) onPhotoTap;

  @override
  Widget build(BuildContext context) {
    if (attachment.isPhoto) {
      return GestureDetector(
        onTap: () => onPhotoTap(attachment),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              base64Decode(attachment.dataBase64),
              width: 168,
              height: 112,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox(
                width: 168,
                height: 112,
                child: Center(child: Icon(Icons.broken_image_outlined)),
              ),
            ),
          ),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insert_drive_file_outlined, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              attachment.filename,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChecklistPanel extends StatelessWidget {
  const _ChecklistPanel({
    required this.checklist,
    required this.enabled,
    required this.itemController,
    required this.onAddItem,
    required this.onToggleItem,
  });

  final TaskChecklist checklist;
  final bool enabled;
  final TextEditingController itemController;
  final VoidCallback onAddItem;
  final void Function(TaskChecklistItem item, bool done) onToggleItem;

  @override
  Widget build(BuildContext context) {
    final progress = checklist.totalCount == 0
        ? 0.0
        : checklist.doneCount / checklist.totalCount;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  checklist.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Text('${checklist.doneCount}/${checklist.totalCount}'),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 8),
          for (final item in checklist.items)
            CheckboxListTile(
              value: item.done,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                item.text,
                style: TextStyle(
                  decoration: item.done
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                ),
              ),
              onChanged: enabled
                  ? (value) => onToggleItem(item, value ?? false)
                  : null,
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: itemController,
                  enabled: enabled,
                  decoration: const InputDecoration(labelText: 'Пункт'),
                  onSubmitted: (_) => onAddItem(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Добавить пункт',
                onPressed: enabled ? onAddItem : null,
                icon: const Icon(Icons.add_task),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry, required this.labelFor});

  final TaskActivityEntry entry;
  final String Function(String profile) labelFor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.bolt_outlined,
            size: 18,
            color: Theme.of(context).hintColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${labelFor(entry.actorProfile)} ${entry.text}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _shortDateTime(entry.createdAt),
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoViewer extends StatelessWidget {
  const _PhotoViewer({required this.attachment});

  final TaskAttachment attachment;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          attachment.filename,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.memory(
            base64Decode(attachment.dataBase64),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.broken_image_outlined,
              color: Colors.white,
              size: 48,
            ),
          ),
        ),
      ),
    );
  }
}

String _shortDateTime(String raw) {
  final value = DateTime.tryParse(raw);
  if (value == null) return raw;
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$day.$month $hour:$minute';
}
