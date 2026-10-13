"""Colourless mask tiles (white RGB, alpha = coverage) from the game's minimap geometry plus the 3D-map base/metro.

One tile set per class; the runtime tints them with SetTintColor from NMTheme:
  base   land/water/cliff of the 3D map (roads and buildings off); only for levels with m/px >= BASE_MIN_MPP
  road   minimap road triangles
  glow   minimap strokes, Gaussian blurred (GLOW_RADIUS px at every level)
  stroke minimap strokes
  metro  3D-map metro (dashed)
Every tile is rendered independently at SS x and downsampled (LANCZOS), with a margin that is cropped away afterwards,
so neighbouring tiles agree along their shared edge and no whole-level image ever exists.
"""
from __future__ import annotations

import math
import multiprocessing as mp
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from nmtiles.glb import Mesh
from nmtiles.render import LevelGrid, render_level, tile_grid
from nmtiles.style import BASE_STYLES, STYLE
from nmtiles.world import Transform

SETS = ("base", "road", "glow", "stroke", "metro")      # draw order, back to front
SS = 2
DEFAULT_JOBS = 4
BASE_MIN_MPP = 2.0
GLOW_RADIUS = 3.0                                        # px at every level
GLOW_GAIN = 1.0
EDGE_MARGIN = 2                                          # px: lets the LANCZOS kernel see the neighbouring tile
GLOW_MARGIN = math.ceil(3 * GLOW_RADIUS) + 3             # >= 3 sigma
_METRO_STYLE = {**STYLE, "metro": {**STYLE["metro"], "fill": (255, 255, 255, 255)}}


class TriIndex:
    """Uniform spatial grid over triangles (binned by bbox) so a tile only touches nearby triangles."""

    def __init__(self, tris: np.ndarray, cell: float):
        self.tris, self.cell = tris, float(cell)
        self.n = len(tris)
        if not self.n:
            return
        lo, hi = tris.min(axis=1), tris.max(axis=1)
        self.origin = lo.min(axis=0).astype(np.float64)
        c0 = np.floor((lo - self.origin) / cell).astype(np.int64)
        c1 = np.floor((hi - self.origin) / cell).astype(np.int64)
        self.nx, self.ny = int(c1[:, 0].max()) + 1, int(c1[:, 1].max()) + 1
        sx, sy = c1[:, 0] - c0[:, 0] + 1, c1[:, 1] - c0[:, 1] + 1
        counts = sx * sy
        ids = np.repeat(np.arange(self.n, dtype=np.int32), counts)
        within = np.arange(len(ids), dtype=np.int64) - np.repeat(np.cumsum(counts) - counts, counts)
        cx = np.repeat(c0[:, 0], counts) + within % np.repeat(sx, counts)
        cy = np.repeat(c0[:, 1], counts) + within // np.repeat(sx, counts)
        keys = cy * self.nx + cx
        order = np.argsort(keys, kind="stable")
        self.ids = ids[order]
        self.start = np.searchsorted(keys[order], np.arange(self.nx * self.ny + 1))

    def query(self, x0: float, y0: float, x1: float, y1: float) -> np.ndarray:
        """Indices of every triangle whose bbox overlaps the box (touching counts), and no others."""
        if not self.n:
            return np.zeros(0, np.int32)
        a0, b0 = (int(math.floor((x0 - self.origin[0]) / self.cell)), int(math.floor((y0 - self.origin[1]) / self.cell)))
        a1, b1 = (int(math.floor((x1 - self.origin[0]) / self.cell)), int(math.floor((y1 - self.origin[1]) / self.cell)))
        a0, b0, a1, b1 = max(a0, 0), max(b0, 0), min(a1, self.nx - 1), min(b1, self.ny - 1)
        if a0 > a1 or b0 > b1:
            return np.zeros(0, np.int32)
        parts = [self.ids[self.start[b * self.nx + a0]:self.start[b * self.nx + a1 + 1]] for b in range(b0, b1 + 1)]
        ids = np.unique(np.concatenate(parts))
        if not len(ids):
            return ids
        t = self.tris[ids]
        lo, hi = t.min(axis=1), t.max(axis=1)
        keep = (hi[:, 0] >= x0) & (lo[:, 0] <= x1) & (hi[:, 1] >= y0) & (lo[:, 1] <= y1)
        return ids[keep]


@dataclass
class TileSources:
    road: TriIndex
    stroke: TriIndex
    metro: TriIndex
    base_meshes: dict[str, list[Mesh]] = field(default_factory=dict)
    metro_meshes: list[Mesh] = field(default_factory=list)
    tf: Transform = field(default_factory=Transform)


def make_sources(city: dict[str, np.ndarray], styled: dict[str, list[Mesh]], tf: Transform, cell: float) -> TileSources:
    metro = [tf.apply(m.positions)[m.triangles] for m in styled.get("metro", [])]
    metro_tris = np.concatenate(metro).astype(np.float32) if metro else np.zeros((0, 3, 2), np.float32)
    return TileSources(TriIndex(city["road"], cell), TriIndex(city["stroke"], cell), TriIndex(metro_tris, cell),
                       {s: styled[s] for s in BASE_STYLES if s in styled}, styled.get("metro", []), tf)


