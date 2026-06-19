// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Семейный ToDo';

  @override
  String get tasksTab => 'Задачи';

  @override
  String get calendarTab => 'Календарь';

  @override
  String get chatsTab => 'Чаты';

  @override
  String get messengerTab => 'Мессенджер';

  @override
  String get familyTab => 'Семья';

  @override
  String get familyTasks => 'Семейные задачи';

  @override
  String get dashboardOnDate => 'На дату';

  @override
  String get dashboardDone => 'Сделано';

  @override
  String get dashboardFamily => 'Семейных';

  @override
  String get dashboardOverdue => 'Просрочено';

  @override
  String get dashboardFamilyHint => 'Семейные';

  @override
  String get dashboardOverdueHint => 'Просрочка';

  @override
  String get selectDate => 'Выбрать дату';

  @override
  String get upcomingTasks => 'Ближайшие задачи';

  @override
  String get filterUpcoming => 'Предстоящие';

  @override
  String get filterOverdue => 'Просроченные';

  @override
  String get filterDone => 'Выполненные';

  @override
  String get filterAll => 'Все';

  @override
  String get noTasks => 'Нет задач';

  @override
  String get noTasksForFilter => 'Под выбранный фильтр задач нет';

  @override
  String get noTasksForDate => 'На эту дату задач нет';

  @override
  String get close => 'Закрыть';

  @override
  String get more => 'еще';

  @override
  String get dropHere => 'Отпустить сюда';

  @override
  String get message => 'Сообщение';

  @override
  String get messageDeleted => 'Сообщение удалено';

  @override
  String get imageMessage => 'Изображение';

  @override
  String get audioMessage => 'Аудио';

  @override
  String get uploadPhasePreparing => 'Подготовка...';

  @override
  String get uploadPhaseCompressing => 'Сжатие...';

  @override
  String get uploadPhaseReading => 'Чтение...';

  @override
  String get uploadPhaseUploading => 'Загрузка...';

  @override
  String get uploadPhaseSending => 'Отправка...';

  @override
  String get uploadPhaseFinishing => 'Завершение...';

  @override
  String get send => 'Отправить';

  @override
  String get attachment => 'Вложение';

  @override
  String get gallery => 'Галерея';

  @override
  String get camera => 'Камера';

  @override
  String get video => 'Видео';

  @override
  String chatFileTooLarge(Object maxMb) {
    return 'Файл слишком большой. Максимум $maxMb МБ.';
  }

  @override
  String chatDocumentSendFailed(Object error) {
    return 'Ошибка отправки документа: $error';
  }

  @override
  String chatVideoTooLarge(Object sizeMb, Object maxMb) {
    return 'Видео слишком большое ($sizeMb МБ). Максимум $maxMb МБ.';
  }

  @override
  String get chatVideoCaptionTitle => 'Подпись к видео';

  @override
  String chatPhotoSendFailed(Object error) {
    return 'Ошибка отправки: $error';
  }

  @override
  String chatVideoSendFailed(Object error) {
    return 'Ошибка отправки видео: $error';
  }

  @override
  String homeChatRefreshFailed(Object error) {
    return 'Ошибка обновления чата: $error';
  }

  @override
  String homeContactAddedToFamily(Object contact) {
    return '$contact добавлен в семью';
  }

  @override
  String homeAddToFamilyFailed(Object error) {
    return 'Не удалось добавить в семью: $error';
  }

  @override
  String homeChatUnavailable(Object error) {
    return 'Чат недоступен: $error';
  }

  @override
  String get homeNoWorkspaceAccess => 'Нет доступа к воркспейсам';

  @override
  String get homeSelectWorkspaceProjectReason => 'Выберите проект, связанный с воркспейсом.';

  @override
  String get homeProjectChatAgentDraftButtonUserMessage => 'Пользователь нажал кнопку создания черновика задачи.';

  @override
  String homeProjectChatAgentTitle(Object projectName) {
    return 'Тудушкер: $projectName';
  }

  @override
  String get homeProjectChatAgentAnalyzing => 'Тудушкер анализирует чат.';

  @override
  String get homeProjectChatAgentUnstructuredResponse => 'Тудушкер вернул неструктурированный ответ.';

  @override
  String get homeProjectChatAgentAnalyzeFailed => 'Не удалось проанализировать чат проекта.';

  @override
  String get homeProjectChatAgentSelectWorkspace => 'Выберите workspace проекта в Project Control Center.';

  @override
  String get homeProjectChatAgentStarting => 'Агент проекта запускается в CodeWhale.';

  @override
  String get homeProjectChatAgentStartFailed => 'Не удалось запустить агента проекта.';

  @override
  String homeProjectChatAgentTaskCreated(Object projectName) {
    return 'Задача создана в проекте $projectName.';
  }

  @override
  String get homeProjectChatAgentUnstructuredResponseMessage => 'Я получил неструктурированный ответ модели и не стал отправлять его в чат. Повторите запрос чуть точнее.';

  @override
  String get homeProjectChatAgentRequestFailedMessage => 'Не смог обработать запрос. Проверьте workspace проекта и доступность CodeWhale.';

  @override
  String get homeProjectChatAgentTaskDraftMissingMessage => 'Я понял, что нужна карточка, но не смог собрать структурированный черновик.';

  @override
  String get homeProjectChatAgentSessionStartedMessage => 'Запустил рабочую сессию в workspace проекта.';

  @override
  String get homeProjectChatAgentEmptyReplyMessage => 'Я посмотрел контекст, но не смог сформулировать полезный ответ.';

  @override
  String get homeProjectChatAgentAiUnavailableReplyMessage => 'Сейчас не получил ответ AI, поэтому не буду придумывать ответ из кусков чата. Проверьте CodeWhale и workspace проекта, затем повторите запрос.';

  @override
  String get homeProjectChatAgentAiUnavailableTaskDraftMessage => 'Я не смог собрать нормальный черновик: не получил ответ AI. Не буду создавать карточку из кусков чата. Проверьте CodeWhale и workspace проекта, затем повторите запрос.';

  @override
  String get homeProjectChatAgentCodeWhaleUnavailable => 'CodeWhale недоступен';

  @override
  String get homeProjectChatAgentDefaultTitle => 'Тудушкер';

  @override
  String homeProjectChatAgentOwnerFallbackMessage(Object message) {
    return 'Тудушкер: $message';
  }

  @override
  String get homeImageSavedToGallery => 'Фото сохранено в галерею';

  @override
  String get homeImageSaveFailed => 'Не удалось сохранить фото';

  @override
  String get colorSchemeTooltip => 'Цветовая схема';

  @override
  String get undoLastAction => 'Откатить последнее действие';

  @override
  String get lastActionUndone => 'Последнее действие отменено';

  @override
  String get fcmDiagnostics => 'FCM диагностика';

  @override
  String get fcmRefreshInProgress => 'FCM: обновляю диагностику...';

  @override
  String get fcmResetInProgress => 'FCM: сбрасываю токен...';

  @override
  String get fcmResetToken => 'Сбросить токен';

  @override
  String get editMessage => 'Изменить сообщение';

  @override
  String replyPreview(String message) {
    return 'Ответ: $message';
  }

  @override
  String get editingMessage => 'Редактирование сообщения';

  @override
  String get incomingVideoCall => 'Входящий видеозвонок';

  @override
  String get incomingAudioCall => 'Входящий аудиозвонок';

  @override
  String get videoCall => 'Видеозвонок';

  @override
  String get audioCall => 'Аудиозвонок';

  @override
  String get ongoingVideoCall => 'Идет видеозвонок';

  @override
  String get ongoingAudioCall => 'Идет аудиозвонок';

  @override
  String get openCallScreen => 'Открыть экран звонка';

  @override
  String get open => 'Открыть';

  @override
  String get shareText => 'Поделиться текстом';

  @override
  String get sharePhoto => 'Поделиться фото';

  @override
  String get returnToCall => 'Вернуться';

  @override
  String get calling => 'Вызов...';

  @override
  String get incomingCall => 'Входящий звонок...';

  @override
  String get inCall => 'Разговор';

  @override
  String get callEnded => 'Звонок завершён';

  @override
  String get missedAudioCall => 'Пропущенный аудиозвонок';

  @override
  String get missedVideoCall => 'Пропущенный видеозвонок';

  @override
  String get audioCallEnded => 'Аудиозвонок завершён';

  @override
  String get videoCallEnded => 'Видеозвонок завершён';

  @override
  String get decline => 'Отклонить';

  @override
  String get accept => 'Принять';

  @override
  String get endCall => 'Завершить';

  @override
  String get microphone => 'Микрофон';

  @override
  String get unmute => 'Вкл. микро';

  @override
  String get speaker => 'Динамик';

  @override
  String get headset => 'Гарнитура';

  @override
  String get search => 'Поиск';

  @override
  String get delete => 'Удалить';

  @override
  String get edit => 'Редактировать';

  @override
  String get edited => 'изменено';

  @override
  String get cancel => 'Отмена';

  @override
  String get save => 'Сохранить';

  @override
  String get done => 'Готово';

  @override
  String get undo => 'Отменить';

  @override
  String get syncAction => 'Синхронизировать';

  @override
  String get voice => 'Голос';

  @override
  String get playVoiceMessage => 'Воспроизвести';

  @override
  String get pauseVoiceMessage => 'Пауза';

  @override
  String get voicePermissionRequired => 'Нужен доступ к микрофону';

  @override
  String get voiceMicrophoneErrorPrefix => 'Ошибка микрофона: ';

  @override
  String get voiceRecordingTooShort => 'Слишком коротко';

  @override
  String get voiceSendErrorPrefix => 'Ошибка: ';

  @override
  String get today => 'Сегодня';

  @override
  String get addTask => 'Добавить задачу';

  @override
  String get newTask => 'Новая задача';

  @override
  String get editTask => 'Редактирование задачи';

  @override
  String get taskSettingsTab => 'Настройки';

  @override
  String get taskWorkTab => 'Работа';

  @override
  String get taskAgentTab => 'Агент';

  @override
  String get taskAgent => 'Агент';

  @override
  String get taskUserFallback => 'Пользователь';

  @override
  String get taskAgentAccessGranted => 'Доступ есть';

  @override
  String get taskAgentNoAccess => 'Нет доступа';

  @override
  String get taskAgentQuestions => 'Вопросы агента';

  @override
  String get taskAgentLoadingChats => 'Загружаю чаты';

  @override
  String get taskAgentConnectChat => 'Подключить чат';

  @override
  String get taskSelectAgentChat => 'Выберите агентский чат';

  @override
  String get taskSelectAgentWorkspace => 'Выберите воркспейс для агентского чата';

  @override
  String get taskAgentNewChat => 'Новый чат';

  @override
  String get taskAgentChat => 'Агентский чат';

  @override
  String taskAgentSessionTitle(String title) {
    return 'Агент: $title';
  }

  @override
  String get taskAgentTaskChats => 'Чаты задачи';

  @override
  String get taskAgentNoChats => 'Агентские чаты не подключены';

  @override
  String get taskNoAgentChatsInWorkspace => 'В этом воркспейсе нет агентских чатов';

  @override
  String get taskAgentChatNotLinkedToWorkspace => 'Агентский чат не связан с воркспейсом';

  @override
  String get taskAgentConnectNoAccess => 'Нет прав на подключение чата';

  @override
  String get taskConnectedAgentChatTitle => 'Подключенный агентский чат';

  @override
  String get taskAgentChatConnectedToCard => 'Агентский чат подключен к карточке';

  @override
  String taskAgentChatConnectFailed(Object error) {
    return 'Не удалось подключить чат: $error';
  }

  @override
  String get taskAgentLaunchStarted => 'Новый агентский чат запускается';

  @override
  String taskAgentQueueLaunchStarted(int count) {
    return 'Агент запускает очередь: $count инструментов';
  }

  @override
  String get taskAgentStartNoAccess => 'Нет прав на запуск агента';

  @override
  String taskAgentStartFailed(Object error) {
    return 'Не удалось запустить агента: $error';
  }

  @override
  String get taskAgentQueueRunning => 'Очередь идет';

  @override
  String get taskAgentQuestionBlocksWork => 'Блокирует работу';

  @override
  String get taskWorkspace => 'Воркспейс';

  @override
  String get taskWorkspaceField => 'Рабочее пространство';

  @override
  String get taskWorkspaceNotSelected => 'Не выбран';

  @override
  String get taskWorkspaceListNotLoaded => 'Список воркспейсов CodeWhale не загружен';

  @override
  String get taskLaunchMode => 'Режим запуска';

  @override
  String get taskLaunchAuto => 'Авто';

  @override
  String get taskLaunchManual => 'Ручной';

  @override
  String get taskAgentProvider => 'Провайдер';

  @override
  String get taskAgentModel => 'Модель';

  @override
  String get taskAgentConfirmations => 'Подтверждения';

  @override
  String get taskAgentToolAutoMode => 'Авто-режим инструментов';

  @override
  String get taskAgentTools => 'Инструменты';

  @override
  String get taskAgentToolsLoading => 'Список инструментов загружается';

  @override
  String get taskAgentToolsNotLoaded => 'Инструменты CodeWhale не загружены';

  @override
  String get taskCodeWhaleUnavailable => 'CodeWhale недоступен';

  @override
  String taskAgentToolsLoadFailed(Object error) {
    return 'Не удалось загрузить инструменты агента: $error';
  }

  @override
  String taskAgentWorkspacesLoadFailed(Object error) {
    return 'Не удалось загрузить воркспейсы: $error';
  }

  @override
  String get taskContinueWork => 'Продолжить работу';

  @override
  String get taskSaveTaskFirst => 'Сначала сохраните задачу';

  @override
  String get taskSaveTitleRequired => 'Укажите название задачи.';

  @override
  String get taskSaveGroupNotInProject => 'Выбранная группа не входит в проект.';

  @override
  String get taskSaveGroupCreateNoAccess => 'Нет прав на создание задачи в этой группе.';

  @override
  String get taskSaveAssigneesOutsideGroup => 'Ответственные должны входить в выбранную группу.';

  @override
  String get taskSaveInvalidStatus => 'Некорректный статус задачи.';

  @override
  String get taskSaveInvalidPriority => 'Некорректный приоритет задачи.';

  @override
  String get taskSaveInvalidReminders => 'Некорректные интервалы напоминаний.';

  @override
  String get taskSaveGenericFailure => 'Невозможно сохранить задачу.';

  @override
  String get taskAgentContinueNoAccess => 'Нет прав на продолжение агента';

  @override
  String get taskAgentContinuesFreshCard => 'Агент продолжает работу по свежей карточке';

  @override
  String taskAgentContinueFailed(Object error) {
    return 'Не удалось продолжить агента: $error';
  }

  @override
  String get taskActivityAgentSessionRequested => 'запросил новый агентский чат';

  @override
  String get taskActivityAgentSessionStartFailed => 'не смог запустить агентский чат';

  @override
  String get taskActivityAgentSessionResumed => 'продолжил агентский чат';

  @override
  String get taskActivityAgentSessionResumeFailed => 'не смог продолжить агентский чат';

  @override
  String get taskActivityAgentSessionError => 'получил ошибку агентского чата';

  @override
  String get taskActivityAgentSessionLinked => 'подключил агентский чат';

  @override
  String get taskActivityAgentExistingSessionLinked => 'подключил существующий агентский чат';

  @override
  String taskActivityAgentAutoMovedToStatus(Object status) {
    return 'автоматически перевел карточку в статус $status';
  }

  @override
  String get taskActivityAgentQueueWaitingReview => 'ждет проверки карточки';

  @override
  String get taskActivityAgentQueueCompleted => 'завершил очередь агента';

  @override
  String get taskActivityAgentQueueNeedsMoreWork => 'ждет дальнейших правок';

  @override
  String taskActivityAgentStatusChanged(Object status) {
    return 'перевел карточку в статус $status';
  }

  @override
  String get taskActivityAgentCardUpdated => 'обновил карточку задачи';

  @override
  String get taskAgentPlanTitle => 'План агента';

  @override
  String taskAgentQueueStepFailed(Object status) {
    return 'Один из шагов агента не выполнен: $status';
  }

  @override
  String get taskAgentQueueTaskCardUnavailable => 'family-task-card недоступен. Очередь агента остановлена.';

  @override
  String get taskAgentSkills => 'Скиллы';

  @override
  String get taskAgentCommands => 'Команды';

  @override
  String taskAgentAvailableCount(int count) {
    return 'Доступно: $count';
  }

  @override
  String get taskAgentQueue => 'Очередь выполнения';

  @override
  String get taskAgentQueueHint => 'Выберите инструменты; рабочий шаг пойдет последним';

  @override
  String get taskMoveUp => 'Выше';

  @override
  String get taskMoveDown => 'Ниже';

  @override
  String get taskAgentTaskCardStep => 'Карточка задачи';

  @override
  String get taskAgentTaskCardReadStep => 'Чтение карточки';

  @override
  String get taskAgentAppContextStep => 'Контекст приложения';

  @override
  String get taskWorkStep => 'Работа по задаче';

  @override
  String get taskWorkStepSubtitle => 'Чеклисты, комментарии и файлы карточки обязательны';

  @override
  String get taskTitle => 'Название';

  @override
  String get taskDetails => 'Описание';

  @override
  String get chatTaskDraft => 'Черновик задачи';

  @override
  String get taskSummary => 'Резюме';

  @override
  String get taskComments => 'Комментарии';

  @override
  String get taskCommentComposerHint => 'Комментарий или подпись';

  @override
  String get taskCommentActions => 'Действия комментария';

  @override
  String get taskReplyToComment => 'Ответ на комментарий';

  @override
  String get taskEditingComment => 'Редактирование комментария';

  @override
  String get taskCommentDeleted => 'Комментарий удалён';

  @override
  String get taskCommentFallback => 'Комментарий';

  @override
  String get taskActivityCommentEdited => 'отредактировал комментарий';

  @override
  String get taskActivityCommentAdded => 'добавил комментарий';

  @override
  String get taskActivityCommentAddedWithAttachment => 'добавил комментарий с вложением';

  @override
  String get taskActivityCommentReplied => 'ответил на комментарий';

  @override
  String get taskActivityCommentDeleted => 'удалил комментарий';

  @override
  String taskActivityChecklistAdded(Object title) {
    return 'создал чеклист \"$title\"';
  }

  @override
  String taskActivityChecklistItemAdded(Object item) {
    return 'добавил пункт \"$item\"';
  }

  @override
  String get taskActivityChecklistItemDone => 'закрыл пункт чеклиста';

  @override
  String get taskActivityChecklistItemReopened => 'вернул пункт чеклиста';

  @override
  String taskActivityChecklistRenamed(Object title) {
    return 'переименовал чеклист \"$title\"';
  }

  @override
  String taskActivityChecklistDeleted(Object title) {
    return 'удалил чеклист \"$title\"';
  }

  @override
  String get taskActivityChecklistItemRenamed => 'отредактировал пункт чеклиста';

  @override
  String get taskActivityChecklistItemDeleted => 'удалил пункт чеклиста';

  @override
  String get taskCancelCommentAction => 'Отменить';

  @override
  String get taskDeleteCommentTitle => 'Удалить комментарий?';

  @override
  String get taskDeleteCommentMessage => 'Комментарий будет удалён из карточки задачи.';

  @override
  String get taskOpenPhotoAttachment => 'Открыть фото';

  @override
  String get taskOpenFileAttachment => 'Открыть файл';

  @override
  String get taskRemoveAttachment => 'Убрать вложение';

  @override
  String get taskPhotoCaptionTitle => 'Подпись к фото';

  @override
  String get taskFileCaptionTitle => 'Подпись к файлу';

  @override
  String get taskAttachmentCaptionHint => 'Добавить подпись (необязательно)';

  @override
  String get taskSkipAttachmentCaption => 'Пропустить';

  @override
  String taskAttachmentUploadFailed(Object error) {
    return 'Не удалось загрузить вложение: $error';
  }

  @override
  String get taskAttachmentEmptyOrCorrupt => 'Файл пустой или повреждён.';

  @override
  String get taskAttachmentUploadMissingUrl => 'Сервер не вернул ссылку на файл.';

  @override
  String get taskFileReadFailed => 'Не удалось прочитать файл';

  @override
  String get taskFileOpenFailed => 'Не удалось открыть файл';

  @override
  String get taskNoComments => 'Комментариев нет';

  @override
  String get checklist => 'Чеклист';

  @override
  String get taskChecklists => 'Чеклисты';

  @override
  String get taskNewChecklist => 'Новый чеклист';

  @override
  String get taskAddChecklist => 'Добавить чеклист';

  @override
  String get taskNoChecklists => 'Чеклистов нет';

  @override
  String get taskEditChecklist => 'Редактировать чеклист';

  @override
  String get taskChecklistName => 'Название чеклиста';

  @override
  String get taskDeleteChecklist => 'Удалить чеклист';

  @override
  String get taskDeleteChecklistTitle => 'Удалить чеклист?';

  @override
  String get taskDeleteChecklistMessage => 'Чеклист и все его пункты будут удалены из задачи.';

  @override
  String get taskEditChecklistItem => 'Редактировать пункт';

  @override
  String get taskChecklistItemText => 'Текст пункта';

  @override
  String get taskDeleteChecklistItem => 'Удалить пункт';

  @override
  String get taskDeleteChecklistItemTitle => 'Удалить пункт?';

  @override
  String get taskDeleteChecklistItemMessage => 'Пункт будет удалён из чеклиста.';

  @override
  String get taskChecklistItem => 'Пункт';

  @override
  String get taskAddChecklistItem => 'Добавить пункт';

  @override
  String get taskActivity => 'Активность';

  @override
  String get taskActivityEmpty => 'Пока пусто';

  @override
  String get actionItems => 'Action items';

  @override
  String get decisions => 'Решения';

  @override
  String get blockers => 'Блокеры';

  @override
  String get sources => 'Источники';

  @override
  String get createTask => 'Создать задачу';

  @override
  String get taskFromChat => 'Задача из чата';

  @override
  String get taskProject => 'Проект';

  @override
  String get taskGroup => 'Группа';

  @override
  String get dueDate => 'Срок';

  @override
  String get time => 'Время';

  @override
  String get priority => 'Приоритет';

  @override
  String get taskStatus => 'Статус';

  @override
  String get low => 'Низкий';

  @override
  String get medium => 'Средний';

  @override
  String get high => 'Высокий';

  @override
  String get workflowTodo => 'К выполнению';

  @override
  String get workflowInProgress => 'В работе';

  @override
  String get workflowInReview => 'На проверке';

  @override
  String get workflowDone => 'Выполнено';

  @override
  String get workflowArchive => 'Архив';

  @override
  String get reminder => 'Напоминание';

  @override
  String get taskReminders => 'Напоминания';

  @override
  String get taskReminderBefore24Hours => 'За 24 часа';

  @override
  String get taskReminderBefore12Hours => 'За 12 часов';

  @override
  String get taskReminderBefore3Hours => 'За 3 часа';

  @override
  String get taskReminderBefore2Hours => 'За 2 часа';

  @override
  String get taskReminderBefore1Hour => 'За 1 час';

  @override
  String get taskReminderBefore30Minutes => 'За 30 минут';

  @override
  String get taskReminderBefore15Minutes => 'За 15 минут';

  @override
  String get taskReminderBefore5Minutes => 'За 5 минут';

  @override
  String get participants => 'Участники';

  @override
  String get taskAssignees => 'Ответственные';

  @override
  String get taskDuration => 'Оценка времени (мин)';

  @override
  String get selectProject => 'Выберите проект';

  @override
  String get selectGroup => 'Выберите группу';

  @override
  String get projectHasNoGroups => 'У проекта нет групп.';

  @override
  String get selectProjectGroup => 'Выберите группу проекта.';

  @override
  String get groupMembersMissing => 'Участники группы не найдены в контактах.';

  @override
  String get newProject => 'Новый проект';

  @override
  String get editProject => 'Редактировать проект';

  @override
  String get projectNameLabel => 'Название';

  @override
  String get description => 'Описание';

  @override
  String get groups => 'Группы';

  @override
  String get create => 'Создать';

  @override
  String get projectNameRequired => 'Введите название проекта';

  @override
  String projectSaveFailed(Object error) {
    return 'Ошибка: $error';
  }

  @override
  String get newGroup => 'Новая группа';

  @override
  String get editGroup => 'Редактировать группу';

  @override
  String get groupDefaultName => 'Группа';

  @override
  String get groupRenameAction => 'Назвать';

  @override
  String get groupAddMember => 'Добавить участника';

  @override
  String get groupAvatarUpdated => 'Аватар обновлён';

  @override
  String get groupNameLabel => 'Название группы';

  @override
  String get groupNameHint => 'Например: Работа';

  @override
  String get contacts => 'Контакты';

  @override
  String get refreshContacts => 'Обновить контакты';

  @override
  String get noContacts => 'Нет контактов. Добавьте контакты в мессенджере.';

  @override
  String get noRegisteredPhoneContacts => 'Нет зарегистрированных контактов из телефона';

  @override
  String get addToFamily => 'Добавить в семью';

  @override
  String get groupNameRequired => 'Введите название группы';

  @override
  String get groupMemberRequired => 'Выберите хотя бы одного участника';

  @override
  String groupSaveFailed(Object error) {
    return 'Ошибка: $error';
  }

  @override
  String groupChatDeleteMessage(Object title) {
    return 'Группа \"$title\" исчезнет у всех участников вместе с перепиской.';
  }

  @override
  String get groupNoAvailableContacts => 'Нет доступных контактов';

  @override
  String get groupSelectMember => 'Выбрать участника';

  @override
  String groupMemberAdded(Object profile) {
    return '$profile добавлен';
  }

  @override
  String groupAvatarUploadFailed(Object error) {
    return 'Ошибка загрузки аватара: $error';
  }

  @override
  String get groupDeletedLocally => 'Группа удалена из локального списка';

  @override
  String get projectsSection => 'Проекты';

  @override
  String get createProjectAction => 'Создать проект';

  @override
  String get createGroupAction => 'Создать группу';

  @override
  String get projectChats => 'Проектные чаты';

  @override
  String get homeProjectChatsUnavailable => 'Проектные чаты недоступны';

  @override
  String get homeProjectNotFound => 'Проект не найден';

  @override
  String get homeProjectRequestingFiles => 'Запрашиваю файлы проекта...';

  @override
  String homeProjectFileLink(Object path) {
    return 'Файл: $path';
  }

  @override
  String get homeProjectFileContentLoading => 'Загрузка содержимого...';

  @override
  String get homeProjectFileFallbackName => 'Файл';

  @override
  String get homeProjectCopyAll => 'Копировать всё';

  @override
  String get homeProjectCopiedToClipboard => 'Скопировано в буфер';

  @override
  String get homeProjectFileEmpty => 'Файл пуст';

  @override
  String get homeProjectBridgeStartSent => 'Команда запуска bridge отправлена';

  @override
  String get homeProjectBridgeStartFailed => 'Не удалось отправить команду запуска bridge';

  @override
  String get homeProjectNewSessionStarting => 'Создаю новую сессию...';

  @override
  String get homeProjectStopCommandSent => 'Команда остановки отправлена';

  @override
  String get homeProjectPhotoCommentTitle => 'Комментарий к фото';

  @override
  String get homeProjectDeepSeekPromptHint => 'Промт для DeepSeek после загрузки (необязательно)';

  @override
  String get homeProjectSaveOnly => 'Только сохранить';

  @override
  String homeProjectPhotosSavedToVision(int count) {
    return 'Фото сохранено в vision: $count';
  }

  @override
  String get homeProjectPhotosNotSent => 'Фото не отправлено. Проверьте соединение или размер файла.';

  @override
  String homeProjectPhotosNotSentCount(int count) {
    return 'Не отправлено фото: $count';
  }

  @override
  String get homeProjectDocumentCommentTitle => 'Комментарий к документу';

  @override
  String homeProjectDocumentMessage(Object filename) {
    return '📎 Документ: $filename';
  }

  @override
  String get homeProjectServerTitle => 'Сервер проектов';

  @override
  String get homeProjectServerDescription => 'IP-адрес и порт ПК, на котором запущен project_bridge.py';

  @override
  String get homeProjectAddressLabel => 'Адрес';

  @override
  String get projectChatStartBridge => 'Запустить bridge';

  @override
  String get projectChatNewSession => 'Новая сессия';

  @override
  String get projectChatStopDeepSeek => 'Остановить DeepSeek';

  @override
  String get projectChatServerSettings => 'Настроить сервер';

  @override
  String get projectChatProjectFiles => 'Файлы проекта';

  @override
  String projectChatConnectedTo(Object address) {
    return 'Подключено • $address';
  }

  @override
  String projectChatConnectingTo(Object address) {
    return 'Подключение к $address...';
  }

  @override
  String get projectChatTerminalTitle => 'Терминал проекта';

  @override
  String get projectChatTerminalHint => 'Напишите сообщение для взаимодействия с AI-ассистентом в проекте';

  @override
  String get projectChatReconnect => 'Переподключиться';

  @override
  String get projectChatPhotoToVision => 'Фото в vision';

  @override
  String get projectChatDocumentToVision => 'Документ в vision';

  @override
  String get regularGroups => 'Обычные группы';

  @override
  String chatParticipantsCount(int count) {
    return 'Участники: $count';
  }

  @override
  String get noProjectsYetAction => 'Проектов пока нет. Нажмите + чтобы создать.';

  @override
  String get noGroupsYetAction => 'Групп пока нет. Нажмите + чтобы создать.';

  @override
  String get projectControlCreateProjectHint => 'Создайте проект, чтобы подключить чат и агента.';

  @override
  String get projectControlChatsNotLinked => 'Чаты не связаны';

  @override
  String projectControlChatsCount(int count) {
    return 'Чатов: $count';
  }

  @override
  String get projectControlWorkspaceNotSelected => 'Workspace не выбран';

  @override
  String projectControlWorkspaceChip(Object label) {
    return 'Workspace: $label';
  }

  @override
  String projectControlWorkspaceUnavailable(Object label) {
    return 'Workspace: $label (нет доступа)';
  }

  @override
  String get projectControlNoAgentAccess => 'Нет прав на агента';

  @override
  String get projectControlWorkspaceLoading => 'Workspace загружается';

  @override
  String get projectControlAgentAvailable => 'Агент доступен';

  @override
  String get projectControlLinkedChats => 'Связанные чаты';

  @override
  String get projectControlAssignGroupForChat => 'Назначьте группу проекту, чтобы появился проектный чат.';

  @override
  String get projectControlCreateChat => 'Создать проектный чат';

  @override
  String get projectControlRefreshChat => 'Обновить проектный чат';

  @override
  String get projectControlAnalyzeChat => 'Анализ чата';

  @override
  String get projectControlDraftTask => 'Черновик задачи';

  @override
  String get projectControlStartAgent => 'Запустить агента';

  @override
  String get projectAgentMenu => 'Агент проекта';

  @override
  String get projectControlProjectStatus => 'Статус проекта';

  @override
  String get homeProjectDescriptionMissing => 'Описание не задано';

  @override
  String homeProjectParticipants(Object members) {
    return 'Участники: $members';
  }

  @override
  String get homeProjectWorkspaceNotSelected => 'Workspace не выбран';

  @override
  String get homeProjectWorkspaceHint => 'Выберите workspace в Project Control Center';

  @override
  String get homeProjectAgentAvailableByButton => 'Агент доступен по кнопке';

  @override
  String get homeProjectAgentNoAccess => 'Нет прав на AI-агента';

  @override
  String get homeProjectActiveAgentSession => 'Активная сессия агента';

  @override
  String get workspaceBridgeNotLoaded => 'Список workspace ещё не загружен.';

  @override
  String get workspaceBridgeEmpty => 'CodeWhale не вернул workspace.';

  @override
  String workspaceBridgeLoaded(int count) {
    return 'Загружено workspace: $count';
  }

  @override
  String get primaryWorkspace => 'Основной workspace';

  @override
  String get refreshWorkspaceList => 'Обновить список';

  @override
  String get workspaceSearchHint => 'Поиск по имени, id или пути';

  @override
  String workspaceFoundSummary(int found, int total, Object source) {
    return 'Найдено: $found из $total. Источник: $source';
  }

  @override
  String get workspaceSourceBackendAccess => 'права backend';

  @override
  String get workspaceSourceCodeWhale => 'CodeWhale';

  @override
  String get clearWorkspaceBinding => 'Снять привязку';

  @override
  String get projectAgentDisabledAfterClearing => 'Агент проекта будет отключён.';

  @override
  String get noWorkspacesFound => 'Workspace не найдены.';

  @override
  String get projectWorkspaceCleared => 'Workspace проекта очищен.';

  @override
  String get projectWorkspaceSaved => 'Workspace проекта сохранён.';

  @override
  String get projectWorkspaceSaveFailed => 'Не удалось сохранить workspace проекта.';

  @override
  String projectChatReady(Object title) {
    return 'Проектный чат «$title» готов.';
  }

  @override
  String projectChatCreateFailed(Object error) {
    return 'Не удалось создать проектный чат: $error';
  }

  @override
  String get openProjectChatHint => 'Откройте проектный чат.';

  @override
  String get selectWorkspace => 'Выбрать workspace';

  @override
  String get changeWorkspace => 'Сменить workspace';

  @override
  String get workspaceNotSelectedSentence => 'Workspace не выбран.';

  @override
  String workspaceSelected(Object label) {
    return 'Выбран: $label.';
  }

  @override
  String workspaceControlAvailable(Object selectedText, int count) {
    return '$selectedText Доступно: $count.';
  }

  @override
  String get noAvailableWorkspacesToSelect => 'Нет доступных workspace для выбора.';

  @override
  String get workspaceSettingLoading => 'Загружаю настройку workspace...';

  @override
  String get refreshWorkspaces => 'Обновить workspace';

  @override
  String get selectAction => 'Выбрать';

  @override
  String projectGroupsSummary(Object groups) {
    return 'Группы: $groups';
  }

  @override
  String groupParticipantsSummary(Object participants) {
    return 'Участники: $participants';
  }

  @override
  String get deleteProjectTitle => 'Удалить проект?';

  @override
  String get deleteProjectMessage => 'Проект и привязки групп будут удалены.';

  @override
  String get deleteGroupTitle => 'Удалить группу?';

  @override
  String get deleteGroupMessage => 'Группа будет удалена из всех проектов.';

  @override
  String get connecting => 'Подключение...';

  @override
  String get reconnecting => 'Переподключение...';

  @override
  String get connected => 'Подключено';

  @override
  String get disconnected => 'Соединение потеряно';

  @override
  String get connectionError => 'Ошибка соединения';

  @override
  String get retry => 'Повторить';

  @override
  String get settings => 'Настройки';

  @override
  String get profile => 'Профиль';

  @override
  String get changePhoto => 'Изменить фото';

  @override
  String get name => 'Имя';

  @override
  String get saveName => 'Сохранить имя';

  @override
  String get phone => 'Телефон';

  @override
  String get phoneNumberLabel => 'Номер телефона';

  @override
  String get initialProfileTitle => 'Вход по номеру телефона';

  @override
  String get continueAction => 'Продолжить';

  @override
  String get administration => 'Администрирование';

  @override
  String get profileAdminSubtitle => 'Пользователи, проекты, воркспейсы и роли агентов';

  @override
  String get profileSystemCalls => 'Системные звонки';

  @override
  String get profileSystemCallsEnabled => 'Входящие звонки могут открываться через экран звонка Android';

  @override
  String get profileSystemCallsDisabled => 'Включите, чтобы входящие звонки открывались на экране блокировки';

  @override
  String get profileSystemCallsFullScreenDisabled => 'Разрешите полноэкранные уведомления для звонков на экране блокировки';

  @override
  String get profileSystemCallsNotificationsDisabled => 'Разрешите уведомления для звонков на экране блокировки';

  @override
  String get profileEnableSystemCalls => 'Включить';

  @override
  String get profileAllowSystemCallsFullScreen => 'Разрешить';

  @override
  String get profileAllowSystemCallsNotifications => 'Разрешить уведомления';

  @override
  String get profileSystemCallsSettingsFailed => 'Не удалось открыть настройки системных звонков';

  @override
  String get adminNoAccess => 'Нет доступа к администрированию';

  @override
  String get adminBridgeNotConnected => 'Воркспейсы CodeWhale не подключены';

  @override
  String get adminCodeWhaleDisabled => 'CodeWhale отключен';

  @override
  String get adminNewAccess => 'Новый доступ';

  @override
  String get adminContactFromContacts => 'Пользователь из контактов';

  @override
  String get adminContactsNotFound => 'Контакты не найдены';

  @override
  String get adminWorkspace => 'Воркспейс';

  @override
  String get adminRole => 'Роль';

  @override
  String get adminGrantAccess => 'Выдать доступ';

  @override
  String get adminGrantedAccess => 'Кому что выдано';

  @override
  String get adminNoActiveAccess => 'Активных доступов пока нет';

  @override
  String get adminRevokeAccess => 'Отозвать доступ';

  @override
  String get adminAgentRoles => 'Агенты и роли';

  @override
  String get adminWorkspaceKind => 'Воркспейс';

  @override
  String get adminSelectUserAndWorkspace => 'Выберите пользователя и воркспейс';

  @override
  String get adminAccessGranted => 'Доступ выдан';

  @override
  String get adminAccessRevoked => 'Доступ отозван';

  @override
  String adminRefreshProjectsFailed(Object error) {
    return 'Не удалось обновить проекты: $error';
  }

  @override
  String adminLoadAccessFailed(Object error) {
    return 'Не удалось загрузить доступы: $error';
  }

  @override
  String adminGrantAccessFailed(Object error) {
    return 'Не удалось выдать доступ: $error';
  }

  @override
  String adminRevokeAccessFailed(Object error) {
    return 'Не удалось отозвать доступ: $error';
  }

  @override
  String adminUsersCount(int count) {
    return 'Пользователи: $count';
  }

  @override
  String adminWorkspacesCount(int count) {
    return 'Воркспейсы: $count';
  }

  @override
  String adminProjectsCount(int count) {
    return 'Проекты: $count';
  }

  @override
  String get adminRoleWorkspaceUser => 'Участник воркспейса';

  @override
  String get adminRoleWorkspaceUserDescription => 'Видит рабочее пространство и может пользоваться ИИ.';

  @override
  String get adminRoleAgentOperator => 'Оператор агентов';

  @override
  String get adminRoleAgentOperatorDescription => 'Запускает агентские чаты из задач и ведет работу в них.';

  @override
  String get adminRoleWorkspaceAdmin => 'Администратор воркспейса';

  @override
  String get adminRoleWorkspaceAdminDescription => 'Управляет доступами и расширенными действиями агентов.';

  @override
  String avatarUploadFailed(Object error) {
    return 'Не удалось загрузить аватарку: $error';
  }

  @override
  String get nameSaved => 'Имя сохранено';

  @override
  String get theme => 'Тема';

  @override
  String get light => 'Светлая';

  @override
  String get dark => 'Тёмная';

  @override
  String get system => 'Системная';

  @override
  String get about => 'О приложении';

  @override
  String get version => 'Версия';

  @override
  String get loading => 'Загрузка...';

  @override
  String get error => 'Ошибка';

  @override
  String get photo => 'Фото';

  @override
  String get file => 'Файл';

  @override
  String get sticker => 'Стикер';

  @override
  String get stickers => 'Стикеры';

  @override
  String get noStickersLoaded => 'Стикеры еще не загружены';

  @override
  String get stickerUnavailable => 'Стикер недоступен';

  @override
  String get noSearchResults => 'Ничего не найдено';

  @override
  String get allStyles => 'Все стили';

  @override
  String get allTopics => 'Все темы';

  @override
  String get voiceMessage => 'Голосовое сообщение';

  @override
  String get typing => 'печатает...';

  @override
  String profileTyping(String profile) {
    return '$profile печатает...';
  }

  @override
  String peopleTyping(int count) {
    return '$count человека печатают...';
  }

  @override
  String get online => 'в сети';

  @override
  String get offline => 'не в сети';

  @override
  String get markRead => 'Пометить прочитанным';

  @override
  String get reply => 'Ответить';

  @override
  String get forward => 'Переслать';

  @override
  String get copy => 'Копировать';

  @override
  String get share => 'Поделиться';

  @override
  String get chatNoForwardTargets => 'Нет контактов для пересылки';

  @override
  String get chatShareWithTitle => 'Поделиться с...';

  @override
  String chatForwardedTo(Object contact) {
    return 'Переслано → $contact';
  }

  @override
  String chatForwardFailed(Object error) {
    return 'Ошибка пересылки: $error';
  }

  @override
  String get chatDeleteMessageTitle => 'Удалить сообщение?';

  @override
  String get chatDeleteMessageBody => 'Сообщение будет удалено у всех участников.';

  @override
  String chatDeleteFailed(Object error) {
    return 'Ошибка удаления: $error';
  }

  @override
  String get chatRemoveReaction => 'Убрать реакцию';

  @override
  String chatReactionFailed(Object error) {
    return 'Ошибка реакции: $error';
  }

  @override
  String chatStickerSendFailed(Object error) {
    return 'Ошибка отправки стикера: $error';
  }

  @override
  String get newSession => 'Новая сессия';

  @override
  String get workspaces => 'Рабочие пространства';

  @override
  String get attachFolder => 'Подключить папку';

  @override
  String get createWorkspace => 'Создать рабочее пространство';

  @override
  String get codeWhaleConnecting => 'Подключение к CodeWhale...';

  @override
  String get codeWhaleErrorFallback => 'Ошибка CodeWhale';

  @override
  String get codeWhaleThinking => 'CodeWhale думает...';

  @override
  String get codeWhaleStartingEvent => 'Запуск CodeWhale';

  @override
  String codeWhaleFileAttachedEvent(Object path) {
    return 'Файл прикреплен: $path';
  }

  @override
  String get codeWhaleFileAttachedStatus => 'Файл прикреплен';

  @override
  String get codeWhaleReadyStatus => 'CodeWhale готов';

  @override
  String get codeWhaleNewWorkspaceTitle => 'Новое рабочее пространство';

  @override
  String get workspaceNameLabel => 'Название';

  @override
  String get codeWhalePhotoCommentTitle => 'Комментарий к фото';

  @override
  String get codeWhaleDocumentCommentTitle => 'Комментарий к документу';

  @override
  String get codeWhaleUploadPromptHint => 'Пусто = только сохранить';

  @override
  String get noWorkspacesYet => 'Рабочих пространств пока нет';

  @override
  String get back => 'Назад';

  @override
  String get createSession => 'Создать сессию';

  @override
  String get manageSession => 'Управление сессией';

  @override
  String get noSessionsYet => 'Сессий пока нет';

  @override
  String get running => 'Работает';

  @override
  String get port => 'порт';

  @override
  String get waitingToStart => 'Ожидает запуска';

  @override
  String get stopped => 'Остановлена';

  @override
  String get killed => 'Убита';

  @override
  String get unknownStatus => 'Неизвестный статус';

  @override
  String get folderSelection => 'Выбор папки';

  @override
  String get refreshFolders => 'Обновить папки';

  @override
  String get currentFolder => 'Текущая папка';

  @override
  String get copyPath => 'Копировать путь';

  @override
  String get parentFolder => 'На уровень выше';

  @override
  String get noFoldersHere => 'Папок здесь нет';

  @override
  String get connectThisFolder => 'Подключить эту папку';

  @override
  String get sessionHistoryEmpty => 'История сессии пуста';

  @override
  String get attachPhoto => 'Прикрепить фото';

  @override
  String get attachDocument => 'Прикрепить документ';

  @override
  String get copyText => 'Копировать текст';

  @override
  String get copied => 'Скопировано';

  @override
  String get workProgress => 'Ход работы';

  @override
  String get stopGeneration => 'Остановить генерацию';

  @override
  String get sessionTab => 'Сессия';

  @override
  String get filesTab => 'Файлы';

  @override
  String get commandsTab => 'Команды';

  @override
  String get sessionStatusLabel => 'Статус';

  @override
  String get sessionPidLabel => 'PID';

  @override
  String get sessionPortLabel => 'Порт';

  @override
  String get sessionEventsLabel => 'Событий';

  @override
  String get noValue => 'нет';

  @override
  String get sessionIdleStatus => 'Ожидает';

  @override
  String get sessionUnknownStatus => 'Неизвестно';

  @override
  String get restartWorker => 'Перезапустить worker';

  @override
  String get stopSession => 'Остановить сессию';

  @override
  String get killStuckSession => 'Убить зависшую сессию';

  @override
  String get restartAction => 'Перезапустить';

  @override
  String get stopAction => 'Остановить';

  @override
  String get killAction => 'Убить';

  @override
  String get document => 'Документ';

  @override
  String get projectRoot => 'Корень проекта';

  @override
  String get upOneLevel => 'Наверх';

  @override
  String get refreshFiles => 'Обновить файлы';

  @override
  String get copyFileText => 'Копировать текст файла';

  @override
  String get noFiles => 'Файлов нет';

  @override
  String get insertPathInChat => 'Путь в чат';

  @override
  String get previewFile => 'Просмотр файла';

  @override
  String projectFilesTitle(Object projectName) {
    return 'Файлы - $projectName';
  }

  @override
  String get loadingFiles => 'Загрузка файлов...';

  @override
  String get folderEmpty => 'Папка пуста';

  @override
  String get previewAction => 'Просмотр';

  @override
  String get linkToChat => 'Ссылка в чат';

  @override
  String get sessionCodeWhaleModes => 'Режимы CodeWhale';

  @override
  String get provider => 'Провайдер';

  @override
  String get model => 'Модель';

  @override
  String get approvalPolicy => 'Подтверждения';

  @override
  String get sandbox => 'Sandbox';

  @override
  String get defaultValue => 'по умолчанию';

  @override
  String get autoModeTools => 'Авто-режим инструментов';

  @override
  String get autoModeToolsTooltip => 'Автоматически выполнять инструменты';

  @override
  String get autoModeToolsSubtitle => 'Передает --auto в CodeWhale exec';

  @override
  String get codeWhaleCommandsLoading => 'Команды CodeWhale загружаются...';

  @override
  String get skills => 'Скиллы';

  @override
  String get runSelected => 'Запустить выбранные';

  @override
  String get chooseSkills => 'Выбери один или несколько навыков';

  @override
  String selectedSkillsCount(int count) {
    return 'Выбрано: $count';
  }

  @override
  String get diagnostics => 'Диагностика';

  @override
  String get resetToken => 'Сбросить токен';

  @override
  String get refresh => 'Обновить';

  @override
  String get notificationChannelName => 'Уведомления';

  @override
  String get notificationChannelDesc => 'Пуш-уведомления о задачах и напоминаниях';

  @override
  String get notificationNewMessage => 'Новое сообщение';

  @override
  String get yes => 'Да';

  @override
  String get no => 'Нет';

  @override
  String get ok => 'OK';
}
