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
  });
}
