import 'package:family_todo_mobile/features/tasks/agent_launch_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentLaunchPlan', () {
    test('builds ordered command steps, app context and task prompt', () {
      final plan = AgentLaunchPlan.build(
        contextPrompt: 'Контекст задачи',
        selectedCommandValues: const ['/skill tdd', '/skill review'],
        commands: const [
          {
            'label': 'TDD',
            'value': '/skill tdd',
            'description': 'Разработка через тесты',
          },
          {
            'label': 'Review',
            'value': '/skill review',
            'description': 'Проверка результата',
          },
        ],
      );

      expect(plan.steps.map((step) => step.text), [
        allOf(
          contains('Family Todo'),
          contains('Карточка задачи не файл в проекте'),
        ),
        '/skill tdd',
        '/skill review',
        contains('Контекст задачи'),
      ]);
      expect(plan.steps.map((step) => step.label), [
        'Контекст приложения',
        'TDD',
        'Review',
        'Работа по задаче',
      ]);
    });

    test('ignores unknown and duplicate command values', () {
      final plan = AgentLaunchPlan.build(
        contextPrompt: 'Контекст задачи',
        selectedCommandValues: const [
          '/skill tdd',
          '/unknown',
          '/skill tdd',
        ],
        commands: const [
          {'label': 'TDD', 'value': '/skill tdd'},
        ],
      );

      expect(plan.steps.map((step) => step.text), [
        contains('Family Todo'),
        '/skill tdd',
        contains('Контекст задачи'),
      ]);
    });

    test('parses task card actions for comments, checklists and files', () {
      final actions = AgentTaskActions.parse('''
Итог готов.
TASK_CARD_ACTIONS_JSON:
```json
{
  "comments": ["Проверил экран и приложил отчет."],
  "status": "in_review",
  "checklists": [
    {"title": "QA", "items": ["Открыть экран", "Проверить права"]}
  ],
  "attachments": [
    {"path": "vision/admin.png", "filename": "admin.png", "caption": "Скрин админки"}
  ]
}
```
''');

      expect(actions.comments, ['Проверил экран и приложил отчет.']);
      expect(actions.status, 'in_review');
      expect(actions.checklists.single.title, 'QA');
      expect(actions.checklists.single.items, [
        'Открыть экран',
        'Проверить права',
      ]);
      expect(actions.attachments.single.path, 'vision/admin.png');
    });

    test('accepts nested actions, files and screenshots aliases', () {
      final actions = AgentTaskActions.parse('''
TASK_CARD_ACTIONS_JSON:
{
  "task_card_actions": {
    "comments": [{"text": "Собрал отчет и приложил скрин."}],
    "lists": [
      {
        "title": "Что проверить дальше",
        "items": [{"text": "Принять отчет"}, {"title": "Проверить скрин"}]
      }
    ],
    "files": [
      {"file_path": "reports/agent-report.md", "name": "agent-report.md"}
    ],
    "screenshots": ["reports/admin-screen.png"]
  }
}
''');

      expect(actions.comments, ['Собрал отчет и приложил скрин.']);
      expect(actions.checklists.single.items, [
        'Принять отчет',
        'Проверить скрин',
      ]);
      expect(actions.attachments.map((item) => item.path), [
        'reports/agent-report.md',
        'reports/admin-screen.png',
      ]);
    });

    test('parses workflow status aliases from task card actions', () {
      final actions = AgentTaskActions.parse('''
TASK_CARD_ACTIONS_JSON:
{
  "task_card_actions": {
    "move_to": "done"
  }
}
''');

      expect(actions.status, 'done');
      expect(actions.isEmpty, isFalse);
    });
  });
}
