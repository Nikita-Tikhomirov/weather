import '../../l10n/app_localizations.dart';

class HomeProjectDataLabels {
  const HomeProjectDataLabels(this.l10n);

  final AppLocalizations? l10n;

  String get projectChatsUnavailable =>
      l10n?.homeProjectChatsUnavailable ?? 'Project chats are unavailable';
  String get projectNotFound =>
      l10n?.homeProjectNotFound ?? 'Project not found';
  String get requestingProjectFiles =>
      l10n?.homeProjectRequestingFiles ?? 'Requesting project files...';
  String get fileContentLoading =>
      l10n?.homeProjectFileContentLoading ?? 'Loading content...';
  String get close => l10n?.close ?? 'Close';
  String get fileFallbackName => l10n?.homeProjectFileFallbackName ?? 'File';
  String get copyAll => l10n?.homeProjectCopyAll ?? 'Copy all';
  String get copiedToClipboard =>
      l10n?.homeProjectCopiedToClipboard ?? 'Copied to clipboard';
  String get fileEmpty => l10n?.homeProjectFileEmpty ?? 'File is empty';
  String get bridgeStartSent =>
      l10n?.homeProjectBridgeStartSent ?? 'Bridge start command sent';
  String get bridgeStartFailed =>
      l10n?.homeProjectBridgeStartFailed ??
      'Could not send bridge start command';
  String get newSessionStarting =>
      l10n?.homeProjectNewSessionStarting ?? 'Creating new session...';
  String get stopCommandSent =>
      l10n?.homeProjectStopCommandSent ?? 'Stop command sent';
  String get photoCommentTitle =>
      l10n?.homeProjectPhotoCommentTitle ?? 'Photo comment';
  String get deepSeekPromptHint =>
      l10n?.homeProjectDeepSeekPromptHint ??
      'Prompt for DeepSeek after upload (optional)';
  String get saveOnly => l10n?.homeProjectSaveOnly ?? 'Save only';
  String get send => l10n?.send ?? 'Send';
  String get photosNotSent =>
      l10n?.homeProjectPhotosNotSent ??
      'Photo was not sent. Check connection or file size.';
  String get documentCommentTitle =>
      l10n?.homeProjectDocumentCommentTitle ?? 'Document comment';
  String get projectServerTitle =>
      l10n?.homeProjectServerTitle ?? 'Project server';
  String get projectServerDescription =>
      l10n?.homeProjectServerDescription ??
      'IP address and port of the PC running project_bridge.py';
  String get addressLabel => l10n?.homeProjectAddressLabel ?? 'Address';
  String get cancel => l10n?.cancel ?? 'Cancel';
  String get save => l10n?.save ?? 'Save';

  String fileLink(String path) {
    return l10n?.homeProjectFileLink(path) ?? 'File: $path';
  }

  String photosSavedToVision(int count) {
    return l10n?.homeProjectPhotosSavedToVision(count) ??
        'Photo saved to vision: $count';
  }

  String photosNotSentCount(int count) {
    return l10n?.homeProjectPhotosNotSentCount(count) ??
        'Photos not sent: $count';
  }

  String documentMessage(String filename) {
    return l10n?.homeProjectDocumentMessage(filename) ?? 'Document: $filename';
  }
}
