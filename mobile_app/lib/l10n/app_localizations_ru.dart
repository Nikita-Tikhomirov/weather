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
  String get taskAgentNewChat => 'Новый чат';

  @override
  String get taskAgentChat => 'Агентский чат';

  @override
  String get taskAgentTaskChats => 'Чаты задачи';

  @override
  String get taskAgentNoChats => 'Агентские чаты не подключены';

  @override
  String get taskAgentQueueRunning => 'Очередь идет';

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
  String get groupNameLabel => 'Название группы';

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
  String get projectsSection => 'Проекты';

  @override
  String get createProjectAction => 'Создать проект';

  @override
  String get createGroupAction => 'Создать группу';

  @override
  String get projectChats => 'Проектные чаты';

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
