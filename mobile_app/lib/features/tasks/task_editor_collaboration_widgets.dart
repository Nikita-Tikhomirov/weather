part of 'task_editor_sheet.dart';

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

class _AgentModeDropdown extends StatelessWidget {
  const _AgentModeDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> values;
  final void Function(String value) onChanged;

  @override
  Widget build(BuildContext context) {
    final safeValue = values.contains(value) ? value : '';
    return DropdownButtonFormField<String>(
      key: ValueKey('agent-mode-$label-$safeValue'),
      initialValue: safeValue,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final item in values)
          DropdownMenuItem<String>(
            value: item,
            child: Text(item.isEmpty ? 'по умолчанию' : item),
          ),
      ],
      onChanged: (value) => onChanged(value ?? ''),
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
    final text = TaskEditorText.of(context);
    final editing = editingComment;
    final reply = replyToComment;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          if (editing != null)
            _ComposerContextBanner(
              title: text.editingComment,
              subtitle: _commentPreview(editing, text),
              onClose: onCancelEdit,
            )
          else if (reply != null)
            _ComposerContextBanner(
              title: text.replyToComment,
              subtitle:
                  '${labelFor(reply.authorProfile)}: ${_commentPreview(reply, text)}',
              onClose: onCancelReply,
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                tooltip: text.photo,
                onPressed: attachmentsEnabled ? onPickPhoto : null,
                icon: const Icon(Icons.image_outlined),
              ),
              IconButton(
                tooltip: text.file,
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
                  decoration: InputDecoration(
                    hintText: text.commentOrCaption,
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(24)),
                    ),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: text.send,
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
    final text = TaskEditorText.of(context);
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
            tooltip: text.cancelCommentAction,
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
    final text = TaskEditorText.of(context);
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
                message: text.openPhotoAttachment,
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
                  tooltip: text.removeAttachment,
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
    final text = TaskEditorText.of(context);
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
                tooltip: text.removeAttachment,
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
    final text = TaskEditorText.of(context);
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
                    tooltip: text.commentActions,
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
                preview: _commentPreview(replyToComment!, text),
              ),
            ],
            if (deleted) ...[
              const SizedBox(height: 4),
              Text(
                text.commentDeleted,
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
                  : '${_shortDateTime(comment.createdAt)} · ${text.edited}',
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
    final text = TaskEditorText.of(context);
    if (attachment.isPhoto) {
      final bytes = _decodeAttachmentBytes(attachment.dataBase64);
      final imageUrl =
          _absoluteAttachmentUrl(attachment.assetUrl, assetBaseUrl);
      return Tooltip(
        message: text.openPhotoAttachment,
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
      message:
          attachment.assetUrl.isEmpty ? text.file : text.openFileAttachment,
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
    final text = TaskEditorText.of(context);
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
                tooltip: text.editChecklist,
                visualDensity: VisualDensity.compact,
                onPressed: enabled ? onRenameChecklist : null,
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
              IconButton(
                tooltip: text.deleteChecklist,
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
                          tooltip: text.editChecklistItem,
                          visualDensity: VisualDensity.compact,
                          onPressed: () => onRenameItem(item),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                        ),
                        IconButton(
                          tooltip: text.deleteChecklistItem,
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
                  decoration: InputDecoration(labelText: text.checklistItem),
                  onSubmitted: (_) => onAddItem(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: text.addChecklistItem,
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
  const _AgentSessionRow({
    required this.session,
    this.canContinue = false,
    this.onContinue,
  });

  final TaskAgentSession session;
  final bool canContinue;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final text = TaskEditorText.of(context);
    final subtitle = [
      if (session.workspaceId.isNotEmpty) session.workspaceId,
      if (session.mode.isNotEmpty) session.mode,
      if (session.status.isNotEmpty) _agentStatusText(session.status, text),
    ].join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.smart_toy_outlined),
      title: Text(
        session.title.isEmpty ? text.agentChat : session.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: canContinue
          ? TextButton.icon(
              icon: const Icon(Icons.play_arrow_outlined),
              label: Text(text.continueAction),
              onPressed: onContinue,
            )
          : session.sessionId.isEmpty
              ? const Icon(Icons.pending_outlined)
              : const Icon(Icons.link),
    );
  }
}

class _AgentContinuationPanel extends StatelessWidget {
  const _AgentContinuationPanel({
    required this.title,
    required this.onPressed,
  });

  final String title;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = TaskEditorText.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.play_circle_outline,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.play_arrow),
            label: Text(text.continueWork),
          ),
        ],
      ),
    );
  }
}

class _AgentQuestionTile extends StatelessWidget {
  const _AgentQuestionTile({required this.question});

  final TaskAgentQuestion question;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = TaskEditorText.of(context);
    final blocking = question.blocking;
    final borderColor = blocking
        ? theme.colorScheme.error.withValues(alpha: 0.35)
        : theme.colorScheme.outlineVariant;
    final background = blocking
        ? theme.colorScheme.errorContainer.withValues(alpha: 0.35)
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            blocking ? Icons.priority_high : Icons.help_outline,
            size: 18,
            color:
                blocking ? theme.colorScheme.error : theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(question.text),
                if (blocking) ...[
                  const SizedBox(height: 4),
                  Text(
                    text.agentQuestionBlocksWork,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
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

String _agentStatusText(String value, TaskEditorText text) {
  switch (value) {
    case 'pending':
      return text.agentStatusPending;
    case 'linked':
      return text.agentStatusLinked;
    case 'running':
      return text.agentStatusRunning;
    case 'done':
      return text.agentStatusDone;
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

String _commentPreview(TaskComment comment, TaskEditorText text) {
  if (comment.isDeleted) {
    return text.commentDeleted;
  }
  final body = comment.text.trim();
  if (body.isNotEmpty) {
    return body;
  }
  if (comment.attachmentIds.isNotEmpty) {
    return text.attachment;
  }
  return text.commentFallback;
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
