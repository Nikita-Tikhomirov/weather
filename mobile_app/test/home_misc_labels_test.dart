import 'package:family_todo_mobile/features/home/home_misc_labels.dart';
import 'package:family_todo_mobile/l10n/app_localizations_ru.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses English fallback misc labels without localizations', () {
    const labels = HomeMiscLabels(null);

    expect(
      labels.chatRefreshFailed('network'),
      'Could not refresh chat: network',
    );
    expect(labels.newGroup, 'New group');
    expect(labels.groupNameLabel, 'Group name');
    expect(labels.create, 'Create');
    expect(labels.contactAddedToFamily('Alice'), 'Alice added to family');
    expect(
      labels.addToFamilyFailed('network'),
      'Could not add to family: network',
    );
    expect(labels.chatUnavailable('network'), 'Chat unavailable: network');
    expect(labels.noWorkspaceAccess, 'No workspace access');
    expect(
      labels.selectWorkspaceProjectReason,
      'Select a project linked to a workspace.',
    );
    expect(labels.colorSchemeTooltip, 'Color scheme');
    expect(labels.profile, 'Profile');
    expect(labels.administration, 'Administration');
    expect(labels.undoLastAction, 'Undo last action');
    expect(labels.lastActionUndone, 'Last action undone');
    expect(labels.fcmDiagnostics, 'FCM diagnostics');
    expect(labels.calendar, 'Calendar');
    expect(labels.sync, 'Sync');
    expect(labels.fcmRefreshInProgress, 'FCM: refreshing diagnostics...');
    expect(labels.fcmResetInProgress, 'FCM: resetting token...');
    expect(labels.refresh, 'Refresh');
    expect(labels.resetToken, 'Reset token');
    expect(labels.close, 'Close');
  });

  test('uses Russian generated misc labels when localizations exist', () {
    final labels = HomeMiscLabels(AppLocalizationsRu());

    expect(labels.chatRefreshFailed('сеть'), 'Ошибка обновления чата: сеть');
    expect(labels.newGroup, 'Новая группа');
    expect(labels.groupNameLabel, 'Название группы');
    expect(labels.create, 'Создать');
    expect(labels.contactAddedToFamily('Алиса'), 'Алиса добавлен в семью');
    expect(
      labels.addToFamilyFailed('сеть'),
      'Не удалось добавить в семью: сеть',
    );
    expect(labels.chatUnavailable('сеть'), 'Чат недоступен: сеть');
    expect(labels.noWorkspaceAccess, 'Нет доступа к воркспейсам');
    expect(
      labels.selectWorkspaceProjectReason,
      'Выберите проект, связанный с воркспейсом.',
    );
    expect(labels.colorSchemeTooltip, 'Цветовая схема');
    expect(labels.profile, 'Профиль');
    expect(labels.administration, 'Администрирование');
    expect(labels.undoLastAction, 'Откатить последнее действие');
    expect(labels.lastActionUndone, 'Последнее действие отменено');
    expect(labels.fcmDiagnostics, 'FCM диагностика');
    expect(labels.calendar, 'Календарь');
    expect(labels.sync, 'Синхронизировать');
    expect(labels.fcmRefreshInProgress, 'FCM: обновляю диагностику...');
    expect(labels.fcmResetInProgress, 'FCM: сбрасываю токен...');
    expect(labels.refresh, 'Обновить');
    expect(labels.resetToken, 'Сбросить токен');
    expect(labels.close, 'Закрыть');
  });
}
