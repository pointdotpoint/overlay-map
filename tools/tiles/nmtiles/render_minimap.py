"""Colourless mask tiles (white RGB, alpha = coverage) from the game's minimap geometry (spec 11.6).

One tile set per class, in draw order; the runtime tints them with SetTintColor from NMTheme:
  glow     blurred road edges + footprint outlines (levels with mpp >= GLOW_MIN_MPP only; the runtime draws it from a
           level 2 steps coarser than the camera's, upscaled, so bilinear filtering makes the bloom soft)
  road     minimap road triangles
  bfill    building footprint fill
  outline  footprint exterior as a 1 px line at the level's resolution (drawn at 2x, width 2, downsampled)
Every tile is rendered independently at SS x and downsampled (LANCZOS), with a margin that is cropped away afterwards,
so neighbouring tiles agree along their shared edge and no whole-level image ever exists.
"""
from __future__ import annotations

import math
import multiprocessing as mp
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from nmtiles.render import LevelGrid

SETS = ("glow", "road", "bfill", "outline")      # draw order, back to front
SS = 2
DEFAULT_JOBS = 4
GLOW_MIN_MPP = 2.0                                       # glow tiles exist only at m/px >= this (L2..L5)
GLOW_RADIUS = 1.5                                        # Gaussian sigma in px at every glow level: 3 m at 2 m/px, reach ~9 m
GLOW_GAIN = 2.5                                          # gain at 2 m/px (a blurred 1 px line peaks near 0.26); falls with sqrt(mpp)


def glow_gain(mpp: float) -> float:
    """Coarser levels are drawn at the same screen size from a blur whose reach grows with mpp, so they get less gain:
    otherwise the far zoom reads as haze, not glow."""
    return GLOW_GAIN * math.sqrt(GLOW_MIN_MPP / max(mpp, GLOW_MIN_MPP))

GLOW_MARGIN = math.ceil(3 * GLOW_RADIUS) + 3             # >= 3 sigma plus the LANCZOS support
EDGE_MARGIN = 3                                          # px: >= the LANCZOS support, so the kernel sees the neighbouring tile
BATCH = 100_000                                          # primitives drawn per Python list conversion (bounded memory)


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
    foot: TriIndex                  # over the footprints' bboxes, as (n, 2, 2) corner pairs
    polys: list[np.ndarray]         # footprint exteriors, world xy


def make_sources(road: np.ndarray, polys: list[np.ndarray], cell: float) -> TileSources:
    boxes = np.array([[p.min(axis=0), p.max(axis=0)] for p in polys], np.float64).reshape(-1, 2, 2)
    return TileSources(TriIndex(road, cell), TriIndex(boxes, cell), polys)


def _window(grid: LevelGrid, ix: int, iy: int, margin: int) -> tuple[float, float, float, float, int]:
    """(x0, y1, x1, y0, px size): the world box of tile (ix, iy) plus `margin` px, top-left x0 / y1."""
    mpp, tw = grid.mpp, grid.tile_world
    x0, y1 = grid.origin_x + ix * tw - margin * mpp, grid.origin_top - iy * tw + margin * mpp
    return x0, y1, x0 + tw + 2 * margin * mpp, y1 - tw - 2 * margin * mpp, (grid.tile + 2 * margin) * SS


def _fill_mask(index: TriIndex, grid: LevelGrid, ix: int, iy: int, margin: int) -> np.ndarray | None:
    """Coverage (uint8, margin included) of the index's triangles. Pixel coordinates are floored before drawing, so
    negative and positive coordinates round the same way and neighbouring tiles agree."""
    x0, y1, x1, y0, size = _window(grid, ix, iy, margin)
    sel = index.query(x0, y0, x1, y1)
    if not len(sel):
        return None
    img = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(img)
    s = SS / grid.mpp
    for i in range(0, len(sel), BATCH):
        px = index.tris[sel[i:i + BATCH]].astype(np.float64)
        px[..., 0] = np.floor((px[..., 0] - x0) * s)
        px[..., 1] = np.floor((y1 - px[..., 1]) * s)
        for t in px.reshape(-1, 6).tolist():
            draw.polygon(t, fill=255)
    return _down(img)


