import '../../l10n/app_localizations.dart';

class DesktopShellLabels {
  const DesktopShellLabels(this.l10n);

  final AppLocalizations? l10n;

  String get tasks => l10n?.tasksTab ?? 'Задачи';
  String get calendar => l10n?.calendarTab ?? 'Календарь';
  String get messenger => l10n?.messengerTab ?? 'Мессенджер';
  String get light => l10n?.light ?? 'Свет';
  String get dark => l10n?.dark ?? 'Тьма';
  String get theme => l10n?.theme ?? 'Тема';
  String get voice => l10n?.voice ?? 'Голос';
  String get addTask => l10n?.addTask ?? 'Добавить';
  String get sync => l10n?.syncAction ?? 'Синхронизация';
  String get undo => l10n?.undo ?? 'Отменить';
  String get administration => l10n?.administration ?? 'Администрирование';

  String taskTitle(String selectedDateKey) => '$tasks - $selectedDateKey';
}
