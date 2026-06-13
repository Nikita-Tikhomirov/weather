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

  String fileLink(String path) {
    return l10n?.homeProjectFileLink(path) ?? 'File: $path';
  }
}
