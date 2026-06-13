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
    expect(text.agent, 'Агент');
    expect(text.user, 'Пользователь');
    expect(text.openPhotoAttachment, 'Открыть фото');
    expect(text.openFileAttachment, 'Открыть файл');
    expect(text.removeAttachment, 'Убрать вложение');
    expect(text.fileReadFailed, 'Не удалось прочитать файл');
    expect(text.fileOpenFailed, 'Не удалось открыть файл');
    expect(
      text.selectAgentWorkspace,
      'Выберите воркспейс для агентского чата',
    );
    expect(
      text.noAgentChatsInWorkspace,
      'В этом воркспейсе нет агентских чатов',
    );
    expect(
      text.agentChatNotLinkedToWorkspace,
      'Агентский чат не связан с воркспейсом',
    );
    expect(text.agentConnectNoAccess, 'Нет прав на подключение чата');
    expect(text.connectedAgentChatTitle, 'Подключенный агентский чат');
    expect(
      text.agentChatConnectedToCard,
      'Агентский чат подключен к карточке',
    );
    expect(
      text.agentChatConnectFailed('ошибка'),
      'Не удалось подключить чат: ошибка',
    );
    expect(text.codeWhaleUnavailable, 'CodeWhale недоступен');
    expect(
      text.agentToolsLoadFailed('ошибка'),
      'Не удалось загрузить инструменты агента: ошибка',
    );
    expect(
      text.agentWorkspacesLoadFailed('ошибка'),
      'Не удалось загрузить воркспейсы: ошибка',
    );
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
    expect(text.agent, 'Agent');
    expect(text.user, 'User');
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
    expect(text.selectAgentWorkspace, 'Select workspace for agent chat');
    expect(
      text.noAgentChatsInWorkspace,
      'No agent chats in this workspace',
    );
    expect(
      text.agentChatNotLinkedToWorkspace,
      'Agent chat is not linked to a workspace',
    );
    expect(text.agentConnectNoAccess, 'No permission to connect chat');
    expect(text.connectedAgentChatTitle, 'Connected agent chat');
    expect(
      text.agentChatConnectedToCard,
      'Agent chat connected to the task card',
    );
    expect(
      text.agentChatConnectFailed('network'),
      'Could not connect chat: network',
    );
    expect(text.codeWhaleUnavailable, 'CodeWhale is unavailable');
    expect(
      text.agentToolsLoadFailed('network'),
      'Could not load agent tools: network',
    );
    expect(
      text.agentWorkspacesLoadFailed('network'),
      'Could not load workspaces: network',
    );
  });
}
