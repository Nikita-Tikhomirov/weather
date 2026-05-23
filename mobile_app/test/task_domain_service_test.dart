import 'package:family_todo_mobile/domain/task_domain_service.dart';
import 'package:family_todo_mobile/domain/task_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = TaskDomainService();

  TaskDraft validDraft() => const TaskDraft(
        title: 'Кормить крыс',
        details: 'В 19:30',
        dueDate: '2026-05-24',
        time: '19:30',
        priority: 'medium',
        workflowStatus: 'todo',
        isFamily: false,
        assignees: [],
        durationMinutes: 0,
        reminderOffsetsMinutes: [],
      );

  group('validateDraft', () {
    // ── Title ──

    test('rejects empty title', () {
      final draft = validDraft().copyWith(title: '');
      expect(service.validateDraft(draft: draft, actorProfile: 'nik'),
          isNotNull);
    });

    test('rejects whitespace-only title', () {
      final draft = validDraft().copyWith(title: '   ');
      expect(service.validateDraft(draft: draft, actorProfile: 'nik'),
          isNotNull);
    });

    test('accepts valid title', () {
      expect(
          service.validateDraft(draft: validDraft(), actorProfile: 'nik'),
          isNull);
    });

    // ── Family task permissions ──

    test('rejects family task from child profile', () {
      final draft = validDraft().copyWith(
        isFamily: true,
        assignees: ['misha'],
      );
      expect(service.validateDraft(draft: draft, actorProfile: 'misha'),
          isNotNull);
    });

    test('accepts family task from adult profile', () {
      final draft = validDraft().copyWith(
        isFamily: true,
        assignees: ['misha', 'arisha'],
      );
      expect(
          service.validateDraft(draft: draft, actorProfile: 'nik'), isNull);
    });

    test('rejects family task with empty assignees', () {
      final draft = validDraft().copyWith(
        isFamily: true,
        assignees: [],
      );
      expect(service.validateDraft(draft: draft, actorProfile: 'nik'),
          isNotNull);
    });

    // ── Workflow status ──

    test('rejects invalid workflow status', () {
      final draft = validDraft().copyWith(workflowStatus: 'unknown');
      expect(service.validateDraft(draft: draft, actorProfile: 'nik'),
          isNotNull);
    });

    test('accepts all valid workflow statuses', () {
      for (final status in TaskDomainService.allowedStatuses) {
        final draft = validDraft().copyWith(workflowStatus: status);
        expect(service.validateDraft(draft: draft, actorProfile: 'nik'),
            isNull,
            reason: 'status=$status');
      }
    });

    // ── Priority ──

    test('rejects invalid priority', () {
      final draft = validDraft().copyWith(priority: 'extreme');
      expect(service.validateDraft(draft: draft, actorProfile: 'nik'),
          isNotNull);
    });

    test('accepts all valid priorities', () {
      for (final p in TaskDomainService.allowedPriority) {
        final draft = validDraft().copyWith(priority: p);
        expect(service.validateDraft(draft: draft, actorProfile: 'nik'),
            isNull,
            reason: 'priority=$p');
      }
    });

    // ── Reminder offsets ──

    test('rejects invalid reminder offset', () {
      final draft =
          validDraft().copyWith(reminderOffsetsMinutes: const [7]);
      expect(service.validateDraft(draft: draft, actorProfile: 'nik'),
          isNotNull);
    });

    test('accepts all valid reminder offsets', () {
      for (final offset in TaskDomainService.allowedReminderOffsets) {
        final draft =
            validDraft().copyWith(reminderOffsetsMinutes: [offset]);
        expect(service.validateDraft(draft: draft, actorProfile: 'nik'),
            isNull,
            reason: 'offset=$offset');
      }
    });

    test('accepts multiple valid reminder offsets', () {
      final draft = validDraft()
          .copyWith(reminderOffsetsMinutes: const [60, 30, 15]);
      expect(service.validateDraft(draft: draft, actorProfile: 'nik'),
          isNull);
    });
  });

  group('materializeTask', () {
    test('generates id and updatedAt for new task', () {
      final draft = validDraft();
      final now = DateTime(2026, 5, 23, 14, 0);
      final task = service.materializeTask(
        draft: draft,
        actorProfile: 'nik',
        now: now,
      );

      expect(task.title, 'Кормить крыс');
      expect(task.ownerKey, 'nik');
      expect(task.workflowStatus, 'todo');
      expect(task.updatedAt, now.toIso8601String());
      expect(task.version, 1);
      expect(task.id, startsWith('m-'));
    });

    test('increments version for existing task', () {
      final draft = validDraft().copyWith(title: 'Updated');
      final now = DateTime(2026, 5, 23, 14, 0);
      final existing = service.materializeTask(
        draft: validDraft(),
        actorProfile: 'nik',
        now: DateTime(2026, 5, 22),
      );

      final updated = service.materializeTask(
        draft: draft,
        actorProfile: 'nik',
        now: now,
        existing: existing,
      );

      expect(updated.version, 2);
      expect(updated.title, 'Updated');
      expect(updated.id, existing.id);
    });

    test('family task ownerKey is always family', () {
      final draft = validDraft().copyWith(
        isFamily: true,
        assignees: ['misha'],
      );
      final task = service.materializeTask(
        draft: draft,
        actorProfile: 'nik',
        now: DateTime(2026, 5, 23),
      );

      expect(task.ownerKey, 'family');
      expect(task.isFamily, isTrue);
    });

    test('trims title and details', () {
      final draft = validDraft().copyWith(
        title: '  Важно  ',
        details: '  Описание  ',
      );
      final task = service.materializeTask(
        draft: draft,
        actorProfile: 'nik',
        now: DateTime(2026, 5, 23),
      );

      expect(task.title, 'Важно');
      expect(task.details, 'Описание');
    });
  });
}

// Minimal copyWith for TaskDraft since the original doesn't have one.
extension _TaskDraftCopy on TaskDraft {
  TaskDraft copyWith({
    String? title,
    String? details,
    String? dueDate,
    String? time,
    String? priority,
    String? workflowStatus,
    bool? isFamily,
    List<String>? assignees,
    int? durationMinutes,
    List<int>? reminderOffsetsMinutes,
  }) {
    return TaskDraft(
      title: title ?? this.title,
      details: details ?? this.details,
      dueDate: dueDate ?? this.dueDate,
      time: time ?? this.time,
      priority: priority ?? this.priority,
      workflowStatus: workflowStatus ?? this.workflowStatus,
      isFamily: isFamily ?? this.isFamily,
      assignees: assignees ?? this.assignees,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      reminderOffsetsMinutes:
          reminderOffsetsMinutes ?? this.reminderOffsetsMinutes,
    );
  }
}
