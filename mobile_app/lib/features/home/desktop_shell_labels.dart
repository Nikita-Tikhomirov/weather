import '../../l10n/app_localizations.dart';

class DesktopShellLabels {
  const DesktopShellLabels(this.l10n);

  final AppLocalizations? l10n;

  String get tasks => l10n?.tasksTab ?? 'Tasks';
  String get calendar => l10n?.calendarTab ?? 'Calendar';
  String get messenger => l10n?.messengerTab ?? 'Messenger';
  String get light => l10n?.light ?? 'Light';
  String get dark => l10n?.dark ?? 'Dark';
  String get theme => l10n?.theme ?? 'Theme';
  String get voice => l10n?.voice ?? 'Voice';
  String get addTask => l10n?.addTask ?? 'Add';
  String get sync => l10n?.syncAction ?? 'Sync';
  String get undo => l10n?.undo ?? 'Undo';
  String get administration => l10n?.administration ?? 'Administration';

  String taskTitle(String selectedDateKey) => '$tasks - $selectedDateKey';
}
