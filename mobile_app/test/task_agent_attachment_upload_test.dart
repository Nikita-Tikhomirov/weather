import 'package:family_todo_mobile/features/tasks/task_agent_attachment_upload.dart';
import 'package:family_todo_mobile/models/task_collaboration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('task agent attachment upload defaults', () {
    test('uses saved attachment fields when present', () {
      const attachment = TaskAttachment(
        id: 'att-1',
        kind: 'file',
        filename: 'report.md',
        mimeType: 'text/markdown',
        dataBase64: 'ZmlsZQ==',
        caption: 'Final report',
        createdAt: '2026-06-18T10:00:00',
      );

      expect(taskAgentUploadFilename(attachment), 'report.md');
      expect(taskAgentUploadMimeType(attachment), 'text/markdown');
      expect(taskAgentUploadCaption(attachment), 'Final report');
    });

    test('uses English fallback fields for unnamed attachments', () {
      const attachment = TaskAttachment(
        id: 'att-2',
        kind: 'file',
        filename: '',
        mimeType: '',
        dataBase64: 'ZmlsZQ==',
        caption: '',
        createdAt: '2026-06-18T10:00:00',
      );

      expect(taskAgentUploadFilename(attachment), 'task-attachment.bin');
      expect(taskAgentUploadMimeType(attachment), 'application/octet-stream');
      expect(taskAgentUploadCaption(attachment), 'File from task card');
      expect(
        taskAgentUploadCaption(attachment),
        isNot(contains(RegExp(r'[А-Яа-яЁё]'))),
      );
    });

    test('infers mime type from filename when attachment mime is empty', () {
      const attachment = TaskAttachment(
        id: 'att-3',
        kind: 'file',
        filename: 'screen.png',
        mimeType: '',
        dataBase64: 'ZmlsZQ==',
        caption: '',
        createdAt: '2026-06-18T10:00:00',
      );

      expect(taskAgentUploadMimeType(attachment), 'image/png');
    });
  });
}
