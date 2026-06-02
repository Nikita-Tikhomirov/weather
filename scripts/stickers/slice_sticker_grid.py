from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any

import numpy as np


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Slice a sticker grid into individual stickers.")
    parser.add_argument("--grid", required=True, type=Path, help="Source 5x5 grid image.")
    parser.add_argument("--out", required=True, type=Path, help="Output directory.")
    parser.add_argument("--prefix", required=True, help="Output file prefix.")
    parser.add_argument("--rows", type=int, default=5)
    parser.add_argument("--cols", type=int, default=5)
    parser.add_argument("--start-index", type=int, default=1, help="First output sticker index.")
    parser.add_argument("--padding", type=int, default=42, help="Padding on final 512x512 canvas.")
    parser.add_argument("--format", choices=["png", "webp"], default="png")
    parser.add_argument("--key", default="00ff00", help="Chroma key color as RRGGBB.")
    parser.add_argument("--tolerance", type=int, default=48)
    parser.add_argument("--edge-contract", type=int, default=1, help="Shrink alpha edge to remove key fringe.")
    parser.add_argument(
        "--mode",
        choices=["object", "grid"],
        default="object",
        help="Use object-aware connected-component slicing or legacy equal grid slicing.",
    )
    parser.add_argument("--min-component-area", type=int, default=8)
    parser.add_argument("--component-margin", type=int, default=10)
    return parser.parse_args()


def import_pillow():
    try:
        from PIL import Image
    except ImportError as exc:
        raise SystemExit("Pillow is required: python -m pip install Pillow") from exc
    return Image


def import_cv2():
    try:
        import cv2
    except ImportError as exc:
        raise SystemExit("OpenCV is required for object-aware slicing: python -m pip install opencv-python") from exc
    return cv2


def parse_hex_color(value: str) -> tuple[int, int, int]:
    clean = value.strip().lstrip("#")
    if len(clean) != 6:
        raise SystemExit("--key must be a 6-digit hex color, for example 00ff00")
    return tuple(int(clean[index : index + 2], 16) for index in (0, 2, 4))


def remove_chroma_key(image, key: tuple[int, int, int], tolerance: int):
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    width, height = rgba.size
    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            distance = abs(r - key[0]) + abs(g - key[1]) + abs(b - key[2])
            key_dominance = g - max(r, b)
            green_screen_like = (
                (g >= 120 and r <= 130 and b <= 130 and key_dominance >= 55)
                or (g >= 165 and key_dominance >= 35)
            )
            if distance <= tolerance or green_screen_like:
                pixels[x, y] = (0, 0, 0, 0)
            elif a:
                pixels[x, y] = (r, g, b, 255)
    return rgba


def foreground_mask(image, key: tuple[int, int, int], tolerance: int) -> np.ndarray:
    rgba = np.asarray(image.convert("RGBA"), dtype=np.int16)
    r = rgba[:, :, 0]
    g = rgba[:, :, 1]
    b = rgba[:, :, 2]
    a = rgba[:, :, 3]
    distance = np.abs(r - key[0]) + np.abs(g - key[1]) + np.abs(b - key[2])
    key_dominance = g - np.maximum(r, b)
    green_screen_like = (
        ((g >= 120) & (r <= 130) & (b <= 130) & (key_dominance >= 55))
        | ((g >= 165) & (key_dominance >= 35))
    )
    return (a > 0) & ~(distance <= tolerance) & ~green_screen_like


def contract_alpha(image, pixels: int):
    if pixels <= 0:
        return image
    try:
        from PIL import ImageFilter
    except ImportError as exc:
        raise SystemExit("Pillow is required: python -m pip install Pillow") from exc

    alpha = image.getchannel("A")
    for _ in range(pixels):
        alpha = alpha.filter(ImageFilter.MinFilter(3))
    image.putalpha(alpha)
    return image


