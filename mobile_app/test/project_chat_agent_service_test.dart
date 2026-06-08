import 'package:family_todo_mobile/models/agent_policy.dart';
import 'package:family_todo_mobile/models/chat_models.dart';
import 'package:family_todo_mobile/models/project_control_models.dart';
import 'package:family_todo_mobile/models/task_item.dart';
import 'package:family_todo_mobile/models/task_project.dart';
import 'package:family_todo_mobile/services/project_chat_agent_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProjectChatAgentService', () {
    test('detects Tudushker wake word anywhere without phrase commands', () {
      expect(
        ProjectChatAgentService.isAddressed('Тудушкер, что думаешь?'),
        isTrue,
      );
      expect(
        ProjectChatAgentService.isAddressed('а можно тудушкер посмотрит?'),
        isTrue,
      );
      expect(
        ProjectChatAgentService.isAddressed(
          'Создай карточку по этому разговору',
        ),
        isFalse,
      );
      expect(
        ProjectChatAgentService.isAddressed('тудушкерский стиль текста'),
        isFalse,
      );
    });

    test('builds model intent prompt with strict JSON contract', () {
      final prompt = ProjectChatAgentService.buildIntentPrompt(
        context: _contextPack(),
        userMessage: 'Тудушкер, как лучше разложить работу?',
      );

      expect(prompt, contains('Тудушкер'));
      expect(prompt, contains('"action"'));
      expect(prompt, contains('"reply"'));
      expect(prompt, contains('"task_draft"'));
      expect(prompt, contains('"start_agent"'));
      expect(
        prompt,
        contains('не используй последнее сообщение как заголовок'),
      );
      expect(prompt, contains('msg-1 nik: Нужно сделать нормальный checkout'));
      expect(prompt, contains('Тудушкер, как лучше разложить работу?'));
    });

    test('parses task draft directive from model JSON', () {
      final directive = ProjectChatAgentService.parseModelDirective('''
Вот результат:
```json
{
  "action": "task_draft",
  "draft": {
    "title": "Настроить checkout и оплату",
    "details": "Собрать понятный сценарий покупки для магазина.",
    "checklist": ["Спроектировать форму", "Подключить оплату"],
    "assignees": ["nik"],
    "source_message_ids": ["msg-1", "msg-2"],
    "priority": "high"
  }
}
```
''');

      expect(directive.action, ProjectChatAgentAction.taskDraft);
      expect(directive.draft?.title, 'Настроить checkout и оплату');
      expect(directive.draft?.checklist, [
        'Спроектировать форму',
        'Подключить оплату',
      ]);
      expect(directive.draft?.priority, Priority.high);
    });

    test('plain model text is treated as chat reply', () {
      final directive = ProjectChatAgentService.parseModelDirective(
        'Я бы сначала уточнил ограничения, а потом разделил задачу на этапы.',
      );

      expect(directive.action, ProjectChatAgentAction.reply);
      expect(directive.replyText, contains('сначала уточнил ограничения'));
    });

    test('chat task draft creates editable task with real checklist', () {
      final taskDraft = const ChatTaskDraft(
        title: 'Настроить checkout и оплату',
        details: 'Собрать понятный сценарий покупки.',
        checklist: ['Спроектировать форму', 'Подключить оплату'],
        assignees: ['nik'],
      ).toTaskDraft(projectId: 'project-1', groupId: 'group-1');

      expect(taskDraft.title, 'Настроить checkout и оплату');
      expect(taskDraft.collaboration.checklists, hasLength(1));
      expect(taskDraft.collaboration.checklists.single.title, 'Чеклист');
      expect(
        taskDraft.collaboration.checklists.single.items
            .map((item) => item.text),
        ['Спроектировать форму', 'Подключить оплату'],
      );
    });
  });
}

ProjectChatContextPack _contextPack() {
  return const ProjectChatContextPack(
    project: TaskProject(
      id: 'project-1',
      name: 'Stylish house',
      description: 'Магазин laravel',
    ),
    binding: ProjectChatBinding(
      projectId: 'project-1',
      conversationKey: 'grp:project:project-1',
      title: 'Stylish house',
      members: ['nik', 'nastya'],
    ),
    automation: ProjectAutomationConfig(
      projectId: 'project-1',
      primaryWorkspaceId: 'stylish-house',
      agentEnabled: true,
      defaultAgentMode: 'planner',
      chatAnalysisMessageLimit: 40,
    ),
    messages: [
      ChatMessage(
        id: 'msg-1',
        conversationKey: 'grp:project:project-1',
        senderProfile: 'nik',
        messageType: 'text',
        text: 'Нужно сделать нормальный checkout',
        createdAt: '2026-06-09T10:00:00Z',
      ),
      ChatMessage(
        id: 'msg-2',
        conversationKey: 'grp:project:project-1',
        senderProfile: 'nastya',
        messageType: 'text',
        text: 'И оплату без лишних шагов',
        createdAt: '2026-06-09T10:01:00Z',
      ),
    ],
    policy: AgentRunPolicy(
      allowed: true,
      workspaceId: 'stylish-house',
      mode: 'planner',
      modeLabel: 'Планировщик',
      plugins: ['project_chat_context'],
      allowedCommands: ['session_create', 'session_send'],
      reason: '',
    ),
    workspaceId: 'stylish-house',
  );
}
