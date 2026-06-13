import 'package:family_todo_mobile/features/home/home_attachment_labels.dart';
import 'package:family_todo_mobile/l10n/app_localizations_ru.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses English fallback attachment labels without localizations', () {
    const labels = HomeAttachmentLabels(null);

    expect(labels.fileReadFailed, 'Could not read file');
    expect(labels.fileTooLarge(maxMb: 50), 'File is too large. Maximum 50 MB.');
    expect(
      labels.videoTooLarge(sizeMb: 600, maxMb: 500),
      'Video is too large (600 MB). Maximum 500 MB.',
    );
    expect(
      labels.documentSendFailed('network'),
      'Could not send document: network',
    );
    expect(labels.photoCaptionTitle, 'Photo caption');
    expect(labels.videoCaptionTitle, 'Video caption');
    expect(labels.captionHint, 'Add caption (optional)');
    expect(labels.skipCaption, 'Skip');
    expect(labels.done, 'Done');
    expect(labels.photoSendFailed('network'), 'Could not send: network');
    expect(labels.videoSendFailed('network'), 'Could not send video: network');
    expect(labels.gallery, 'Gallery');
    expect(labels.camera, 'Camera');
    expect(labels.video, 'Video');
    expect(labels.document, 'Document');
    expect(labels.sticker, 'Sticker');
  });

  test('uses Russian generated attachment labels when localizations exist', () {
    final labels = HomeAttachmentLabels(AppLocalizationsRu());

    expect(labels.fileReadFailed, 'Не удалось прочитать файл');
    expect(
      labels.fileTooLarge(maxMb: 50),
      'Файл слишком большой. Максимум 50 МБ.',
    );
    expect(
      labels.videoTooLarge(sizeMb: 600, maxMb: 500),
      'Видео слишком большое (600 МБ). Максимум 500 МБ.',
    );
    expect(
      labels.documentSendFailed('сеть'),
      'Ошибка отправки документа: сеть',
    );
    expect(labels.photoCaptionTitle, 'Подпись к фото');
    expect(labels.videoCaptionTitle, 'Подпись к видео');
    expect(labels.captionHint, 'Добавить подпись (необязательно)');
    expect(labels.skipCaption, 'Пропустить');
    expect(labels.done, 'Готово');
    expect(labels.photoSendFailed('сеть'), 'Ошибка отправки: сеть');
    expect(labels.videoSendFailed('сеть'), 'Ошибка отправки видео: сеть');
    expect(labels.gallery, 'Галерея');
    expect(labels.camera, 'Камера');
    expect(labels.video, 'Видео');
    expect(labels.document, 'Документ');
    expect(labels.sticker, 'Стикер');
  });
}
