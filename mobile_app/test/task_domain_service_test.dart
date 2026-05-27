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

    // ── Family task permissions (any registered user can create shared tasks) ──

    test('accepts family task from any profile', () {
      final draft = validDraft().copyWith(
        isFamily: true,
        assignees: ['misha'],
      );
      expect(
          service.validateDraft(draft: draft, actorProfile: 'misha'), isNull);
    });

    test('accepts family task from any profile (nik)', () {
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

    test('rejects project task without selected group', () {
      final draft = validDraft().copyWith(projectId: 'project-1');
      expect(
        service.validateDraft(
          draft: draft,
          actorProfile: 'nik',
          projectGroupMembers: const {'group-1': ['nik']},
        ),
        'Выберите группу проекта.',
      );
    });

    test('rejects assignee outside selected project group', () {
      final draft = validDraft().copyWith(
        projectId: 'project-1',
        groupId: 'group-1',
        assignees: const ['nik', 'misha'],
      );
      expect(
        service.validateDraft(
          draft: draft,
          actorProfile: 'nik',
          projectGroupMembers: const {'group-1': ['nik']},
        ),
        'Ответственные должны входить в выбранную группу.',
      );
    });

    test('rejects project group task when actor is not project owner or group member', () {
      final draft = validDraft().copyWith(
        projectId: 'project-1',
        groupId: 'group-1',
        assignees: const ['misha'],
      );
      expect(
        service.validateDraft(
          draft: draft,
          actorProfile: 'nik',
          projectOwnerKey: 'owner',
          projectGroupMembers: const {'group-1': ['misha']},
        ),
        'Нет прав на создание задачи в этой группе.',
      );
    });

    test('accepts project group task for project owner', () {
      final draft = validDraft().copyWith(
        projectId: 'project-1',
        groupId: 'group-1',
        assignees: const ['misha'],
      );
      expect(
        service.validateDraft(
          draft: draft,
          actorProfile: 'nik',
          projectOwnerKey: 'nik',
          projectGroupMembers: const {'group-1': ['misha']},
        ),
        isNull,
      );
    });

    test('accepts project group task for group member', () {
      final draft = validDraft().copyWith(
        projectId: 'project-1',
        groupId: 'group-1',
        assignees: const ['nik'],
      );
      expect(
        service.validateDraft(
          draft: draft,
          actorProfile: 'nik',
          projectOwnerKey: 'owner',
          projectGroupMembers: const {'group-1': ['nik']},
        ),
        isNull,
      );
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

