"""Assemble one vector level: grid, per-cell shapes in draw order, draw bounds (spec 2026-10-12 §4.3)."""
from __future__ import annotations

import math
import multiprocessing
import os
from concurrent.futures import ProcessPoolExecutor
from dataclasses import dataclass
from typing import Callable

import numpy as np

from nmtiles.buildings import box_corners
from nmtiles.vector_config import MIN_BOX_HEIGHT, STYLES, VLevel
from nmtiles.vector_extract import (Rect, Shape, Sources, area_features, block_features, line_features, owner_point,
                                    road_features, warm_sources)


@dataclass(frozen=True)
class VGrid:
    ox: float        # world x of column 0's left edge
    otop: float      # world y of row 0's top edge (rows grow south)
    nx: int
    ny: int
    cell: float

    def rect(self, ix: int, iy: int) -> Rect:
        return (self.ox + ix * self.cell, self.otop - (iy + 1) * self.cell,
                self.ox + (ix + 1) * self.cell, self.otop - iy * self.cell)


def grid_for(level: VLevel, extent: Rect) -> VGrid:
    minx, miny, maxx, maxy = extent
    c = level.cell
    ox = math.floor(minx / c) * c
    otop = math.ceil(maxy / c) * c
    return VGrid(ox, otop, max(1, math.ceil((maxx - ox) / c)), max(1, math.ceil((otop - miny) / c)), c)


@dataclass
class Cell:
    ix: int
    iy: int
    shapes: list[Shape]

    def bounds(self) -> Rect:
        allp = np.vstack([s.pts for s in self.shapes])
        return (float(allp[:, 0].min()), float(allp[:, 1].min()), float(allp[:, 0].max()), float(allp[:, 1].max()))

    def style_counts(self) -> tuple[list[int], list[int]]:
        counts = [0] * len(STYLES)
        points = [0] * len(STYLES)
        for s in self.shapes:
            i = STYLES.index(s.style)
            counts[i] += 1
            points[i] += len(s.pts)
        return counts, points


def order(shapes: list[Shape]) -> list[Shape]:
    return sorted(shapes, key=lambda s: (STYLES.index(s.style), -s.prio))


BLOCK_TILE = 4        # block windows are built per BLOCK_TILE x BLOCK_TILE cells, not per cell

# Large inputs live in this module global so forked workers inherit them without pickling.
_JOB: dict = {}


def _row_job(args):
    iy, kinds = args
    level, src, g = _JOB["level"], _JOB["src"], _JOB["grid"]
    out = []
    for ix in range(g.nx):
        r = g.rect(ix, iy)
        shapes = []
        if "area" in kinds:
            shapes += area_features(src, r, level)
        if "road" in kinds:
            shapes += road_features(src.roads, src.tf, r, level, level.road_min_width)
        if "metro" in kinds:
            shapes += line_features(src.metro, src.tf, r, level, "metro")
        out += [((ix, iy), s) for s in shapes]
    return out


def _tile_job(tile):
    tx, ty = tile
    level, g = _JOB["level"], _JOB["grid"]
    ix0, ix1 = tx * BLOCK_TILE, min(g.nx, (tx + 1) * BLOCK_TILE)
    iy0, iy1 = ty * BLOCK_TILE, min(g.ny, (ty + 1) * BLOCK_TILE)
    ra, rb = g.rect(ix0, iy1 - 1), g.rect(ix1 - 1, iy0)
    rect = (ra[0], ra[1], rb[2], rb[3])
    out, stats = [], {}
    for s in block_features(_JOB["corners"], _JOB["centres"], _JOB["heights"], rect, level, stats):
        c = owner_point(s.pts)
        ix = min(max(math.floor((c[0] - g.ox) / g.cell), ix0), ix1 - 1)
        iy = min(max(math.ceil((g.otop - c[1]) / g.cell) - 1, iy0), iy1 - 1)   # rect(): y0 <= c < y1
        out.append(((ix, iy), s))
    return out, stats.get("dropped", 0)


def _run(fn, items, workers: int | None):
    n = (os.cpu_count() or 1) if workers is None else workers
    if n <= 1 or len(items) <= 1:
        return [fn(i) for i in items]
    with ProcessPoolExecutor(min(n, len(items)), mp_context=multiprocessing.get_context("fork")) as ex:
        return list(ex.map(fn, items, chunksize=1))


def road_shapes(level: VLevel, src: Sources, grid: VGrid,
                workers: int | None = None) -> dict[tuple[int, int], list[Shape]]:
    warm_sources(src)
    _JOB.clear()
    _JOB.update(level=level, src=src, grid=grid)
    try:
        rows = _run(_row_job, [(iy, ("road",)) for iy in range(grid.ny)], workers)
    finally:
        _JOB.clear()
    out: dict = {}
    for row in rows:
        for k, s in row:
            out.setdefault(k, []).append(s)
    return out


def build_level(level: VLevel, src: Sources, extent: Rect, log: Callable[[str], None] = print,
                workers: int | None = None) -> tuple[VGrid, dict[tuple[int, int], Cell]]:
    g = grid_for(level, extent)
    warm_sources(src)
    keep = np.asarray(src.boxes.dz, float) >= MIN_BOX_HEIGHT       # the single place low boxes are ignored
    corners = (box_corners(src.boxes) + np.array([src.tf.dx, src.tf.dy]))[keep]
    _JOB.clear()
    _JOB.update(level=level, src=src, grid=g, corners=corners, centres=corners.mean(axis=1),
                heights=np.asarray(src.boxes.dz, float)[keep])
    try:
        rows = _run(_row_job, [(iy, ("area", "road", "metro")) for iy in range(g.ny)], workers)
        log(f"{level.name}: rows done, grid {g.nx} x {g.ny}")
        tiles = [(tx, ty) for ty in range(math.ceil(g.ny / BLOCK_TILE)) for tx in range(math.ceil(g.nx / BLOCK_TILE))]
        tile_out = _run(_tile_job, tiles, workers)
        blocks = [b for b, _ in tile_out]
        log(f"{level.name}: dropped {sum(d for _, d in tile_out)} truncated blocks (touching the window border)")
    finally:
        _JOB.clear()
    by_cell: dict = {}
    for part in rows + blocks:          # fixed order: rows by iy, then tiles in raster order
        for k, s in part:
            by_cell.setdefault(k, []).append(s)
    cells = {k: Cell(k[0], k[1], order(v)) for k, v in sorted(by_cell.items(), key=lambda kv: (kv[0][1], kv[0][0]))}
    log(f"{level.name}: {len(cells)} cells")
    return g, cells
