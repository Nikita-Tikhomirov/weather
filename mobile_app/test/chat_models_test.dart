import 'package:family_todo_mobile/models/chat_models.dart';
import 'package:family_todo_mobile/features/chat/sticker_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat attachment tolerates legacy list image metadata', () {
    final attachment = ChatAttachment.fromJson(const {
      'kind': 'image',
      'asset_url': '/chat_uploads/photo.jpg',
      'image_meta': [],
      'sort_order': 0,
    });

    expect(attachment.kind, 'image');
    expect(attachment.assetUrl, '/chat_uploads/photo.jpg');
    expect(attachment.imageMeta, isEmpty);
    expect(attachment.sortOrder, 0);
  });

  test('sticker catalog filters legacy stickers and parses generated packs',
      () {
    const packs = [
      StickerPack(
        packKey: 'emoji',
        title: 'Emoji',
        items: [
          StickerItem(
            stickerId: 'builtin-emoji-smile',
            title: ':)',
            assetUrl: 'emoji://grinning-face',
            sortOrder: 1,
          ),
        ],
      ),
      StickerPack(
        packKey: 'rats_plush_3d_emotions',
        title: '',
        items: [
          StickerItem(
            stickerId: 'rats_plush_3d_emotions_002',
            title: 'sleepy blink',
            assetUrl: 'https://s3.example.test/stickers/002.png',
            sortOrder: 2,
          ),
          StickerItem(
            stickerId: 'rats_plush_3d_emotions_001',
            title: 'happy nod',
            assetUrl: 'https://s3.example.test/stickers/001.png',
            sortOrder: 1,
          ),
        ],
      ),
    ];

    final entries = buildStickerCatalogEntries(
      packs,
      resolveAssetUrl: (value) => value,
    );

    expect(entries, hasLength(2));
    expect(entries.first.item.stickerId, 'rats_plush_3d_emotions_001');
    expect(entries.first.meta.group, 'rats');
    expect(entries.first.meta.style, 'plush_3d');
    expect(entries.first.meta.category, 'emotions');
    expect(entries.first.meta.title, 'Rats · Emotions');
  });

  test('sticker catalog exposes English labels', () {
    expect(stickerGroupLabel('rats'), 'Rats');
    expect(stickerStyleLabel('meme_wobbly'), 'Meme');
    expect(stickerCategoryLabel('food_sleep'), 'Food and sleep');
    expect(stickerCategoryLabel('weather_seasons'), 'Weather');
    expect(stickerCategoryLabel('unknown_topic'), 'Unknown topic');
    expect(stickerGroupLabel(''), 'Stickers');
  });
}
