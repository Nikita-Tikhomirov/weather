import 'package:family_todo_mobile/features/home/home_group_chat_labels.dart';
import 'package:family_todo_mobile/l10n/app_localizations_ru.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses English fallback group chat labels without localizations', () {
    const labels = HomeGroupChatLabels(null);

    expect(labels.defaultGroupName, 'Group');
    expect(labels.renameAction, 'Rename');
    expect(labels.delete, 'Delete');
    expect(labels.addMember, 'Add member');
    expect(labels.avatarUpdated, 'Avatar updated');
    expect(labels.groupNameTitle, 'Group name');
    expect(labels.groupNameHint, 'For example: Work');
    expect(labels.cancel, 'Cancel');
    expect(labels.save, 'Save');
    expect(labels.deleteGroupTitle, 'Delete group?');
    expect(
      labels.deleteGroupMessage('Family'),
      'Group "Family" will disappear for all participants with its chat history.',
    );
    expect(labels.noAvailableContacts, 'No available contacts');
    expect(labels.selectMember, 'Select member');
    expect(labels.memberAdded('Alice'), 'Alice added');
    expect(labels.genericError('network'), 'Error: network');
    expect(
      labels.avatarUploadFailed('network'),
      'Could not upload avatar: network',
    );
    expect(labels.groupDeletedLocally, 'Group removed from local list');
  });

  test('uses Russian generated group chat labels when localizations exist', () {
    final labels = HomeGroupChatLabels(AppLocalizationsRu());

    expect(labels.defaultGroupName, 'Группа');
    expect(labels.renameAction, 'Назвать');
    expect(labels.delete, 'Удалить');
    expect(labels.addMember, 'Добавить участника');
    expect(labels.avatarUpdated, 'Аватар обновлён');
    expect(labels.groupNameTitle, 'Название группы');
    expect(labels.groupNameHint, 'Например: Работа');
    expect(labels.cancel, 'Отмена');
    expect(labels.save, 'Сохранить');
    expect(labels.deleteGroupTitle, 'Удалить группу?');
    expect(
      labels.deleteGroupMessage('Семья'),
      'Группа "Семья" исчезнет у всех участников вместе с перепиской.',
    );
    expect(labels.noAvailableContacts, 'Нет доступных контактов');
    expect(labels.selectMember, 'Выбрать участника');
    expect(labels.memberAdded('Алиса'), 'Алиса добавлен');
    expect(labels.genericError('сеть'), 'Ошибка: сеть');
    expect(labels.avatarUploadFailed('сеть'), 'Ошибка загрузки аватара: сеть');
    expect(labels.groupDeletedLocally, 'Группа удалена из локального списка');
  });
}
