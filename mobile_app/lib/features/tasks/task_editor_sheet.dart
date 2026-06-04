import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/task_draft.dart';
import '../../models/agent_policy.dart';
import '../../models/chat_models.dart';
import '../../models/family_group.dart';
import '../../models/task_collaboration.dart';
import '../../models/task_item.dart';
import '../../models/task_project.dart';
import '../../services/codewhale_bridge_service.dart';
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
  AgentRunPolicy agentPolicy = const AgentRunPolicy.unavailable(),
  String actorPhone = '',
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
        agentPolicy: agentPolicy,
        actorPhone: actorPhone,
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
    this.initialPendingAttachments = const <TaskAttachment>[],
    this.agentPolicy = const AgentRunPolicy.unavailable(),
    this.actorPhone = '',
  });

  final TaskStore store;
  final List<ChatContact> knownContacts;
  final String Function(ChatContact contact) contactLabel;
  final String Function(DateTime value) dateKey;
  final Future<void> Function() onSaved;
  final TaskItem? existing;
  final List<TaskAttachment> initialPendingAttachments;
  final AgentRunPolicy agentPolicy;
  final String actorPhone;

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
  TaskItem? _savedTask;
  Timer? _autosaveTimer;
  final List<TaskAttachment> _pendingAttachments = [];
  final Map<String, double> _attachmentUploadProgress = {};
  TaskComment? _replyToComment;
  String _editingCommentId = '';

  bool _saving = false;
  bool _autosaveInFlight = false;
  bool _autosaveAgain = false;
  bool _sendingComment = false;
  bool _agentLaunching = false;
  CodeWhaleBridgeService? _agentBridge;
  String _pendingAgentSessionId = '';
  String _pendingAgentWorkspaceId = '';
  String _pendingAgentPrompt = '';

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _savedTask = existing;
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
    _pendingAttachments.addAll(widget.initialPendingAttachments);
    _normalizeProjectSelection();
    _titleCtl.addListener(_queueAutosave);
    _detailsCtl.addListener(_queueAutosave);
    _durationCtl.addListener(_queueAutosave);
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _titleCtl.removeListener(_queueAutosave);
    _detailsCtl.removeListener(_queueAutosave);
    _durationCtl.removeListener(_queueAutosave);
    _titleCtl.dispose();
    _detailsCtl.dispose();
    _durationCtl.dispose();
    _commentCtl.dispose();
    _checklistTitleCtl.dispose();
    for (final controller in _checklistItemControllers.values) {
      controller.dispose();
    }
    _agentBridge?.dispose();
    super.dispose();
  }

  bool get _canEdit {
    final task = _savedTask ?? widget.existing;
    if (task == null) return true;
    final actor = widget.store.owner.value;
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
    await _persistDraft(closeOnSuccess: true);
  }

  void _queueAutosave() {
    _scheduleAutosave();
  }

  void _scheduleAutosave([
    Duration delay = const Duration(milliseconds: 500),
  ]) {
    if (!_canEdit) return;
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(delay, () {
      unawaited(_persistDraft(automatic: true));
    });
  }

  void _autosaveNow() {
    if (!_canEdit) return;
    _autosaveTimer?.cancel();
    unawaited(_persistDraft(automatic: true));
  }

  Future<void> _persistDraft({
    bool closeOnSuccess = false,
    bool automatic = false,
  }) async {
    if (!_canEdit) return;
    if (_saving) return;
    if (_selectedProjectId.isEmpty && !automatic) {
      _showSnack('Выберите проект');
      return;
    }

    if (_autosaveInFlight) {
      _autosaveAgain = true;
      if (automatic) return;
    }

    final messenger = automatic ? null : ScaffoldMessenger.of(context);
    if (automatic) {
      _autosaveInFlight = true;
    } else {
      setState(() => _saving = true);
    }
    var result = await widget.store.saveDraftWithResult(
      draft: _buildDraft(),
      existing: _savedTask ?? widget.existing,
      rememberUndo: !automatic,
    );
    if (!result.isSuccess &&
        automatic &&
        _canUseExistingSnapshotAutosave(result.error)) {
      result = await _saveExistingSnapshot();
    }
    if (automatic) {
      _autosaveInFlight = false;
    }
    if (!mounted) return;
    if (!automatic) {
      setState(() => _saving = false);
    }
    if (!result.isSuccess) {
      if (!automatic) {
        messenger?.showSnackBar(SnackBar(content: Text(result.error!)));
      }
      return;
    }
    _savedTask = result.task ?? _savedTask;
    await widget.onSaved();
    if (!mounted) return;
    if (closeOnSuccess) {
      Navigator.of(context).pop();
      return;
    }
    if (automatic && _autosaveAgain) {
      _autosaveAgain = false;
      _scheduleAutosave(Duration.zero);
    }
  }

  bool _canUseExistingSnapshotAutosave(String? error) {
    if (error == null || (_savedTask ?? widget.existing) == null) {
      return false;
    }
    return error == 'Выберите проект.' ||
        error == 'Выберите группу проекта.' ||
        error == 'Выбранная группа не входит в проект.' ||
        error == 'Нет прав на создание задачи в этой группе.' ||
        error == 'Ответственные должны входить в выбранную группу.';
  }

  Future<TaskSaveResult> _saveExistingSnapshot() {
    final previous = _savedTask ?? widget.existing;
    if (previous == null) {
      return Future.value(
        const TaskSaveResult.failure('Невозможно сохранить задачу.'),
      );
    }
    final title = _titleCtl.text.trim();
    final task = previous.copyWith(
      title: title.isEmpty ? previous.title : title,
      details: _detailsCtl.text.trim(),
      dueDate: widget.dateKey(_selectedDate),
      time: _time,
      workflowStatus: _status,
      priority: _priority,
      assignees: _selectedAssignees.toList(),
      reminderOffsetsMinutes: _selectedReminderOffsets.toList(),
      collaboration: _collaboration,
      durationMinutes:
          int.tryParse(_durationCtl.text.trim()) ?? previous.durationMinutes,
      updatedAt: DateTime.now().toIso8601String(),
      version: previous.version + 1,
    );
    return widget.store.saveExistingSnapshot(
      previous: previous,
      task: task,
      rememberUndo: false,
    );
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

  Future<void> _sendComment() async {
    if (!_canEdit || _sendingComment) return;
    final text = _commentCtl.text.trim();
    final editingId = _editingCommentId;
    if (editingId.isNotEmpty) {
      if (text.isEmpty) return;
      final now = DateTime.now().toIso8601String();
      var edited = false;
      final comments = _collaboration.comments.map((comment) {
        if (comment.id != editingId || comment.isDeleted) {
          return comment;
        }
        edited = true;
        return comment.copyWith(text: text, editedAt: now);
      }).toList();
      if (!edited) {
        _cancelCommentEdit();
        return;
      }
      setState(() {
        _collaboration = _collaboration.copyWith(
          comments: comments,
          activity: [
            ..._collaboration.activity,
            _activity(
              type: 'comment_edited',
              text: 'отредактировал комментарий',
              targetId: editingId,
            ),
          ],
        );
        _editingCommentId = '';
        _commentCtl.clear();
      });
      _autosaveNow();
      return;
    }

    if (text.isEmpty && _pendingAttachments.isEmpty) {
      return;
    }
    final now = DateTime.now().toIso8601String();
    final pending = List<TaskAttachment>.from(_pendingAttachments);
    final replyTo = _replyToComment;
    if (mounted) {
      setState(() => _sendingComment = true);
    }

    late final List<TaskAttachment> attachments;
    try {
      attachments = [];
      for (final item in pending) {
        attachments.add(
          await _uploadAttachmentIfNeeded(
            item.copyWith(caption: text, createdAt: now),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        _showSnack('Не удалось загрузить вложение: $error');
        setState(() {
          _sendingComment = false;
          _attachmentUploadProgress.clear();
        });
      }
      return;
    }
    if (!mounted) return;

    final comment = TaskComment(
      id: _newId('comment'),
      authorProfile: widget.store.owner.value,
      text: text,
      createdAt: now,
      attachmentIds: attachments.map((item) => item.id).toList(),
      replyToCommentId: replyTo?.id ?? '',
    );
    setState(() {
      _collaboration = _collaboration.copyWith(
        comments: [..._collaboration.comments, comment],
        attachments: [..._collaboration.attachments, ...attachments],
        activity: [
          ..._collaboration.activity,
          _activity(
            type: replyTo == null ? 'comment_added' : 'comment_replied',
            text: replyTo == null
                ? attachments.isEmpty
                    ? 'добавил комментарий'
                    : 'добавил комментарий с вложением'
                : 'ответил на комментарий',
            targetId: comment.id,
          ),
        ],
      );
      _pendingAttachments.clear();
      _attachmentUploadProgress.clear();
      _replyToComment = null;
      _commentCtl.clear();
    });
    _autosaveNow();
    if (mounted) {
      setState(() => _sendingComment = false);
    }
  }

  Future<TaskAttachment> _uploadAttachmentIfNeeded(
    TaskAttachment attachment,
  ) async {
    if (attachment.assetUrl.trim().isNotEmpty) {
      return attachment.copyWith(dataBase64: '');
    }

    final bytes = _decodeAttachmentBytes(attachment.dataBase64);
    if (bytes == null || bytes.isEmpty) {
      throw StateError('файл пустой или повреждён');
    }

    final api = widget.store.repository.api;
    void updateProgress(double progress) {
      if (!mounted) return;
      setState(() {
        _attachmentUploadProgress[attachment.id] =
            progress.clamp(0.0, 1.0).toDouble();
      });
    }

    final upload = attachment.isPhoto
        ? await api.chatUploadMedia(
            actorProfile: widget.store.owner.value,
            bytes: bytes,
            filename: attachment.filename.isEmpty
                ? 'task-photo.jpg'
                : attachment.filename,
            onProgress: updateProgress,
          )
        : await api.chatUploadDocument(
            actorProfile: widget.store.owner.value,
            bytes: bytes,
            filename: attachment.filename.isEmpty
                ? 'task-file.bin'
                : attachment.filename,
            onProgress: updateProgress,
          );

    if (upload.assetUrl.trim().isEmpty) {
      throw StateError('сервер не вернул ссылку на файл');
    }

    return attachment.copyWith(
      assetUrl: upload.assetUrl,
      imageMeta:
          upload.imageMeta.isEmpty ? attachment.imageMeta : upload.imageMeta,
      dataBase64: '',
    );
  }

  Future<void> _pickPhoto() async {
    if (!_canEdit || _editingCommentId.isNotEmpty) return;
    final picker = ImagePicker();
    List<XFile> picked;
    try {
      picked = await picker.pickMultiImage(
        imageQuality: 72,
        maxWidth: 1600,
        maxHeight: 1600,
      );
    } catch (_) {
      final one = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 72,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      picked = one == null ? const <XFile>[] : [one];
    }
    if (picked.isEmpty) return;
    final caption = await _promptAttachmentCaption('Подпись к фото');
    _applyAttachmentCaption(caption);
    final attachments = <TaskAttachment>[];
    for (final item in picked) {
      final bytes = await item.readAsBytes();
      attachments.add(
        TaskAttachment(
          id: _newId('att'),
          kind: 'photo',
          filename: item.name,
          mimeType: item.mimeType ?? 'image/jpeg',
          dataBase64: base64Encode(bytes),
          authorProfile: widget.store.owner.value,
          createdAt: DateTime.now().toIso8601String(),
          sizeBytes: bytes.length,
        ),
      );
    }
    if (!mounted) return;
    setState(() {
      _pendingAttachments.addAll(attachments);
    });
  }

  Future<void> _pickFile() async {
    if (!_canEdit || _editingCommentId.isNotEmpty) return;
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) {
      if (mounted) _showSnack('Не удалось прочитать файл');
      return;
    }
    final caption = await _promptAttachmentCaption('Подпись к файлу');
    _applyAttachmentCaption(caption);
    if (!mounted) return;
    setState(() {
      _pendingAttachments.add(
        TaskAttachment(
          id: _newId('att'),
          kind: 'file',
          filename: file.name,
          mimeType: _mimeTypeForName(file.name),
          dataBase64: base64Encode(bytes),
          authorProfile: widget.store.owner.value,
          createdAt: DateTime.now().toIso8601String(),
          sizeBytes: bytes.length,
        ),
      );
    });
  }

  void _removePendingAttachment(String id) {
    setState(() {
      _pendingAttachments.removeWhere((item) => item.id == id);
      _attachmentUploadProgress.remove(id);
    });
  }

  Future<String?> _promptAttachmentCaption(String title) async {
    if (!mounted) return null;
    final controller = TextEditingController();
    var disposeAfterFrame = false;
    try {
      final result = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(title),
            content: TextField(
              controller: controller,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Добавить подпись (необязательно)',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(''),
                child: const Text('Пропустить'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(
                  controller.text.trim(),
                ),
                child: const Text('Готово'),
              ),
            ],
          );
        },
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.dispose();
      });
      disposeAfterFrame = true;
      return result;
    } finally {
      if (!disposeAfterFrame) {
        controller.dispose();
      }
    }
  }

  void _applyAttachmentCaption(String? caption) {
    final value = caption?.trim() ?? '';
    if (value.isEmpty) return;
    final current = _commentCtl.text.trim();
    _commentCtl.text = current.isEmpty ? value : '$current\n$value';
    _commentCtl.selection = TextSelection.collapsed(
      offset: _commentCtl.text.length,
    );
  }

  TaskComment? _commentById(String id) {
    if (id.isEmpty) return null;
    for (final comment in _collaboration.comments) {
      if (comment.id == id) {
        return comment;
      }
    }
    return null;
  }

  void _startCommentReply(TaskComment comment) {
    if (!_canEdit || comment.isDeleted) return;
    setState(() {
      _replyToComment = comment;
      _editingCommentId = '';
    });
  }

  void _startCommentEdit(TaskComment comment) {
    if (!_canEdit || comment.isDeleted) return;
    setState(() {
      _replyToComment = null;
      _editingCommentId = comment.id;
      _commentCtl.text = comment.text;
      _commentCtl.selection = TextSelection.collapsed(
        offset: _commentCtl.text.length,
      );
    });
  }

  void _cancelCommentReply() {
    setState(() => _replyToComment = null);
  }

  void _cancelCommentEdit() {
    setState(() {
      _editingCommentId = '';
      _commentCtl.clear();
    });
  }

  Future<void> _deleteComment(TaskComment comment) async {
    if (!_canEdit || comment.isDeleted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Удалить комментарий?'),
          content: const Text('Комментарий будет удалён из карточки задачи.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Удалить'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    final now = DateTime.now().toIso8601String();
    final nextComments = _collaboration.comments.map((item) {
      if (item.id != comment.id) return item;
      return item.copyWith(
        text: '',
        attachmentIds: const [],
        deletedAt: now,
      );
    }).toList();
    final activeAttachmentIds = nextComments
        .where((item) => !item.isDeleted)
        .expand((item) => item.attachmentIds)
        .toSet();
    setState(() {
      _collaboration = _collaboration.copyWith(
        comments: nextComments,
        attachments: _collaboration.attachments
            .where((item) => activeAttachmentIds.contains(item.id))
            .toList(),
        activity: [
          ..._collaboration.activity,
          _activity(
            type: 'comment_deleted',
            text: 'удалил комментарий',
            targetId: comment.id,
          ),
        ],
      );
      if (_replyToComment?.id == comment.id) {
        _replyToComment = null;
      }
      if (_editingCommentId == comment.id) {
        _editingCommentId = '';
        _commentCtl.clear();
      }
    });
    _autosaveNow();
  }

  Future<void> _openCommentActions(TaskComment comment) async {
    if (!_canEdit || comment.isDeleted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.reply_outlined),
                title: const Text('Ответить'),
                onTap: () => Navigator.of(sheetContext).pop('reply'),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Редактировать'),
                onTap: () => Navigator.of(sheetContext).pop('edit'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Удалить'),
                onTap: () => Navigator.of(sheetContext).pop('delete'),
              ),
            ],
          ),
        );
      },
    );
    if (action == 'reply') {
      _startCommentReply(comment);
    } else if (action == 'edit') {
      _startCommentEdit(comment);
    } else if (action == 'delete') {
      await _deleteComment(comment);
    }
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
    _autosaveNow();
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
    _autosaveNow();
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
    _autosaveNow();
  }

  Future<void> _renameChecklist(TaskChecklist checklist) async {
    if (!_canEdit) return;
    final title = await _promptTextEdit(
      title: 'Редактировать чеклист',
      label: 'Название чеклиста',
      initialValue: checklist.title,
    );
    final nextTitle = title?.trim() ?? '';
    if (nextTitle.isEmpty || nextTitle == checklist.title) return;

    final nextChecklists = _collaboration.checklists.map((item) {
      if (item.id != checklist.id) return item;
      return item.copyWith(title: nextTitle);
    }).toList();
    setState(() {
      _collaboration = _collaboration.copyWith(
        checklists: nextChecklists,
        activity: [
          ..._collaboration.activity,
          _activity(
            type: 'checklist_renamed',
            text: 'переименовал чеклист "$nextTitle"',
            targetId: checklist.id,
          ),
        ],
      );
    });
    _autosaveNow();
  }

  Future<void> _deleteChecklist(TaskChecklist checklist) async {
    if (!_canEdit) return;
    final confirmed = await _confirmDelete(
      title: 'Удалить чеклист?',
      message: 'Чеклист и все его пункты будут удалены из задачи.',
    );
    if (!confirmed) return;

    setState(() {
      _collaboration = _collaboration.copyWith(
        checklists: _collaboration.checklists
            .where((item) => item.id != checklist.id)
            .toList(),
        activity: [
          ..._collaboration.activity,
          _activity(
            type: 'checklist_deleted',
            text: 'удалил чеклист "${checklist.title}"',
            targetId: checklist.id,
          ),
        ],
      );
      _checklistItemControllers.remove(checklist.id)?.dispose();
    });
    _autosaveNow();
  }

  Future<void> _renameChecklistItem(
    String checklistId,
    TaskChecklistItem item,
  ) async {
    if (!_canEdit) return;
    final text = await _promptTextEdit(
      title: 'Редактировать пункт',
      label: 'Текст пункта',
      initialValue: item.text,
    );
    final nextText = text?.trim() ?? '';
    if (nextText.isEmpty || nextText == item.text) return;

    final nextChecklists = _collaboration.checklists.map((checklist) {
      if (checklist.id != checklistId) return checklist;
      return checklist.copyWith(
        items: checklist.items.map((candidate) {
          if (candidate.id != item.id) return candidate;
          return candidate.copyWith(text: nextText);
        }).toList(),
      );
    }).toList();
    setState(() {
      _collaboration = _collaboration.copyWith(
        checklists: nextChecklists,
        activity: [
          ..._collaboration.activity,
          _activity(
            type: 'checklist_item_renamed',
            text: 'отредактировал пункт чеклиста',
            targetId: item.id,
          ),
        ],
      );
    });
    _autosaveNow();
  }

  Future<void> _deleteChecklistItem(
    String checklistId,
    TaskChecklistItem item,
  ) async {
    if (!_canEdit) return;
    final confirmed = await _confirmDelete(
      title: 'Удалить пункт?',
      message: 'Пункт будет удалён из чеклиста.',
    );
    if (!confirmed) return;

    final nextChecklists = _collaboration.checklists.map((checklist) {
      if (checklist.id != checklistId) return checklist;
      return checklist.copyWith(
        items: checklist.items
            .where((candidate) => candidate.id != item.id)
            .toList(),
      );
    }).toList();
    setState(() {
      _collaboration = _collaboration.copyWith(
        checklists: nextChecklists,
        activity: [
          ..._collaboration.activity,
          _activity(
            type: 'checklist_item_deleted',
            text: 'удалил пункт чеклиста',
            targetId: item.id,
          ),
        ],
      );
    });
    _autosaveNow();
  }

  Future<String?> _promptTextEdit({
    required String title,
    required String label,
    required String initialValue,
  }) async {
    if (!mounted) return null;
    final controller = TextEditingController(text: initialValue);
    var disposeAfterFrame = false;
    try {
      final result = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(title),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(
                  controller.text.trim(),
                ),
                child: const Text('Сохранить'),
              ),
            ],
          );
        },
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.dispose();
      });
      disposeAfterFrame = true;
      return result;
    } finally {
      if (!disposeAfterFrame) {
        controller.dispose();
      }
    }
  }

  Future<bool> _confirmDelete({
    required String title,
    required String message,
  }) async {
    if (!mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Удалить'),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }

  void _openPhoto(TaskAttachment attachment) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PhotoViewer(
          attachment: attachment,
          assetBaseUrl: _assetBaseUrl,
        ),
      ),
    );
  }

  String get _assetBaseUrl => widget.store.repository.api.baseUrl.trim();

  Future<void> _openFile(TaskAttachment attachment) async {
    final url = _absoluteAttachmentUrl(attachment.assetUrl, _assetBaseUrl);
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      debugPrint('[tasks] open attachment error: $error');
      if (mounted) {
        _showSnack('Не удалось открыть файл');
      }
    }
  }

  void _requestNewAgentChat() {
    unawaited(_startNewAgentChat());
  }

  Future<void> _startNewAgentChat() async {
    final policy = widget.agentPolicy;
    if (!_canEdit || _agentLaunching) return;
    if (!policy.canStartAgentChat) {
      _showSnack(
        policy.reason.isEmpty ? 'Нет прав на запуск агента' : policy.reason,
      );
      return;
    }
    if (policy.workspaceId.trim().isEmpty) {
      _showSnack('Выберите воркспейс для агентского чата');
      return;
    }
    setState(() => _agentLaunching = true);
    await _persistDraft(automatic: true);
    final saved = _savedTask ?? widget.existing;
    if (saved == null || saved.id.trim().isEmpty) {
      if (mounted) {
        setState(() => _agentLaunching = false);
        _showSnack('Сначала сохраните задачу');
      }
      return;
    }

    final now = DateTime.now().toIso8601String();
    final title = _titleCtl.text.trim().isEmpty
        ? 'Агентский чат'
        : 'Агент: ${_titleCtl.text.trim()}';
    final session = TaskAgentSession(
      id: _newId('agent-session'),
      workspaceId: policy.workspaceId,
      sessionId: '',
      title: title,
      mode: policy.mode,
      status: 'pending',
      createdBy: widget.store.owner.value,
      createdAt: now,
    );
    setState(() {
      _upsertAgentSession(session);
      _appendAgentActivity(
        type: 'agent_session_requested',
        text: 'запросил новый агентский чат',
        targetId: session.id,
      );
      if (_status == WorkflowStatus.todo) {
        _status = WorkflowStatus.in_progress;
      }
    });
    _autosaveNow();
    try {
      final api = widget.store.repository.api;
      final ticket = await api.requestAgentTicket(
        actorProfile: widget.store.owner.value,
        actorPhone: widget.actorPhone,
        taskId: saved.id,
        taskType: _taskTypeForAgent(saved),
        workspaceId: policy.workspaceId,
        requestedMode: policy.mode,
      );
      final contextPack = await api.fetchAgentContext(
        actorProfile: widget.store.owner.value,
        actorPhone: widget.actorPhone,
        taskId: saved.id,
        workspaceId: policy.workspaceId,
        taskType: _taskTypeForAgent(saved),
        requestedMode: policy.mode,
      );
      await api.recordAgentSession(
        actorProfile: widget.store.owner.value,
        actorPhone: widget.actorPhone,
        taskId: saved.id,
        workspaceId: policy.workspaceId,
        agentSessionId: session.id,
        title: title,
        taskType: _taskTypeForAgent(saved),
        requestedMode: policy.mode,
        status: 'pending',
      );

      _pendingAgentSessionId = session.id;
      _pendingAgentWorkspaceId = policy.workspaceId;
      _pendingAgentPrompt = contextPack.toPrompt();
      final bridge = _ensureAgentBridge();
      bridge.updatePolicyTicket(ticket.policyTicket);
      final connected = await bridge.connect();
      if (!connected) {
        throw StateError('CodeWhale недоступен');
      }
      bridge.createSession(policy.workspaceId, title: title);
      if (mounted) {
        _showSnack('Новый агентский чат запускается');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _upsertAgentSession(session.copyWith(status: 'error'));
        _appendAgentActivity(
          type: 'agent_session_error',
          text: 'не смог запустить агентский чат',
          targetId: session.id,
        );
        _agentLaunching = false;
      });
      _autosaveNow();
      _showSnack('Не удалось запустить агента: $error');
    }
  }

  CodeWhaleBridgeService _ensureAgentBridge() {
    final existing = _agentBridge;
    if (existing != null) {
      return existing;
    }
    final bridge = CodeWhaleBridgeService(
      onMessage: _handleAgentBridgeMessage,
      onStatusChange: (connected, status) {
        if (!mounted || connected) {
          return;
        }
        _showSnack(status);
      },
    );
    _agentBridge = bridge;
    return bridge;
  }

  void _handleAgentBridgeMessage(CodeWhaleBridgeMessage message) {
    if (!mounted) return;
    final pendingId = _pendingAgentSessionId;
    if (message.isError) {
      if (pendingId.isNotEmpty) {
        setState(() {
          _markAgentSession(pendingId, status: 'error');
          _appendAgentActivity(
            type: 'agent_session_error',
            text: 'получил ошибку агентского чата',
            targetId: pendingId,
          );
          _agentLaunching = false;
        });
        _autosaveNow();
      }
      _showSnack(message.error.isEmpty ? 'Ошибка CodeWhale' : message.error);
      return;
    }

    final bridgeSession = message.session;
    if (bridgeSession != null && pendingId.isNotEmpty) {
      final workspaceId = bridgeSession.workspaceId.isNotEmpty
          ? bridgeSession.workspaceId
          : _pendingAgentWorkspaceId;
      setState(() {
        _markAgentSession(
          pendingId,
          workspaceId: workspaceId,
          sessionId: bridgeSession.id,
          status: 'linked',
        );
        _appendAgentActivity(
          type: 'agent_session_linked',
          text: 'подключил агентский чат',
          targetId: pendingId,
        );
        _agentLaunching = false;
      });
      _autosaveNow();
      unawaited(
        widget.store.repository.api.recordAgentSession(
          actorProfile: widget.store.owner.value,
          actorPhone: widget.actorPhone,
          taskId: (_savedTask ?? widget.existing)?.id ?? '',
          workspaceId: workspaceId,
          agentSessionId: pendingId,
          sessionId: bridgeSession.id,
          title: bridgeSession.title,
          requestedMode: widget.agentPolicy.mode,
          status: 'linked',
        ),
      );
      if (_pendingAgentPrompt.trim().isNotEmpty) {
        _agentBridge?.sendSessionMessage(
          workspaceId,
          bridgeSession.id,
          _pendingAgentPrompt,
        );
        unawaited(
          widget.store.repository.api.recordAgentEvent(
            actorProfile: widget.store.owner.value,
            actorPhone: widget.actorPhone,
            taskId: (_savedTask ?? widget.existing)?.id ?? '',
            workspaceId: workspaceId,
            agentSessionId: pendingId,
            eventType: 'agent_task_started',
            payload: {'session_id': bridgeSession.id},
            requestedMode: widget.agentPolicy.mode,
          ),
        );
      }
      return;
    }

    if (message.type == 'session_task' && pendingId.isNotEmpty) {
      unawaited(
        widget.store.repository.api.recordAgentEvent(
          actorProfile: widget.store.owner.value,
          actorPhone: widget.actorPhone,
          taskId: (_savedTask ?? widget.existing)?.id ?? '',
          workspaceId: message.workspaceId.isNotEmpty
              ? message.workspaceId
              : _pendingAgentWorkspaceId,
          agentSessionId: pendingId,
          eventType: 'agent_task_started',
          payload: {
            'bridge_task_id': message.taskId,
            'status': message.taskStatus,
          },
          requestedMode: widget.agentPolicy.mode,
        ),
      );
      _pendingAgentSessionId = '';
      _pendingAgentPrompt = '';
      _pendingAgentWorkspaceId = '';
    }
  }

  void _upsertAgentSession(TaskAgentSession session) {
    final sessions = List<TaskAgentSession>.from(_collaboration.agentSessions);
    final index = sessions.indexWhere((item) => item.id == session.id);
    if (index >= 0) {
      sessions[index] = session;
    } else {
      sessions.add(session);
    }
    _collaboration = _collaboration.copyWith(agentSessions: sessions);
  }

  void _markAgentSession(
    String id, {
    String? workspaceId,
    String? sessionId,
    String? status,
  }) {
    final sessions = _collaboration.agentSessions.map((session) {
      if (session.id != id) {
        return session;
      }
      return session.copyWith(
        workspaceId: workspaceId,
        sessionId: sessionId,
        status: status,
      );
    }).toList();
    _collaboration = _collaboration.copyWith(agentSessions: sessions);
  }

  void _appendAgentActivity({
    required String type,
    required String text,
    required String targetId,
  }) {
    _collaboration = _collaboration.copyWith(
      activity: [
        ..._collaboration.activity,
        _activity(type: type, text: text, targetId: targetId),
      ],
    );
  }

  String _taskTypeForAgent(TaskItem task) {
    final tags = task.tags.map((item) => item.toLowerCase()).toSet();
    if (tags.contains('bugfix') || tags.contains('bug')) {
      return 'bugfix';
    }
    if (tags.contains('review')) {
      return 'review';
    }
    if (tags.contains('docs') || tags.contains('doc')) {
      return 'docs';
    }
    if (tags.contains('planning') || tags.contains('plan')) {
      return 'planning';
    }
    return 'feature';
  }

  void _connectAgentChat() {
    final policy = widget.agentPolicy;
    if (!_canEdit) return;
    if (!policy.canLinkExistingChat) {
      _showSnack(
        policy.reason.isEmpty ? 'Нет прав на подключение чата' : policy.reason,
      );
      return;
    }
    if (policy.sessionId.trim().isEmpty) {
      _showSnack('Сначала выберите агентский чат в воркспейсе');
      return;
    }
    final now = DateTime.now().toIso8601String();
    final session = TaskAgentSession(
      id: _newId('agent-session'),
      workspaceId: policy.workspaceId,
      sessionId: policy.sessionId,
      title: 'Подключенный агентский чат',
      mode: policy.mode,
      status: 'linked',
      createdBy: widget.store.owner.value,
      createdAt: now,
    );
    setState(() {
      _collaboration = _collaboration.copyWith(
        agentSessions: [..._collaboration.agentSessions, session],
        activity: [
          ..._collaboration.activity,
          _activity(
            type: 'agent_session_linked',
            text: 'подключил агентский чат',
            targetId: session.id,
          ),
        ],
      );
    });
    _autosaveNow();
    _showSnack('Агентский чат подключен к задаче');
  }

  @override
  Widget build(BuildContext context) {
    final title =
        widget.existing == null ? 'Новая задача' : 'Редактирование задачи';
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.tune), text: 'Настройки'),
              Tab(icon: Icon(Icons.forum_outlined), text: 'Работа'),
              Tab(icon: Icon(Icons.smart_toy_outlined), text: 'Агент'),
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
            _buildAgentTab(),
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
                  _scheduleAutosave();
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
                    _scheduleAutosave();
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
                          _scheduleAutosave();
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
                          _scheduleAutosave();
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
              : (value) {
                  setState(() => _priority = value ?? Priority.medium);
                  _scheduleAutosave();
                },
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
              : (value) {
                  setState(() => _status = value ?? WorkflowStatus.todo);
                  _scheduleAutosave();
                },
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
                        _scheduleAutosave();
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
                      _scheduleAutosave();
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
              replyToComment: _commentById(comment.replyToCommentId),
              attachments: _collaboration.attachmentsFor(comment),
              owner: widget.store.owner.value,
              labelFor: _profileLabel,
              assetBaseUrl: _assetBaseUrl,
              onPhotoTap: _openPhoto,
              onFileTap: _openFile,
              onActions: () => unawaited(_openCommentActions(comment)),
            ),
          ),
        const SizedBox(height: 8),
        if (_pendingAttachments.isNotEmpty)
          _PendingAttachments(
            items: _pendingAttachments,
            assetBaseUrl: _assetBaseUrl,
            progressById: _attachmentUploadProgress,
            onRemove: _removePendingAttachment,
            onPhotoTap: _openPhoto,
          ),
        _CommentComposer(
          controller: _commentCtl,
          enabled: _canEdit && !_sendingComment,
          attachmentsEnabled:
              _canEdit && !_sendingComment && _editingCommentId.isEmpty,
          replyToComment: _replyToComment,
          editingComment: _commentById(_editingCommentId),
          labelFor: _profileLabel,
          onCancelReply: _cancelCommentReply,
          onCancelEdit: _cancelCommentEdit,
          onPickPhoto: _pickPhoto,
          onPickFile: _pickFile,
          onSend: () => unawaited(_sendComment()),
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
              onRenameChecklist: () => unawaited(_renameChecklist(checklist)),
              onDeleteChecklist: () => unawaited(_deleteChecklist(checklist)),
              onRenameItem: (item) => unawaited(
                _renameChecklistItem(checklist.id, item),
              ),
              onDeleteItem: (item) => unawaited(
                _deleteChecklistItem(checklist.id, item),
              ),
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

  Widget _buildAgentTab() {
    final policy = widget.agentPolicy;
    final plugins = policy.pluginLabels;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        _SectionHeader(
          icon: Icons.smart_toy_outlined,
          title: 'Агент',
          trailing: policy.allowed
              ? (policy.modeLabel.isEmpty ? 'Доступ есть' : policy.modeLabel)
              : 'Нет доступа',
        ),
        const SizedBox(height: 10),
        Text(
          policy.allowed
              ? 'Агент может читать задачу, писать в работу и запускаться в воркспейсе.'
              : policy.reason,
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _MetricChip(
              icon: Icons.mode_comment_outlined,
              text: '${_collaboration.agentSessionCount}',
            ),
            if (policy.modeLabel.isNotEmpty)
              _MetricChip(icon: Icons.bolt_outlined, text: policy.modeLabel),
            if (policy.workspaceId.isNotEmpty)
              _MetricChip(
                icon: Icons.workspaces_outline,
                text: policy.workspaceId,
              ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.link),
                label: const Text('Подключить чат'),
                onPressed: _canEdit && policy.canLinkExistingChat
                    ? _connectAgentChat
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.add_comment_outlined),
                label: const Text('Новый чат'),
                onPressed: _canEdit && policy.canStartAgentChat
                    ? _requestNewAgentChat
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        _SectionHeader(
          icon: Icons.extension_outlined,
          title: 'Плагины',
          trailing: '${plugins.length}',
        ),
        const SizedBox(height: 10),
        if (plugins.isEmpty)
          const _EmptyLine(
            icon: Icons.lock_outline,
            text: 'Плагины не выданы',
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: plugins
                .map(
                  (plugin) => _MetricChip(
                    icon: Icons.extension_outlined,
                    text: plugin,
                  ),
                )
                .toList(),
          ),
        const SizedBox(height: 22),
        _SectionHeader(
          icon: Icons.forum_outlined,
          title: 'Чаты задачи',
          trailing: '${_collaboration.agentSessionCount}',
        ),
        const SizedBox(height: 10),
        if (_collaboration.agentSessions.isEmpty)
          const _EmptyLine(
            icon: Icons.chat_bubble_outline,
            text: 'Агентские чаты не подключены',
          )
        else
          ..._collaboration.agentSessions.map(
            (session) => _AgentSessionRow(session: session),
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
    required this.attachmentsEnabled,
    required this.replyToComment,
    required this.editingComment,
    required this.labelFor,
    required this.onCancelReply,
    required this.onCancelEdit,
    required this.onPickPhoto,
    required this.onPickFile,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool attachmentsEnabled;
  final TaskComment? replyToComment;
  final TaskComment? editingComment;
  final String Function(String profile) labelFor;
  final VoidCallback onCancelReply;
  final VoidCallback onCancelEdit;
  final VoidCallback onPickPhoto;
  final VoidCallback onPickFile;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final editing = editingComment;
    final reply = replyToComment;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          if (editing != null)
            _ComposerContextBanner(
              title: 'Редактирование комментария',
              subtitle: _commentPreview(editing),
              onClose: onCancelEdit,
            )
          else if (reply != null)
            _ComposerContextBanner(
              title: 'Ответ на комментарий',
              subtitle:
                  '${labelFor(reply.authorProfile)}: ${_commentPreview(reply)}',
              onClose: onCancelReply,
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'Фото',
                onPressed: attachmentsEnabled ? onPickPhoto : null,
                icon: const Icon(Icons.image_outlined),
              ),
              IconButton(
                tooltip: 'Файл',
                onPressed: attachmentsEnabled ? onPickFile : null,
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
        ],
      ),
    );
  }
}

