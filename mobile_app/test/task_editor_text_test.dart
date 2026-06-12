import 'package:family_todo_mobile/features/tasks/task_editor_text.dart';
import 'package:family_todo_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fallback keeps Russian labels for legacy test harnesses', () {
    const text = TaskEditorText.fallback();

    expect(text.newTask, 'Новая задача');
    expect(text.settingsTab, 'Настройки');
    expect(text.title, 'Название');
    expect(text.openPhotoAttachment, 'Открыть фото');
    expect(text.openFileAttachment, 'Открыть файл');
    expect(text.removeAttachment, 'Убрать вложение');
    expect(text.fileReadFailed, 'Не удалось прочитать файл');
    expect(text.fileOpenFailed, 'Не удалось открыть файл');
  });

  testWidgets('reads English labels from AppLocalizations', (tester) async {
    late TaskEditorText text;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            text = TaskEditorText.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(text.newTask, 'New task');
    expect(text.settingsTab, 'Settings');
    expect(text.title, 'Title');
    expect(text.selectProject, 'Select project');
    expect(text.openPhotoAttachment, 'Open photo');
    expect(text.openFileAttachment, 'Open file');
    expect(text.removeAttachment, 'Remove attachment');
    expect(
      text.attachmentUploadFailed('network'),
      'Could not upload attachment: network',
    );
    expect(text.attachmentEmptyOrCorrupt, 'The file is empty or corrupted.');
    expect(
      text.attachmentUploadMissingUrl,
      'The server did not return a file URL.',
    );
    expect(text.fileReadFailed, 'Could not read file');
    expect(text.fileOpenFailed, 'Could not open file');
  });
}
