import '../../models/task_collaboration.dart';

const taskAgentAttachmentFallbackFilename = 'task-attachment.bin';
const taskAgentAttachmentFallbackCaption = 'File from task card';

String taskAgentUploadFilename(TaskAttachment attachment) {
  return attachment.filename.isEmpty
      ? taskAgentAttachmentFallbackFilename
      : attachment.filename;
}

String taskAgentUploadMimeType(TaskAttachment attachment) {
  return attachment.mimeType.isEmpty
      ? taskAgentMimeTypeForName(attachment.filename)
      : attachment.mimeType;
}

String taskAgentUploadCaption(TaskAttachment attachment) {
  return attachment.caption.isEmpty
      ? taskAgentAttachmentFallbackCaption
      : attachment.caption;
}

String taskAgentMimeTypeForName(String filename) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.md')) return 'text/markdown';
  if (lower.endsWith('.txt')) return 'text/plain';
  return 'application/octet-stream';
}