class _ComposerContextBanner extends StatelessWidget {
  const _ComposerContextBanner({
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  final String title;
  final String subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 34,
            decoration: BoxDecoration(
              color: cs.secondary,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(fontSize: 12, color: cs.onSecondaryContainer),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Отменить',
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}

class _PendingAttachments extends StatelessWidget {
  const _PendingAttachments({
    required this.items,
    required this.assetBaseUrl,
    required this.progressById,
    required this.onRemove,
    required this.onPhotoTap,
  });

  final List<TaskAttachment> items;
  final String assetBaseUrl;
  final Map<String, double> progressById;
  final void Function(String id) onRemove;
  final void Function(TaskAttachment attachment) onPhotoTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: items.map((item) {
          if (item.isPhoto) {
            return _PendingPhotoAttachment(
              attachment: item,
              assetBaseUrl: assetBaseUrl,
              progress: progressById[item.id],
              onOpen: () => onPhotoTap(item),
              onRemove: () => onRemove(item.id),
            );
          }
          return _PendingFileAttachment(
            attachment: item,
            progress: progressById[item.id],
            onDeleted: () => onRemove(item.id),
          );
        }).toList(),
      ),
    );
  }
}

class _PendingPhotoAttachment extends StatelessWidget {
  const _PendingPhotoAttachment({
    required this.attachment,
    required this.assetBaseUrl,
    required this.progress,
    required this.onOpen,
    required this.onRemove,
  });

