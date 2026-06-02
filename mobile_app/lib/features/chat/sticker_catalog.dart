import 'package:flutter/foundation.dart';

import '../../models/chat_models.dart';

@immutable
class StickerPackMeta {
  const StickerPackMeta({
    required this.packKey,
    required this.group,
    required this.style,
    required this.category,
    required this.title,
  });

  final String packKey;
  final String group;
  final String style;
  final String category;
  final String title;
}

@immutable
class StickerCatalogEntry {
  const StickerCatalogEntry({
    required this.pack,
    required this.item,
    required this.meta,
    required this.assetUrl,
  });

  final StickerPack pack;
  final StickerItem item;
  final StickerPackMeta meta;
  final String assetUrl;

  String get searchableText {
    return [
      item.stickerId,
      item.title,
      meta.packKey,
      meta.title,
      stickerGroupLabel(meta.group),
      stickerStyleLabel(meta.style),
      stickerCategoryLabel(meta.category),
    ].join(' ').toLowerCase();
  }
}

const List<String> stickerGroupOrder = [
  'rats',
  'hedgehogs',
  'duos',
  'mixed',
  'custom',
];

const List<String> stickerStyleOrder = [
  'plush_3d',
  'meme_wobbly',
  'custom',
];

const Map<String, String> _groupLabels = {
  'rats': 'Крысы',
  'hedgehogs': 'Ежи',
  'duos': 'Дуэты',
  'mixed': 'Разные',
  'custom': 'Свои',
};

const Map<String, String> _styleLabels = {
  'plush_3d': '3D',
  'meme_wobbly': 'Мемные',
  'custom': 'Свои',
};

const Map<String, String> _categoryLabels = {
  'emotions': 'Эмоции',
  'daily': 'Быт',
  'food_sleep': 'Еда и сон',
  'work_study': 'Работа и учеба',
  'weather_seasons': 'Погода',
  'cozy_love': 'Уют и любовь',
  'adventures': 'Приключения',
  'reactions': 'Реакции',
  'chaos': 'Хаос',
  'daily_fail': 'Бытовые фейлы',
  'office_study_fail': 'Рабочие фейлы',
  'food_sleep_absurd': 'Еда и абсурд',
  'weird_original': 'Странные',
  'cozy': 'Уют',
  'tiny_heroics': 'Маленькие герои',
  'grumpy_reactions': 'Ворчливые',
  'everyday_fails': 'Фейлы',
  'social_moods': 'Общение',
  'friendship': 'Дружба',
  'family': 'Семья',
  'helping': 'Помощь',
  'tiny_adventures': 'Мини-приключения',
  'arguments': 'Споры',
  'chaos_team': 'Командный хаос',
  'roommate_life': 'Соседи',
  'mutual_panic': 'Общая паника',
  'weird_duo': 'Странные дуэты',
  'app_core_reactions': 'Базовые',
  'daily_moods': 'Настроения',
  'celebrations': 'Праздники',
  'love_family': 'Любовь и семья',
  'excuses': 'Отмазки',
  'panic': 'Паника',
  'internet_brain': 'Интернет',
  'household_chaos': 'Домашний хаос',
  'monday_energy': 'Понедельник',
  'suspicious': 'Подозрительные',
  'surreal': 'Сюр',
};

String stickerGroupLabel(String group) {
  return _groupLabels[group] ?? _humanizeKey(group);
}

String stickerStyleLabel(String style) {
  return _styleLabels[style] ?? _humanizeKey(style);
}

String stickerCategoryLabel(String category) {
  return _categoryLabels[category] ?? _humanizeKey(category);
}

List<StickerCatalogEntry> buildStickerCatalogEntries(
  List<StickerPack> packs, {
  required String Function(String rawAssetUrl) resolveAssetUrl,
}) {
  final entries = <StickerCatalogEntry>[];
  for (final pack in packs) {
    final meta = parseStickerPackMeta(pack);
    for (final item in pack.items) {
      if (_isLegacySticker(pack, item)) {
        continue;
      }
      final assetUrl = resolveAssetUrl(item.assetUrl).trim();
      if (assetUrl.isEmpty || assetUrl.startsWith('emoji://')) {
        continue;
      }
      entries.add(
        StickerCatalogEntry(
          pack: pack,
          item: item,
          meta: meta,
          assetUrl: assetUrl,
        ),
      );
    }
  }
  entries.sort(compareStickerCatalogEntries);
  return entries;
}

StickerPackMeta parseStickerPackMeta(StickerPack pack) {
  final packKey = pack.packKey.trim();
  for (final group in stickerGroupOrder.where((item) => item != 'custom')) {
    for (final style in stickerStyleOrder.where((item) => item != 'custom')) {
      final prefix = '${group}_$style';
      if (packKey == prefix || packKey.startsWith('${prefix}_')) {
        final category =
            packKey == prefix ? 'all' : packKey.substring(prefix.length + 1);
        return StickerPackMeta(
          packKey: packKey,
          group: group,
          style: style,
          category: category,
          title: pack.title.trim().isEmpty
              ? '${stickerGroupLabel(group)} · ${stickerCategoryLabel(category)}'
              : pack.title.trim(),
        );
      }
    }
  }

  return StickerPackMeta(
    packKey: packKey,
    group: 'custom',
    style: 'custom',
    category: packKey.isEmpty ? 'custom' : packKey,
    title:
        pack.title.trim().isEmpty ? _humanizeKey(packKey) : pack.title.trim(),
  );
}

int compareStickerCatalogEntries(
  StickerCatalogEntry left,
  StickerCatalogEntry right,
) {
  final groupCompare = _rankCompare(
    stickerGroupOrder,
    left.meta.group,
    right.meta.group,
  );
  if (groupCompare != 0) return groupCompare;

  final styleCompare = _rankCompare(
    stickerStyleOrder,
    left.meta.style,
    right.meta.style,
  );
  if (styleCompare != 0) return styleCompare;

  final categoryCompare = left.meta.category.compareTo(right.meta.category);
  if (categoryCompare != 0) return categoryCompare;

  final sortCompare = left.item.sortOrder.compareTo(right.item.sortOrder);
  if (sortCompare != 0) return sortCompare;

  return left.item.stickerId.compareTo(right.item.stickerId);
}

bool _isLegacySticker(StickerPack pack, StickerItem item) {
  final packKey = pack.packKey.trim();
  final stickerId = item.stickerId.trim();
  final assetUrl = item.assetUrl.trim();
  return packKey == 'emoji' ||
      packKey == 'default' ||
      stickerId.startsWith('builtin-') ||
      assetUrl.startsWith('emoji://') ||
      assetUrl.startsWith('/stickers/default/');
}

int _rankCompare(List<String> order, String left, String right) {
  final leftIndex = order.indexOf(left);
  final rightIndex = order.indexOf(right);
  final normalizedLeft = leftIndex < 0 ? order.length : leftIndex;
  final normalizedRight = rightIndex < 0 ? order.length : rightIndex;
  if (normalizedLeft != normalizedRight) {
    return normalizedLeft.compareTo(normalizedRight);
  }
  return left.compareTo(right);
}

String _humanizeKey(String key) {
  final value = key.trim().replaceAll('_', ' ');
  if (value.isEmpty) {
    return 'Стикеры';
  }
  return value[0].toUpperCase() + value.substring(1);
}
