import 'package:flutter/material.dart';

import '../../models/project_control_models.dart';
import '../../models/task_item.dart';

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
              'Черновик задачи',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('chat-draft-title-field'),
              controller: _titleCtl,
              decoration: const InputDecoration(labelText: 'Заголовок'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('chat-draft-details-field'),
              controller: _detailsCtl,
              decoration: const InputDecoration(labelText: 'Описание'),
              minLines: 3,
              maxLines: 6,
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('chat-draft-summary-field'),
              controller: _summaryCtl,
              decoration: const InputDecoration(labelText: 'Резюме'),
              minLines: 1,
              maxLines: 3,
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('chat-draft-checklist-field'),
              controller: _checklistCtl,
              decoration: const InputDecoration(labelText: 'Чеклист'),
              minLines: 2,
              maxLines: 6,
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('chat-draft-action-items-field'),
              controller: _actionItemsCtl,
              decoration: const InputDecoration(labelText: 'Action items'),
              minLines: 2,
              maxLines: 5,
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('chat-draft-decisions-field'),
              controller: _decisionsCtl,
              decoration: const InputDecoration(labelText: 'Решения'),
              minLines: 1,
              maxLines: 4,
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('chat-draft-blockers-field'),
              controller: _blockersCtl,
              decoration: const InputDecoration(labelText: 'Блокеры'),
              minLines: 1,
              maxLines: 4,
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('chat-draft-assignees-field'),
              controller: _assigneesCtl,
              decoration: const InputDecoration(labelText: 'Ответственные'),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('chat-draft-sources-field'),
              controller: _sourcesCtl,
              decoration: const InputDecoration(labelText: 'Источники'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<Priority>(
              key: const ValueKey('chat-draft-priority-field'),
              initialValue: _priority,
              decoration: const InputDecoration(labelText: 'Приоритет'),
              items: const [
                DropdownMenuItem(value: Priority.low, child: Text('Низкий')),
                DropdownMenuItem(
                  value: Priority.medium,
                  child: Text('Средний'),
                ),
                DropdownMenuItem(value: Priority.high, child: Text('Высокий')),
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
                  child: const Text('Отмена'),
                ),
                const Spacer(),
                FilledButton.icon(
                  key: const ValueKey('chat-draft-confirm'),
                  icon: const Icon(Icons.check),
                  onPressed: () => widget.onConfirm(_buildDraft()),
                  label: const Text('Создать задачу'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  ChatTaskDraft _buildDraft() {
    final fallbackTitle = widget.initialDraft.title.trim().isNotEmpty
        ? widget.initialDraft.title.trim()
        : 'Задача из чата';
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
