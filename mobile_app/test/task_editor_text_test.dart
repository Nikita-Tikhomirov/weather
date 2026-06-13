import 'package:family_todo_mobile/features/tasks/task_editor_text.dart';
import 'package:family_todo_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fallback keeps Russian labels for legacy test harnesses', () {
    const text = TaskEditorText.fallback();

    expect(text.newTask, 'Новая задача');
    expect(text.settingsTab, 'Настройки');
    expect(text.title, 'Название');
    expect(text.agent, 'Агент');
    expect(text.user, 'Пользователь');
    expect(text.openPhotoAttachment, 'Открыть фото');
    expect(text.openFileAttachment, 'Открыть файл');
    expect(text.removeAttachment, 'Убрать вложение');
    expect(text.fileReadFailed, 'Не удалось прочитать файл');
    expect(text.fileOpenFailed, 'Не удалось открыть файл');
    expect(
      text.selectAgentWorkspace,
      'Выберите воркспейс для агентского чата',
    );
    expect(
      text.noAgentChatsInWorkspace,
      'В этом воркспейсе нет агентских чатов',
    );
    expect(text.agentSessionTitle('Формы'), 'Агент: Формы');
    expect(
      text.agentChatNotLinkedToWorkspace,
      'Агентский чат не связан с воркспейсом',
    );
    expect(text.agentConnectNoAccess, 'Нет прав на подключение чата');
    expect(text.connectedAgentChatTitle, 'Подключенный агентский чат');
    expect(
      text.agentChatConnectedToCard,
      'Агентский чат подключен к карточке',
    );
    expect(
      text.agentChatConnectFailed('ошибка'),
      'Не удалось подключить чат: ошибка',
    );
    expect(text.agentLaunchStarted, 'Новый агентский чат запускается');
    expect(
      text.agentQueueLaunchStarted(2),
      'Агент запускает очередь: 2 инструментов',
    );
    expect(text.agentStartNoAccess, 'Нет прав на запуск агента');
    expect(
      text.agentStartFailed('ошибка'),
      'Не удалось запустить агента: ошибка',
    );
    expect(text.agentContinueNoAccess, 'Нет прав на продолжение агента');
    expect(
      text.agentContinuesFreshCard,
      'Агент продолжает работу по свежей карточке',
    );
    expect(
      text.agentContinueFailed('ошибка'),
      'Не удалось продолжить агента: ошибка',
    );
    expect(text.activityAgentSessionRequested, 'запросил новый агентский чат');
    expect(
      text.activityAgentSessionStartFailed,
      'не смог запустить агентский чат',
    );
    expect(text.activityAgentSessionResumed, 'продолжил агентский чат');
    expect(
      text.activityAgentSessionResumeFailed,
      'не смог продолжить агентский чат',
    );
    expect(text.activityAgentSessionError, 'получил ошибку агентского чата');
    expect(text.activityAgentSessionLinked, 'подключил агентский чат');
    expect(
      text.activityAgentExistingSessionLinked,
      'подключил существующий агентский чат',
    );
    expect(
      text.activityAgentAutoMovedToStatus('На проверке'),
      'автоматически перевел карточку в статус На проверке',
    );
    expect(text.activityAgentQueueWaitingReview, 'ждет проверки карточки');
    expect(text.activityAgentQueueCompleted, 'завершил очередь агента');
    expect(text.activityAgentQueueNeedsMoreWork, 'ждет дальнейших правок');
    expect(
      text.activityAgentStatusChanged('Выполнено'),
      'перевел карточку в статус Выполнено',
    );
    expect(text.activityAgentCardUpdated, 'обновил карточку задачи');
    expect(text.agentPlanTitle, 'План агента');
    expect(
      text.agentQueueStepFailed('failed'),
      'Один из шагов агента не выполнен: failed',
    );
    expect(
      text.agentQueueTaskCardUnavailable,
      'family-task-card недоступен. Очередь агента остановлена.',
    );
    expect(text.codeWhaleError, 'Ошибка CodeWhale');
    expect(text.activityCommentEdited, 'отредактировал комментарий');
    expect(text.activityCommentAdded, 'добавил комментарий');
    expect(
      text.activityCommentAddedWithAttachment,
      'добавил комментарий с вложением',
    );
    expect(text.activityCommentReplied, 'ответил на комментарий');
    expect(text.activityCommentDeleted, 'удалил комментарий');
    expect(text.activityChecklistAdded('Запуск'), 'создал чеклист "Запуск"');
    expect(text.activityChecklistItemAdded('Сборка'), 'добавил пункт "Сборка"');
    expect(text.activityChecklistItemDone, 'закрыл пункт чеклиста');
    expect(text.activityChecklistItemReopened, 'вернул пункт чеклиста');
    expect(
      text.activityChecklistRenamed('Релиз'),
      'переименовал чеклист "Релиз"',
    );
    expect(
      text.activityChecklistDeleted('Релиз'),
      'удалил чеклист "Релиз"',
    );
    expect(text.activityChecklistItemRenamed, 'отредактировал пункт чеклиста');
    expect(text.activityChecklistItemDeleted, 'удалил пункт чеклиста');
    expect(
      text.saveError('Укажите название задачи.'),
      'Укажите название задачи.',
    );
    expect(text.saveError('Выберите проект.'), 'Выберите проект');
    expect(
      text.saveError('Неизвестная ошибка'),
      'Неизвестная ошибка',
    );
    expect(text.codeWhaleUnavailable, 'CodeWhale недоступен');
    expect(
      text.agentToolsLoadFailed('ошибка'),
      'Не удалось загрузить инструменты агента: ошибка',
    );
    expect(
      text.agentWorkspacesLoadFailed('ошибка'),
      'Не удалось загрузить воркспейсы: ошибка',
    );
  });

  testWidgets('reads English labels from AppLocalizations', (tester) async {
    late TaskEditorText text;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            text = TaskEditorText.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(text.newTask, 'New task');
    expect(text.settingsTab, 'Settings');
    expect(text.title, 'Title');
    expect(text.selectProject, 'Select project');
    expect(text.agent, 'Agent');
    expect(text.user, 'User');
    expect(text.openPhotoAttachment, 'Open photo');
    expect(text.openFileAttachment, 'Open file');
    expect(text.removeAttachment, 'Remove attachment');
    expect(
      text.attachmentUploadFailed('network'),
      'Could not upload attachment: network',
    );
    expect(text.attachmentEmptyOrCorrupt, 'The file is empty or corrupted.');
    expect(
      text.attachmentUploadMissingUrl,
      'The server did not return a file URL.',
    );
    expect(text.fileReadFailed, 'Could not read file');
    expect(text.fileOpenFailed, 'Could not open file');
    expect(text.selectAgentWorkspace, 'Select workspace for agent chat');
    expect(
      text.noAgentChatsInWorkspace,
      'No agent chats in this workspace',
    );
    expect(text.agentSessionTitle('Forms'), 'Agent: Forms');
    expect(
      text.agentChatNotLinkedToWorkspace,
      'Agent chat is not linked to a workspace',
    );
    expect(text.agentConnectNoAccess, 'No permission to connect chat');
    expect(text.connectedAgentChatTitle, 'Connected agent chat');
    expect(
      text.agentChatConnectedToCard,
      'Agent chat connected to the task card',
    );
    expect(
      text.agentChatConnectFailed('network'),
      'Could not connect chat: network',
    );
    expect(text.agentLaunchStarted, 'New agent chat is starting');
    expect(
      text.agentQueueLaunchStarted(2),
      'Agent is starting the queue: 2 tools',
    );
    expect(text.agentStartNoAccess, 'No permission to start agent');
    expect(
      text.agentStartFailed('network'),
      'Could not start agent: network',
    );
    expect(text.agentContinueNoAccess, 'No permission to continue agent');
    expect(
      text.agentContinuesFreshCard,
      'Agent continues with the fresh task card',
    );
    expect(
      text.agentContinueFailed('network'),
      'Could not continue agent: network',
    );
    expect(
      text.activityAgentSessionRequested,
      'requested a new agent chat',
    );
    expect(
      text.activityAgentSessionStartFailed,
      'could not start agent chat',
    );
    expect(text.activityAgentSessionResumed, 'continued agent chat');
    expect(
      text.activityAgentSessionResumeFailed,
      'could not continue agent chat',
    );
    expect(text.activityAgentSessionError, 'received an agent chat error');
    expect(text.activityAgentSessionLinked, 'linked agent chat');
    expect(
      text.activityAgentExistingSessionLinked,
      'linked existing agent chat',
    );
    expect(
      text.activityAgentAutoMovedToStatus('In review'),
      'automatically moved card to In review',
    );
    expect(text.activityAgentQueueWaitingReview, 'waiting for card review');
    expect(text.activityAgentQueueCompleted, 'completed agent queue');
    expect(text.activityAgentQueueNeedsMoreWork, 'waiting for more changes');
    expect(
      text.activityAgentStatusChanged('Done'),
      'moved card to Done',
    );
    expect(text.activityAgentCardUpdated, 'updated task card');
    expect(text.agentPlanTitle, 'Agent plan');
    expect(
      text.agentQueueStepFailed('failed'),
      'One of the agent steps did not complete: failed',
    );
    expect(
      text.agentQueueTaskCardUnavailable,
      'family-task-card is unavailable. Agent queue stopped.',
    );
    expect(text.codeWhaleError, 'CodeWhale error');
    expect(text.activityCommentEdited, 'edited a comment');
    expect(text.activityCommentAdded, 'added a comment');
    expect(
      text.activityCommentAddedWithAttachment,
      'added a comment with an attachment',
    );
    expect(text.activityCommentReplied, 'replied to a comment');
    expect(text.activityCommentDeleted, 'deleted a comment');
    expect(text.activityChecklistAdded('Launch'), 'created checklist "Launch"');
    expect(text.activityChecklistItemAdded('Build'), 'added item "Build"');
    expect(text.activityChecklistItemDone, 'completed checklist item');
    expect(text.activityChecklistItemReopened, 'reopened checklist item');
    expect(
      text.activityChecklistRenamed('Release'),
      'renamed checklist to "Release"',
    );
    expect(
      text.activityChecklistDeleted('Release'),
      'deleted checklist "Release"',
    );
    expect(text.activityChecklistItemRenamed, 'edited checklist item');
    expect(text.activityChecklistItemDeleted, 'deleted checklist item');
    expect(text.saveError('Укажите название задачи.'), 'Enter a task title');
    expect(text.saveError('Выберите проект.'), 'Select project');
    expect(
      text.saveError('Неизвестная ошибка'),
      'Неизвестная ошибка',
    );
    expect(text.codeWhaleUnavailable, 'CodeWhale is unavailable');
    expect(
      text.agentToolsLoadFailed('network'),
      'Could not load agent tools: network',
    );
    expect(
      text.agentWorkspacesLoadFailed('network'),
      'Could not load workspaces: network',
    );
  });
}
