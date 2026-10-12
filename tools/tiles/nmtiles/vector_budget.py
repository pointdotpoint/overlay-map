"""Worst-view budget check with automatic tightening (spec 2026-10-12 §4.5)."""
from __future__ import annotations

from dataclasses import replace
from typing import Callable

import numpy as np

from nmtiles.vector_cells import Cell, VGrid, order
from nmtiles.vector_config import BLOCK_STYLES, POINT_BUDGET, SHAPE_BUDGET, VIEW_UNITS, VLevel
from nmtiles.vector_geom import douglas_peucker

# Order fixed by the spec: smallest blocks, then road width, then tolerance (at most 2x).
STEPS = (("area", 2.0), ("area", 4.0), ("area", 8.0),
         ("road", 4.0), ("road", 8.0), ("road", 12.0),
         ("tol", 1.25), ("tol", 1.5625), ("tol", 2.0))


class BudgetError(RuntimeError):
    pass


def worst_view(level: VLevel, grid: VGrid, cells: dict) -> tuple[int, int, tuple[float, float]]:
    """Largest (points, shapes) any worst-case view at the level's max zoom-out can touch (half-cell steps)."""
    if not cells:
        return 0, 0, (0.0, 0.0)
    keys = list(cells)
    b = np.array([cells[k].bounds() for k in keys])
    pts = np.array([sum(len(s.pts) for s in cells[k].shapes) for k in keys])
    shp = np.array([len(cells[k].shapes) for k in keys])
    vw, vh = VIEW_UNITS[0] * level.max_mpp, VIEW_UNITS[1] * level.max_mpp
    step = grid.cell / 2.0
    best = (0, 0, (0.0, 0.0))
    best_load = -1.0
    for x0 in np.arange(b[:, 0].min() - vw, b[:, 2].max() + step, step):
        inx = (b[:, 2] >= x0) & (b[:, 0] <= x0 + vw)
        if not inx.any():
            continue
        for y1 in np.arange(b[:, 1].min(), b[:, 3].max() + vh + step, step):
            hit = inx & (b[:, 3] >= y1 - vh) & (b[:, 1] <= y1)
            p, s = int(pts[hit].sum()), int(shp[hit].sum())
            load = max(p / POINT_BUDGET, s / SHAPE_BUDGET)
            if load > best_load:
                best_load, best = load, (p, s, (float(x0), float(y1)))
    return best


def _drop_small_blocks(cells: dict, min_area: float) -> dict:
    out = {}
    for k, c in cells.items():
        keep = [s for s in c.shapes if s.style not in BLOCK_STYLES or s.prio >= min_area]
        if keep:
            out[k] = Cell(c.ix, c.iy, keep)
    return out


def _replace_roads(cells: dict, roads: dict) -> dict:
    out = {}
    for k in set(cells) | set(roads):
        base = [s for s in cells[k].shapes if s.style != "road"] if k in cells else []
        shapes = order(base + roads.get(k, []))
        if shapes:
            out[k] = Cell(k[0], k[1], shapes)
    return out


def _resimplify(cells: dict, tol: float) -> dict:
    out = {}
    for k, c in cells.items():
        shapes = []
        for s in c.shapes:
            pts = douglas_peucker(s.pts, tol)
            if len(pts) >= 2:
                shapes.append(type(s)(s.style, pts, s.prio))
        if shapes:
            out[k] = Cell(c.ix, c.iy, shapes)
    return out


def fit_level(level: VLevel, grid: VGrid, cells: dict, rebuild_roads: Callable[[VLevel], dict],
              log: Callable[[str], None] = print, point_budget: int = POINT_BUDGET,
              shape_budget: int = SHAPE_BUDGET) -> tuple[VLevel, dict, dict]:
    cur, steps = level, []

    def fits() -> tuple[bool, tuple]:
        global_view = worst_view(cur, grid, cells)
        return global_view[0] <= point_budget and global_view[1] <= shape_budget, global_view

    ok, view = fits()
    log(f"{level.name}: worst view {view[0]} points / {view[1]} shapes at {view[2]}")
    for kind, v in STEPS:
        if ok:
            break
        if kind == "area":
            cur = replace(cur, min_area=max(level.min_area, 10.0) * v)
            cells = _drop_small_blocks(cells, cur.min_area)
        elif kind == "road":
            cur = replace(cur, road_min_width=level.road_min_width + v)
            cells = _replace_roads(cells, rebuild_roads(cur))
        else:
            cur = replace(cur, tol=level.tol * v)
            cells = _resimplify(cells, cur.tol)
        steps.append(f"{kind} {v:g}")
        ok, view = fits()
        log(f"{level.name}: after {steps[-1]}: {view[0]} points / {view[1]} shapes")
    if not ok:
        raise BudgetError(f"{level.name}: worst view {view[0]} points / {view[1]} shapes at {view[2]} "
                          f"exceeds {point_budget}/{shape_budget} after {steps}")
    return cur, cells, {"level": level.name, "steps": steps, "points": view[0], "shapes": view[1], "at": view[2]}
