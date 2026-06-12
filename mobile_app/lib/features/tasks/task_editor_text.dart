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
  String get agentNewChat => l10n?.taskAgentNewChat ?? 'Новый чат';
  String get agentChat => l10n?.taskAgentChat ?? 'Агентский чат';
  String get agentTaskChats => l10n?.taskAgentTaskChats ?? 'Чаты задачи';
  String get agentNoChats =>
      l10n?.taskAgentNoChats ?? 'Агентские чаты не подключены';
  String get agentQueueRunning => l10n?.taskAgentQueueRunning ?? 'Очередь идет';
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
  String get duration => l10n?.taskDuration ?? 'Оценка времени (мин)';
  String get details => l10n?.taskDetails ?? 'Описание';
  String get comments => l10n?.taskComments ?? 'Комментарии';
  String get noComments => l10n?.taskNoComments ?? 'Комментариев нет';
  String get checklists => l10n?.taskChecklists ?? 'Чеклисты';
  String get newChecklist => l10n?.taskNewChecklist ?? 'Новый чеклист';
  String get addChecklist => l10n?.taskAddChecklist ?? 'Добавить чеклист';
  String get noChecklists => l10n?.taskNoChecklists ?? 'Чеклистов нет';
}
