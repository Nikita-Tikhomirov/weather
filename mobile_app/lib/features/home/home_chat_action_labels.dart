import '../../l10n/app_localizations.dart';

class HomeChatActionLabels {
  const HomeChatActionLabels(this.l10n);

  final AppLocalizations? l10n;

  String get noForwardTargets =>
      l10n?.chatNoForwardTargets ?? 'No contacts to share with';
  String get shareWithTitle => l10n?.chatShareWithTitle ?? 'Share with...';
  String get cancel => l10n?.cancel ?? 'Cancel';
  String get delete => l10n?.delete ?? 'Delete';
  String get edit => l10n?.edit ?? 'Edit';
  String get reply => l10n?.reply ?? 'Reply';
  String get share => l10n?.share ?? 'Share';
  String get removeReaction => l10n?.chatRemoveReaction ?? 'Remove reaction';
  String get deleteMessageTitle =>
      l10n?.chatDeleteMessageTitle ?? 'Delete message?';
  String get deleteMessageBody =>
      l10n?.chatDeleteMessageBody ??
      'The message will be deleted for all participants.';

  String forwardedSticker(String senderLabel) {
    return '↪ $senderLabel: ${l10n?.sticker ?? 'Sticker'}';
  }

  String forwardedPhoto(String senderLabel) {
    return '↪ $senderLabel: ${l10n?.photo ?? 'Photo'}';
  }

  String forwardedTo(String contact) {
    return l10n?.chatForwardedTo(contact) ?? 'Forwarded to $contact';
  }

  String forwardFailed(Object error) {
    return l10n?.chatForwardFailed(error) ?? 'Could not forward: $error';
  }

  String deleteFailed(Object error) {
    return l10n?.chatDeleteFailed(error) ?? 'Could not delete: $error';
  }

  String reactionFailed(Object error) {
    return l10n?.chatReactionFailed(error) ??
        'Could not update reaction: $error';
  }

  String stickerSendFailed(Object error) {
    return l10n?.chatStickerSendFailed(error) ??
        'Could not send sticker: $error';
  }
}
