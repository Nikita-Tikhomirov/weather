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
      expect(prompt, contains('Не отвечай про файлы workspace'));
      expect(
        prompt,
        isNot(contains('msg-3 tudushker: Принято. Вижу в рабочей области')),
      );
      expect(prompt, isNot(contains('msg-4 Тудушкер:')));
      expect(prompt, isNot(contains('msg-5 nik: Тудушкер:')));
    });

    test('deduplicates repeated chat messages in model prompt', () {
      final prompt = ProjectChatAgentService.buildIntentPrompt(
        context: _contextPackWithRepeatedMessages(),
        userMessage: 'Тудушкер, что думаешь?',
      );

      expect('checkout'.allMatches(prompt), hasLength(1));
    });

    test('strict parser rejects plain workspace chatter', () {
      final directive = ProjectChatAgentService.parseStrictModelDirective(
        'Принято. Вижу в рабочей области task-card.json и index.html.',
      );

      expect(directive, isNull);
    });

    test('strict parser rejects json wrapped workspace chatter', () {
      final directive = ProjectChatAgentService.parseStrictModelDirective(
        '{"action":"reply","reply_text":"Вижу в рабочей области task-card.json и index.html."}',
      );

      expect(directive, isNull);
    });

    test('resolver repairs non-json workspace answer before replying',
        () async {
      final prompts = <String>[];
      final directive = await ProjectChatAgentService.resolveDirective(
        context: _contextPack(),
        userMessage: 'тудушкер что бы нам ещё добавить?',
        runPrompt: (prompt) async {
          prompts.add(prompt);
          if (prompts.length == 1) {
            return 'Принято. Вижу task-card.json и index.html.';
          }
          return '{"action":"reply","reply_text":"Добавьте плавные анимации при прокрутке и отдельную секцию с преимуществами проекта."}';
        },
      );

      expect(prompts, hasLength(2));
      expect(prompts.last, contains('Предыдущий ответ недопустим'));
      expect(directive.action, ProjectChatAgentAction.reply);
      expect(directive.replyText, contains('анимации при прокрутке'));
      expect(directive.replyText, isNot(contains('task-card.json')));
    });

    test('resolver does not fake chat answer when model is unavailable',
        () async {
      final directive = await ProjectChatAgentService.resolveDirective(
        context: _contextPackForWebsiteIdeas(),
        userMessage: 'Тудушкер!',
        runPrompt: (_) async => throw StateError('bridge unavailable'),
      );

      expect(directive.action, ProjectChatAgentAction.reply);
      expect(directive.replyText, contains('не получил ответ AI'));
      expect(directive.replyText, isNot(contains('анимации')));
      expect(directive.replyText, isNot(contains('секцию')));
      expect(directive.replyText, isNot(contains('task-card.json')));
      expect(directive.replyText, isNot(contains('Я бы сделал что-то лишнее')));
    });

    test('resolver does not wait for repair after empty model output',
        () async {
      var calls = 0;
      final directive = await ProjectChatAgentService.resolveDirective(
        context: _contextPackForWebsiteIdeas(),
        userMessage: 'Тудушкер!',
        runPrompt: (_) async {
          calls += 1;
          return '';
        },
      );

      expect(calls, 1);
      expect(directive.action, ProjectChatAgentAction.reply);
      expect(directive.replyText, contains('не получил ответ AI'));
      expect(directive.replyText, isNot(contains('анимации')));
    });

    test('resolver does not create fake task draft when model is unavailable',
        () async {
      final directive = await ProjectChatAgentService.resolveDirective(
        context: _contextPackForWebsiteIdeas(),
        userMessage: 'Пользователь нажал кнопку создания черновика задачи.',
        forcedAction: ProjectChatAgentAction.taskDraft,
        runPrompt: (_) async => '',
      );

      expect(directive.action, ProjectChatAgentAction.reply);
      expect(directive.draft, isNull);
      expect(
        directive.replyText,
        contains('не смог собрать нормальный черновик'),
      );
      expect(directive.replyText, isNot(contains('анимации')));
    });

    test('resolver accepts connected plain model reply without repair',
        () async {
      var calls = 0;
      final directive = await ProjectChatAgentService.resolveDirective(
        context: _contextPackForWebsiteIdeas(),
        userMessage: 'Тудушкер, что думаешь?',
        runPrompt: (_) async {
          calls += 1;
          return 'Я бы усилил главную страницу: добавить плавные анимации при прокрутке и отдельную секцию с понятным обещанием для клиента. Это даст странице больше динамики и быстрее объяснит ценность проекта.';
        },
      );

      expect(calls, 1);
      expect(directive.action, ProjectChatAgentAction.reply);
      expect(directive.replyText, contains('усилил главную страницу'));
      expect(directive.replyText, isNot(contains('task-card.json')));
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

    test('strict parser deduplicates task draft lists from model JSON', () {
      final directive = ProjectChatAgentService.parseStrictModelDirective('''
{
  "action": "task_draft",
  "draft": {
    "title": "Улучшить главную страницу сайта",
    "details": "Нужно продумать и внедрить улучшения главной страницы: добавить плавные анимации при прокрутке и новую смысловую секцию.",
    "summary": "Улучшение главной страницы",
    "action_items": ["Добавить анимации", "Добавить анимации", "Продумать новую секцию"],
    "checklist": ["Добавить анимации", "Добавить анимации", "Продумать новую секцию"],
    "source_message_ids": ["site-1", "site-1", "site-2"],
    "priority": "medium"
  }
}
''');

      expect(directive?.action, ProjectChatAgentAction.taskDraft);
      expect(directive?.draft?.actionItems, [
        'Добавить анимации',
        'Продумать новую секцию',
      ]);
      expect(directive?.draft?.checklist, [
        'Добавить анимации',
        'Продумать новую секцию',
      ]);
      expect(directive?.draft?.sourceMessageIds, ['site-1', 'site-2']);
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
      ChatMessage(
        id: 'msg-3',
        conversationKey: 'grp:project:project-1',
        senderProfile: 'tudushker',
        messageType: 'text',
        text: 'Принято. Вижу в рабочей области task-card.json.',
        createdAt: '2026-06-09T10:02:00Z',
      ),
      ChatMessage(
        id: 'msg-4',
        conversationKey: 'grp:project:project-1',
        senderProfile: 'Тудушкер',
        messageType: 'text',
        text: 'Этот ответ тоже не должен попасть в prompt.',
        createdAt: '2026-06-09T10:03:00Z',
      ),
      ChatMessage(
        id: 'msg-5',
        conversationKey: 'grp:project:project-1',
        senderProfile: 'nik',
        messageType: 'text',
        text: 'Тудушкер: запасной ответ от владельца',
        createdAt: '2026-06-09T10:04:00Z',
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

ProjectChatContextPack _contextPackForWebsiteIdeas() {
  return const ProjectChatContextPack(
    project: TaskProject(
      id: 'project-site',
      name: 'Тесты системы',
      description: 'Сайт проекта',
    ),
    binding: ProjectChatBinding(
      projectId: 'project-site',
      conversationKey: 'grp:project:project-site',
      title: 'Тесты системы',
      members: ['nik', 'tudushker'],
    ),
    automation: ProjectAutomationConfig(
      projectId: 'project-site',
      primaryWorkspaceId: 'workspace-site',
      agentEnabled: true,
      defaultAgentMode: 'planner',
      chatAnalysisMessageLimit: 40,
    ),
    messages: [
      ChatMessage(
        id: 'site-1',
        conversationKey: 'grp:project:project-site',
        senderProfile: 'nik',
        messageType: 'text',
        text: 'надо бы сделать анимации на сайте при прокрутке',
        createdAt: '2026-06-09T10:00:00Z',
      ),
      ChatMessage(
        id: 'site-2',
        conversationKey: 'grp:project:project-site',
        senderProfile: 'nik',
        messageType: 'text',
        text: 'и ещё секцию придумать',
        createdAt: '2026-06-09T10:01:00Z',
      ),
      ChatMessage(
        id: 'site-3',
        conversationKey: 'grp:project:project-site',
        senderProfile: 'tudushker',
        messageType: 'text',
        text: 'Вижу task-card.json',
        createdAt: '2026-06-09T10:02:00Z',
      ),
      ChatMessage(
        id: 'site-4',
        conversationKey: 'grp:project:project-site',
        senderProfile: 'nik',
        messageType: 'text',
        text: 'Тудушкер: Я бы сделал что-то лишнее',
        createdAt: '2026-06-09T10:03:00Z',
      ),
    ],
    policy: AgentRunPolicy(
      allowed: true,
      workspaceId: 'workspace-site',
      mode: 'planner',
      modeLabel: 'Планировщик',
      plugins: ['project_chat_context'],
      allowedCommands: ['session_create', 'session_send'],
      reason: '',
    ),
    workspaceId: 'workspace-site',
  );
}

ProjectChatContextPack _contextPackWithRepeatedMessages() {
  return const ProjectChatContextPack(
    project: TaskProject(
      id: 'project-repeat',
      name: 'Повторы',
      description: 'Проверка контекста',
    ),
    binding: ProjectChatBinding(
      projectId: 'project-repeat',
      conversationKey: 'grp:project:project-repeat',
      title: 'Повторы',
      members: ['nik', 'tudushker'],
    ),
    automation: ProjectAutomationConfig(
      projectId: 'project-repeat',
      primaryWorkspaceId: 'workspace-repeat',
      agentEnabled: true,
      defaultAgentMode: 'planner',
      chatAnalysisMessageLimit: 40,
    ),
    messages: [
      ChatMessage(
        id: 'repeat-1',
        conversationKey: 'grp:project:project-repeat',
        senderProfile: 'nik',
        messageType: 'text',
        text: 'Нужно сделать нормальный checkout',
        createdAt: '2026-06-09T10:00:00Z',
      ),
      ChatMessage(
        id: 'repeat-2',
        conversationKey: 'grp:project:project-repeat',
        senderProfile: 'nik',
        messageType: 'text',
        text: 'Нужно сделать нормальный checkout',
        createdAt: '2026-06-09T10:01:00Z',
      ),
      ChatMessage(
        id: 'repeat-3',
        conversationKey: 'grp:project:project-repeat',
        senderProfile: 'nik',
        messageType: 'text',
        text: 'И оплату без лишних шагов',
        createdAt: '2026-06-09T10:02:00Z',
      ),
    ],
    policy: AgentRunPolicy(
      allowed: true,
      workspaceId: 'workspace-repeat',
      mode: 'planner',
      modeLabel: 'Планировщик',
      plugins: ['project_chat_context'],
      allowedCommands: ['session_create', 'session_send'],
      reason: '',
    ),
    workspaceId: 'workspace-repeat',
  );
}
