"""Preview composites of baked tile PNGs over the UI's dark backdrop (for eyeballing builds)."""
from __future__ import annotations

from pathlib import Path

from PIL import Image

BACKDROP = (8, 10, 18, 255)
TILE = 512


def composite(tiles: dict[tuple[int, int], Path], x0: int, y0: int, nx: int, ny: int) -> Image.Image:
    """Tiles (ix, iy) -> path, laid out over nx x ny cells starting at (x0, y0); missing cells stay backdrop."""
    img = Image.new("RGBA", (nx * TILE, ny * TILE), BACKDROP)
    for (ix, iy), path in tiles.items():
        if x0 <= ix < x0 + nx and y0 <= iy < y0 + ny:
            img.alpha_composite(Image.open(path).convert("RGBA"), ((ix - x0) * TILE, (iy - y0) * TILE))
    return img


def write_previews(level_info: list[dict], tile_pngs: list[tuple[int, int, int, Path]], out_dir: Path,
                   world: tuple[float, float] = (-1800.0, 150.0)) -> list[Path]:
    """preview_city.png: the four L0 tiles meeting nearest `world`; preview_L3.png: every tile of the last level."""
    by_level: dict[int, dict[tuple[int, int], Path]] = {}
    for li, ix, iy, p in tile_pngs:
        by_level.setdefault(li, {})[(ix, iy)] = p
    paths = []
    l0 = level_info[0]
    tw = TILE * l0["mpp"]
    cx = round((world[0] - l0["origin_x"]) / tw) - 1
    cy = round((l0["origin_top"] - world[1]) / tw) - 1
    paths.append(out_dir / "preview_city.png")
    composite(by_level[0], cx, cy, 2, 2).save(paths[-1])
    last = len(level_info) - 1
    li = level_info[last]
    paths.append(out_dir / "preview_L3.png")
    composite(by_level[last], 0, 0, li["nx"], li["ny"]).save(paths[-1])
    return paths