  final TaskAttachment attachment;
  final String assetBaseUrl;
  final double? progress;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final bytes = _decodeAttachmentBytes(attachment.dataBase64);
    final imageUrl = _absoluteAttachmentUrl(attachment.assetUrl, assetBaseUrl);
    final uploadProgress = progress;
    return SizedBox(
      width: 116,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Tooltip(
                message: 'Открыть фото',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: onOpen,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _TaskAttachmentImage(
                        bytes: bytes,
                        imageUrl: imageUrl,
                        width: 116,
                        height: 78,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: IconButton.filledTonal(
                  tooltip: 'Убрать вложение',
                  style: IconButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: onRemove,
                  icon: const Icon(Icons.close, size: 16),
                ),
              ),
              if (uploadProgress != null)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.34),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '${(uploadProgress * 100).round()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (uploadProgress != null) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(value: uploadProgress),
          ],
          const SizedBox(height: 4),
          Text(
            attachment.filename,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _PendingFileAttachment extends StatelessWidget {
  const _PendingFileAttachment({
    required this.attachment,
    required this.progress,
    required this.onDeleted,
  });

  final TaskAttachment attachment;
  final double? progress;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    final uploadProgress = progress;
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.insert_drive_file_outlined, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  attachment.filename,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Убрать вложение',
                visualDensity: VisualDensity.compact,
                onPressed: onDeleted,
                icon: const Icon(Icons.close, size: 16),
              ),
            ],
          ),
          if (uploadProgress != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(child: LinearProgressIndicator(value: uploadProgress)),
                const SizedBox(width: 8),
                Text(
                  '${(uploadProgress * 100).round()}%',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CommentBubble extends StatelessWidget {
  const _CommentBubble({
    required this.comment,
    required this.replyToComment,
    required this.attachments,
    required this.owner,
    required this.labelFor,
    required this.assetBaseUrl,
    required this.onPhotoTap,
    required this.onFileTap,
    required this.onActions,
  });

  final TaskComment comment;
  final TaskComment? replyToComment;
  final List<TaskAttachment> attachments;
  final String owner;
  final String Function(String profile) labelFor;
  final String assetBaseUrl;
  final void Function(TaskAttachment attachment) onPhotoTap;
  final void Function(TaskAttachment attachment) onFileTap;
  final VoidCallback onActions;

  @override
  Widget build(BuildContext context) {
    final mine = comment.authorProfile == owner;
    final cs = Theme.of(context).colorScheme;
    final deleted = comment.isDeleted;
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: Text(
                    labelFor(comment.authorProfile),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                ),
                if (!deleted)
                  IconButton(
                    tooltip: 'Действия комментария',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    onPressed: onActions,
                    icon: const Icon(Icons.more_vert, size: 18),
                  ),
              ],
            ),
            if (replyToComment != null) ...[
              const SizedBox(height: 4),
              _CommentReplyQuote(
                author: labelFor(replyToComment!.authorProfile),
                preview: _commentPreview(replyToComment!),
              ),
            ],
            if (deleted) ...[
              const SizedBox(height: 4),
              Text(
                'Комментарий удалён',
                style: TextStyle(
                  color: cs.outline,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ] else if (comment.text.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(comment.text),
            ],
            if (!deleted && attachments.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...attachments.map(
                (attachment) => _AttachmentPreview(
                  attachment: attachment,
                  assetBaseUrl: assetBaseUrl,
                  onPhotoTap: onPhotoTap,
                  onFileTap: onFileTap,
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              comment.editedAt.isEmpty
                  ? _shortDateTime(comment.createdAt)
                  : '${_shortDateTime(comment.createdAt)} · изменено',
              style: TextStyle(fontSize: 11, color: cs.outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentReplyQuote extends StatelessWidget {
  const _CommentReplyQuote({required this.author, required this.preview});

  final String author;
  final String preview;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.56),
        border: Border(left: BorderSide(color: cs.primary, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: cs.primary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({
    required this.attachment,
    required this.assetBaseUrl,
    required this.onPhotoTap,
    required this.onFileTap,
  });

  final TaskAttachment attachment;
  final String assetBaseUrl;
  final void Function(TaskAttachment attachment) onPhotoTap;
  final void Function(TaskAttachment attachment) onFileTap;

  @override
  Widget build(BuildContext context) {
    if (attachment.isPhoto) {
      final bytes = _decodeAttachmentBytes(attachment.dataBase64);
      final imageUrl =
          _absoluteAttachmentUrl(attachment.assetUrl, assetBaseUrl);
      return Tooltip(
        message: 'Открыть фото',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onPhotoTap(attachment),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _TaskAttachmentImage(
                bytes: bytes,
                imageUrl: imageUrl,
                width: 168,
                height: 112,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
      );
    }
    return Tooltip(
      message: attachment.assetUrl.isEmpty ? 'Файл' : 'Открыть файл',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: attachment.assetUrl.isEmpty ? null : () => onFileTap(attachment),
        child: Container(
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
              if (attachment.assetUrl.isNotEmpty) ...[
                const SizedBox(width: 8),
                const Icon(Icons.open_in_new, size: 16),
              ],
            ],
          ),
        ),
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
    required this.onRenameChecklist,
    required this.onDeleteChecklist,
    required this.onRenameItem,
    required this.onDeleteItem,
  });

  final TaskChecklist checklist;
  final bool enabled;
  final TextEditingController itemController;
  final VoidCallback onAddItem;
  final void Function(TaskChecklistItem item, bool done) onToggleItem;
  final VoidCallback onRenameChecklist;
  final VoidCallback onDeleteChecklist;
  final void Function(TaskChecklistItem item) onRenameItem;
  final void Function(TaskChecklistItem item) onDeleteItem;

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
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Редактировать чеклист',
                visualDensity: VisualDensity.compact,
                onPressed: enabled ? onRenameChecklist : null,
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
              IconButton(
                tooltip: 'Удалить чеклист',
                visualDensity: VisualDensity.compact,
                onPressed: enabled ? onDeleteChecklist : null,
                icon: const Icon(Icons.delete_outline, size: 18),
              ),
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
              secondary: enabled
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Редактировать пункт',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => onRenameItem(item),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                        ),
                        IconButton(
                          tooltip: 'Удалить пункт',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => onDeleteItem(item),
                          icon: const Icon(Icons.delete_outline, size: 18),
                        ),
                      ],
                    )
                  : null,
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

class _AgentSessionRow extends StatelessWidget {
  const _AgentSessionRow({required this.session});

  final TaskAgentSession session;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (session.workspaceId.isNotEmpty) session.workspaceId,
      if (session.mode.isNotEmpty) session.mode,
      if (session.status.isNotEmpty) _agentStatusText(session.status),
    ].join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.smart_toy_outlined),
      title: Text(
        session.title.isEmpty ? 'Агентский чат' : session.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: session.sessionId.isEmpty
          ? const Icon(Icons.pending_outlined)
          : const Icon(Icons.link),
    );
  }
}

class _PhotoViewer extends StatelessWidget {
  const _PhotoViewer({
    required this.attachment,
    required this.assetBaseUrl,
  });

  final TaskAttachment attachment;
  final String assetBaseUrl;

  @override
  Widget build(BuildContext context) {
    final bytes = _decodeAttachmentBytes(attachment.dataBase64);
    final imageUrl = _absoluteAttachmentUrl(attachment.assetUrl, assetBaseUrl);
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
          child: bytes != null
              ? Image.memory(bytes, fit: BoxFit.contain)
              : imageUrl.isNotEmpty
                  ? Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          const _BrokenAttachmentIcon(isDark: true),
                    )
                  : const _BrokenAttachmentIcon(isDark: true),
        ),
      ),
    );
  }
}

