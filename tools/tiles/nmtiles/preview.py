"""Preview crops stitched from the baked mask tile PNGs, tinted with the default theme (so they show what ships)."""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

from nmtiles.style import PREVIEW_BG, PREVIEW_SETS

TILE = 512
VIEW = (1882, 1480)
# name, m/px, centre (game xy): downtown
PREVIEWS = (("close", 0.5), ("mid", 2.0), ("far", 8.0))
CENTRE = (-1800.0, 150.0)


def composite_sets(tiles: dict[str, dict[tuple[int, int], Path]], level: dict, centre: tuple[float, float],
                   size: tuple[int, int] = VIEW) -> Image.Image:
    """The size[0] x size[1] px window of one level around world `centre`; tiles[set][(ix, iy)] -> PNG path."""
    w, h = size
    mpp = level["mpp"]
    left = round((centre[0] - level["origin_x"]) / mpp - w / 2)
    top = round((level["origin_top"] - centre[1]) / mpp - h / 2)
    canvas = np.empty((h, w, 3), np.float32)
    canvas[:] = PREVIEW_BG
    for name, (rgb, scale) in PREVIEW_SETS.items():
        for (ix, iy), path in tiles.get(name, {}).items():
            x0, y0 = ix * TILE - left, iy * TILE - top
            cx0, cy0, cx1, cy1 = max(x0, 0), max(y0, 0), min(x0 + TILE, w), min(y0 + TILE, h)
            if cx0 >= cx1 or cy0 >= cy1:
                continue
            im = Image.open(path).convert("RGBA")
            if im.size != (TILE, TILE):     # half-resolution glow tiles are stretched to 512 in game
                im = im.resize((TILE, TILE), Image.BILINEAR)
            a = np.asarray(im)[cy0 - y0:cy1 - y0, cx0 - x0:cx1 - x0, 3]
            a = (a.astype(np.float32) / 255.0 * scale)[..., None]
            region = canvas[cy0:cy1, cx0:cx1]
            region[:] = region * (1 - a) + np.array(rgb, np.float32) * a
    return Image.fromarray(np.clip(canvas + 0.5, 0, 255).astype(np.uint8), "RGB")


def write_previews(level_info: list[dict], set_pngs: dict[str, dict[tuple[int, int, int], Path]], out_dir: Path,
                   centre: tuple[float, float] = CENTRE) -> list[Path]:
    """build/preview_minimap_{close,mid,far}.png from the level whose m/px is nearest 0.5 / 2 / 8."""
    paths = []
    for name, mpp in PREVIEWS:
        li = min(range(len(level_info)), key=lambda i: abs(level_info[i]["mpp"] - mpp))
        tiles = {s: {(ix, iy): p for (l, ix, iy), p in d.items() if l == li} for s, d in set_pngs.items()}
        paths.append(out_dir / f"preview_minimap_{name}.png")
        composite_sets(tiles, level_info[li], centre).save(paths[-1])
    return paths
