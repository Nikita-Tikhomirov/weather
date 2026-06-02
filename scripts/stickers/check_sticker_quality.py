from __future__ import annotations

import argparse
import json
import re
from collections import defaultdict
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
STICKER_ROOT = PROJECT_ROOT / "assets" / "stickers"
GRID_PROMPTS_PATH = STICKER_ROOT / "catalog" / "grid_prompts.jsonl"
MANIFEST_PATH = STICKER_ROOT / "manifest.json"
GRID_SIZE = 25
CELL_PATTERN = re.compile(
    r"cell\s+(\d{2}):\s*(.*?)(?=;\s*cell\s+\d{2}:|\. No readable text|$)"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate generated sticker content.")
    parser.add_argument("--skip-images", action="store_true", help="Only validate catalog prompts.")
    parser.add_argument(
        "--hash-threshold",
        type=int,
        default=3,
        help="Maximum perceptual hash distance treated as a duplicate inside one grid.",
    )
    return parser.parse_args()


def load_jsonl(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


def load_manifest() -> dict:
    return json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))


def validate_prompts() -> list[str]:
    errors = []
    seen_cells = {}
    for item in load_jsonl(GRID_PROMPTS_PATH):
        cells = [match.group(2).strip() for match in CELL_PATTERN.finditer(item["prompt"])]
        unique_cells = set(cells)
        if len(cells) != GRID_SIZE:
            errors.append(f"{item['grid_id']}: expected {GRID_SIZE} cell briefs, found {len(cells)}")
            continue
        if len(unique_cells) != GRID_SIZE:
            errors.append(f"{item['grid_id']}: cell briefs are not unique")
        for cell in cells:
            previous_grid_id = seen_cells.get(cell)
            if previous_grid_id:
                errors.append(
                    f"{item['grid_id']}: cell brief also exists in {previous_grid_id}: {cell}"
                )
            else:
                seen_cells[cell] = item["grid_id"]
    return errors


def validate_manifest_concepts() -> list[str]:
    manifest = load_manifest()
    seen_concepts = {}
    duplicates = []

    for sticker in manifest["stickers"]:
        concept = sticker["concept"]
        previous_id = seen_concepts.get(concept)
        if previous_id:
            duplicates.append((previous_id, sticker["id"], concept))
        else:
            seen_concepts[concept] = sticker["id"]

    if not duplicates:
        return []

    first_previous, first_current, first_concept = duplicates[0]
    return [
        "manifest: sticker concepts must be globally unique; "
        f"{len(duplicates)} duplicate concepts; first duplicate is "
        f"{first_previous} and {first_current}: {first_concept}"
    ]


def import_pillow():
    try:
        from PIL import Image
    except ImportError as exc:
        raise SystemExit("Pillow is required: python -m pip install Pillow") from exc
    return Image


def image_hash(path: Path) -> tuple[bool, ...]:
    Image = import_pillow()
    image = Image.open(path).convert("RGBA")
    alpha = image.getchannel("A")
    bbox = alpha.getbbox()
    if bbox:
        image = image.crop(bbox)

    background = Image.new("RGB", image.size, "white")
    background.paste(image.convert("RGB"), mask=image.getchannel("A"))
    resampling = getattr(Image, "Resampling", None)
    filter_mode = resampling.LANCZOS if resampling else Image.LANCZOS
    gray = background.convert("L").resize((16, 16), filter_mode)
    pixels = list(gray.getdata())
    mean = sum(pixels) / len(pixels)
    return tuple(pixel >= mean for pixel in pixels)


def hamming(left: tuple[bool, ...], right: tuple[bool, ...]) -> int:
    return sum(a != b for a, b in zip(left, right))


def validate_images(hash_threshold: int) -> list[str]:
    Image = import_pillow()
    manifest = load_manifest()
    errors = []
    ready_by_grid: dict[str, list[dict]] = defaultdict(list)

    for sticker in manifest["stickers"]:
        if sticker["status"] != "ready":
            continue
        path = PROJECT_ROOT / sticker["path"]
        if not path.exists():
            errors.append(f"{sticker['id']}: missing file {sticker['path']}")
            continue
        image = Image.open(path).convert("RGBA")
        corners = [
            image.getpixel((0, 0))[3],
            image.getpixel((511, 0))[3],
            image.getpixel((0, 511))[3],
            image.getpixel((511, 511))[3],
        ]
        if image.size != (512, 512):
            errors.append(f"{sticker['id']}: expected 512x512, found {image.size}")
        if any(corners):
            errors.append(f"{sticker['id']}: transparent corners expected")
        ready_by_grid[sticker["grid_id"]].append(sticker)

    for grid_id, stickers in ready_by_grid.items():
        if len(stickers) != GRID_SIZE:
            continue
        hashes = [(sticker, image_hash(PROJECT_ROOT / sticker["path"])) for sticker in stickers]
        for left_index, (left_sticker, left_hash) in enumerate(hashes):
            for right_sticker, right_hash in hashes[left_index + 1 :]:
                distance = hamming(left_hash, right_hash)
                if distance <= hash_threshold:
                    errors.append(
                        f"{grid_id}: possible duplicate {left_sticker['id']} and "
                        f"{right_sticker['id']} (hash distance {distance})"
                    )

    return errors


def main() -> None:
    args = parse_args()
    errors = validate_prompts()
    errors.extend(validate_manifest_concepts())
    if not args.skip_images:
        errors.extend(validate_images(args.hash_threshold))

    if errors:
        print("Sticker quality check failed:")
        for error in errors[:50]:
            print(f"- {error}")
        if len(errors) > 50:
            print(f"- ... {len(errors) - 50} more")
        raise SystemExit(1)

    print("Sticker quality check passed")


if __name__ == "__main__":
    main()
