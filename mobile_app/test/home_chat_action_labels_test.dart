import 'package:family_todo_mobile/features/home/home_chat_action_labels.dart';
import 'package:family_todo_mobile/l10n/app_localizations_ru.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses English fallback chat action labels without localizations', () {
    const labels = HomeChatActionLabels(null);

    expect(labels.noForwardTargets, 'No contacts to share with');
    expect(labels.shareWithTitle, 'Share with...');
    expect(labels.cancel, 'Cancel');
    expect(labels.delete, 'Delete');
    expect(labels.edit, 'Edit');
    expect(labels.reply, 'Reply');
    expect(labels.share, 'Share');
    expect(labels.removeReaction, 'Remove reaction');
    expect(labels.forwardedSticker('Alice'), '↪ Alice: Sticker');
    expect(labels.forwardedPhoto('Alice'), '↪ Alice: Photo');
    expect(labels.forwardedTo('Bob'), 'Forwarded to Bob');
    expect(labels.forwardFailed('network'), 'Could not forward: network');
    expect(labels.deleteMessageTitle, 'Delete message?');
    expect(
      labels.deleteMessageBody,
      'The message will be deleted for all participants.',
    );
    expect(labels.deleteFailed('network'), 'Could not delete: network');
    expect(
      labels.reactionFailed('network'),
      'Could not update reaction: network',
    );
    expect(
      labels.stickerSendFailed('network'),
      'Could not send sticker: network',
    );
  });

  test('uses Russian generated chat action labels when localizations exist',
      () {
    final labels = HomeChatActionLabels(AppLocalizationsRu());

    expect(labels.noForwardTargets, 'Нет контактов для пересылки');
    expect(labels.shareWithTitle, 'Поделиться с...');
    expect(labels.cancel, 'Отмена');
    expect(labels.delete, 'Удалить');
    expect(labels.edit, 'Редактировать');
    expect(labels.reply, 'Ответить');
    expect(labels.share, 'Поделиться');
    expect(labels.removeReaction, 'Убрать реакцию');
    expect(labels.forwardedSticker('Алиса'), '↪ Алиса: Стикер');
    expect(labels.forwardedPhoto('Алиса'), '↪ Алиса: Фото');
    expect(labels.forwardedTo('Боб'), 'Переслано → Боб');
    expect(labels.forwardFailed('сеть'), 'Ошибка пересылки: сеть');
    expect(labels.deleteMessageTitle, 'Удалить сообщение?');
    expect(
      labels.deleteMessageBody,
      'Сообщение будет удалено у всех участников.',
    );
    expect(labels.deleteFailed('сеть'), 'Ошибка удаления: сеть');
    expect(labels.reactionFailed('сеть'), 'Ошибка реакции: сеть');
    expect(labels.stickerSendFailed('сеть'), 'Ошибка отправки стикера: сеть');
  });
}
