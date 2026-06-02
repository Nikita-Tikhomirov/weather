import 'package:flutter_test/flutter_test.dart';
import 'package:family_todo_mobile/models/task_collaboration.dart';
import 'package:family_todo_mobile/models/task_item.dart';

void main() {
  group('TaskItem serialization', () {
    test('fromJson reads assignees field', () {
      final json = {
        'id': 'task-1',
        'owner_key': 'nik',
        'is_family': true,
        'title': 'Test task',
        'details': '',
        'due_date': '2025-01-01',
        'time': '12:00',
        'workflow_status': 'todo',
        'priority': 'medium',
        'tags': [],
        'assignees': ['nik', 'misha'],
        'reminder_offsets_minutes': [30],
        'duration_minutes': 60,
        'updated_at': '2025-01-01T00:00:00',
        'version': 1,
      };
      final task = TaskItem.fromJson(json);
      expect(task.assignees, ['nik', 'misha']);
      expect(task.workflowStatus, WorkflowStatus.todo);
      expect(task.priority, Priority.medium);
    });

    test('fromJson falls back to participants field', () {
      final json = {
        'id': 'task-2',
        'owner_key': 'nik',
        'is_family': true,
        'title': 'Test task',
        'details': '',
        'due_date': '2025-01-01',
        'time': '12:00',
        'workflow_status': 'todo',
        'priority': 'medium',
        'tags': [],
        'participants': ['nik', 'nastya'],
        'reminder_offsets_minutes': [30],
        'duration_minutes': 60,
        'updated_at': '2025-01-01T00:00:00',
        'version': 1,
      };
      final task = TaskItem.fromJson(json);
      expect(task.assignees, ['nik', 'nastya']);
    });

    test('toJson includes both assignees and participants', () {
      const task = TaskItem(
        id: 'task-3',
        ownerKey: 'nik',
        isFamily: true,
        projectId: 'project-1',
        groupId: 'group-1',
        title: 'Test',
        details: '',
        dueDate: '2025-01-01',
        time: '12:00',
        workflowStatus: WorkflowStatus.todo,
        priority: Priority.medium,
        tags: [],
        assignees: ['nik'],
        reminderOffsetsMinutes: [30],
        durationMinutes: 60,
        updatedAt: '2025-01-01T00:00:00',
        version: 1,
      );
      final json = task.toJson();
      expect(json['assignees'], ['nik']);
      expect(json['participants'], ['nik']);
      expect(json['project_id'], 'project-1');
      expect(json['group_id'], 'group-1');
      expect(json['workflow_status'], 'todo');
      expect(json['priority'], 'medium');
    });

    test('toDbRow includes project and group assignment', () {
      const task = TaskItem(
        id: 'task-3-db',
        ownerKey: 'nik',
        isFamily: true,
        projectId: 'project-1',
        groupId: 'group-1',
        title: 'Test',
        details: '',
        dueDate: '2025-01-01',
        time: '12:00',
        workflowStatus: WorkflowStatus.todo,
        priority: Priority.medium,
        tags: [],
        assignees: ['nik'],
        reminderOffsetsMinutes: [30],
        durationMinutes: 60,
        updatedAt: '2025-01-01T00:00:00',
        version: 1,
      );
      final row = task.toDbRow();
      expect(row['project_id'], 'project-1');
      expect(row['group_id'], 'group-1');
    });

    test('copyWith preserves assignees', () {
      const task = TaskItem(
        id: 'task-4',
        ownerKey: 'nik',
        isFamily: false,
        title: 'Test',
        details: '',
        dueDate: '2025-01-01',
        time: '12:00',
        workflowStatus: WorkflowStatus.todo,
        priority: Priority.medium,
        tags: [],
        assignees: ['nik'],
        reminderOffsetsMinutes: [30],
        durationMinutes: 60,
        updatedAt: '2025-01-01T00:00:00',
        version: 1,
      );
      final copy = task.copyWith(title: 'Updated');
      expect(copy.title, 'Updated');
      expect(copy.assignees, ['nik']);
      expect(copy.id, 'task-4');
    });

    test('serializes collaboration through json and db row', () {
      const collaboration = TaskCollaboration(
        comments: [
          TaskComment(
            id: 'comment-1',
            authorProfile: 'nik',
            text: 'Проверил макет',
            createdAt: '2026-06-01T10:00:00',
            attachmentIds: ['att-1'],
          ),
        ],
        attachments: [
          TaskAttachment(
            id: 'att-1',
            kind: 'photo',
            filename: 'screen.png',
            mimeType: 'image/png',
            dataBase64: 'cG5n',
            caption: 'Главный экран',
            authorProfile: 'nik',
            createdAt: '2026-06-01T10:00:00',
            sizeBytes: 3,
          ),
        ],
        checklists: [
          TaskChecklist(
            id: 'checklist-1',
            title: 'Перед релизом',
            createdBy: 'nik',
            createdAt: '2026-06-01T10:00:00',
            items: [
              TaskChecklistItem(
                id: 'item-1',
                text: 'Проверить Android',
                done: true,
                createdBy: 'nik',
                createdAt: '2026-06-01T10:00:00',
                completedBy: 'misha',
                completedAt: '2026-06-01T11:00:00',
              ),
            ],
          ),
        ],
      );
      const task = TaskItem(
        id: 'task-collab',
        ownerKey: 'family',
        isFamily: true,
        projectId: 'project-1',
        groupId: 'group-1',
        title: 'Test',
        details: 'Описание',
        dueDate: '2026-06-01',
        time: '12:00',
        workflowStatus: WorkflowStatus.todo,
        priority: Priority.medium,
        tags: [],
        assignees: ['nik'],
        reminderOffsetsMinutes: [30],
        collaboration: collaboration,
        durationMinutes: 60,
        updatedAt: '2026-06-01T00:00:00',
        version: 1,
      );

      final fromJson = TaskItem.fromJson(task.toJson());
      final fromDb = TaskItem.fromDbRow(task.toDbRow());

      expect(fromJson.collaboration, collaboration);
      expect(fromDb.collaboration, collaboration);
      expect(fromDb.collaboration.checklistDoneCount, 1);
      expect(fromDb.collaboration.attachmentCount, 1);
    });

    test('preserves task attachment asset url and metadata', () {
      final attachment = TaskAttachment.fromJson(const {
        'id': 'att-s3',
        'kind': 'photo',
        'filename': 'screen.png',
        'mime_type': 'image/png',
        'asset_url': '/chat/media/task-photo',
        'image_meta': {'width': 1200, 'height': 800},
        'caption': 'Главный экран',
        'author_profile': 'nik',
        'created_at': '2026-06-01T10:00:00',
        'size_bytes': 42,
      });

      final json = attachment.toJson();

      expect(json['asset_url'], '/chat/media/task-photo');
      expect(json['image_meta'], const {'width': 1200, 'height': 800});
    });

    test('preserves task comment reply edit and delete metadata', () {
      final comment = TaskComment.fromJson(const {
        'id': 'comment-2',
        'author_profile': 'nik',
        'text': 'Ответил по макету',
        'created_at': '2026-06-01T10:00:00',
        'edited_at': '2026-06-01T10:05:00',
        'deleted_at': '2026-06-01T10:10:00',
        'reply_to_comment_id': 'comment-1',
        'attachment_ids': ['att-2'],
      });

      final json = comment.toJson();

      expect(comment.replyToCommentId, 'comment-1');
      expect(comment.editedAt, '2026-06-01T10:05:00');
      expect(comment.deletedAt, '2026-06-01T10:10:00');
      expect(comment.isDeleted, isTrue);
      expect(json['reply_to_comment_id'], 'comment-1');
      expect(json['edited_at'], '2026-06-01T10:05:00');
      expect(json['deleted_at'], '2026-06-01T10:10:00');
    });
  });

  group('TaskItem family detection', () {
    test('isFamily is true when ownerKey is family', () {
      const task = TaskItem(
        id: 'f-1',
        ownerKey: 'family',
        isFamily: true,
        title: 'Family task',
        details: '',
        dueDate: '2025-01-01',
        time: '12:00',
        workflowStatus: WorkflowStatus.todo,
        priority: Priority.medium,
        tags: [],
        assignees: ['nik', 'misha'],
        reminderOffsetsMinutes: [],
        durationMinutes: 30,
        updatedAt: '2025-01-01T00:00:00',
        version: 1,
      );
      expect(task.isFamily, isTrue);
      expect(task.ownerKey, 'family');
    });
  });
}