String _agentStatusText(String value) {
  switch (value) {
    case 'pending':
      return 'ожидает запуска';
    case 'linked':
      return 'подключен';
    case 'running':
      return 'в работе';
    case 'done':
      return 'готово';
    default:
      return value;
  }
}

Uint8List? _decodeAttachmentBytes(String dataBase64) {
  if (dataBase64.trim().isEmpty) {
    return null;
  }
  try {
    final bytes = base64Decode(dataBase64);
    return bytes.isEmpty ? null : bytes;
  } on FormatException {
    return null;
  }
}

class _TaskAttachmentImage extends StatelessWidget {
  const _TaskAttachmentImage({
    required this.bytes,
    required this.imageUrl,
    required this.width,
    required this.height,
    required this.fit,
  });

  final Uint8List? bytes;
  final String imageUrl;
  final double width;
  final double height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (bytes != null) {
      return Image.memory(bytes!, width: width, height: height, fit: fit);
    }
    if (imageUrl.isNotEmpty) {
      return Image.network(
        imageUrl,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) =>
            _BrokenAttachmentBox(width: width, height: height),
      );
    }
    return _BrokenAttachmentBox(width: width, height: height);
  }
}

class _BrokenAttachmentBox extends StatelessWidget {
  const _BrokenAttachmentBox({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: const Center(child: Icon(Icons.broken_image_outlined)),
    );
  }
}

