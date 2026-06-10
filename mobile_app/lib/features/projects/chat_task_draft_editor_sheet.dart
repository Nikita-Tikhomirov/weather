import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/project_control_models.dart';
import '../../models/task_item.dart';

class _ChatTaskDraftEditorText {
  const _ChatTaskDraftEditorText(this.l10n);

  final AppLocalizations? l10n;

  String get draft => l10n?.chatTaskDraft ?? 'Черновик задачи';
  String get title => l10n?.taskTitle ?? 'Заголовок';
  String get details => l10n?.taskDetails ?? 'Описание';
  String get summary => l10n?.taskSummary ?? 'Резюме';
  String get checklist => l10n?.checklist ?? 'Чеклист';
  String get actionItems => l10n?.actionItems ?? 'Action items';
  String get decisions => l10n?.decisions ?? 'Решения';
  String get blockers => l10n?.blockers ?? 'Блокеры';
  String get assignees => l10n?.taskAssignees ?? 'Ответственные';
  String get sources => l10n?.sources ?? 'Источники';
  String get priority => l10n?.priority ?? 'Приоритет';
  String get low => l10n?.low ?? 'Низкий';
  String get medium => l10n?.medium ?? 'Средний';
  String get high => l10n?.high ?? 'Высокий';
  String get cancel => l10n?.cancel ?? 'Отмена';
  String get createTask => l10n?.createTask ?? 'Создать задачу';
  String get taskFromChat => l10n?.taskFromChat ?? 'Задача из чата';
}

class ChatTaskDraftEditorSheet extends StatefulWidget {
  const ChatTaskDraftEditorSheet({
    super.key,
    required this.initialDraft,
    required this.onCancel,
    required this.onConfirm,
  });

  final ChatTaskDraft initialDraft;
  final VoidCallback onCancel;
  final ValueChanged<ChatTaskDraft> onConfirm;

  @override
  State<ChatTaskDraftEditorSheet> createState() =>
      _ChatTaskDraftEditorSheetState();
}

class _ChatTaskDraftEditorSheetState extends State<ChatTaskDraftEditorSheet> {
  late final TextEditingController _titleCtl;
  late final TextEditingController _detailsCtl;
  late final TextEditingController _summaryCtl;
  late final TextEditingController _decisionsCtl;
  late final TextEditingController _actionItemsCtl;
  late final TextEditingController _blockersCtl;
  late final TextEditingController _checklistCtl;
  late final TextEditingController _assigneesCtl;
  late final TextEditingController _sourcesCtl;
  late Priority _priority;

  @override
  void initState() {
    super.initState();
    final draft = widget.initialDraft;
    _titleCtl = TextEditingController(text: draft.title);
    _detailsCtl = TextEditingController(text: draft.details);
    _summaryCtl = TextEditingController(text: draft.summary);
    _decisionsCtl = TextEditingController(text: draft.decisions.join('\n'));
    _actionItemsCtl = TextEditingController(text: draft.actionItems.join('\n'));
    _blockersCtl = TextEditingController(text: draft.blockers.join('\n'));
    _checklistCtl = TextEditingController(text: draft.checklist.join('\n'));
    _assigneesCtl = TextEditingController(text: draft.assignees.join(', '));
    _sourcesCtl =
        TextEditingController(text: draft.sourceMessageIds.join(', '));
    _priority = draft.priority;
  }

  @override
  void dispose() {
    _titleCtl.dispose();
    _detailsCtl.dispose();
    _summaryCtl.dispose();
    _decisionsCtl.dispose();
    _actionItemsCtl.dispose();
    _blockersCtl.dispose();
    _checklistCtl.dispose();
    _assigneesCtl.dispose();
    _sourcesCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _ChatTaskDraftEditorText(AppLocalizations.of(context));
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text.draft,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('chat-draft-title-field'),
              controller: _titleCtl,
              decoration: InputDecoration(labelText: text.title),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('chat-draft-details-field'),
              controller: _detailsCtl,
              decoration: InputDecoration(labelText: text.details),
              minLines: 3,
              maxLines: 6,
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('chat-draft-summary-field'),
              controller: _summaryCtl,
              decoration: InputDecoration(labelText: text.summary),
              minLines: 1,
              maxLines: 3,
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('chat-draft-checklist-field'),
              controller: _checklistCtl,
              decoration: InputDecoration(labelText: text.checklist),
              minLines: 2,
              maxLines: 6,
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('chat-draft-action-items-field'),
              controller: _actionItemsCtl,
              decoration: InputDecoration(labelText: text.actionItems),
              minLines: 2,
              maxLines: 5,
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('chat-draft-decisions-field'),
              controller: _decisionsCtl,
              decoration: InputDecoration(labelText: text.decisions),
              minLines: 1,
              maxLines: 4,
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('chat-draft-blockers-field'),
              controller: _blockersCtl,
              decoration: InputDecoration(labelText: text.blockers),
              minLines: 1,
              maxLines: 4,
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('chat-draft-assignees-field'),
              controller: _assigneesCtl,
              decoration: InputDecoration(labelText: text.assignees),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('chat-draft-sources-field'),
              controller: _sourcesCtl,
              decoration: InputDecoration(labelText: text.sources),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<Priority>(
              key: const ValueKey('chat-draft-priority-field'),
              initialValue: _priority,
              decoration: InputDecoration(labelText: text.priority),
              items: [
                DropdownMenuItem(value: Priority.low, child: Text(text.low)),
                DropdownMenuItem(
                  value: Priority.medium,
                  child: Text(text.medium),
                ),
                DropdownMenuItem(value: Priority.high, child: Text(text.high)),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _priority = value);
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  key: const ValueKey('chat-draft-cancel'),
                  onPressed: widget.onCancel,
                  child: Text(text.cancel),
                ),
                const Spacer(),
                FilledButton.icon(
                  key: const ValueKey('chat-draft-confirm'),
                  icon: const Icon(Icons.check),
                  onPressed: () => widget.onConfirm(_buildDraft(text)),
                  label: Text(text.createTask),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  ChatTaskDraft _buildDraft(_ChatTaskDraftEditorText text) {
    final fallbackTitle = widget.initialDraft.title.trim().isNotEmpty
        ? widget.initialDraft.title.trim()
        : text.taskFromChat;
    return ChatTaskDraft(
      title:
          _titleCtl.text.trim().isEmpty ? fallbackTitle : _titleCtl.text.trim(),
      details: _detailsCtl.text.trim(),
      summary: _summaryCtl.text.trim(),
      decisions: _splitLines(_decisionsCtl.text),
      actionItems: _splitLines(_actionItemsCtl.text),
      blockers: _splitLines(_blockersCtl.text),
      checklist: _splitLines(_checklistCtl.text),
      assignees: _splitPeople(_assigneesCtl.text),
      sourceMessageIds: _splitPeople(_sourcesCtl.text),
      priority: _priority,
    );
  }

  List<String> _splitLines(String raw) {
    return raw
        .split(RegExp(r'\r?\n'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  List<String> _splitPeople(String raw) {
    return raw
        .split(RegExp(r'[,;\r\n]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
}
