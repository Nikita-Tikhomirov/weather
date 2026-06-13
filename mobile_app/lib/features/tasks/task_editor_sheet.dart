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
import '../../models/workspace_item.dart';
import '../../models/workspace_session.dart';
import '../../services/codewhale_bridge_service.dart';
import '../../state/task_store.dart';
import 'agent_launch_plan.dart';
import 'task_editor_text.dart';

part 'task_editor_collaboration_widgets.dart';

const _reminderOptions = <int>[1440, 720, 180, 120, 60, 30, 15, 5];

typedef AgentBridgeFactory = CodeWhaleBridgeService Function({
  required void Function(CodeWhaleBridgeMessage message) onMessage,
  required void Function(bool connected, String status) onStatusChange,
});

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
  AgentBridgeFactory? agentBridgeFactory,
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
        agentBridgeFactory: agentBridgeFactory,
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
    this.agentBridgeFactory,
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
  final AgentBridgeFactory? agentBridgeFactory;

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
  String _pendingAgentBridgeSessionId = '';
  Timer? _agentTaskPoller;
  List<AgentLaunchStep> _pendingAgentSteps = const [];
  AgentLaunchStep? _activeAgentStep;
  StringBuffer? _agentResultBuffer;
  int _pendingAgentStepTotal = 0;
  bool _agentQueueActive = false;
  Map<String, dynamic> _pendingAgentTaskCard = const {};
  final Map<String, String> _pendingAgentAttachmentReads = {};
  int _localIdSequence = 0;
  List<Map<String, dynamic>> _agentCommands = const [];
  List<String> _selectedAgentCommandValues = const [];
  bool _agentCommandsLoading = false;
  List<WorkspaceItem> _agentWorkspaces = const [];
  Completer<List<WorkspaceItem>>? _agentWorkspaceListCompleter;
  bool _agentWorkspacesLoading = false;
  bool _agentWorkspaceManuallySelected = false;
  bool _agentWorkspaceAutoRequested = false;
  Completer<List<WorkspaceSession>>? _agentSessionListCompleter;
  bool _agentSessionsLoading = false;
  bool _agentAutoResumeRequested = false;
  String _selectedAgentWorkspaceId = '';
  String _agentLaunchError = '';
  String _agentProvider = '';
  String _agentModel = '';
  String _agentApprovalPolicy = '';
  String _agentSandboxMode = '';
  bool _agentAutoMode = false;

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
    final agentSettings = _restoredAgentSettings();
    _selectedAgentWorkspaceId = agentSettings.workspaceId.trim().isNotEmpty
        ? agentSettings.workspaceId.trim()
        : widget.agentPolicy.workspaceId.trim();
    _agentWorkspaceManuallySelected =
        agentSettings.workspaceId.trim().isNotEmpty;
    _agentProvider = agentSettings.provider;
    _agentModel = agentSettings.model;
    _agentApprovalPolicy = agentSettings.approvalPolicy;
    _agentSandboxMode = agentSettings.sandboxMode;
    _agentAutoMode = agentSettings.autoMode;
    _selectedAgentCommandValues =
        List<String>.from(agentSettings.commandValues);
    if (!agentSettings.isEmpty) {
      _storeCurrentAgentSettings();
    }
    _pendingAttachments.addAll(widget.initialPendingAttachments);
    _normalizeProjectSelection();
    _titleCtl.addListener(_queueAutosave);
    _detailsCtl.addListener(_queueAutosave);
    _durationCtl.addListener(_queueAutosave);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _maybeAutoResumeLatestAgentSession();
      }
    });
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
    _agentTaskPoller?.cancel();
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
      collaboration: _collaboration.copyWith(
        agentSettings: _currentAgentSettings(),
      ),
    );
  }

  TaskAgentSettings _restoredAgentSettings() {
    final explicit = _collaboration.agentSettings;
    if (!explicit.isEmpty) {
      return explicit;
    }
    for (final session in _collaboration.agentSessions.reversed) {
      final settings = TaskAgentSettings(
        workspaceId: session.workspaceId,
        provider: session.provider,
        model: session.model,
        approvalPolicy: session.approvalPolicy,
        sandboxMode: session.sandboxMode,
        autoMode: session.autoMode,
        commandValues: List<String>.from(session.commandValues),
      );
      if (!settings.isEmpty) {
        return settings;
      }
    }
    return const TaskAgentSettings();
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
      _showSnack(TaskEditorText.of(context).selectProject);
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
    _localIdSequence += 1;
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$_localIdSequence';
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
    final uiText = TaskEditorText.of(context);
    try {
      attachments = [];
      for (final item in pending) {
        attachments.add(
          await _uploadAttachmentIfNeeded(
            item.copyWith(caption: text, createdAt: now),
            uiText,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        _showSnack(TaskEditorText.of(context).attachmentUploadFailed(error));
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
    TaskEditorText text,
  ) async {
    if (attachment.assetUrl.trim().isNotEmpty) {
      return attachment.copyWith(dataBase64: '');
    }

    final bytes = _decodeAttachmentBytes(attachment.dataBase64);
    if (bytes == null || bytes.isEmpty) {
      throw StateError(text.attachmentEmptyOrCorrupt);
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
      throw StateError(text.attachmentUploadMissingUrl);
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
    final text = TaskEditorText.of(context);
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
    final caption = await _promptAttachmentCaption(
      text.photoCaptionTitle,
    );
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
    final text = TaskEditorText.of(context);
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) {
      if (mounted) _showSnack(text.fileReadFailed);
      return;
    }
    final caption = await _promptAttachmentCaption(
      text.fileCaptionTitle,
    );
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
    final text = TaskEditorText.of(context);
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
              decoration: InputDecoration(
                hintText: text.attachmentCaptionHint,
                border: const OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(''),
                child: Text(text.skipAttachmentCaption),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(
                  controller.text.trim(),
                ),
                child: Text(text.done),
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
    final text = TaskEditorText.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(text.deleteCommentTitle),
          content: Text(text.deleteCommentMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(text.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(text.delete),
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
    final text = TaskEditorText.of(context);
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
                title: Text(text.reply),
                onTap: () => Navigator.of(sheetContext).pop('reply'),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(text.edit),
                onTap: () => Navigator.of(sheetContext).pop('edit'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(text.delete),
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
    final strings = TaskEditorText.of(context);
    final title = await _promptTextEdit(
      title: strings.editChecklist,
      label: strings.checklistName,
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
    final strings = TaskEditorText.of(context);
    final confirmed = await _confirmDelete(
      title: strings.deleteChecklistTitle,
      message: strings.deleteChecklistMessage,
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
    final strings = TaskEditorText.of(context);
    final editedText = await _promptTextEdit(
      title: strings.editChecklistItem,
      label: strings.checklistItemText,
      initialValue: item.text,
    );
    final nextText = editedText?.trim() ?? '';
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
    final strings = TaskEditorText.of(context);
    final confirmed = await _confirmDelete(
      title: strings.deleteChecklistItemTitle,
      message: strings.deleteChecklistItemMessage,
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
    final strings = TaskEditorText.of(context);
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
                child: Text(strings.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(
                  controller.text.trim(),
                ),
                child: Text(strings.save),
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
    final strings = TaskEditorText.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(strings.delete),
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
        _showSnack(TaskEditorText.of(context).fileOpenFailed);
      }
    }
  }

  void _requestNewAgentChat() {
    unawaited(_startNewAgentChat());
  }

  Future<void> _loadAgentCommands() async {
    if (_agentCommandsLoading || !widget.agentPolicy.allowed) {
      return;
    }
    final text = TaskEditorText.of(context);
    setState(() => _agentCommandsLoading = true);
    final bridge = _ensureAgentBridge();
    try {
      final connected = await bridge.connect();
      if (!connected) {
        throw StateError(text.codeWhaleUnavailable);
      }
      await _requestAgentWorkspaces(bridge);
      bridge.requestCodeWhaleCommands();
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (_agentBridge == bridge) {
        bridge.dispose();
        _agentBridge = null;
      }
      setState(() => _agentCommandsLoading = false);
      _showSnack(text.agentToolsLoadFailed(error));
    }
  }

  Future<void> _refreshAgentWorkspaces() async {
    final text = TaskEditorText.of(context);
    final bridge = _ensureAgentBridge();
    try {
      final connected = await bridge.connect();
      if (!connected) {
        throw StateError(text.codeWhaleUnavailable);
      }
      await _requestAgentWorkspaces(bridge);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack(text.agentWorkspacesLoadFailed(error));
    }
  }

  Future<void> _requestAgentWorkspaces(CodeWhaleBridgeService bridge) async {
    final existing = _agentWorkspaceListCompleter;
    if (existing != null) {
      try {
        await existing.future.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        return;
      }
      return;
    }

    final completer = Completer<List<WorkspaceItem>>();
    _agentWorkspaceListCompleter = completer;
    if (mounted) {
      setState(() => _agentWorkspacesLoading = true);
    }
    bridge.requestWorkspaceList();
    try {
      await completer.future.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      if (!completer.isCompleted) {
        completer.complete(_agentWorkspaces);
      }
    } finally {
      if (_agentWorkspaceListCompleter == completer) {
        _agentWorkspaceListCompleter = null;
      }
      if (mounted) {
        setState(() => _agentWorkspacesLoading = false);
      }
    }
  }

  Future<List<WorkspaceSession>> _requestAgentSessions(
    CodeWhaleBridgeService bridge,
    String workspaceId,
  ) async {
    final existing = _agentSessionListCompleter;
    if (existing != null) {
      try {
        return await existing.future.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        return const [];
      }
    }

    final completer = Completer<List<WorkspaceSession>>();
    _agentSessionListCompleter = completer;
    if (mounted) {
      setState(() => _agentSessionsLoading = true);
    }
    bridge.requestSessionList(workspaceId);
    try {
      return await completer.future.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      if (!completer.isCompleted) {
        completer.complete(const []);
      }
      return const [];
    } finally {
      if (_agentSessionListCompleter == completer) {
        _agentSessionListCompleter = null;
      }
      if (mounted) {
        setState(() => _agentSessionsLoading = false);
      }
    }
  }

  String _effectiveAgentWorkspaceId(AgentRunPolicy policy) {
    return _resolveAgentWorkspaceId(policy);
  }

  String _resolveAgentWorkspaceId(AgentRunPolicy policy) {
    final workspaces = _agentWorkspaces
        .where((item) => item.id.trim().isNotEmpty)
        .toList(growable: false);
    if (workspaces.isEmpty) {
      return _selectedAgentWorkspaceId.trim().isNotEmpty
          ? _selectedAgentWorkspaceId.trim()
          : policy.workspaceId.trim();
    }
    final preferredWorkspaces = _availableAgentWorkspaces(workspaces);
    if (_agentWorkspaceManuallySelected) {
      final selected = _selectedAgentWorkspaceId.trim();
      return _findAgentWorkspace(
            preferredWorkspaces,
            [selected],
            allowLooseMatch: false,
          )?.id ??
          _findAgentWorkspace(
            preferredWorkspaces,
            [selected],
            allowLooseMatch: true,
          )?.id ??
          selected;
    }
    final projectMatch = _findAgentWorkspace(
      preferredWorkspaces,
      _agentProjectWorkspaceCandidates(),
      allowLooseMatch: true,
    );
    if (projectMatch != null) {
      return projectMatch.id;
    }
    if (_hasAgentProjectContext()) {
      return preferredWorkspaces.length == 1
          ? preferredWorkspaces.first.id
          : '';
    }
    final policyWorkspace = _findAgentWorkspace(
      preferredWorkspaces,
      [policy.workspaceId],
      allowLooseMatch: false,
    );
    if (policyWorkspace != null) {
      return policyWorkspace.id;
    }
    return preferredWorkspaces.length == 1 ? preferredWorkspaces.first.id : '';
  }

  List<WorkspaceItem> _availableAgentWorkspaces(
    List<WorkspaceItem> workspaces,
  ) {
    final available = workspaces.where((item) {
      return item.status == WorkspaceStatus.available;
    }).toList(growable: false);
    return available.isEmpty ? workspaces : available;
  }

  bool _hasAgentProjectContext() {
    return _agentProjectWorkspaceCandidates().isNotEmpty;
  }

  List<String> _agentProjectWorkspaceCandidates() {
    final values = <String>[];
    void add(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || values.contains(trimmed)) {
        return;
      }
      values.add(trimmed);
    }

    final projectIds = <String>[
      _selectedProjectId,
      _savedTask?.projectId ?? '',
      widget.existing?.projectId ?? '',
      widget.store.currentProjectId.value,
    ];
    for (final id in projectIds) {
      add(id);
      final project = _projectList.cast<TaskProject?>().firstWhere(
            (item) => item?.id == id,
            orElse: () => null,
          );
      if (project == null) {
        continue;
      }
      add(project.id);
      add(project.name);
      add(project.description);
    }
    return values;
  }

  WorkspaceItem? _findAgentWorkspace(
    List<WorkspaceItem> workspaces,
    Iterable<String> candidates, {
    required bool allowLooseMatch,
  }) {
    for (final candidate in candidates) {
      final candidateKey = _workspaceLookupKey(candidate);
      if (candidateKey.isEmpty) {
        continue;
      }
      for (final workspace in workspaces) {
        final keys = _workspaceLookupKeys(workspace);
        if (keys.contains(candidateKey)) {
          return workspace;
        }
        if (!allowLooseMatch) {
          continue;
        }
        if (keys.any((key) => _workspaceKeysCompatible(key, candidateKey))) {
          return workspace;
        }
      }
    }
    return null;
  }

  Set<String> _workspaceLookupKeys(WorkspaceItem workspace) {
    return {
      _workspaceLookupKey(workspace.id),
      _workspaceLookupKey(workspace.name),
      _workspaceLookupKey(_lastPathSegment(workspace.path)),
    }.where((item) => item.isNotEmpty).toSet();
  }

  bool _workspaceKeysCompatible(String key, String candidate) {
    if (key == candidate) {
      return true;
    }
    if (key.length < 3 || candidate.length < 3) {
      return false;
    }
    return key.startsWith('$candidate-') || candidate.startsWith('$key-');
  }

  String _workspaceLookupKey(String value) {
    final lower = value.trim().toLowerCase();
    if (lower.isEmpty) {
      return '';
    }
    return lower
        .replaceAll(RegExp(r'[\s_./\\]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  String _lastPathSegment(String path) {
    final parts = path.split(RegExp(r'[\\/]+'));
    return parts.isEmpty ? path : parts.last;
  }

  Future<void> _startNewAgentChat() async {
    final policy = widget.agentPolicy;
    final text = TaskEditorText.of(context);
    if (!_canEdit || _agentLaunching) return;
    if (!policy.canStartAgentChat) {
      _showSnack(
        policy.reason.isEmpty ? 'Нет прав на запуск агента' : policy.reason,
      );
      return;
    }
    setState(() {
      _agentLaunching = true;
      _agentLaunchError = '';
      _storeCurrentAgentSettings();
    });
    await _persistDraft(automatic: true);
    final saved = _savedTask ?? widget.existing;
    if (saved == null || saved.id.trim().isEmpty) {
      if (mounted) {
        setState(() => _agentLaunching = false);
        _showSnack(text.saveTaskFirst);
      }
      return;
    }
    await _syncAgentDraftBestEffort();

    final now = DateTime.now().toIso8601String();
    final taskTitle = _titleCtl.text.trim();
    final title =
        taskTitle.isEmpty ? text.agentChat : text.agentSessionTitle(taskTitle);
    final bridge = _ensureAgentBridge();
    try {
      final connected = await bridge.connect();
      if (!connected) {
        throw StateError(text.codeWhaleUnavailable);
      }
      await _requestAgentWorkspaces(bridge);
    } catch (error) {
      if (!mounted) return;
      setState(() => _agentLaunching = false);
      _showSnack(text.agentWorkspacesLoadFailed(error));
      return;
    }
    final workspaceId = _effectiveAgentWorkspaceId(policy);
    if (workspaceId.trim().isEmpty) {
      if (mounted) {
        final message = text.selectAgentWorkspace;
        setState(() {
          _agentLaunching = false;
          _agentLaunchError = message;
        });
        _showSnack(message);
      }
      return;
    }
    final session = TaskAgentSession(
      id: _newId('agent-session'),
      workspaceId: workspaceId,
      sessionId: '',
      title: title,
      mode: policy.mode,
      status: 'pending',
      createdBy: widget.store.owner.value,
      createdAt: now,
      provider: _agentProvider,
      model: _agentModel,
      approvalPolicy: _agentApprovalPolicy,
      sandboxMode: _agentSandboxMode,
      autoMode: _agentAutoMode,
      commandValues: List<String>.from(_selectedAgentCommandValues),
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
      final taskType = _taskTypeForAgent(saved);
      final ticket = await api.requestAgentTicket(
        actorProfile: widget.store.owner.value,
        actorPhone: widget.actorPhone,
        taskId: saved.id,
        taskType: taskType,
        workspaceId: workspaceId,
        requestedMode: policy.mode,
      );
      final backendPrompt = await _fetchAgentContextPromptBestEffort(
        saved,
        policy,
        workspaceId,
      );
      _recordAgentSessionBestEffort(
        taskId: saved.id,
        workspaceId: workspaceId,
        agentSessionId: session.id,
        title: title,
        taskType: taskType,
        requestedMode: policy.mode,
        status: 'pending',
      );

      _pendingAgentSessionId = session.id;
      _pendingAgentWorkspaceId = workspaceId;
      final prompt = _buildAgentCardPrompt(backendPrompt, saved);
      final selectedCommands = _selectedAgentCommands();
      final launchPlan = AgentLaunchPlan.build(
        contextPrompt: prompt,
        selectedCommandValues: _selectedAgentCommandValues,
        commands: _agentCommands,
      );
      _pendingAgentSteps = launchPlan.steps;
      _pendingAgentStepTotal = launchPlan.steps.length;
      _activeAgentStep = null;
      _agentResultBuffer = null;
      _agentQueueActive = true;
      final taskCard = {
        'task_id': saved.id,
        'agent_session_id': session.id,
        'actor_profile': widget.store.owner.value,
        'actor_phone': widget.actorPhone,
        'api_url': api.baseUrl,
        'policy_ticket': ticket.policyTicket,
        'task_type': taskType,
        'mode': policy.mode,
        'workspace_id': workspaceId,
      };
      _pendingAgentTaskCard = taskCard;
      bridge.updatePolicyTicket(ticket.policyTicket);
      bridge.requestCodeWhaleCommands();
      bridge.createSession(
        workspaceId,
        title: title,
        taskCard: taskCard,
      );
      if (mounted) {
        _showSnack(
          selectedCommands.isEmpty
              ? text.agentLaunchStarted
              : text.agentQueueLaunchStarted(selectedCommands.length),
        );
      }
    } catch (error) {
      if (!mounted) return;
      final message = 'Не удалось запустить агента: $error';
      setState(() {
        _upsertAgentSession(session.copyWith(status: 'error'));
        _appendAgentActivity(
          type: 'agent_session_error',
          text: 'не смог запустить агентский чат',
          targetId: session.id,
        );
        _agentLaunching = false;
        _agentQueueActive = false;
        _agentLaunchError = message;
      });
      _autosaveNow();
      _showSnack(message);
    }
  }

  CodeWhaleBridgeService _ensureAgentBridge() {
    final existing = _agentBridge;
    if (existing != null) {
      return existing;
    }
    void handleStatusChange(bool connected, String status) {
      if (!mounted) {
        return;
      }
      if (connected) {
        _agentBridge?.requestCodeWhaleCommands();
        _agentBridge?.requestWorkspaceList();
        return;
      }
      _showSnack(status);
    }

    final factory = widget.agentBridgeFactory;
    final bridge = factory == null
        ? CodeWhaleBridgeService(
            onMessage: _handleAgentBridgeMessage,
            onStatusChange: handleStatusChange,
          )
        : factory(
            onMessage: _handleAgentBridgeMessage,
            onStatusChange: handleStatusChange,
          );
    _agentBridge = bridge;
    return bridge;
  }

  Future<void> _syncAgentDraftBestEffort() async {
    try {
      await widget.store.syncDelta();
    } catch (error) {
      debugPrint('Task agent draft sync skipped: $error');
    }
  }

  TaskAgentSettings _currentAgentSettings() {
    return TaskAgentSettings(
      workspaceId: _selectedAgentWorkspaceId.trim(),
      provider: _agentProvider.trim(),
      model: _agentModel.trim(),
      approvalPolicy: _agentApprovalPolicy.trim(),
      sandboxMode: _agentSandboxMode.trim(),
      autoMode: _agentAutoMode,
      commandValues: List<String>.from(_selectedAgentCommandValues),
    );
  }

  void _storeCurrentAgentSettings() {
    _collaboration = _collaboration.copyWith(
      agentSettings: _currentAgentSettings(),
    );
  }

  List<String> _agentCommandValuesFor(TaskAgentSession session) {
    if (session.commandValues.isNotEmpty) {
      return session.commandValues;
    }
    return _selectedAgentCommandValues;
  }

  String _sessionProvider(TaskAgentSession session) {
    return session.provider.trim().isNotEmpty
        ? session.provider
        : _agentProvider;
  }

  String _sessionModel(TaskAgentSession session) {
    return session.model.trim().isNotEmpty ? session.model : _agentModel;
  }

  String _sessionApprovalPolicy(TaskAgentSession session) {
    return session.approvalPolicy.trim().isNotEmpty
        ? session.approvalPolicy
        : _agentApprovalPolicy;
  }

  String _sessionSandboxMode(TaskAgentSession session) {
    return session.sandboxMode.trim().isNotEmpty
        ? session.sandboxMode
        : _agentSandboxMode;
  }

  bool _sessionAutoMode(TaskAgentSession session) {
    return session.autoMode || _agentAutoMode;
  }

  Future<String> _fetchAgentContextPromptBestEffort(
    TaskItem task,
    AgentRunPolicy policy,
    String workspaceId, [
    String requestedMode = '',
  ]) async {
    try {
      final contextPack = await widget.store.repository.api.fetchAgentContext(
        actorProfile: widget.store.owner.value,
        actorPhone: widget.actorPhone,
        taskId: task.id,
        workspaceId: workspaceId,
        taskType: _taskTypeForAgent(task),
        requestedMode:
            requestedMode.trim().isEmpty ? policy.mode : requestedMode.trim(),
      );
      return contextPack.toPrompt();
    } catch (error) {
      debugPrint('Task agent backend context skipped: $error');
      return '';
    }
  }

  void _recordAgentSessionBestEffort({
    required String taskId,
    required String workspaceId,
    required String agentSessionId,
    String sessionId = '',
    String title = '',
    String taskType = 'feature',
    String requestedMode = '',
    String status = 'pending',
  }) {
    if (taskId.trim().isEmpty || workspaceId.trim().isEmpty) {
      return;
    }
    final future = widget.store.repository.api.recordAgentSession(
      actorProfile: widget.store.owner.value,
      actorPhone: widget.actorPhone,
      taskId: taskId,
      workspaceId: workspaceId,
      agentSessionId: agentSessionId,
      sessionId: sessionId,
      title: title,
      taskType: taskType,
      requestedMode: requestedMode,
      status: status,
    );
    unawaited(
      future.catchError((Object error) {
        debugPrint('Task agent session record skipped: $error');
      }),
    );
  }

  void _recordAgentEventBestEffort({
    required String taskId,
    required String workspaceId,
    required String agentSessionId,
    required String eventType,
    Map<String, dynamic> payload = const {},
    String taskType = 'feature',
    String requestedMode = '',
  }) {
    if (taskId.trim().isEmpty || workspaceId.trim().isEmpty) {
      return;
    }
    final future = widget.store.repository.api.recordAgentEvent(
      actorProfile: widget.store.owner.value,
      actorPhone: widget.actorPhone,
      taskId: taskId,
      workspaceId: workspaceId,
      agentSessionId: agentSessionId,
      eventType: eventType,
      payload: payload,
      taskType: taskType,
      requestedMode: requestedMode,
    );
    unawaited(
      future.catchError((Object error) {
        debugPrint('Task agent event record skipped: $error');
      }),
    );
  }

  Future<void> _continueAgentSession(TaskAgentSession session) async {
    final policy = widget.agentPolicy;
    final text = TaskEditorText.of(context);
    if (!_canEdit || !_canContinueAgentSession(session, policy)) {
      _showSnack(
        policy.reason.isEmpty
            ? 'Нет прав на продолжение агента'
            : policy.reason,
      );
      return;
    }
    if (_agentQueueActive || _agentLaunching) {
      return;
    }
    final workspaceId = session.workspaceId.trim().isNotEmpty
        ? session.workspaceId.trim()
        : _effectiveAgentWorkspaceId(policy);
    final bridgeSessionId = session.sessionId.trim();
    if (workspaceId.isEmpty || bridgeSessionId.isEmpty) {
      _showSnack(text.agentChatNotLinkedToWorkspace);
      return;
    }
    setState(() {
      _agentLaunching = true;
      _agentLaunchError = '';
    });
    await _persistDraft(automatic: true);
    final saved = _savedTask ?? widget.existing;
    if (saved == null || saved.id.trim().isEmpty) {
      if (mounted) {
        setState(() => _agentLaunching = false);
        _showSnack(text.saveTaskFirst);
      }
      return;
    }
    await _syncAgentDraftBestEffort();
    final bridge = _ensureAgentBridge();
    try {
      final connected = await bridge.connect();
      if (!connected) {
        throw StateError(text.codeWhaleUnavailable);
      }
      final api = widget.store.repository.api;
      final taskType = _taskTypeForAgent(saved);
      final requestedMode =
          session.mode.trim().isNotEmpty ? session.mode.trim() : policy.mode;
      final selectedCommandValues = _agentCommandValuesFor(session);
      final ticket = await api.requestAgentTicket(
        actorProfile: widget.store.owner.value,
        actorPhone: widget.actorPhone,
        taskId: saved.id,
        taskType: taskType,
        workspaceId: workspaceId,
        requestedMode: requestedMode,
      );
      final backendPrompt = await _fetchAgentContextPromptBestEffort(
        saved,
        policy,
        workspaceId,
        requestedMode,
      );
      final prompt = _buildAgentCardPrompt(backendPrompt, saved);
      final launchPlan = AgentLaunchPlan.buildContinuation(
        contextPrompt: prompt,
        selectedCommandValues: selectedCommandValues,
        commands: _agentCommands,
      );
      final taskCard = {
        'task_id': saved.id,
        'agent_session_id': session.id,
        'actor_profile': widget.store.owner.value,
        'actor_phone': widget.actorPhone,
        'api_url': api.baseUrl,
        'policy_ticket': ticket.policyTicket,
        'task_type': taskType,
        'mode': requestedMode,
        'workspace_id': workspaceId,
      };
      setState(() {
        _pendingAgentSessionId = session.id;
        _pendingAgentWorkspaceId = workspaceId;
        _pendingAgentBridgeSessionId = bridgeSessionId;
        _pendingAgentSteps = launchPlan.steps;
        _pendingAgentStepTotal = launchPlan.steps.length;
        _activeAgentStep = null;
        _agentResultBuffer = null;
        _agentQueueActive = true;
        _pendingAgentTaskCard = taskCard;
        _agentLaunching = false;
        _markAgentSession(session.id, status: 'running');
        _appendAgentActivity(
          type: 'agent_session_resumed',
          text: 'продолжил агентский чат',
          targetId: session.id,
        );
      });
      _autosaveNow();
      _recordAgentSessionBestEffort(
        taskId: saved.id,
        workspaceId: workspaceId,
        agentSessionId: session.id,
        sessionId: bridgeSessionId,
        title: session.title,
        taskType: taskType,
        requestedMode: requestedMode,
        status: 'running',
      );
      bridge.updatePolicyTicket(ticket.policyTicket);
      bridge.requestCodeWhaleCommands();
      bridge.updateSessionTaskCard(
        workspaceId: workspaceId,
        sessionId: bridgeSessionId,
        taskCard: taskCard,
      );
      bridge.updateSessionSettings(
        workspaceId: workspaceId,
        sessionId: bridgeSessionId,
        provider: _sessionProvider(session),
        model: _sessionModel(session),
        approvalPolicy: _sessionApprovalPolicy(session),
        sandboxMode: _sessionSandboxMode(session),
        autoMode: _sessionAutoMode(session),
      );
      _uploadAgentCardFiles(workspaceId, bridgeSessionId);
      _sendNextAgentStep(workspaceId: workspaceId, sessionId: bridgeSessionId);
      if (mounted) {
        _showSnack('Агент продолжает работу по свежей карточке');
      }
    } catch (error) {
      if (!mounted) return;
      final message = 'Не удалось продолжить агента: $error';
      setState(() {
        _markAgentSession(session.id, status: 'error');
        _appendAgentActivity(
          type: 'agent_session_error',
          text: 'не смог продолжить агентский чат',
          targetId: session.id,
        );
        _agentLaunchError = message;
        _clearAgentQueueState();
      });
      _autosaveNow();
      _showSnack(message);
    }
  }

  bool _canContinueAgentSession(
    TaskAgentSession session,
    AgentRunPolicy policy,
  ) {
    if (!policy.allowed || session.sessionId.trim().isEmpty) {
      return false;
    }
    if (_status == WorkflowStatus.done || _status == WorkflowStatus.archive) {
      return false;
    }
    if (!policy.allowedCommands.contains('session_send')) {
      return false;
    }
    if (!policy.allowedCommands.contains('session_update_task_card')) {
      return false;
    }
    return session.status != 'error' && session.status != 'running';
  }

  void _handleAgentBridgeMessage(CodeWhaleBridgeMessage message) {
    if (!mounted) return;
    if (message.type == 'workspace_list' || message.workspaces.isNotEmpty) {
      final workspaces = message.workspaces;
      setState(() {
        _agentWorkspaces = workspaces;
        _agentWorkspacesLoading = false;
        final resolved = _resolveAgentWorkspaceId(widget.agentPolicy);
        if (!_agentWorkspaceManuallySelected) {
          _selectedAgentWorkspaceId = resolved;
        }
        if (resolved.isNotEmpty) {
          _agentLaunchError = '';
        }
      });
      final completer = _agentWorkspaceListCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete(workspaces);
      }
      _agentWorkspaceListCompleter = null;
      return;
    }
    if (message.type == 'codewhale_command_list') {
      setState(() {
        _agentCommands = message.commands;
        _agentCommandsLoading = false;
      });
      return;
    }
    if (message.type == 'session_list') {
      final completer = _agentSessionListCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete(message.sessions);
      }
      _agentSessionListCompleter = null;
      if (mounted) {
        setState(() => _agentSessionsLoading = false);
      }
      return;
    }
    if (message.type == 'workspace_file_content') {
      _applyAgentWorkspaceFileContent(message);
      return;
    }
    if (message.type == 'session_task_card') {
      return;
    }
    final pendingId = _pendingAgentSessionId;
    if (message.isError) {
      final errorText =
          message.error.isEmpty ? 'Ошибка CodeWhale' : message.error;
      if (pendingId.isNotEmpty) {
        setState(() {
          _markAgentSession(pendingId, status: 'error');
          _appendAgentActivity(
            type: 'agent_session_error',
            text: 'получил ошибку агентского чата',
            targetId: pendingId,
          );
          _agentLaunchError = errorText;
          _clearAgentQueueState();
        });
        _autosaveNow();
      }
      _showSnack(errorText);
      return;
    }

    if (message.type == 'assistant_delta' && pendingId.isNotEmpty) {
      final buffer = _agentResultBuffer ?? StringBuffer();
      buffer.write(message.text);
      _agentResultBuffer = buffer;
      return;
    }

    final bridgeSession = message.session;
    if (bridgeSession != null && pendingId.isNotEmpty) {
      if (_pendingAgentBridgeSessionId.isNotEmpty &&
          bridgeSession.id == _pendingAgentBridgeSessionId) {
        return;
      }
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
      _recordAgentSessionBestEffort(
        taskId: (_savedTask ?? widget.existing)?.id ?? '',
        workspaceId: workspaceId,
        agentSessionId: pendingId,
        sessionId: bridgeSession.id,
        title: bridgeSession.title,
        requestedMode: widget.agentPolicy.mode,
        status: 'linked',
      );
      _pendingAgentBridgeSessionId = bridgeSession.id;
      _agentBridge?.updateSessionTaskCard(
        workspaceId: workspaceId,
        sessionId: bridgeSession.id,
        taskCard: _pendingAgentTaskCard,
      );
      _agentBridge?.updateSessionSettings(
        workspaceId: workspaceId,
        sessionId: bridgeSession.id,
        provider: _agentProvider,
        model: _agentModel,
        approvalPolicy: _agentApprovalPolicy,
        sandboxMode: _agentSandboxMode,
        autoMode: _agentAutoMode,
      );
      _uploadAgentCardFiles(workspaceId, bridgeSession.id);
      _sendNextAgentStep(workspaceId: workspaceId, sessionId: bridgeSession.id);
      return;
    }

    if (message.type == 'session_task' && pendingId.isNotEmpty) {
      final workspaceId = message.workspaceId.isNotEmpty
          ? message.workspaceId
          : _pendingAgentWorkspaceId;
      final sessionId = message.sessionId.isNotEmpty
          ? message.sessionId
          : _pendingAgentBridgeSessionId;
      if (!_isBridgeTaskDone(message.taskStatus)) {
        _scheduleAgentTaskPoll(workspaceId, sessionId, message.taskId);
        return;
      }
      if (message.taskResultSummary.trim().isNotEmpty) {
        final buffer = _agentResultBuffer ?? StringBuffer();
        buffer.write(message.taskResultSummary);
        _agentResultBuffer = buffer;
      }
      _finishActiveAgentStep(
        workspaceId: workspaceId,
        sessionId: sessionId,
        taskStatus: message.taskStatus,
      );
      return;
    }

    if (message.type == 'session_stream_done' && pendingId.isNotEmpty) {
      _finishActiveAgentStep(
        workspaceId: message.workspaceId.isNotEmpty
            ? message.workspaceId
            : _pendingAgentWorkspaceId,
        sessionId: message.sessionId.isNotEmpty
            ? message.sessionId
            : _pendingAgentBridgeSessionId,
        taskStatus: 'completed',
      );
    }
  }

  String _buildAgentCardPrompt(String backendPrompt, TaskItem task) {
    final lines = <String>[];
    final remote = backendPrompt.trim();
    if (remote.isNotEmpty) {
      lines.add(remote);
      lines.add('');
    }
    lines.add('Актуальная карточка из мобильного приложения:');
    lines.add(
      'Название: ${_titleCtl.text.trim().isEmpty ? task.title : _titleCtl.text.trim()}',
    );
    final details = _detailsCtl.text.trim();
    if (details.isNotEmpty) {
      lines.add('Описание: $details');
    }
    lines.add('Статус: ${_status.name}');
    lines.add(
      'Проект: ${_selectedProjectId.isEmpty ? task.projectId : _selectedProjectId}',
    );

    final comments = _collaboration.comments.where((item) => !item.isDeleted);
    if (comments.isNotEmpty) {
      lines.add('');
      lines.add('Комментарии карточки:');
      for (final comment in comments.take(30)) {
        final text = comment.text.trim();
        if (text.isEmpty) {
          continue;
        }
        lines.add('- ${_profileLabel(comment.authorProfile)}: $text');
      }
    }

    if (_collaboration.checklists.isNotEmpty) {
      lines.add('');
      lines.add('Чеклисты карточки:');
      for (final checklist in _collaboration.checklists) {
        lines.add('- ${checklist.title}');
        for (final item in checklist.items) {
          lines.add('  - [${item.done ? 'x' : ' '}] ${item.text}');
        }
      }
    }

    final attachments = _agentCardAttachments();
    if (attachments.isNotEmpty) {
      lines.add('');
      lines.add('Вложения карточки:');
      for (final attachment in attachments) {
        final source = attachment.assetUrl.trim().isNotEmpty
            ? attachment.assetUrl.trim()
            : 'будет прикреплено в агентский чат';
        final caption = attachment.caption.trim();
        lines.add(
          '- ${attachment.filename} · $source'
          '${caption.isEmpty ? '' : ' · $caption'}',
        );
      }
    }

    lines.add('');
    lines.add(
      'После работы обнови карточку через family-task-card и не спрашивай подтверждение на перевод: если работа готова и нет блокирующего вопроса, сразу выполни family-task-card finish --summary "<краткий итог>" --result-status ready_for_review.',
    );
    lines.add(
      'Если family-task-card недоступен, используй TASK_CARD_ACTIONS_JSON: добавь комментарий-итог, новые чеклисты/пункты, пути файлов отчета или скриншотов и status=in_review.',
    );
    return lines.join('\n');
  }

  List<TaskAttachment> _agentCardAttachments() {
    final seen = <String>{};
    final result = <TaskAttachment>[];
    for (final attachment in [
      ..._collaboration.attachments,
      ..._pendingAttachments,
    ]) {
      final key = attachment.id.isNotEmpty
          ? attachment.id
          : '${attachment.filename}:${attachment.assetUrl}';
      if (seen.add(key)) {
        result.add(attachment);
      }
    }
    return result;
  }

  void _uploadAgentCardFiles(String workspaceId, String sessionId) {
    for (final attachment in _agentCardAttachments()) {
      final bytes = _decodeAttachmentBytes(attachment.dataBase64);
      if (bytes == null || bytes.isEmpty) {
        continue;
      }
      _agentBridge?.uploadSessionFile(
        workspaceId: workspaceId,
        sessionId: sessionId,
        bytes: bytes,
        filename: attachment.filename.isEmpty
            ? 'task-attachment.bin'
            : attachment.filename,
        mimeType: attachment.mimeType.isEmpty
            ? _mimeTypeForName(attachment.filename)
            : attachment.mimeType,
        caption: attachment.caption.isEmpty
            ? 'Файл из карточки задачи'
            : attachment.caption,
      );
    }
  }

  void _sendNextAgentStep({
    required String workspaceId,
    required String sessionId,
  }) {
    if (_pendingAgentSteps.isEmpty) {
      unawaited(_completeAgentQueue());
      return;
    }
    final step = _pendingAgentSteps.first;
    _pendingAgentSteps = _pendingAgentSteps.skip(1).toList();
    _activeAgentStep = step;
    _agentResultBuffer = StringBuffer();
    final stepIndex = _pendingAgentStepTotal - _pendingAgentSteps.length;
    _agentBridge?.sendSessionMessage(workspaceId, sessionId, step.text);
    final pendingId = _pendingAgentSessionId;
    if (pendingId.isNotEmpty) {
      _recordAgentEventBestEffort(
        taskId: (_savedTask ?? widget.existing)?.id ?? '',
        workspaceId: workspaceId,
        agentSessionId: pendingId,
        eventType: 'agent_queue_step_sent',
        payload: {
          'step': stepIndex,
          'total': _pendingAgentStepTotal,
          'label': step.label,
          'kind': step.kind.name,
        },
        requestedMode: widget.agentPolicy.mode,
      );
    }
  }

  void _finishActiveAgentStep({
    required String workspaceId,
    required String sessionId,
    required String taskStatus,
  }) {
    if (workspaceId.trim().isEmpty || sessionId.trim().isEmpty) {
      return;
    }
    _agentTaskPoller?.cancel();
    if (taskStatus == 'failed' || taskStatus == 'canceled') {
      _failAgentQueue('Один из шагов агента не выполнен: $taskStatus');
      return;
    }
    final step = _activeAgentStep;
    final resultText = _agentResultBuffer?.toString() ?? '';
    if (_mandatoryAgentStepFailed(step, resultText)) {
      _failAgentQueue(
        'family-task-card недоступен. Очередь агента остановлена.',
      );
      return;
    }
    _activeAgentStep = null;
    _agentResultBuffer = null;
    if (step?.kind == AgentLaunchStepKind.taskPrompt) {
      _applyAgentResultToCard(resultText);
    }
    _sendNextAgentStep(workspaceId: workspaceId, sessionId: sessionId);
  }

  bool _mandatoryAgentStepFailed(AgentLaunchStep? step, String resultText) {
    if (step == null) {
      return false;
    }
    final mandatory = step.kind == AgentLaunchStepKind.taskCardRead ||
        step.text.trim() == '/skill family-task-card';
    if (!mandatory) {
      return false;
    }
    final lower = resultText.toLowerCase();
    if (lower.trim().isEmpty) {
      return false;
    }
    return lower.contains('not found') ||
        lower.contains('unknown skill') ||
        lower.contains('command not found') ||
        lower.contains('no such file') ||
        lower.contains('не найден') ||
        lower.contains('не найдена') ||
        lower.contains('недоступ') ||
        lower.contains('ошибка') ||
        lower.contains('error') ||
        lower.contains('/familly-task-card');
  }

  void _failAgentQueue(String message) {
    final pendingId = _pendingAgentSessionId;
    setState(() {
      if (pendingId.isNotEmpty) {
        _markAgentSession(pendingId, status: 'error');
        _appendAgentActivity(
          type: 'agent_session_error',
          text: message,
          targetId: pendingId,
        );
      }
      _agentLaunchError = message;
      _clearAgentQueueState();
    });
    _autosaveNow();
    _showSnack(message);
  }

  Future<void> _completeAgentQueue() async {
    final pendingId = _pendingAgentSessionId;
    await _refreshAgentCardFromBackendBestEffort();
    if (!mounted) {
      return;
    }
    _forceReviewAfterSuccessfulAgentQueue(pendingId);
    final sessionStatus = _agentSessionStatusAfterQueue();
    final activityText = _agentQueueCompletionText(sessionStatus);
    if (pendingId.isNotEmpty) {
      _recordAgentEventBestEffort(
        taskId: (_savedTask ?? widget.existing)?.id ?? '',
        workspaceId: _pendingAgentWorkspaceId,
        agentSessionId: pendingId,
        eventType: 'agent_queue_completed',
        payload: {'steps': _pendingAgentStepTotal},
        requestedMode: widget.agentPolicy.mode,
      );
    }
    setState(() {
      if (pendingId.isNotEmpty) {
        _markAgentSession(pendingId, status: sessionStatus);
        _appendAgentActivity(
          type: 'agent_queue_completed',
          text: activityText,
          targetId: pendingId,
        );
      }
      _clearAgentQueueState();
    });
    _autosaveNow();
  }

  void _forceReviewAfterSuccessfulAgentQueue(String agentSessionId) {
    if (_status == WorkflowStatus.in_review ||
        _status == WorkflowStatus.done ||
        _status == WorkflowStatus.archive ||
        _hasOpenBlockingAgentQuestion()) {
      return;
    }
    setState(() {
      _status = WorkflowStatus.in_review;
      _appendAgentActivity(
        type: 'agent_status_changed',
        text: 'автоматически перевел карточку в статус На проверке',
        targetId: agentSessionId,
      );
    });
  }

  bool _hasOpenBlockingAgentQuestion() {
    return _collaboration.questions.any((question) {
      return question.blocking && question.isOpen;
    });
  }

  Future<void> _refreshAgentCardFromBackendBestEffort() async {
    final task = _savedTask ?? widget.existing;
    final workspaceId = _pendingAgentWorkspaceId.trim();
    if (task == null || task.id.trim().isEmpty || workspaceId.isEmpty) {
      return;
    }
    try {
      final contextPack = await widget.store.repository.api.fetchAgentContext(
        actorProfile: widget.store.owner.value,
        actorPhone: widget.actorPhone,
        taskId: task.id,
        workspaceId: workspaceId,
        taskType: _taskTypeForAgent(task),
        requestedMode: widget.agentPolicy.mode,
      );
      if (!mounted) {
        return;
      }
      setState(() => _applyAgentContextPack(contextPack));
    } catch (error) {
      debugPrint('Task agent backend card refresh skipped: $error');
    }
  }

  void _applyAgentContextPack(AgentContextPack contextPack) {
    final hasRemoteCardPayload = contextPack.comments.isNotEmpty ||
        contextPack.checklists.isNotEmpty ||
        contextPack.attachments.isNotEmpty ||
        contextPack.questions.isNotEmpty ||
        contextPack.activity.isNotEmpty ||
        contextPack.agentSessions.isNotEmpty;
    final status = _agentActionStatus(
      (contextPack.task['workflow_status'] ?? '').toString(),
    );
    if (status != null &&
        (hasRemoteCardPayload ||
            _workflowRank(status) >= _workflowRank(_status))) {
      _status = status;
    }
    final remoteComments =
        contextPack.comments.map(TaskComment.fromJson).toList();
    final remoteAttachments =
        contextPack.attachments.map(TaskAttachment.fromJson).toList();
    final remoteChecklists =
        contextPack.checklists.map(TaskChecklist.fromJson).toList();
    final remoteQuestions =
        contextPack.questions.map(TaskAgentQuestion.fromJson).toList();
    final remoteActivity =
        contextPack.activity.map(TaskActivityEntry.fromJson).toList();
    final remoteSessions =
        contextPack.agentSessions.map(TaskAgentSession.fromJson).toList();
    _collaboration = _collaboration.copyWith(
      comments: _mergeById(
        _collaboration.comments,
        remoteComments,
        (item) => item.id,
      ),
      attachments: _mergeById(
        _collaboration.attachments,
        remoteAttachments,
        (item) => item.id,
      ),
      checklists: _mergeById(
        _collaboration.checklists,
        remoteChecklists,
        (item) => item.id,
      ),
      questions: _mergeById(
        _collaboration.questions,
        remoteQuestions,
        (item) => item.id,
      ),
      activity: _mergeById(
        _collaboration.activity,
        remoteActivity,
        (item) => item.id,
      ),
      agentSessions: _mergeAgentSessions(
        _collaboration.agentSessions,
        remoteSessions,
      ),
    );
  }

  int _workflowRank(WorkflowStatus status) {
    switch (status) {
      case WorkflowStatus.todo:
        return 0;
      case WorkflowStatus.in_progress:
        return 1;
      case WorkflowStatus.in_review:
        return 2;
      case WorkflowStatus.done:
        return 3;
      case WorkflowStatus.archive:
        return 4;
    }
  }

  List<T> _mergeById<T>(
    List<T> local,
    List<T> remote,
    String Function(T item) idOf,
  ) {
    if (remote.isEmpty) {
      return local;
    }
    final remoteIds =
        remote.map(idOf).where((id) => id.trim().isNotEmpty).toSet();
    return [
      ...remote,
      ...local.where((item) {
        final id = idOf(item).trim();
        return id.isEmpty || !remoteIds.contains(id);
      }),
    ];
  }

  List<TaskAgentSession> _mergeAgentSessions(
    List<TaskAgentSession> local,
    List<TaskAgentSession> remote,
  ) {
    if (remote.isEmpty) {
      return local;
    }
    final localById = {for (final session in local) session.id: session};
    final mergedRemote = remote.map((session) {
      final localSession = localById[session.id];
      if (localSession == null) {
        return session;
      }
      return session.copyWith(
        provider: session.provider.trim().isNotEmpty
            ? session.provider
            : localSession.provider,
        model: session.model.trim().isNotEmpty
            ? session.model
            : localSession.model,
        approvalPolicy: session.approvalPolicy.trim().isNotEmpty
            ? session.approvalPolicy
            : localSession.approvalPolicy,
        sandboxMode: session.sandboxMode.trim().isNotEmpty
            ? session.sandboxMode
            : localSession.sandboxMode,
        autoMode: session.autoMode || localSession.autoMode,
        commandValues: session.commandValues.isNotEmpty
            ? session.commandValues
            : localSession.commandValues,
      );
    }).toList();
    return _mergeById(local, mergedRemote, (item) => item.id);
  }

  String _agentSessionStatusAfterQueue() {
    if (_status == WorkflowStatus.in_review) {
      return 'waiting_review';
    }
    if (_status == WorkflowStatus.done || _status == WorkflowStatus.archive) {
      return 'completed';
    }
    return 'linked';
  }

  String _agentQueueCompletionText(String status) {
    switch (status) {
      case 'waiting_review':
        return 'ждет проверки карточки';
      case 'completed':
        return 'завершил очередь агента';
      default:
        return 'ждет дальнейших правок';
    }
  }

  void _clearAgentQueueState() {
    _pendingAgentSessionId = '';
    _pendingAgentWorkspaceId = '';
    _pendingAgentBridgeSessionId = '';
    _pendingAgentSteps = const [];
    _pendingAgentStepTotal = 0;
    _activeAgentStep = null;
    _agentResultBuffer = null;
    _agentQueueActive = false;
    _agentLaunching = false;
    _pendingAgentTaskCard = const {};
  }

  void _changeWorkflowStatus(WorkflowStatus nextStatus) {
    final previousStatus = _status;
    setState(() {
      _status = nextStatus;
      if (nextStatus == WorkflowStatus.done ||
          nextStatus == WorkflowStatus.archive) {
        _markOpenAgentSessionsCompleted();
      }
    });
    _scheduleAutosave();
    if (previousStatus == WorkflowStatus.in_review &&
        nextStatus == WorkflowStatus.in_progress) {
      final session = _latestContinuableAgentSession(widget.agentPolicy);
      if (session != null) {
        _agentAutoResumeRequested = true;
        unawaited(_continueAgentSession(session));
      }
    }
  }

  void _maybeAutoResumeLatestAgentSession() {
    if (_agentAutoResumeRequested ||
        !_canEdit ||
        _status != WorkflowStatus.in_progress ||
        _agentQueueActive ||
        _agentLaunching) {
      return;
    }
    final session = _latestAutoContinuableAgentSession(widget.agentPolicy);
    if (session == null) {
      return;
    }
    _agentAutoResumeRequested = true;
    unawaited(_continueAgentSession(session));
  }

  TaskAgentSession? _latestContinuableAgentSession(AgentRunPolicy policy) {
    for (final session in _collaboration.agentSessions.reversed) {
      if (_canContinueAgentSession(session, policy)) {
        return session;
      }
    }
    return null;
  }

  TaskAgentSession? _latestAutoContinuableAgentSession(AgentRunPolicy policy) {
    for (final session in _collaboration.agentSessions.reversed) {
      if (_shouldAutoResumeAgentSession(session) &&
          _canContinueAgentSession(session, policy)) {
        return session;
      }
    }
    return null;
  }

  bool _shouldAutoResumeAgentSession(TaskAgentSession session) {
    switch (session.status.trim()) {
      case 'pending':
      case 'linked':
      case 'waiting_review':
      case 'blocked':
      case 'completed':
        return true;
      default:
        return false;
    }
  }

  void _markOpenAgentSessionsCompleted() {
    final sessions = _collaboration.agentSessions.map((session) {
      if (session.status == 'completed' || session.status == 'error') {
        return session;
      }
      return session.copyWith(status: 'completed');
    }).toList();
    _collaboration = _collaboration.copyWith(agentSessions: sessions);
  }

  void _scheduleAgentTaskPoll(
    String workspaceId,
    String sessionId,
    String taskId,
  ) {
    if (workspaceId.trim().isEmpty ||
        sessionId.trim().isEmpty ||
        taskId.trim().isEmpty) {
      return;
    }
    _agentTaskPoller?.cancel();
    _agentTaskPoller = Timer.periodic(const Duration(seconds: 2), (_) {
      _agentBridge?.pollSessionTask(workspaceId, sessionId, taskId);
    });
  }

  bool _isBridgeTaskDone(String status) {
    return status == 'completed' || status == 'failed' || status == 'canceled';
  }

  List<Map<String, dynamic>> _selectedAgentCommands() {
    return _selectedAgentCommandValues
        .map(
          (value) => _agentCommands.cast<Map<String, dynamic>?>().firstWhere(
                (command) =>
                    command != null && _agentCommandValue(command) == value,
                orElse: () => null,
              ),
        )
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  String _agentCommandValue(Map<String, dynamic> command) {
    return (command['value'] ?? '').toString().trim();
  }

  String _agentCommandLabel(Map<String, dynamic> command) {
    final label = (command['label'] ?? '').toString().trim();
    return label.isEmpty ? _agentCommandValue(command) : label;
  }

  String _agentCommandDescription(Map<String, dynamic> command) {
    return (command['description'] ?? '').toString().trim();
  }

  bool _isAgentSkillCommand(Map<String, dynamic> command) {
    final value = _agentCommandValue(command);
    final group = (command['group'] ?? '').toString().toLowerCase();
    return value.startsWith('/skill') || group == 'навыки';
  }

  void _toggleAgentCommand(String value, bool selected) {
    setState(() {
      final next = List<String>.from(_selectedAgentCommandValues);
      if (selected) {
        if (!next.contains(value)) {
          next.add(value);
        }
      } else {
        next.remove(value);
      }
      _selectedAgentCommandValues = next;
      _storeCurrentAgentSettings();
    });
    _autosaveNow();
  }

  void _moveAgentCommand(String value, int delta) {
    final next = List<String>.from(_selectedAgentCommandValues);
    final index = next.indexOf(value);
    if (index < 0) {
      return;
    }
    final newIndex = index + delta;
    if (newIndex < 0 || newIndex >= next.length) {
      return;
    }
    setState(() {
      next
        ..removeAt(index)
        ..insert(newIndex, value);
      _selectedAgentCommandValues = next;
      _storeCurrentAgentSettings();
    });
    _autosaveNow();
  }

  void _applyAgentTaskActionsFromText(String text) {
    final actions = AgentTaskActions.parse(text);
    final summary = AgentTaskActions.stripActionsBlock(text);
    if (actions.isEmpty && summary.trim().isEmpty) {
      return;
    }
    final now = DateTime.now().toIso8601String();
    final nextStatus = _agentActionStatus(actions.status);
    final newAttachments = actions.attachments.map((draft) {
      final filename = draft.filename.isNotEmpty
          ? draft.filename
          : draft.path.split(RegExp(r'[/\\]')).last;
      final mimeType = draft.mimeType.isNotEmpty
          ? draft.mimeType
          : _mimeTypeForName(filename);
      return TaskAttachment(
        id: _newId('attachment'),
        kind: _attachmentKind(filename, mimeType),
        filename: filename.isEmpty ? 'agent-report' : filename,
        mimeType: mimeType,
        assetUrl: draft.path,
        caption: draft.caption,
        authorProfile: 'agent',
        createdAt: now,
      );
    }).toList();
    final newComments = <TaskComment>[];
    final actionComments = actions.comments.isEmpty && summary.trim().isNotEmpty
        ? [summary.trim()]
        : actions.comments;
    for (final commentText in actionComments) {
      newComments.add(
        TaskComment(
          id: _newId('comment'),
          authorProfile: 'agent',
          text: commentText,
          createdAt: now,
          attachmentIds: newAttachments.map((item) => item.id).toList(),
        ),
      );
    }
    final newChecklists = actions.checklists.map((draft) {
      return TaskChecklist(
        id: _newId('checklist'),
        title: draft.title.isEmpty ? 'План агента' : draft.title,
        createdBy: 'agent',
        createdAt: now,
        items: draft.items
            .map(
              (text) => TaskChecklistItem(
                id: _newId('checklist-item'),
                text: text,
                createdAt: now,
                createdBy: 'agent',
              ),
            )
            .toList(),
      );
    }).toList();
    final activity = [
      ..._collaboration.activity,
      if (nextStatus != null && nextStatus != _status)
        _activity(
          type: 'agent_status_changed',
          text:
              'перевел карточку в статус ${_agentWorkflowStatusLabel(nextStatus)}',
          targetId: _pendingAgentSessionId,
        ),
      _activity(
        type: 'agent_card_updated',
        text: 'обновил карточку задачи',
        targetId: _pendingAgentSessionId,
      ),
    ];
    setState(() {
      if (nextStatus != null) {
        _status = nextStatus;
      }
      _collaboration = _collaboration.copyWith(
        comments: [..._collaboration.comments, ...newComments],
        attachments: [..._collaboration.attachments, ...newAttachments],
        checklists: [..._collaboration.checklists, ...newChecklists],
        activity: activity,
      );
    });
    _requestAgentActionAttachmentFiles(newAttachments);
    _autosaveNow();
  }

  void _applyAgentResultToCard(String text) {
    if (_applyAgentContextPackFromText(text)) {
      _autosaveNow();
      return;
    }
    _applyAgentTaskActionsFromText(text);
  }

  bool _applyAgentContextPackFromText(String text) {
    for (final json in _jsonMapsFromText(text)) {
      final rawSnapshot = json['snapshot'] ?? json['context'];
      if (rawSnapshot is! Map && json['task'] is! Map) {
        continue;
      }
      final rawPack = rawSnapshot is Map ? rawSnapshot : json;
      final pack = AgentContextPack.fromJson(
        Map<String, dynamic>.from(rawPack),
      );
      if (!_hasAgentContextPayload(pack)) {
        continue;
      }
      setState(() => _applyAgentContextPack(pack));
      return true;
    }
    return false;
  }

  bool _hasAgentContextPayload(AgentContextPack pack) {
    return (pack.task['workflow_status'] ?? '').toString().trim().isNotEmpty ||
        pack.comments.isNotEmpty ||
        pack.checklists.isNotEmpty ||
        pack.attachments.isNotEmpty ||
        pack.questions.isNotEmpty ||
        pack.activity.isNotEmpty ||
        pack.agentSessions.isNotEmpty;
  }

  Iterable<Map<String, dynamic>> _jsonMapsFromText(String text) sync* {
    for (var start = 0; start < text.length; start += 1) {
      if (text.codeUnitAt(start) != 123) {
        continue;
      }
      var depth = 0;
      var inString = false;
      var escaped = false;
      for (var index = start; index < text.length; index += 1) {
        final unit = text.codeUnitAt(index);
        if (inString) {
          if (escaped) {
            escaped = false;
          } else if (unit == 92) {
            escaped = true;
          } else if (unit == 34) {
            inString = false;
          }
          continue;
        }
        if (unit == 34) {
          inString = true;
          continue;
        }
        if (unit == 123) {
          depth += 1;
        } else if (unit == 125) {
          depth -= 1;
          if (depth == 0) {
            final candidate = text.substring(start, index + 1);
            try {
              final decoded = jsonDecode(candidate);
              if (decoded is Map) {
                yield Map<String, dynamic>.from(decoded);
              }
            } on FormatException {
              // Ignore non-JSON braces from the agent output.
            }
            start = index;
            break;
          }
        }
      }
    }
  }

  void _requestAgentActionAttachmentFiles(List<TaskAttachment> attachments) {
    final workspaceId = _pendingAgentWorkspaceId.trim();
    if (workspaceId.isEmpty || attachments.isEmpty) {
      return;
    }
    for (final attachment in attachments) {
      final path = attachment.assetUrl.trim();
      if (!_isWorkspaceAttachmentPath(path)) {
        continue;
      }
      _pendingAgentAttachmentReads[_agentAttachmentReadKey(workspaceId, path)] =
          attachment.id;
      _agentBridge?.requestWorkspaceFileRead(workspaceId, path);
    }
  }

  void _applyAgentWorkspaceFileContent(CodeWhaleBridgeMessage message) {
    final workspaceId = message.workspaceId.trim();
    final path = message.filePath.trim();
    if (workspaceId.isEmpty || path.isEmpty) {
      return;
    }
    final attachmentId = _pendingAgentAttachmentReads.remove(
      _agentAttachmentReadKey(
        workspaceId,
        path,
      ),
    );
    if (attachmentId == null || attachmentId.isEmpty) {
      return;
    }
    final dataBase64 = message.fileDataBase64.trim().isNotEmpty
        ? message.fileDataBase64.trim()
        : message.fileText.trim().isEmpty
            ? ''
            : base64Encode(utf8.encode(message.fileText));
    setState(() {
      _collaboration = _collaboration.copyWith(
        attachments: _collaboration.attachments.map((attachment) {
          if (attachment.id != attachmentId) {
            return attachment;
          }
          return attachment.copyWith(
            dataBase64: dataBase64,
            mimeType: message.mimeType.trim().isNotEmpty
                ? message.mimeType.trim()
                : attachment.mimeType,
            sizeBytes:
                message.fileSize > 0 ? message.fileSize : attachment.sizeBytes,
          );
        }).toList(),
      );
    });
    _autosaveNow();
  }

  bool _isWorkspaceAttachmentPath(String path) {
    final value = path.trim();
    if (value.isEmpty) {
      return false;
    }
    return !value.startsWith('http://') &&
        !value.startsWith('https://') &&
        !value.startsWith('file://') &&
        !value.startsWith('content://') &&
        !value.startsWith('/');
  }

  String _agentAttachmentReadKey(String workspaceId, String path) {
    return '${workspaceId.trim()}::${path.trim().replaceAll('\\', '/')}';
  }

  WorkflowStatus? _agentActionStatus(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return null;
    }
    return WorkflowStatus.values.cast<WorkflowStatus?>().firstWhere(
          (item) => item?.name == value,
          orElse: () => null,
        );
  }

  String _agentWorkflowStatusLabel(WorkflowStatus status) {
    switch (status) {
      case WorkflowStatus.todo:
        return 'К выполнению';
      case WorkflowStatus.in_progress:
        return 'В работе';
      case WorkflowStatus.in_review:
        return 'На проверке';
      case WorkflowStatus.done:
        return 'Выполнено';
      case WorkflowStatus.archive:
        return 'Архив';
    }
  }

  String _attachmentKind(String filename, String mimeType) {
    final lower = '$filename $mimeType'.toLowerCase();
    if (lower.contains('image/') ||
        lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif')) {
      return 'photo';
    }
    return 'file';
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
    unawaited(_connectAgentChatFlow());
  }

  Future<void> _connectAgentChatFlow() async {
    final policy = widget.agentPolicy;
    final text = TaskEditorText.of(context);
    if (!_canEdit) return;
    if (!policy.canLinkExistingChat) {
      _showSnack(
        policy.reason.isEmpty ? text.agentConnectNoAccess : policy.reason,
      );
      return;
    }
    await _persistDraft(automatic: true);
    final saved = _savedTask ?? widget.existing;
    if (saved == null || saved.id.trim().isEmpty) {
      _showSnack(text.saveTaskFirst);
      return;
    }
    final bridge = _ensureAgentBridge();
    try {
      final connected = await bridge.connect();
      if (!connected) {
        throw StateError(text.codeWhaleUnavailable);
      }
      await _requestAgentWorkspaces(bridge);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack(text.agentWorkspacesLoadFailed(error));
      return;
    }
    final workspaceId = _effectiveAgentWorkspaceId(policy);
    if (workspaceId.trim().isEmpty) {
      final message = text.selectAgentWorkspace;
      setState(() => _agentLaunchError = message);
      _showSnack(message);
      return;
    }
    final sessions = await _requestAgentSessions(bridge, workspaceId);
    if (!mounted) {
      return;
    }
    if (sessions.isEmpty) {
      _showSnack(text.noAgentChatsInWorkspace);
      return;
    }
    final selected = await _showAgentSessionPicker(sessions);
    if (!mounted || selected == null) {
      return;
    }
    await _linkAgentSession(saved, policy, bridge, selected);
  }

  Future<WorkspaceSession?> _showAgentSessionPicker(
    List<WorkspaceSession> sessions,
  ) {
    final text = TaskEditorText.of(context);
    return showModalBottomSheet<WorkspaceSession>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _SectionHeader(
                icon: Icons.forum_outlined,
                title: text.selectAgentChat,
                trailing: '',
              ),
              const SizedBox(height: 8),
              for (final session in sessions)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.smart_toy_outlined),
                  title: Text(
                    session.title.trim().isEmpty
                        ? text.agentChat
                        : session.title.trim(),
                  ),
                  subtitle: Text(
                    [
                      _workspaceSessionStatusText(session.status),
                      if (session.provider.trim().isNotEmpty) session.provider,
                      if (session.model.trim().isNotEmpty) session.model,
                    ].join(' · '),
                  ),
                  onTap: () => Navigator.of(context).pop(session),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _linkAgentSession(
    TaskItem saved,
    AgentRunPolicy policy,
    CodeWhaleBridgeService bridge,
    WorkspaceSession bridgeSession,
  ) async {
    final text = TaskEditorText.of(context);
    final workspaceId = bridgeSession.workspaceId.trim().isNotEmpty
        ? bridgeSession.workspaceId.trim()
        : _effectiveAgentWorkspaceId(policy);
    if (workspaceId.isEmpty || bridgeSession.id.trim().isEmpty) {
      _showSnack(text.agentChatNotLinkedToWorkspace);
      return;
    }
    final now = DateTime.now().toIso8601String();
    final existing =
        _collaboration.agentSessions.cast<TaskAgentSession?>().firstWhere(
              (session) =>
                  session?.workspaceId == workspaceId &&
                  session?.sessionId == bridgeSession.id,
              orElse: () => null,
            );
    final session = (existing ??
            TaskAgentSession(
              id: _newId('agent-session'),
              workspaceId: workspaceId,
              sessionId: bridgeSession.id,
              title: bridgeSession.title.trim().isEmpty
                  ? text.connectedAgentChatTitle
                  : bridgeSession.title.trim(),
              mode: policy.mode,
              status: 'linked',
              createdBy: widget.store.owner.value,
              createdAt: now,
            ))
        .copyWith(
      workspaceId: workspaceId,
      sessionId: bridgeSession.id,
      title: bridgeSession.title.trim().isEmpty
          ? (existing?.title.isNotEmpty == true
              ? existing!.title
              : text.connectedAgentChatTitle)
          : bridgeSession.title.trim(),
      mode: policy.mode.trim().isNotEmpty ? policy.mode : existing?.mode,
      status: 'linked',
      provider: bridgeSession.provider.trim().isNotEmpty
          ? bridgeSession.provider
          : _agentProvider,
      model: bridgeSession.model.trim().isNotEmpty
          ? bridgeSession.model
          : _agentModel,
      approvalPolicy: bridgeSession.approvalPolicy.trim().isNotEmpty
          ? bridgeSession.approvalPolicy
          : _agentApprovalPolicy,
      sandboxMode: bridgeSession.sandboxMode.trim().isNotEmpty
          ? bridgeSession.sandboxMode
          : _agentSandboxMode,
      autoMode: bridgeSession.autoMode || _agentAutoMode,
      commandValues: List<String>.from(_selectedAgentCommandValues),
    );
    try {
      final api = widget.store.repository.api;
      final taskType = _taskTypeForAgent(saved);
      final requestedMode =
          session.mode.trim().isNotEmpty ? session.mode.trim() : policy.mode;
      final ticket = await api.requestAgentTicket(
        actorProfile: widget.store.owner.value,
        actorPhone: widget.actorPhone,
        taskId: saved.id,
        taskType: taskType,
        workspaceId: workspaceId,
        requestedMode: requestedMode,
      );
      final taskCard = {
        'task_id': saved.id,
        'agent_session_id': session.id,
        'actor_profile': widget.store.owner.value,
        'actor_phone': widget.actorPhone,
        'api_url': api.baseUrl,
        'policy_ticket': ticket.policyTicket,
        'task_type': taskType,
        'mode': requestedMode,
        'workspace_id': workspaceId,
      };
      setState(() {
        _selectedAgentWorkspaceId = workspaceId;
        _agentWorkspaceManuallySelected = true;
        _agentProvider = session.provider;
        _agentModel = session.model;
        _agentApprovalPolicy = session.approvalPolicy;
        _agentSandboxMode = session.sandboxMode;
        _agentAutoMode = session.autoMode;
        _selectedAgentCommandValues = List<String>.from(
          session.commandValues,
        );
        _storeCurrentAgentSettings();
        _upsertAgentSession(session);
        _appendAgentActivity(
          type: 'agent_session_linked',
          text: 'подключил существующий агентский чат',
          targetId: session.id,
        );
        if (_status == WorkflowStatus.todo) {
          _status = WorkflowStatus.in_progress;
        }
      });
      _recordAgentSessionBestEffort(
        taskId: saved.id,
        workspaceId: workspaceId,
        agentSessionId: session.id,
        sessionId: bridgeSession.id,
        title: session.title,
        taskType: taskType,
        requestedMode: requestedMode,
        status: 'linked',
      );
      bridge.updatePolicyTicket(ticket.policyTicket);
      bridge.updateSessionTaskCard(
        workspaceId: workspaceId,
        sessionId: bridgeSession.id,
        taskCard: taskCard,
      );
      bridge.updateSessionSettings(
        workspaceId: workspaceId,
        sessionId: bridgeSession.id,
        provider: _sessionProvider(session),
        model: _sessionModel(session),
        approvalPolicy: _sessionApprovalPolicy(session),
        sandboxMode: _sessionSandboxMode(session),
        autoMode: _sessionAutoMode(session),
      );
      bridge.openSession(workspaceId, bridgeSession.id);
      _autosaveNow();
      _showSnack(text.agentChatConnectedToCard);
    } catch (error) {
      _showSnack(text.agentChatConnectFailed(error));
    }
  }

  String _workspaceSessionStatusText(WorkspaceSessionStatus status) {
    final text = TaskEditorText.of(context);
    switch (status) {
      case WorkspaceSessionStatus.idle:
        return text.sessionStatusIdle;
      case WorkspaceSessionStatus.running:
        return text.sessionStatusRunning;
      case WorkspaceSessionStatus.stopped:
        return text.sessionStatusStopped;
      case WorkspaceSessionStatus.killed:
        return text.sessionStatusKilled;
      case WorkspaceSessionStatus.error:
        return text.sessionStatusError;
      case WorkspaceSessionStatus.unknown:
        return text.sessionStatusUnknown;
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = TaskEditorText.of(context);
    final title = widget.existing == null ? text.newTask : text.editTask;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          bottom: TabBar(
            tabs: [
              Tab(icon: const Icon(Icons.tune), text: text.settingsTab),
              Tab(icon: const Icon(Icons.forum_outlined), text: text.workTab),
              Tab(
                icon: const Icon(Icons.smart_toy_outlined),
                text: text.agentTab,
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: text.save,
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
    final text = TaskEditorText.of(context);
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
          decoration: InputDecoration(labelText: text.title),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _projectList.any((p) => p.id == _selectedProjectId)
              ? _selectedProjectId
              : null,
          decoration: InputDecoration(labelText: text.project),
          hint: Text(text.selectProject),
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
            decoration: InputDecoration(labelText: text.group),
            hint: Text(text.selectGroup),
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
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(text.projectHasNoGroups),
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
          decoration: InputDecoration(labelText: text.priority),
          items: [
            DropdownMenuItem(value: Priority.low, child: Text(text.low)),
            DropdownMenuItem(value: Priority.medium, child: Text(text.medium)),
            DropdownMenuItem(value: Priority.high, child: Text(text.high)),
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
          decoration: InputDecoration(labelText: text.status),
          items: [
            DropdownMenuItem(
              value: WorkflowStatus.todo,
              child: Text(text.workflowTodo),
            ),
            DropdownMenuItem(
              value: WorkflowStatus.in_progress,
              child: Text(text.workflowInProgress),
            ),
            DropdownMenuItem(
              value: WorkflowStatus.in_review,
              child: Text(text.workflowInReview),
            ),
            DropdownMenuItem(
              value: WorkflowStatus.done,
              child: Text(text.workflowDone),
            ),
            DropdownMenuItem(
              value: WorkflowStatus.archive,
              child: Text(text.workflowArchive),
            ),
          ],
          onChanged: !_canEdit
              ? null
              : (value) {
                  _changeWorkflowStatus(value ?? WorkflowStatus.todo);
                },
        ),
        const SizedBox(height: 16),
        Text(text.assignees, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (isProjectTask && selectedGroup == null)
          Text(text.selectProjectGroup)
        else if (selectedGroup != null && assigneeContacts.isEmpty)
          Text(text.groupMembersMissing)
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
        Text(text.reminders, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _reminderOptions.map((offset) {
            return FilterChip(
              label: Text(text.reminderLabel(offset)),
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
          decoration: InputDecoration(labelText: text.duration),
        ),
      ],
    );
  }

  Widget _buildWorkTab() {
    final text = TaskEditorText.of(context);
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
          decoration: InputDecoration(
            labelText: text.details,
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 18),
        _SectionHeader(
          icon: Icons.forum_outlined,
          title: text.comments,
          trailing: '${_collaboration.commentCount}',
        ),
        const SizedBox(height: 10),
        if (_collaboration.comments.isEmpty)
          _EmptyLine(
            icon: Icons.chat_bubble_outline,
            text: text.noComments,
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
          title: text.checklists,
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
                decoration: InputDecoration(labelText: text.newChecklist),
                onSubmitted: (_) => _addChecklist(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: text.addChecklist,
              onPressed: _canEdit ? _addChecklist : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_collaboration.checklists.isEmpty)
          _EmptyLine(
            icon: Icons.playlist_add_check,
            text: text.noChecklists,
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
          title: text.activity,
          trailing: '${_collaboration.activity.length}',
        ),
        const SizedBox(height: 10),
        if (_collaboration.activity.isEmpty)
          _EmptyLine(icon: Icons.bolt_outlined, text: text.activityEmpty)
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
    final text = TaskEditorText.of(context);
    if (policy.allowed &&
        !_agentWorkspaceAutoRequested &&
        !_agentWorkspacesLoading &&
        _agentWorkspaces.isEmpty) {
      _agentWorkspaceAutoRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_refreshAgentWorkspaces());
        }
      });
    }
    final workspaceId = _effectiveAgentWorkspaceId(policy);
    final continuationSession = _latestContinuableAgentSession(policy);
    final canContinueVisible = continuationSession != null &&
        !_agentQueueActive &&
        !_agentLaunching &&
        _canEdit;
    final openQuestions = _collaboration.questions
        .where((question) => question.isOpen)
        .toList(growable: false);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        _SectionHeader(
          icon: Icons.smart_toy_outlined,
          title: text.agent,
          trailing: policy.allowed
              ? (policy.modeLabel.isEmpty
                  ? text.agentAccessGranted
                  : policy.modeLabel)
              : text.agentNoAccess,
        ),
        const SizedBox(height: 10),
        if (!policy.allowed && policy.reason.trim().isNotEmpty) ...[
          Text(policy.reason),
          const SizedBox(height: 14),
        ],
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
            if (workspaceId.isNotEmpty)
              _MetricChip(
                icon: Icons.workspaces_outline,
                text: workspaceId,
              ),
          ],
        ),
        const SizedBox(height: 18),
        if (openQuestions.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.help_outline,
            title: text.agentQuestions,
            trailing: '${openQuestions.length}',
          ),
          const SizedBox(height: 10),
          ...openQuestions.map((question) {
            return _AgentQuestionTile(question: question);
          }),
          const SizedBox(height: 18),
        ],
        _buildAgentWorkspacePanel(policy),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.link),
                label: Text(
                  _agentSessionsLoading
                      ? text.agentLoadingChats
                      : text.agentConnectChat,
                ),
                onPressed: _canEdit &&
                        policy.canLinkExistingChat &&
                        !_agentSessionsLoading
                    ? _connectAgentChat
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.add_comment_outlined),
                label: Text(
                  _agentQueueActive
                      ? text.agentQueueRunning
                      : text.agentNewChat,
                ),
                onPressed:
                    _canEdit && policy.canStartAgentChat && !_agentQueueActive
                        ? _requestNewAgentChat
                        : null,
              ),
            ),
          ],
        ),
        if (canContinueVisible) ...[
          const SizedBox(height: 12),
          _AgentContinuationPanel(
            title: continuationSession.title.isEmpty
                ? text.agentChat
                : continuationSession.title,
            onPressed: () => _continueAgentSession(continuationSession),
          ),
        ],
        _buildAgentModePanel(),
        const SizedBox(height: 22),
        _buildAgentToolsPanel(),
        const SizedBox(height: 22),
        _buildAgentQueuePanel(),
        const SizedBox(height: 22),
        _SectionHeader(
          icon: Icons.forum_outlined,
          title: text.agentTaskChats,
          trailing: '${_collaboration.agentSessionCount}',
        ),
        const SizedBox(height: 10),
        if (_collaboration.agentSessions.isEmpty)
          _EmptyLine(
            icon: Icons.chat_bubble_outline,
            text: text.agentNoChats,
          )
        else
          ..._collaboration.agentSessions.map(
            (session) => _AgentSessionRow(
              session: session,
              canContinue: _canContinueAgentSession(session, policy) &&
                  !_agentQueueActive &&
                  !_agentLaunching,
              onContinue: () => _continueAgentSession(session),
            ),
          ),
      ],
    );
  }

  Widget _buildAgentWorkspacePanel(AgentRunPolicy policy) {
    final text = TaskEditorText.of(context);
    final selected = _effectiveAgentWorkspaceId(policy);
    final ids = _agentWorkspaces.map((item) => item.id).toSet();
    final selectedValue = ids.contains(selected) ? selected : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          icon: Icons.workspaces_outline,
          title: text.workspace,
          trailing: selected.isEmpty ? text.workspaceNotSelected : selected,
        ),
        const SizedBox(height: 10),
        if (_agentWorkspacesLoading) const LinearProgressIndicator(),
        if (_agentWorkspaces.isEmpty)
          _EmptyLine(
            icon: Icons.cloud_off_outlined,
            text: text.workspaceListNotLoaded,
          )
        else
          DropdownButtonFormField<String>(
            key: ValueKey(
              'agent-workspace-$selected-${_agentWorkspaces.length}',
            ),
            initialValue: selectedValue,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: text.workspaceField,
              border: const OutlineInputBorder(),
            ),
            items: _agentWorkspaces.map((workspace) {
              final title = workspace.name.trim().isEmpty
                  ? workspace.id
                  : workspace.name.trim();
              final label =
                  title == workspace.id ? title : '$title · ${workspace.id}';
              return DropdownMenuItem<String>(
                value: workspace.id,
                child: Text(label, overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: !_canEdit
                ? null
                : (value) {
                    setState(() {
                      _selectedAgentWorkspaceId = value ?? '';
                      _agentWorkspaceManuallySelected =
                          _selectedAgentWorkspaceId.trim().isNotEmpty;
                      _agentLaunchError = '';
                      _storeCurrentAgentSettings();
                    });
                    _autosaveNow();
                  },
          ),
        if (_agentLaunchError.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _agentLaunchError,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _agentWorkspacesLoading
                ? null
                : () => unawaited(_refreshAgentWorkspaces()),
            icon: const Icon(Icons.refresh),
            label: Text(text.refresh),
          ),
        ),
      ],
    );
  }

  Widget _buildAgentModePanel() {
    final text = TaskEditorText.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          icon: Icons.tune,
          title: text.launchMode,
          trailing: _agentAutoMode ? text.launchAuto : text.launchManual,
        ),
        const SizedBox(height: 10),
        _AgentModeDropdown(
          label: text.agentProvider,
          value: _agentProvider,
          values: const [
            '',
            'deepseek',
            'openrouter',
            'openai',
            'nvidia-nim',
            'ollama',
            'moonshot',
            'xiaomi',
          ],
          onChanged: (value) {
            setState(() {
              _agentProvider = value;
              _storeCurrentAgentSettings();
            });
            _autosaveNow();
          },
        ),
        const SizedBox(height: 8),
        _AgentModeDropdown(
          label: text.agentModel,
          value: _agentModel,
          values: const [
            '',
            'deepseek-v4-pro',
            'deepseek-v4-flash',
            'deepseek-coder:1.3b',
            'kimi-k2.6',
          ],
          onChanged: (value) {
            setState(() {
              _agentModel = value;
              _storeCurrentAgentSettings();
            });
            _autosaveNow();
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _AgentModeDropdown(
                label: text.agentConfirmations,
                value: _agentApprovalPolicy,
                values: const ['', 'on-request', 'on-failure', 'never'],
                onChanged: (value) {
                  setState(() {
                    _agentApprovalPolicy = value;
                    _storeCurrentAgentSettings();
                  });
                  _autosaveNow();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _AgentModeDropdown(
                label: 'Sandbox',
                value: _agentSandboxMode,
                values: const ['', 'read-only', 'workspace-write'],
                onChanged: (value) {
                  setState(() {
                    _agentSandboxMode = value;
                    _storeCurrentAgentSettings();
                  });
                  _autosaveNow();
                },
              ),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(text.agentToolAutoMode),
          value: _agentAutoMode,
          onChanged: (value) {
            setState(() {
              _agentAutoMode = value;
              _storeCurrentAgentSettings();
            });
            _autosaveNow();
          },
        ),
      ],
    );
  }

  Widget _buildAgentToolsPanel() {
    final text = TaskEditorText.of(context);
    final skillCommands = _agentCommands.where(_isAgentSkillCommand).toList();
    final otherCommands = _agentCommands.where((command) {
      return !_isAgentSkillCommand(command);
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          icon: Icons.extension_outlined,
          title: text.agentTools,
          trailing: '${_agentCommands.length}',
        ),
        const SizedBox(height: 10),
        if (_agentCommandsLoading) const LinearProgressIndicator(),
        if (_agentCommands.isEmpty)
          _EmptyLine(
            icon: Icons.refresh,
            text: _agentCommandsLoading
                ? text.agentToolsLoading
                : text.agentToolsNotLoaded,
          )
        else ...[
          if (skillCommands.isNotEmpty)
            _buildAgentCommandGroup(text.agentSkills, skillCommands, text),
          if (otherCommands.isNotEmpty)
            _buildAgentCommandGroup(text.agentCommands, otherCommands, text),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _agentCommandsLoading ? null : _loadAgentCommands,
            icon: const Icon(Icons.refresh),
            label: Text(text.refresh),
          ),
        ),
      ],
    );
  }

  Widget _buildAgentCommandGroup(
    String title,
    List<Map<String, dynamic>> commands,
    TaskEditorText text,
  ) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(text.agentAvailableCount(commands.length)),
      children: [
        for (final command in commands)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _selectedAgentCommandValues.contains(
              _agentCommandValue(command),
            ),
            title: Text(_agentCommandLabel(command)),
            subtitle: _agentCommandDescription(command).isEmpty
                ? null
                : Text(_agentCommandDescription(command)),
            onChanged: (value) {
              _toggleAgentCommand(_agentCommandValue(command), value == true);
            },
          ),
      ],
    );
  }

  Widget _buildAgentQueuePanel() {
    final text = TaskEditorText.of(context);
    final selected = _selectedAgentCommands();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          icon: Icons.playlist_play,
          title: text.agentQueue,
          trailing: '${selected.length + 1}',
        ),
        const SizedBox(height: 10),
        if (selected.isEmpty)
          _EmptyLine(
            icon: Icons.info_outline,
            text: text.agentQueueHint,
          )
        else
          ...selected.asMap().entries.map((entry) {
            final value = _agentCommandValue(entry.value);
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Text('${entry.key + 1}'),
              title: Text(_agentCommandLabel(entry.value)),
              subtitle: Text(value),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: text.moveUp,
                    onPressed: entry.key == 0
                        ? null
                        : () => _moveAgentCommand(value, -1),
                    icon: const Icon(Icons.keyboard_arrow_up),
                  ),
                  IconButton(
                    tooltip: text.moveDown,
                    onPressed: entry.key == selected.length - 1
                        ? null
                        : () => _moveAgentCommand(value, 1),
                    icon: const Icon(Icons.keyboard_arrow_down),
                  ),
                ],
              ),
            );
          }),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.flag_outlined),
          title: Text(text.workStep),
          subtitle: Text(text.workStepSubtitle),
        ),
      ],
    );
  }

  String _profileLabel(String profile) {
    final text = TaskEditorText.of(context);
    if (profile == 'agent') {
      return text.agent;
    }
    final contact = widget.knownContacts.cast<ChatContact?>().firstWhere(
          (item) => item?.profileKey == profile,
          orElse: () => null,
        );
    if (contact != null) {
      return widget.contactLabel(contact);
    }
    return profile.isEmpty ? text.user : profile;
  }
}
