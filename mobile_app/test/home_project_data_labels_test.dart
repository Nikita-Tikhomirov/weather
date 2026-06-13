import 'package:family_todo_mobile/features/home/home_project_data_labels.dart';
import 'package:family_todo_mobile/l10n/app_localizations_ru.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses English fallback project data labels without localizations', () {
    const labels = HomeProjectDataLabels(null);

    expect(labels.projectChatsUnavailable, 'Project chats are unavailable');
    expect(labels.projectNotFound, 'Project not found');
    expect(labels.requestingProjectFiles, 'Requesting project files...');
    expect(labels.fileLink('/tmp/file.txt'), 'File: /tmp/file.txt');
    expect(labels.fileContentLoading, 'Loading content...');
    expect(labels.close, 'Close');
    expect(labels.fileFallbackName, 'File');
    expect(labels.copyAll, 'Copy all');
    expect(labels.copiedToClipboard, 'Copied to clipboard');
    expect(labels.fileEmpty, 'File is empty');
    expect(labels.bridgeStartSent, 'Bridge start command sent');
    expect(labels.bridgeStartFailed, 'Could not send bridge start command');
    expect(labels.newSessionStarting, 'Creating new session...');
    expect(labels.stopCommandSent, 'Stop command sent');
    expect(labels.photoCommentTitle, 'Photo comment');
    expect(
      labels.deepSeekPromptHint,
      'Prompt for DeepSeek after upload (optional)',
    );
    expect(labels.saveOnly, 'Save only');
    expect(labels.send, 'Send');
    expect(labels.photosSavedToVision(2), 'Photo saved to vision: 2');
    expect(
      labels.photosNotSent,
      'Photo was not sent. Check connection or file size.',
    );
    expect(labels.photosNotSentCount(3), 'Photos not sent: 3');
    expect(labels.documentCommentTitle, 'Document comment');
    expect(labels.documentMessage('spec.pdf'), 'Document: spec.pdf');
    expect(labels.projectServerTitle, 'Project server');
    expect(
      labels.projectServerDescription,
      'IP address and port of the PC running project_bridge.py',
    );
    expect(labels.addressLabel, 'Address');
    expect(labels.cancel, 'Cancel');
    expect(labels.save, 'Save');
  });

  test('uses Russian generated project data labels when localizations exist',
      () {
    final labels = HomeProjectDataLabels(AppLocalizationsRu());

    expect(labels.projectChatsUnavailable, 'Проектные чаты недоступны');
    expect(labels.projectNotFound, 'Проект не найден');
    expect(labels.requestingProjectFiles, 'Запрашиваю файлы проекта...');
    expect(labels.fileLink('/tmp/file.txt'), 'Файл: /tmp/file.txt');
    expect(labels.fileContentLoading, 'Загрузка содержимого...');
    expect(labels.close, 'Закрыть');
    expect(labels.fileFallbackName, 'Файл');
    expect(labels.copyAll, 'Копировать всё');
    expect(labels.copiedToClipboard, 'Скопировано в буфер');
    expect(labels.fileEmpty, 'Файл пуст');
    expect(labels.bridgeStartSent, 'Команда запуска bridge отправлена');
    expect(
      labels.bridgeStartFailed,
      'Не удалось отправить команду запуска bridge',
    );
    expect(labels.newSessionStarting, 'Создаю новую сессию...');
    expect(labels.stopCommandSent, 'Команда остановки отправлена');
    expect(labels.photoCommentTitle, 'Комментарий к фото');
    expect(
      labels.deepSeekPromptHint,
      'Промт для DeepSeek после загрузки (необязательно)',
    );
    expect(labels.saveOnly, 'Только сохранить');
    expect(labels.send, 'Отправить');
    expect(labels.photosSavedToVision(2), 'Фото сохранено в vision: 2');
    expect(
      labels.photosNotSent,
      'Фото не отправлено. Проверьте соединение или размер файла.',
    );
    expect(labels.photosNotSentCount(3), 'Не отправлено фото: 3');
    expect(labels.documentCommentTitle, 'Комментарий к документу');
    expect(labels.documentMessage('spec.pdf'), '📎 Документ: spec.pdf');
    expect(labels.projectServerTitle, 'Сервер проектов');
    expect(
      labels.projectServerDescription,
      'IP-адрес и порт ПК, на котором запущен project_bridge.py',
    );
    expect(labels.addressLabel, 'Адрес');
    expect(labels.cancel, 'Отмена');
    expect(labels.save, 'Сохранить');
  });
}
