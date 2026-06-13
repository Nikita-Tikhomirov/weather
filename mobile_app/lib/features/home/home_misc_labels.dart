import '../../l10n/app_localizations.dart';

class HomeMiscLabels {
  const HomeMiscLabels(this.l10n);

  final AppLocalizations? l10n;

  String get newGroup => l10n?.newGroup ?? 'New group';
  String get groupNameLabel => l10n?.groupNameLabel ?? 'Group name';
  String get create => l10n?.create ?? 'Create';
  String get noWorkspaceAccess =>
      l10n?.homeNoWorkspaceAccess ?? 'No workspace access';
  String get selectWorkspaceProjectReason =>
      l10n?.homeSelectWorkspaceProjectReason ??
      'Select a project linked to a workspace.';
  String get colorSchemeTooltip => l10n?.colorSchemeTooltip ?? 'Color scheme';
  String get profile => l10n?.profile ?? 'Profile';
  String get administration => l10n?.administration ?? 'Administration';
  String get undoLastAction => l10n?.undoLastAction ?? 'Undo last action';
  String get lastActionUndone => l10n?.lastActionUndone ?? 'Last action undone';
  String get fcmDiagnostics => l10n?.fcmDiagnostics ?? 'FCM diagnostics';
  String get calendar => l10n?.calendarTab ?? 'Calendar';
  String get sync => l10n?.syncAction ?? 'Sync';
  String get fcmRefreshInProgress =>
      l10n?.fcmRefreshInProgress ?? 'FCM: refreshing diagnostics...';
  String get fcmResetInProgress =>
      l10n?.fcmResetInProgress ?? 'FCM: resetting token...';
  String get refresh => l10n?.refresh ?? 'Refresh';
  String get resetToken => l10n?.fcmResetToken ?? 'Reset token';
  String get close => l10n?.close ?? 'Close';

  String chatRefreshFailed(Object error) {
    return l10n?.homeChatRefreshFailed(error) ??
        'Could not refresh chat: $error';
  }

  String contactAddedToFamily(String contact) {
    return l10n?.homeContactAddedToFamily(contact) ??
        '$contact added to family';
  }

  String addToFamilyFailed(Object error) {
    return l10n?.homeAddToFamilyFailed(error) ??
        'Could not add to family: $error';
  }

  String chatUnavailable(Object error) {
    return l10n?.homeChatUnavailable(error) ?? 'Chat unavailable: $error';
  }
}
