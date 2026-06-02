from __future__ import annotations

import argparse
from pathlib import Path


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
    return parser.parse_args()


def import_pillow():
    try:
        from PIL import Image
    except ImportError as exc:
        raise SystemExit("Pillow is required: python -m pip install Pillow") from exc
    return Image


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


def main() -> None:
    args = parse_args()
    Image = import_pillow()
    key = parse_hex_color(args.key)
    args.out.mkdir(parents=True, exist_ok=True)

    source = Image.open(args.grid).convert("RGBA")
    cell_width = source.width // args.cols
    cell_height = source.height // args.rows
    if args.start_index < 1:
        raise SystemExit("--start-index must be 1 or greater")

    index = args.start_index
    saved_count = 0

    for row in range(args.rows):
        for col in range(args.cols):
            left = col * cell_width
            upper = row * cell_height
            right = source.width if col == args.cols - 1 else left + cell_width
            lower = source.height if row == args.rows - 1 else upper + cell_height
            cell = source.crop((left, upper, right, lower))
            sticker = remove_chroma_key(cell, key, args.tolerance)
            sticker = contract_alpha(sticker, args.edge_contract)
            sticker = fit_to_canvas(sticker, 512, args.padding)
            output = args.out / f"{args.prefix}_{index:03d}.{args.format}"
            if args.format == "webp":
                sticker.save(output, "WEBP", lossless=True, quality=100)
            else:
                sticker.save(output, "PNG")
            index += 1
            saved_count += 1

    print(f"Saved {saved_count} stickers to {args.out}")


if __name__ == "__main__":
    main()