def _mask(index: TriIndex, grid: LevelGrid, ix: int, iy: int, margin: int, outline: bool) -> np.ndarray | None:
    """Coverage (uint8, (tile + 2 margin)^2, margin included) of the index's triangles, or None when none are near."""
    mpp, tw = grid.mpp, grid.tile_world
    x0, y1 = grid.origin_x + ix * tw - margin * mpp, grid.origin_top - iy * tw + margin * mpp
    x1, y0 = x0 + tw + 2 * margin * mpp, y1 - tw - 2 * margin * mpp
    sel = index.query(x0, y0, x1, y1)
    if not len(sel):
        return None
    size = (grid.tile + 2 * margin) * SS
    px = index.tris[sel].astype(np.float64)
    px[..., 0] = (px[..., 0] - x0) * (SS / mpp)
    px[..., 1] = (y1 - px[..., 1]) * (SS / mpp)
    img = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(img)
    for t in px.reshape(-1, 6).tolist():
        draw.polygon(t, fill=255, outline=255 if outline else None)     # outline keeps sub-pixel strokes visible
    return np.asarray(img.resize((size // SS, size // SS), Image.LANCZOS))


def _crop(a: np.ndarray, margin: int) -> np.ndarray:
    return a[margin:a.shape[0] - margin, margin:a.shape[1] - margin]


def _white(alpha: np.ndarray) -> Image.Image | None:
    if not alpha.any():
        return None
    out = np.empty(alpha.shape + (4,), np.uint8)
    out[..., :3] = 255
    out[..., 3] = alpha
    return Image.fromarray(out, "RGBA")


def render_tile(src: TileSources, grid: LevelGrid, ix: int, iy: int) -> dict[str, Image.Image]:
    """The non-empty mask tiles of tile (ix, iy), by set name. An empty dict means: write nothing."""
    out: dict[str, Image.Image] = {}

    def put(name: str, alpha: np.ndarray | None) -> None:
        img = None if alpha is None else _white(alpha)
        if img is not None:
            out[name] = img

    if grid.mpp >= BASE_MIN_MPP and src.base_meshes:
        tg = tile_grid(grid, ix, iy, SS, EDGE_MARGIN)
        rgba = render_level(src.base_meshes, src.tf, tg)
        a = rgba.getchannel("A").resize((grid.tile + 2 * EDGE_MARGIN,) * 2, Image.LANCZOS)
        put("base", _crop(np.asarray(a), EDGE_MARGIN))
    m = _mask(src.road, grid, ix, iy, EDGE_MARGIN, outline=False)
    put("road", None if m is None else _crop(m, EDGE_MARGIN))
    m = _mask(src.stroke, grid, ix, iy, GLOW_MARGIN, outline=True)
    if m is not None:
        put("stroke", _crop(m, GLOW_MARGIN))
        blurred = Image.fromarray(m).filter(ImageFilter.GaussianBlur(GLOW_RADIUS))
        g = np.asarray(blurred).astype(np.float32) * GLOW_GAIN
        put("glow", _crop(np.minimum(g, 255).astype(np.uint8), GLOW_MARGIN))
    tw, mpp = grid.tile_world, grid.mpp
    x0, y1 = grid.origin_x + ix * tw, grid.origin_top - iy * tw
    if len(src.metro.query(x0 - 2 * mpp, y1 - tw - 2 * mpp, x0 + tw + 2 * mpp, y1 + 2 * mpp)):
        tg = tile_grid(grid, ix, iy, SS, EDGE_MARGIN)
        rgba = render_level({"metro": src.metro_meshes}, src.tf, tg, style=_METRO_STYLE)
        a = rgba.getchannel("A").resize((grid.tile + 2 * EDGE_MARGIN,) * 2, Image.LANCZOS)
        put("metro", _crop(np.asarray(a), EDGE_MARGIN))
    return out


def png_name(set_name: str, li: int, ix: int, iy: int) -> str:
    return f"{set_name}_L{li}_t_{ix}_{iy}.png"


_JOB: tuple | None = None       # (sources, grid, level index, png dir); set before the fork so workers inherit it


def _low_priority() -> None:
    os.nice(19)


def _work(cell: tuple[int, int]) -> tuple[int, int, list[str]]:
    src, grid, li, png_dir = _JOB
    ix, iy = cell
    tiles = render_tile(src, grid, ix, iy)
    for name, img in tiles.items():
        img.save(png_dir / png_name(name, li, ix, iy), compress_level=3)
    return ix, iy, list(tiles)


def render_level_tiles(src: TileSources, grid: LevelGrid, li: int, png_dir: Path, workers: int = DEFAULT_JOBS,
                       log: Callable[[str], None] = print) -> dict[str, list[tuple[int, int]]]:
    """Render every tile of one level to PNGs in a fork pool; returns the sorted (ix, iy) list per non-empty set."""
    global _JOB
    _JOB = (src, grid, li, png_dir)
    cells = [(ix, iy) for iy in range(grid.ny) for ix in range(grid.nx)]
    found: dict[str, list[tuple[int, int]]] = {s: [] for s in SETS}
    done = 0
    with mp.get_context("fork").Pool(workers, initializer=_low_priority) as pool:
        for ix, iy, names in pool.imap_unordered(_work, cells, chunksize=4):
            for n in names:
                found[n].append((ix, iy))
            done += 1
            if done % 500 == 0:
                log(f"  level {li}: {done}/{len(cells)} cells")
    _JOB = None
    return {s: sorted(v) for s, v in found.items() if v}
