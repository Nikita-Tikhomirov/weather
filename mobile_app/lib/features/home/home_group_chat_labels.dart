import '../../l10n/app_localizations.dart';

class HomeGroupChatLabels {
  const HomeGroupChatLabels(this.l10n);

  final AppLocalizations? l10n;

  String get defaultGroupName => l10n?.groupDefaultName ?? 'Group';
  String get renameAction => l10n?.groupRenameAction ?? 'Rename';
  String get delete => l10n?.delete ?? 'Delete';
  String get addMember => l10n?.groupAddMember ?? 'Add member';
  String get avatarUpdated => l10n?.groupAvatarUpdated ?? 'Avatar updated';
  String get groupNameTitle => l10n?.groupNameLabel ?? 'Group name';
  String get groupNameHint => l10n?.groupNameHint ?? 'For example: Work';
  String get cancel => l10n?.cancel ?? 'Cancel';
  String get save => l10n?.save ?? 'Save';
  String get deleteGroupTitle => l10n?.deleteGroupTitle ?? 'Delete group?';
  String get noAvailableContacts =>
      l10n?.groupNoAvailableContacts ?? 'No available contacts';
  String get selectMember => l10n?.groupSelectMember ?? 'Select member';
  String get groupDeletedLocally =>
      l10n?.groupDeletedLocally ?? 'Group removed from local list';

  String deleteGroupMessage(String title) {
    return l10n?.groupChatDeleteMessage(title) ??
        'Group "$title" will disappear for all participants with its chat history.';
  }

  String memberAdded(String profile) {
    return l10n?.groupMemberAdded(profile) ?? '$profile added';
  }

  String genericError(Object error) {
    return l10n?.groupSaveFailed(error) ?? 'Error: $error';
  }

  String avatarUploadFailed(Object error) {
    return l10n?.groupAvatarUploadFailed(error) ??
        'Could not upload avatar: $error';
  }
}
