import '../../l10n/app_localizations.dart';

class HomeAttachmentLabels {
  const HomeAttachmentLabels(this.l10n);

  final AppLocalizations? l10n;

  String get fileReadFailed =>
      l10n?.taskFileReadFailed ?? 'Could not read file';
  String get photoCaptionTitle =>
      l10n?.taskPhotoCaptionTitle ?? 'Photo caption';
  String get videoCaptionTitle =>
      l10n?.chatVideoCaptionTitle ?? 'Video caption';
  String get captionHint =>
      l10n?.taskAttachmentCaptionHint ?? 'Add caption (optional)';
  String get skipCaption => l10n?.taskSkipAttachmentCaption ?? 'Skip';
  String get done => l10n?.done ?? 'Done';
  String get gallery => l10n?.gallery ?? 'Gallery';
  String get camera => l10n?.camera ?? 'Camera';
  String get video => l10n?.video ?? 'Video';
  String get document => l10n?.document ?? 'Document';
  String get sticker => l10n?.sticker ?? 'Sticker';

  String fileTooLarge({required int maxMb}) {
    return l10n?.chatFileTooLarge(maxMb) ??
        'File is too large. Maximum $maxMb MB.';
  }

  String documentSendFailed(Object error) {
    return l10n?.chatDocumentSendFailed(error) ??
        'Could not send document: $error';
  }

  String videoTooLarge({required int sizeMb, required int maxMb}) {
    return l10n?.chatVideoTooLarge(sizeMb, maxMb) ??
        'Video is too large ($sizeMb MB). Maximum $maxMb MB.';
  }

  String photoSendFailed(Object error) {
    return l10n?.chatPhotoSendFailed(error) ?? 'Could not send: $error';
  }

  String videoSendFailed(Object error) {
    return l10n?.chatVideoSendFailed(error) ?? 'Could not send video: $error';
  }
}
