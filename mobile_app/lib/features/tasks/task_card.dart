import 'package:flutter/material.dart';

import '../../app/app_labels.dart';
import '../../l10n/app_localizations.dart';
import '../../models/task_item.dart';

class TaskCard extends StatelessWidget {
  const TaskCard({
    super.key,
    required this.item,
    required this.onEdit,
    required this.onDelete,
    required this.onDoneToggle,
    this.labelFor,
    this.groupLabel,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectionToggle,
  });

  final TaskItem item;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onSelectionToggle;
  final String Function(String profile)? labelFor;
  final String Function(String groupId)? groupLabel;
  final Future<void> Function() onEdit;
  final Future<void> Function() onDelete;
  final Future<void> Function() onDoneToggle;

  static Color _statusColor(WorkflowStatus status) {
    switch (status) {
      case WorkflowStatus.todo:
        return const Color(0xFF3B82F6);
      case WorkflowStatus.in_progress:
        return const Color(0xFFF59E0B);
      case WorkflowStatus.in_review:
        return const Color(0xFF8B5CF6);
      case WorkflowStatus.done:
        return const Color(0xFF10B981);
      case WorkflowStatus.archive:
        return const Color(0xFF6B7280);
    }
  }

  static Widget _statusChip(WorkflowStatus status, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _statusColor(status).withAlpha(30),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _statusColor(status), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _statusColor(status),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final resolveLabel = labelFor ?? profileLabel;
    final statusColor = _statusColor(item.workflowStatus);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F2937) : const Color(0xFFFFFFFF);
    final textColor = Theme.of(context).colorScheme.onSurface;
    final collaboration = item.collaboration;
    final checklistText = collaboration.checklistTotalCount == 0
        ? ''
        : '${collaboration.checklistDoneCount}/${collaboration.checklistTotalCount}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: statusColor.withAlpha(25),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border(
          left: BorderSide(color: statusColor, width: 4),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: selectionMode ? onSelectionToggle : onEdit,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (selectionMode)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Checkbox(
                        value: selected,
                        onChanged: (_) => onSelectionToggle?.call(),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      item.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _statusChip(
                    item.workflowStatus,
                    _workflowLabel(l10n, item.workflowStatus),
                  ),
                ],
              ),
              if (item.dueDate.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.calendar_today, size: 14, color: statusColor),
                    const SizedBox(width: 6),
                    Text(
                      '${item.dueDate} ${item.time}'.trim(),
                      style: TextStyle(
                        fontSize: 12,
                        color: textColor.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ],
              if (item.groupId.isNotEmpty && groupLabel != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.group, size: 12, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      groupLabel!(item.groupId),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: statusColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
              if (item.details.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  item.details,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: textColor.withValues(alpha: 0.7),
                  ),
                ),
              ],
              if (collaboration.commentCount > 0 ||
                  collaboration.attachmentCount > 0 ||
                  collaboration.checklistTotalCount > 0) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (collaboration.commentCount > 0)
                      _TaskMetaPill(
                        icon: Icons.chat_bubble_outline,
                        label: '${collaboration.commentCount}',
                        color: statusColor,
                      ),
                    if (collaboration.attachmentCount > 0)
                      _TaskMetaPill(
                        icon: Icons.attachment,
                        label: '${collaboration.attachmentCount}',
                        color: statusColor,
                      ),
                    if (checklistText.isNotEmpty)
                      _TaskMetaPill(
                        icon: Icons.checklist,
                        label: checklistText,
                        color: statusColor,
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  if (item.assignees.isNotEmpty)
                    ...item.assignees.take(3).map((assignee) {
                      final initials = resolveLabel(assignee).isNotEmpty
                          ? resolveLabel(assignee).substring(0, 1).toUpperCase()
                          : '?';
                      return Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: CircleAvatar(
                          radius: 11,
                          backgroundColor: statusColor.withAlpha(40),
                          child: Text(
                            initials,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ),
                      );
                    }),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      resolveLabel(item.ownerKey),
                      style: TextStyle(
                        fontSize: 11,
                        color: textColor.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                  if (!selectionMode) ...[
                    IconButton(
                      tooltip:
                          '${l10n?.done ?? 'Done'}/${l10n?.undo ?? 'Undo'}',
                      iconSize: 20,
                      icon: Icon(
                        item.workflowStatus == WorkflowStatus.done
                            ? Icons.undo
                            : Icons.check_circle,
                        color: statusColor,
                      ),
                      onPressed: onDoneToggle,
                    ),
                    IconButton(
                      tooltip: l10n?.delete ?? 'Delete',
                      iconSize: 20,
                      icon: Icon(
                        Icons.delete_outline,
                        color: textColor.withValues(alpha: 0.5),
                      ),
                      onPressed: onDelete,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _workflowLabel(AppLocalizations? l10n, WorkflowStatus status) {
  switch (status) {
    case WorkflowStatus.todo:
      return l10n?.workflowTodo ?? workflowLabel(status);
    case WorkflowStatus.in_progress:
      return l10n?.workflowInProgress ?? workflowLabel(status);
    case WorkflowStatus.in_review:
      return l10n?.workflowInReview ?? workflowLabel(status);
    case WorkflowStatus.done:
      return l10n?.workflowDone ?? workflowLabel(status);
    case WorkflowStatus.archive:
      return l10n?.workflowArchive ?? 'Archive';
  }
}

class _TaskMetaPill extends StatelessWidget {
  const _TaskMetaPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(22),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
