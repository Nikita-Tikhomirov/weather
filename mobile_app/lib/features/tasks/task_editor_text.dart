import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

class TaskEditorText {
  const TaskEditorText(this.l10n);

  const TaskEditorText.fallback() : l10n = null;

  factory TaskEditorText.of(BuildContext context) {
    return TaskEditorText(AppLocalizations.of(context));
  }

  final AppLocalizations? l10n;

  String get newTask => l10n?.newTask ?? 'Новая задача';
  String get editTask => l10n?.editTask ?? 'Редактирование задачи';
  String get settingsTab => l10n?.taskSettingsTab ?? 'Настройки';
  String get workTab => l10n?.taskWorkTab ?? 'Работа';
  String get agentTab => l10n?.taskAgentTab ?? 'Агент';
  String get agent => l10n?.taskAgent ?? 'Агент';
  String get agentAccessGranted =>
      l10n?.taskAgentAccessGranted ?? 'Доступ есть';
  String get agentNoAccess => l10n?.taskAgentNoAccess ?? 'Нет доступа';
  String get agentQuestions => l10n?.taskAgentQuestions ?? 'Вопросы агента';
  String get agentLoadingChats =>
      l10n?.taskAgentLoadingChats ?? 'Загружаю чаты';
  String get agentConnectChat => l10n?.taskAgentConnectChat ?? 'Подключить чат';
  String get selectAgentChat =>
      l10n?.taskSelectAgentChat ?? 'Выберите агентский чат';
  String get agentNewChat => l10n?.taskAgentNewChat ?? 'Новый чат';
  String get agentChat => l10n?.taskAgentChat ?? 'Агентский чат';
  String get agentTaskChats => l10n?.taskAgentTaskChats ?? 'Чаты задачи';
  String get agentNoChats =>
      l10n?.taskAgentNoChats ?? 'Агентские чаты не подключены';
  String get agentQueueRunning => l10n?.taskAgentQueueRunning ?? 'Очередь идет';
  String get workspace => l10n?.taskWorkspace ?? 'Воркспейс';
  String get workspaceField =>
      l10n?.taskWorkspaceField ?? 'Рабочее пространство';
  String get workspaceNotSelected =>
      l10n?.taskWorkspaceNotSelected ?? 'Не выбран';
  String get workspaceListNotLoaded =>
      l10n?.taskWorkspaceListNotLoaded ??
      'Список воркспейсов CodeWhale не загружен';
  String get launchMode => l10n?.taskLaunchMode ?? 'Режим запуска';
  String get launchAuto => l10n?.taskLaunchAuto ?? 'Авто';
  String get launchManual => l10n?.taskLaunchManual ?? 'Ручной';
  String get agentProvider => l10n?.taskAgentProvider ?? 'Провайдер';
  String get agentModel => l10n?.taskAgentModel ?? 'Модель';
  String get defaultValue => l10n?.defaultValue ?? 'по умолчанию';
  String get agentConfirmations =>
      l10n?.taskAgentConfirmations ?? 'Подтверждения';
  String get agentToolAutoMode =>
      l10n?.taskAgentToolAutoMode ?? 'Авто-режим инструментов';
  String get agentTools => l10n?.taskAgentTools ?? 'Инструменты';
  String get agentToolsLoading =>
      l10n?.taskAgentToolsLoading ?? 'Список инструментов загружается';
  String get agentToolsNotLoaded =>
      l10n?.taskAgentToolsNotLoaded ?? 'Инструменты CodeWhale не загружены';
  String get continueAction => l10n?.continueAction ?? 'Продолжить';
  String get continueWork => l10n?.taskContinueWork ?? 'Продолжить работу';
  String get agentStatusPending => l10n?.waitingToStart ?? 'ожидает запуска';
  String get agentStatusLinked => l10n?.connected ?? 'подключен';
  String get agentStatusRunning => l10n?.running ?? 'в работе';
  String get agentStatusDone => l10n?.done ?? 'готово';
  String get sessionStatusIdle => l10n?.sessionIdleStatus ?? 'Ожидает';
  String get sessionStatusRunning => l10n?.running ?? 'Запущен';
  String get sessionStatusStopped => l10n?.stopped ?? 'Остановлен';
  String get sessionStatusKilled => l10n?.killed ?? 'Завершен';
  String get sessionStatusError => l10n?.error ?? 'Ошибка';
  String get sessionStatusUnknown =>
      l10n?.sessionUnknownStatus ?? 'Статус неизвестен';
  String get agentQuestionBlocksWork =>
      l10n?.taskAgentQuestionBlocksWork ?? 'Блокирует работу';
  String get agentSkills => l10n?.taskAgentSkills ?? 'Скиллы';
  String get agentCommands => l10n?.taskAgentCommands ?? 'Команды';
  String agentAvailableCount(int count) =>
      l10n?.taskAgentAvailableCount(count) ?? 'Доступно: $count';
  String get agentQueue => l10n?.taskAgentQueue ?? 'Очередь выполнения';
  String get agentQueueHint =>
      l10n?.taskAgentQueueHint ??
      'Выберите инструменты; рабочий шаг пойдет последним';
  String get moveUp => l10n?.taskMoveUp ?? 'Выше';
  String get moveDown => l10n?.taskMoveDown ?? 'Ниже';
  String get workStep => l10n?.taskWorkStep ?? 'Работа по задаче';
  String get workStepSubtitle =>
      l10n?.taskWorkStepSubtitle ??
      'Чеклисты, комментарии и файлы карточки обязательны';
  String get refresh => l10n?.refresh ?? 'Обновить';
  String get save => l10n?.save ?? 'Сохранить';
  String get title => l10n?.taskTitle ?? 'Название';
  String get project => l10n?.taskProject ?? 'Проект';
  String get group => l10n?.taskGroup ?? 'Группа';
  String get selectProject => l10n?.selectProject ?? 'Выберите проект';
  String get selectGroup => l10n?.selectGroup ?? 'Выберите группу';
  String get projectHasNoGroups =>
      l10n?.projectHasNoGroups ?? 'У проекта нет групп.';
  String get priority => l10n?.priority ?? 'Приоритет';
  String get status => l10n?.taskStatus ?? 'Статус';
  String get low => l10n?.low ?? 'Низкий';
  String get medium => l10n?.medium ?? 'Средний';
  String get high => l10n?.high ?? 'Высокий';
  String get workflowTodo => l10n?.workflowTodo ?? 'К выполнению';
  String get workflowInProgress => l10n?.workflowInProgress ?? 'В работе';
  String get workflowInReview => l10n?.workflowInReview ?? 'На проверке';
  String get workflowDone => l10n?.workflowDone ?? 'Выполнено';
  String get workflowArchive => l10n?.workflowArchive ?? 'Архив';
  String get assignees => l10n?.taskAssignees ?? 'Ответственные';
  String get selectProjectGroup =>
      l10n?.selectProjectGroup ?? 'Выберите группу проекта.';
  String get groupMembersMissing =>
      l10n?.groupMembersMissing ?? 'Участники группы не найдены в контактах.';
  String get reminders => l10n?.taskReminders ?? 'Напоминания';
  String reminderLabel(int minutes) {
    switch (minutes) {
      case 1440:
        return l10n?.taskReminderBefore24Hours ?? 'За 24 часа';
      case 720:
        return l10n?.taskReminderBefore12Hours ?? 'За 12 часов';
      case 180:
        return l10n?.taskReminderBefore3Hours ?? 'За 3 часа';
      case 120:
        return l10n?.taskReminderBefore2Hours ?? 'За 2 часа';
      case 60:
        return l10n?.taskReminderBefore1Hour ?? 'За 1 час';
      case 30:
        return l10n?.taskReminderBefore30Minutes ?? 'За 30 минут';
      case 15:
        return l10n?.taskReminderBefore15Minutes ?? 'За 15 минут';
      case 5:
        return l10n?.taskReminderBefore5Minutes ?? 'За 5 минут';
    }
    return '$minutes min';
  }

