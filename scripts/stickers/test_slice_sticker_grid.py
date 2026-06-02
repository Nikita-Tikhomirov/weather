from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from scripts.stickers.slice_sticker_grid import slice_grid_object_aware


def test_object_aware_slice_keeps_owner_component_and_drops_neighbor_fragment():
    source = Image.new("RGBA", (200, 100), (0, 255, 0, 255))
    draw = ImageDraw.Draw(source)

    # Red belongs to the left cell and crosses into the right cell.
    draw.rectangle((30, 18, 120, 45), fill=(255, 0, 0, 255))
    # Blue belongs to the right cell and crosses back into the left cell.
    draw.rectangle((82, 58, 170, 85), fill=(0, 0, 255, 255))

    stickers = slice_grid_object_aware(
        source,
        rows=1,
        cols=2,
        key=(0, 255, 0),
        tolerance=8,
        edge_contract=0,
        padding=20,
        min_component_area=10,
    )

    assert len(stickers) == 2
    left_colors = stickers[0].convert("RGBA").getdata()
    right_colors = stickers[1].convert("RGBA").getdata()

    assert any(r > 200 and g < 40 and b < 40 and a > 0 for r, g, b, a in left_colors)
    assert not any(b > 200 and r < 40 and g < 40 and a > 0 for r, g, b, a in left_colors)
    assert any(b > 200 and r < 40 and g < 40 and a > 0 for r, g, b, a in right_colors)
    assert not any(r > 200 and g < 40 and b < 40 and a > 0 for r, g, b, a in right_colors)
