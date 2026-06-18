import 'package:family_todo_mobile/features/tasks/task_agent_card_prompt.dart';
import 'package:family_todo_mobile/models/task_collaboration.dart';
import 'package:family_todo_mobile/models/task_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds task card prompt from current card state', () {
    final prompt = buildTaskAgentCardPrompt(
      backendPrompt: '  Контекст от backend  ',
      card: const TaskAgentCardPromptInput(
        title: 'Обновленный запуск агента',
        details: '  Проверить очередь инструментов.  ',
        status: 'in_progress',
        projectId: 'weather',
        comments: [
          TaskComment(
            id: 'deleted',
            authorProfile: 'nik',
            text: 'не показывать',
            createdAt: '2026-06-01T10:00:00',
            deletedAt: '2026-06-01T11:00:00',
          ),
          TaskComment(
            id: 'empty',
            authorProfile: 'nik',
            text: '   ',
            createdAt: '2026-06-01T10:10:00',
          ),
          TaskComment(
            id: 'comment',
            authorProfile: 'nik',
            text: '  Учитывай свежий комментарий.  ',
            createdAt: '2026-06-01T10:20:00',
          ),
        ],
        checklists: [
          TaskChecklist(
            id: 'checklist',
            title: 'Проверки',
            createdAt: '2026-06-01T10:30:00',
            items: [
              TaskChecklistItem(
                id: 'done',
                text: 'Запустить тесты',
                createdAt: '2026-06-01T10:31:00',
                done: true,
              ),
              TaskChecklistItem(
                id: 'todo',
                text: 'Проверить сборку',
                createdAt: '2026-06-01T10:32:00',
              ),
            ],
          ),
        ],
        attachments: [
          TaskAttachment(
            id: 'report',
            kind: 'file',
            filename: 'report.txt',
            assetUrl: '',
            caption: 'лог проверки',
            createdAt: '2026-06-01T10:40:00',
          ),
        ],
      ),
      commentAuthorLabel: (profile) => profile == 'nik' ? 'Nik' : profile,
      footerInstructions: const ['Инструкция агента.'],
    );

    expect(
      prompt,
      [
        'Контекст от backend',
        '',
        'Актуальная карточка из мобильного приложения:',
        'Название: Обновленный запуск агента',
        'Описание: Проверить очередь инструментов.',
        'Статус: in_progress',
        'Проект: weather',
        '',
        'Комментарии карточки:',
        '- Nik: Учитывай свежий комментарий.',
        '',
        'Чеклисты карточки:',
        '- Проверки',
        '  - [x] Запустить тесты',
        '  - [ ] Проверить сборку',
        '',
        'Вложения карточки:',
        '- report.txt - будет прикреплено в агентский чат - лог проверки',
        '',
        'Инструкция агента.',
      ].join('\n'),
    );
  });

  test('creates prompt input from saved task values', () {
    const task = TaskItem(
      id: 'task-1',
      ownerKey: 'nik',
      isFamily: true,
      projectId: 'weather',
      title: 'Сохраненная задача',
      details: 'Описание из модели',
      dueDate: '2026-06-01',
      time: '10:00',
      workflowStatus: WorkflowStatus.in_review,
      priority: Priority.medium,
      tags: [],
      assignees: [],
      reminderOffsetsMinutes: [],
      durationMinutes: 0,
      updatedAt: '2026-06-01T10:00:00',
      version: 1,
    );

    final input = TaskAgentCardPromptInput.fromTask(task);

    expect(input.title, 'Сохраненная задача');
    expect(input.details, 'Описание из модели');
    expect(input.status, 'in_review');
    expect(input.projectId, 'weather');
  });
}