  String get duration => l10n?.taskDuration ?? 'Оценка времени (мин)';
  String get details => l10n?.taskDetails ?? 'Описание';
  String get comments => l10n?.taskComments ?? 'Комментарии';
  String get commentOrCaption =>
      l10n?.taskCommentComposerHint ?? 'Комментарий или подпись';
  String get commentActions =>
      l10n?.taskCommentActions ?? 'Действия комментария';
  String get replyToComment =>
      l10n?.taskReplyToComment ?? 'Ответ на комментарий';
  String get editingComment =>
      l10n?.taskEditingComment ?? 'Редактирование комментария';
  String get commentDeleted => l10n?.taskCommentDeleted ?? 'Комментарий удалён';
  String get commentFallback => l10n?.taskCommentFallback ?? 'Комментарий';
  String get deleteCommentTitle =>
      l10n?.taskDeleteCommentTitle ?? 'Удалить комментарий?';
  String get deleteCommentMessage =>
      l10n?.taskDeleteCommentMessage ??
      'Комментарий будет удалён из карточки задачи.';
  String get cancelCommentAction => l10n?.taskCancelCommentAction ?? 'Отменить';
  String get edited => l10n?.edited ?? 'изменено';
  String get photo => l10n?.photo ?? 'Фото';
  String get file => l10n?.file ?? 'Файл';
  String get send => l10n?.send ?? 'Отправить';
  String get attachment => l10n?.attachment ?? 'Вложение';
  String get openPhotoAttachment =>
      l10n?.taskOpenPhotoAttachment ?? 'Открыть фото';
  String get openFileAttachment =>
      l10n?.taskOpenFileAttachment ?? 'Открыть файл';
  String get removeAttachment =>
      l10n?.taskRemoveAttachment ?? 'Убрать вложение';
  String get photoCaptionTitle =>
      l10n?.taskPhotoCaptionTitle ?? 'Подпись к фото';
  String get fileCaptionTitle =>
      l10n?.taskFileCaptionTitle ?? 'Подпись к файлу';
  String get attachmentCaptionHint =>
      l10n?.taskAttachmentCaptionHint ?? 'Добавить подпись (необязательно)';
  String get skipAttachmentCaption =>
      l10n?.taskSkipAttachmentCaption ?? 'Пропустить';
  String get reply => l10n?.reply ?? 'Ответить';
  String get edit => l10n?.edit ?? 'Редактировать';
  String get delete => l10n?.delete ?? 'Удалить';
  String get cancel => l10n?.cancel ?? 'Отмена';
  String get done => l10n?.done ?? 'Готово';
  String get noComments => l10n?.taskNoComments ?? 'Комментариев нет';
  String get checklists => l10n?.taskChecklists ?? 'Чеклисты';
  String get newChecklist => l10n?.taskNewChecklist ?? 'Новый чеклист';
  String get addChecklist => l10n?.taskAddChecklist ?? 'Добавить чеклист';
  String get noChecklists => l10n?.taskNoChecklists ?? 'Чеклистов нет';
  String get editChecklist =>
      l10n?.taskEditChecklist ?? 'Редактировать чеклист';
  String get checklistName =>
      l10n?.taskChecklistName ?? 'Название чеклиста';
  String get deleteChecklist => l10n?.taskDeleteChecklist ?? 'Удалить чеклист';
  String get deleteChecklistTitle =>
      l10n?.taskDeleteChecklistTitle ?? 'Удалить чеклист?';
  String get deleteChecklistMessage =>
      l10n?.taskDeleteChecklistMessage ??
      'Чеклист и все его пункты будут удалены из задачи.';
  String get editChecklistItem =>
      l10n?.taskEditChecklistItem ?? 'Редактировать пункт';
  String get checklistItemText =>
      l10n?.taskChecklistItemText ?? 'Текст пункта';
  String get deleteChecklistItem =>
      l10n?.taskDeleteChecklistItem ?? 'Удалить пункт';
  String get deleteChecklistItemTitle =>
      l10n?.taskDeleteChecklistItemTitle ?? 'Удалить пункт?';
  String get deleteChecklistItemMessage =>
      l10n?.taskDeleteChecklistItemMessage ?? 'Пункт будет удалён из чеклиста.';
  String get checklistItem => l10n?.taskChecklistItem ?? 'Пункт';
  String get addChecklistItem => l10n?.taskAddChecklistItem ?? 'Добавить пункт';
  String get activity => l10n?.taskActivity ?? 'Активность';
  String get activityEmpty => l10n?.taskActivityEmpty ?? 'Пока пусто';
}