def _down(img: Image.Image) -> np.ndarray:
    return np.asarray(img.resize((img.width // SS, img.height // SS), Image.LANCZOS))


def _foot_masks(src: TileSources, grid: LevelGrid, ix: int, iy: int, margin: int) -> tuple[np.ndarray, np.ndarray] | None:
    """(fill, outline) coverage of the footprints, margin included."""
    x0, y1, x1, y0, size = _window(grid, ix, iy, margin)
    sel = src.foot.query(x0, y0, x1, y1)
    if not len(sel):
        return None
    fill, line = Image.new("L", (size, size), 0), Image.new("L", (size, size), 0)
    df, dl = ImageDraw.Draw(fill), ImageDraw.Draw(line)
    s = SS / grid.mpp
    for i in sel:
        p = src.polys[i]
        c = np.column_stack((np.floor((p[:, 0] - x0) * s), np.floor((y1 - p[:, 1]) * s)))
        pts = [tuple(v) for v in c.tolist()]
        df.polygon(pts, fill=255)
        dl.line(pts + pts[:1], fill=255, width=SS, joint="curve")
    return _down(fill), _down(line)


def _crop(a: np.ndarray, margin: int) -> np.ndarray:
    return a[margin:a.shape[0] - margin, margin:a.shape[1] - margin]


def _white(alpha: np.ndarray) -> Image.Image | None:
    if not alpha.any():
        return None
    out = np.empty(alpha.shape + (4,), np.uint8)
    out[..., :3] = 255
    out[..., 3] = alpha
    return Image.fromarray(out, "RGBA")


def _road_edge(road: np.ndarray) -> np.ndarray:
    """1-2 px wide rim of the road coverage (coverage minus its 3x3 erosion)."""
    eroded = np.asarray(Image.fromarray(road).filter(ImageFilter.MinFilter(3)))
    return road - np.minimum(road, eroded)


def _glow(road: np.ndarray | None, line: np.ndarray | None, gain: float = GLOW_GAIN) -> np.ndarray | None:
    """Blurred max(road rim, footprint outline), lifted by GLOW_GAIN; margin included."""
    parts = []
    if road is not None:
        parts.append(_road_edge(road))
    if line is not None:
        parts.append(line)
    if not parts:
        return None
    src = np.maximum.reduce(parts)
    blurred = np.asarray(Image.fromarray(src).filter(ImageFilter.GaussianBlur(GLOW_RADIUS)))
    return np.minimum(blurred.astype(np.float32) * gain, 255).astype(np.uint8)


def render_tile(src: TileSources, grid: LevelGrid, ix: int, iy: int) -> dict[str, Image.Image]:
    """The non-empty mask tiles of tile (ix, iy), by set name. An empty dict means: write nothing."""
    out: dict[str, Image.Image] = {}

    def put(name: str, alpha: np.ndarray | None) -> None:
        img = None if alpha is None else _white(alpha)
        if img is not None:
            out[name] = img

    # Levels with a glow set render every mask with the larger margin (the window shifts by whole pixels, so the
    # cropped result is identical) and blur it before cropping.
    glow_on = grid.mpp >= GLOW_MIN_MPP
    margin = GLOW_MARGIN if glow_on else EDGE_MARGIN
    road = _fill_mask(src.road, grid, ix, iy, margin)
    put("road", None if road is None else _crop(road, margin))
    masks = _foot_masks(src, grid, ix, iy, margin)
    line = None
    if masks is not None:
        fill, line = masks
        put("bfill", _crop(fill, margin))
        put("outline", _crop(line, margin))
    if glow_on:
        g = _glow(road, line, glow_gain(grid.mpp))
        put("glow", None if g is None else _crop(g, margin))
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