def fit_to_canvas(image, size: int, padding: int):
    bbox = image.getbbox()
    if bbox:
        image = image.crop(bbox)

    max_side = max(image.size)
    target = max(1, size - (padding * 2))
    scale = target / max_side
    new_size = (max(1, round(image.width * scale)), max(1, round(image.height * scale)))
    resampling = getattr(import_pillow(), "Resampling", None)
    filter_mode = resampling.LANCZOS if resampling else import_pillow().LANCZOS
    image = image.resize(new_size, filter_mode)

    canvas = import_pillow().new("RGBA", (size, size), (0, 0, 0, 0))
    offset = ((size - image.width) // 2, (size - image.height) // 2)
    canvas.alpha_composite(image, offset)
    return canvas


def _cell_index_for_centroid(
    centroid: tuple[float, float],
    width: int,
    height: int,
    rows: int,
    cols: int,
) -> int:
    x, y = centroid
    col = min(cols - 1, max(0, int(x * cols / width)))
    row = min(rows - 1, max(0, int(y * rows / height)))
    return (row * cols) + col


def _component_labels_by_cell(
    mask: np.ndarray,
    rows: int,
    cols: int,
    min_component_area: int,
) -> tuple[np.ndarray, list[list[int]]]:
    cv2 = import_cv2()
    count, labels, stats, centroids = cv2.connectedComponentsWithStats(
        mask.astype("uint8"),
        8,
    )
    labels_by_cell: list[list[int]] = [[] for _ in range(rows * cols)]
    height, width = mask.shape
    for label in range(1, count):
        area = int(stats[label, cv2.CC_STAT_AREA])
        if area < min_component_area:
            continue
        cell_index = _cell_index_for_centroid(
            (float(centroids[label][0]), float(centroids[label][1])),
            width,
            height,
            rows,
            cols,
        )
        labels_by_cell[cell_index].append(label)
    return labels, labels_by_cell


def _proportional_cell_box(width: int, height: int, rows: int, cols: int, row: int, col: int):
    left = round(col * width / cols)
    upper = round(row * height / rows)
    right = round((col + 1) * width / cols)
    lower = round((row + 1) * height / rows)
    return left, upper, right, lower


def _transparent_crop_from_mask(
    source_rgba: np.ndarray,
    mask: np.ndarray,
    margin: int,
):
    Image = import_pillow()
    ys, xs = np.nonzero(mask)
    if len(xs) == 0 or len(ys) == 0:
        return None
    left = max(0, int(xs.min()) - margin)
    upper = max(0, int(ys.min()) - margin)
    right = min(mask.shape[1], int(xs.max()) + margin + 1)
    lower = min(mask.shape[0], int(ys.max()) + margin + 1)
    cropped_mask = mask[upper:lower, left:right]
    cropped = source_rgba[upper:lower, left:right].copy()
    cropped[~cropped_mask] = (0, 0, 0, 0)
    cropped[cropped_mask, 3] = 255
    return Image.fromarray(cropped, "RGBA")


def slice_grid_object_aware(
    source: Any,
    *,
    rows: int,
    cols: int,
    key: tuple[int, int, int],
    tolerance: int,
    edge_contract: int,
    padding: int,
    min_component_area: int = 8,
    component_margin: int = 10,
) -> list[Any]:
    source = source.convert("RGBA")
    mask = foreground_mask(source, key, tolerance)
    labels, labels_by_cell = _component_labels_by_cell(mask, rows, cols, min_component_area)
    source_rgba = np.asarray(source, dtype=np.uint8)
    stickers = []

    for row in range(rows):
        for col in range(cols):
            cell_index = (row * cols) + col
            label_ids = labels_by_cell[cell_index]
            if label_ids:
                cell_mask = np.isin(labels, label_ids)
                sticker = _transparent_crop_from_mask(source_rgba, cell_mask, component_margin)
            else:
                left, upper, right, lower = _proportional_cell_box(
                    source.width,
                    source.height,
                    rows,
                    cols,
                    row,
                    col,
                )
                sticker = remove_chroma_key(source.crop((left, upper, right, lower)), key, tolerance)

            if sticker is None:
                sticker = import_pillow().new("RGBA", (1, 1), (0, 0, 0, 0))
            sticker = contract_alpha(sticker, edge_contract)
            stickers.append(fit_to_canvas(sticker, 512, padding))

    return stickers


def slice_grid_equal(
    source: Any,
    *,
    rows: int,
    cols: int,
    key: tuple[int, int, int],
    tolerance: int,
    edge_contract: int,
    padding: int,
) -> list[Any]:
    stickers = []
    for row in range(rows):
        for col in range(cols):
            left, upper, right, lower = _proportional_cell_box(
                source.width,
                source.height,
                rows,
                cols,
                row,
                col,
            )
            cell = source.crop((left, upper, right, lower))
            sticker = remove_chroma_key(cell, key, tolerance)
            sticker = contract_alpha(sticker, edge_contract)
            stickers.append(fit_to_canvas(sticker, 512, padding))
    return stickers


def main() -> None:
    args = parse_args()
    Image = import_pillow()
    key = parse_hex_color(args.key)
    args.out.mkdir(parents=True, exist_ok=True)

    source = Image.open(args.grid).convert("RGBA")
    if args.start_index < 1:
        raise SystemExit("--start-index must be 1 or greater")

    index = args.start_index
    if args.mode == "object":
        stickers = slice_grid_object_aware(
            source,
            rows=args.rows,
            cols=args.cols,
            key=key,
            tolerance=args.tolerance,
            edge_contract=args.edge_contract,
            padding=args.padding,
            min_component_area=args.min_component_area,
            component_margin=args.component_margin,
        )
    else:
        stickers = slice_grid_equal(
            source,
            rows=args.rows,
            cols=args.cols,
            key=key,
            tolerance=args.tolerance,
            edge_contract=args.edge_contract,
            padding=args.padding,
        )

    for sticker in stickers:
        output = args.out / f"{args.prefix}_{index:03d}.{args.format}"
        if args.format == "webp":
            sticker.save(output, "WEBP", lossless=True, quality=100)
        else:
            sticker.save(output, "PNG")
        index += 1

    print(f"Saved {len(stickers)} stickers to {args.out}")


if __name__ == "__main__":
    main()
