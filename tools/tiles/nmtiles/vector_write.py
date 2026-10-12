"""Per-cell inkShapeCollection JSON and manifest rows (spec 2026-10-12 §4.4)."""
from __future__ import annotations

import copy
from pathlib import Path

import numpy as np

from nmtiles.pack import write_resource
from nmtiles.vector_cells import Cell, VGrid
from nmtiles.vector_config import VLevel

MIN_EXTENT = 0.01      # widget size floor (units) for degenerate bounds


def depot_path(level_idx: int, ix: int, iy: int) -> str:
    return f"nightmap\\vec\\V{level_idx}\\c_{ix}_{iy}.inkshapecollection"


def local_points(pts: np.ndarray, bounds: tuple, unit: float) -> np.ndarray:
    """World metres -> level units relative to the draw-bounds corner (min x, max y); Y points down."""
    minx, _, _, maxy = bounds
    return np.column_stack(((pts[:, 0] - minx) / unit, (maxy - pts[:, 1]) / unit))


def collection_json(template: dict, cell: Cell, unit: float) -> dict:
    doc = copy.deepcopy(template)
    b = cell.bounds()
    doc["Data"]["RootChunk"]["presets"] = [
        {"$type": "inkShapePreset",
         "name": {"$type": "CName", "$storage": "string", "$value": f"s{i}"},
         "points": [{"$type": "Vector2", "X": round(float(x), 3), "Y": round(float(y), 3)}
                    for x, y in local_points(s.pts, b, unit)]}
        for i, s in enumerate(cell.shapes)]
    return doc


def write_level(ws: Path, level_idx: int, level: VLevel, grid: VGrid, cells: dict, template: dict) -> dict:
    u = level.min_mpp
    rows = []
    for (ix, iy), cell in sorted(cells.items(), key=lambda kv: (kv[0][1], kv[0][0])):
        write_resource(ws, depot_path(level_idx, ix, iy), collection_json(template, cell, u))
        minx, miny, maxx, maxy = cell.bounds()
        counts, points = cell.style_counts()
        rows.append({"key": iy * grid.nx + ix,
                     "bounds": ((minx - grid.ox) / u, (grid.otop - maxy) / u,
                                max((maxx - minx) / u, MIN_EXTENT), max((maxy - miny) / u, MIN_EXTENT)),
                     "counts": counts, "points": points})
    return {"min_mpp": level.min_mpp, "max_mpp": level.max_mpp, "unit": u, "cell": grid.cell,
            "ox": grid.ox, "otop": grid.otop, "nx": grid.nx, "ny": grid.ny, "cells": rows}
