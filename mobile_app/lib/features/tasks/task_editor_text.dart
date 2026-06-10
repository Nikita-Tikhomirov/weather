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
}