class _BrokenAttachmentIcon extends StatelessWidget {
  const _BrokenAttachmentIcon({this.isDark = false});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.broken_image_outlined,
      color: isDark ? Colors.white : null,
      size: 48,
    );
  }
}

String _absoluteAttachmentUrl(String raw, String baseUrl) {
  final value = raw.trim();
  if (value.isEmpty ||
      value.startsWith('http://') ||
      value.startsWith('https://') ||
      value.startsWith('file://') ||
      value.startsWith('content://')) {
    return value;
  }
  if (!value.startsWith('/')) {
    return value;
  }
  final base = baseUrl.trim();
  if (base.isEmpty) {
    return value;
  }
  return '${base.replaceFirst(RegExp(r'/+$'), '')}$value';
}

String _mimeTypeForName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.png')) {
    return 'image/png';
  }
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    return 'image/jpeg';
  }
  if (lower.endsWith('.gif')) {
    return 'image/gif';
  }
  if (lower.endsWith('.pdf')) {
    return 'application/pdf';
  }
  if (lower.endsWith('.doc')) {
    return 'application/msword';
  }
  if (lower.endsWith('.docx')) {
    return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  }
  if (lower.endsWith('.xls')) {
    return 'application/vnd.ms-excel';
  }
  if (lower.endsWith('.xlsx')) {
    return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  }
  if (lower.endsWith('.txt') || lower.endsWith('.md')) {
    return 'text/plain';
  }
  return 'application/octet-stream';
}

String _commentPreview(TaskComment comment) {
  if (comment.isDeleted) {
    return 'Комментарий удалён';
  }
  final text = comment.text.trim();
  if (text.isNotEmpty) {
    return text;
  }
  if (comment.attachmentIds.isNotEmpty) {
    return 'Вложение';
  }
  return 'Комментарий';
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
