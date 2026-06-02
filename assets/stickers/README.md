# Sticker Content Library

Библиотека стикеров хранится отдельно от кода приложения. Сейчас это контентный
план, промпты для генерации сеток, исходные сетки и будущие нарезанные файлы.

## Объем

- Целевой объем: 2500 стикеров.
- Формат генерации: 100 сеток по 25 стикеров.
- Текущий срез после остановки генерации: 1100 готовых PNG. Из них 500 старых
  файлов в `library` и 600 новых файлов в `library_v2`.
- Основные стили:
  - `plush_3d` - мягкий 3D toy/plush стиль.
  - `meme_wobbly` - смешной мемный кривоватый стиль.
- Большие линейки:
  - крысы: 1000 стикеров;
  - ежи: 750 стикеров;
  - дуэты крыс и ежей: 250 стикеров;
  - универсальные реакции и бытовые сцены: 500 стикеров.

## Структура

```text
assets/stickers/
  catalog/
    pack_plan.json
    grid_prompts.jsonl
  source_grids/
    ...
  library/
    ...
  source_grids_v2/
    ...
  library_v2/
    ...
  manifest.json
```

`source_grids` и `library` - старые сохраненные сетки и нарезанные файлы.
`source_grids_v2` и `library_v2` - новая библиотека с промптами
`prompt_version=2`, где внутри каждой сетки требуются 25 уникальных идей, а
каждый стикер получает уникальный визуальный акцент на уровне всего нового
набора.
`manifest.json` - список запланированных файлов, категорий и тегов.

Начиная с `prompt_version=2`, исходные сетки сохраняются с суффиксом `_v2`.
Старые сетки без суффикса не удаляются и остаются в `source_grids`/`library` как
архив, но в приложение импортируется только `library_v2`. Новый `manifest.json`
считает готовыми только файлы из `source_grids_v2` и `library_v2`.

Для загрузки в приложение через S3 используется backend-команда:

```bash
php artisan chat:stickers-import assets/stickers
```

Она импортирует только `library_v2`, заполняет `chat_stickers.asset_url`
ссылками через `CHAT_MEDIA_DISK` и деактивирует старые активные стикеры, которых
нет в новом v2-наборе. `pack_key` формируется как `group_style_category`,
например `rats_plush_3d_emotions` или
`hedgehogs_meme_wobbly_grumpy_reactions`: мобильный интерфейс по этому ключу
раскладывает стикеры по группам, стилям и темам.

## Генерация каталога

```powershell
python .\scripts\stickers\build_sticker_catalog.py
```

Команда пересобирает `pack_plan.json`, `grid_prompts.jsonl`,
`manifest.json` и создает папки для будущих файлов.

## Нарезка сетки

Пример:

```powershell
python .\scripts\stickers\slice_sticker_grid.py `
  --grid .\assets\stickers\source_grids_v2\rats\plush_3d\emotions\rats_plush_3d_emotions_grid_001_v2.png `
  --out .\assets\stickers\library_v2\rats\plush_3d\emotions `
  --prefix rats_plush_3d_emotions `
  --start-index 1 `
  --format png
```

По умолчанию утилита ожидает сетку 5x5, убирает chroma-key фон `#00ff00`,
триммит пустые края и кладет каждый стикер на квадратный холст 512x512.
Для второй сетки в той же категории используйте `--start-index 26`, для третьей -
`--start-index 51` и так далее.

## Проверка качества

```powershell
python .\scripts\stickers\check_sticker_quality.py
```

Проверка требует 25 уникальных брифов в каждой сетке, PNG 512x512 с прозрачными
углами, глобально уникальные брифы в `manifest.json` и отсутствие почти
одинаковых стикеров внутри одной готовой сетки.
