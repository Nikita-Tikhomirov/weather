from __future__ import annotations

import argparse
import re
from pathlib import Path

from PIL import Image

from slice_sticker_grid import parse_hex_color, slice_grid_object_aware


PROJECT_ROOT = Path(__file__).resolve().parents[2]
STICKER_ROOT = PROJECT_ROOT / "assets" / "stickers"
GRID_NAME_PATTERN = re.compile(r"(.+)_grid_(\d{3})(?:_v\d+)?\.png$")
GRID_SIZE = 25


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Re-slice generated sticker grids without regenerating images.")
    parser.add_argument("--rows", type=int, default=5)
    parser.add_argument("--cols", type=int, default=5)
    parser.add_argument("--padding", type=int, default=42)
    parser.add_argument("--key", default="00ff00")
    parser.add_argument("--tolerance", type=int, default=48)
    parser.add_argument("--edge-contract", type=int, default=1)
    parser.add_argument("--min-component-area", type=int, default=8)
    parser.add_argument("--component-margin", type=int, default=10)
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def iter_grid_jobs():
    for source_name, output_name in [
        ("source_grids", "library"),
        ("source_grids_v2", "library_v2"),
    ]:
        source_root = STICKER_ROOT / source_name
        output_root = STICKER_ROOT / output_name
        for grid_path in sorted(source_root.rglob("*.png")):
            match = GRID_NAME_PATTERN.fullmatch(grid_path.name)
            if match is None:
                continue
            prefix = match.group(1)
            grid_number = int(match.group(2))
            relative_dir = grid_path.parent.relative_to(source_root)
            output_dir = output_root / relative_dir
            start_index = ((grid_number - 1) * GRID_SIZE) + 1
            yield grid_path, output_dir, prefix, start_index


def save_stickers(stickers, output_dir: Path, prefix: str, start_index: int, dry_run: bool) -> int:
    if dry_run:
        return len(stickers)
    output_dir.mkdir(parents=True, exist_ok=True)
    for offset, sticker in enumerate(stickers):
        sticker.save(output_dir / f"{prefix}_{start_index + offset:03d}.png", "PNG")
    return len(stickers)


def main() -> None:
    args = parse_args()
    key = parse_hex_color(args.key)
    total_grids = 0
    total_stickers = 0

    for grid_path, output_dir, prefix, start_index in iter_grid_jobs():
        total_grids += 1
        source = Image.open(grid_path).convert("RGBA")
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
        total_stickers += save_stickers(stickers, output_dir, prefix, start_index, args.dry_run)
        print(f"{grid_path.as_posix()} -> {output_dir.as_posix()} [{start_index:03d}-{start_index + len(stickers) - 1:03d}]")

    print(f"Re-sliced {total_stickers} stickers from {total_grids} grids")


if __name__ == "__main__":
    main()
