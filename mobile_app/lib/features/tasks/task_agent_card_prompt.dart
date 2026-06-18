import '../../models/task_collaboration.dart';
import '../../models/task_item.dart';

typedef TaskAgentProfileLabel = String Function(String profile);

class TaskAgentCardPromptInput {
  const TaskAgentCardPromptInput({
    required this.title,
    required this.details,
    required this.status,
    required this.projectId,
    this.comments = const [],
    this.checklists = const [],
    this.attachments = const [],
  });

  factory TaskAgentCardPromptInput.fromTask(TaskItem task) {
    return TaskAgentCardPromptInput(
      title: task.title,
      details: task.details,
      status: task.workflowStatus.name,
      projectId: task.projectId,
      comments: task.collaboration.comments,
      checklists: task.collaboration.checklists,
      attachments: task.collaboration.attachments,
    );
  }

  final String title;
  final String details;
  final String status;
  final String projectId;
  final List<TaskComment> comments;
  final List<TaskChecklist> checklists;
  final List<TaskAttachment> attachments;
}

String buildTaskAgentCardPrompt({
  required String backendPrompt,
  required TaskAgentCardPromptInput card,
  TaskAgentProfileLabel? commentAuthorLabel,
  List<String> footerInstructions = const [],
}) {
  final lines = <String>[];
  final remote = backendPrompt.trim();
  if (remote.isNotEmpty) {
    lines.add(remote);
    lines.add('');
  }

  lines.add('Актуальная карточка из мобильного приложения:');
  lines.add('Название: ${card.title.trim()}');
  final details = card.details.trim();
  if (details.isNotEmpty) {
    lines.add('Описание: $details');
  }
  lines.add('Статус: ${card.status}');
  lines.add('Проект: ${card.projectId}');

  _appendComments(lines, card.comments, commentAuthorLabel);
  _appendChecklists(lines, card.checklists);
  _appendAttachments(lines, card.attachments);

  final footers = footerInstructions
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  if (footers.isNotEmpty) {
    lines.add('');
    lines.addAll(footers);
  }

  return lines.join('\n');
}

void _appendComments(
  List<String> lines,
  List<TaskComment> comments,
  TaskAgentProfileLabel? commentAuthorLabel,
) {
  final visibleComments = comments
      .where((comment) => !comment.isDeleted)
      .map(
        (comment) => (
          author: comment.authorProfile,
          text: comment.text.trim(),
        ),
      )
      .where((comment) => comment.text.isNotEmpty)
      .take(30)
      .toList(growable: false);
  if (visibleComments.isEmpty) {
    return;
  }

  lines.add('');
  lines.add('Комментарии карточки:');
  for (final comment in visibleComments) {
    final author = commentAuthorLabel?.call(comment.author) ?? comment.author;
    lines.add('- $author: ${comment.text}');
  }
}

void _appendChecklists(List<String> lines, List<TaskChecklist> checklists) {
  if (checklists.isEmpty) {
    return;
  }

  lines.add('');
  lines.add('Чеклисты карточки:');
  for (final checklist in checklists) {
    lines.add('- ${checklist.title}');
    for (final item in checklist.items) {
      lines.add('  - [${item.done ? 'x' : ' '}] ${item.text}');
    }
  }
}

void _appendAttachments(List<String> lines, List<TaskAttachment> attachments) {
  if (attachments.isEmpty) {
    return;
  }

  lines.add('');
  lines.add('Вложения карточки:');
  for (final attachment in attachments) {
    final source = attachment.assetUrl.trim().isNotEmpty
        ? attachment.assetUrl.trim()
        : 'будет прикреплено в агентский чат';
    final caption = attachment.caption.trim();
    lines.add(
      '- ${attachment.filename} - $source'
      '${caption.isEmpty ? '' : ' - $caption'}',
    );
  }
}
