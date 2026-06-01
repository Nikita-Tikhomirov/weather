# Sticker Content Library

Библиотека стикеров хранится отдельно от кода приложения. Сейчас это контентный
план, промпты для генерации сеток, исходные сетки и будущие нарезанные файлы.

## Объем

- Целевой объем: 2500 стикеров.
- Формат генерации: 100 сеток по 25 стикеров.
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
  manifest.json
```

`source_grids` - сюда кладутся сгенерированные сетки 5x5.  
`library` - сюда попадают нарезанные отдельные PNG/WebP.  
`manifest.json` - список запланированных файлов, категорий и тегов.

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
  --grid .\assets\stickers\source_grids\rats\plush_3d\emotions\rat_plush_3d_emotions_grid_001.png `
  --out .\assets\stickers\library\rats\plush_3d\emotions `
  --prefix rat_plush_3d_emotions `
  --format png
```

По умолчанию утилита ожидает сетку 5x5, убирает chroma-key фон `#00ff00`,
триммит пустые края и кладет каждый стикер на квадратный холст 512x512.

