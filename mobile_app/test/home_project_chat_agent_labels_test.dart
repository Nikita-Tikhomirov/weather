import 'package:family_todo_mobile/features/home/home_project_chat_agent_labels.dart';
import 'package:family_todo_mobile/l10n/app_localizations_ru.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses English fallback project chat agent labels without localizations',
      () {
    const labels = HomeProjectChatAgentLabels(null);

    expect(
      labels.draftButtonUserMessage,
      'User pressed the task draft button.',
    );
    expect(labels.agentTitle('Cifra'), 'Tudushker: Cifra');
    expect(
      labels.analyzingChat,
      'Tudushker is analyzing the chat.',
    );
    expect(
      labels.unstructuredResponseSnack,
      'Tudushker returned an unstructured response.',
    );
    expect(labels.analyzeFailed, 'Could not analyze the project chat.');
    expect(
      labels.selectProjectWorkspace,
      'Select the project workspace in Project Control Center.',
    );
    expect(labels.agentStarting, 'Project agent is starting in CodeWhale.');
    expect(labels.agentStartFailed, 'Could not start the project agent.');
    expect(
      labels.taskCreatedInProject('Cifra'),
      'Task created in project Cifra.',
    );
    expect(
      labels.unstructuredResponseMessage,
      'I received an unstructured model response and did not send it to the '
      'chat. Try making the request a little more specific.',
    );
    expect(
      labels.requestFailedMessage,
      'I could not process the request. Check the project workspace and '
      'CodeWhale availability.',
    );
    expect(
      labels.taskDraftMissingMessage,
      'I understood that a task card is needed, but could not build a '
      'structured draft.',
    );
    expect(
      labels.agentSessionStartedMessage,
      'Started a work session in the project workspace.',
    );
    expect(
      labels.emptyReplyMessage,
      'I checked the context, but could not formulate a useful response.',
    );
    expect(labels.ownerFallbackMessage('hello'), 'Tudushker: hello');
    expect(labels.codeWhaleErrorFallback, 'CodeWhale error');
    expect(labels.imageSavedToGallery, 'Photo saved to gallery');
    expect(labels.imageSaveFailed, 'Could not save photo');
  });

  test(
      'uses Russian generated project chat agent labels when localizations exist',
      () {
    final labels = HomeProjectChatAgentLabels(AppLocalizationsRu());

    expect(
      labels.draftButtonUserMessage,
      'Пользователь нажал кнопку создания черновика задачи.',
    );
    expect(labels.agentTitle('Цифра'), 'Тудушкер: Цифра');
    expect(labels.analyzingChat, 'Тудушкер анализирует чат.');
    expect(
      labels.unstructuredResponseSnack,
      'Тудушкер вернул неструктурированный ответ.',
    );
    expect(labels.analyzeFailed, 'Не удалось проанализировать чат проекта.');
    expect(
      labels.selectProjectWorkspace,
      'Выберите workspace проекта в Project Control Center.',
    );
    expect(labels.agentStarting, 'Агент проекта запускается в CodeWhale.');
    expect(labels.agentStartFailed, 'Не удалось запустить агента проекта.');
    expect(
      labels.taskCreatedInProject('Цифра'),
      'Задача создана в проекте Цифра.',
    );
    expect(
      labels.unstructuredResponseMessage,
      'Я получил неструктурированный ответ модели и не стал отправлять его в '
      'чат. Повторите запрос чуть точнее.',
    );
    expect(
      labels.requestFailedMessage,
      'Не смог обработать запрос. Проверьте workspace проекта и доступность '
      'CodeWhale.',
    );
    expect(
      labels.taskDraftMissingMessage,
      'Я понял, что нужна карточка, но не смог собрать структурированный '
      'черновик.',
    );
    expect(
      labels.agentSessionStartedMessage,
      'Запустил рабочую сессию в workspace проекта.',
    );
    expect(
      labels.emptyReplyMessage,
      'Я посмотрел контекст, но не смог сформулировать полезный ответ.',
    );
    expect(labels.ownerFallbackMessage('привет'), 'Тудушкер: привет');
    expect(labels.codeWhaleErrorFallback, 'Ошибка CodeWhale');
    expect(labels.imageSavedToGallery, 'Фото сохранено в галерею');
    expect(labels.imageSaveFailed, 'Не удалось сохранить фото');
  });
}
