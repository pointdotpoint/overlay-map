"""Per-cell vector features (spec 2026-10-12 §4.1-4.2): road/metro edges, land/water fills, building blocks.

Cell origins, window margins and raster resolution are whole multiples of each other, so neighbouring cells
see identical pixel grids and trace identical contours along their shared edges.
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

from nmtiles.buildings import Boxes
from nmtiles.glb import Mesh
from nmtiles.render import rasterize_mask
from nmtiles.vector_config import HEIGHT_BUCKETS, VLevel
from nmtiles.vector_geom import clip_polyline, disk, douglas_peucker, mask_rings, polygon_area
from nmtiles.world import Transform

Rect = tuple[float, float, float, float]   # (min_x, min_y, max_x, max_y), world metres
BOX_PICK_MARGIN = 150.0                     # boxes whose centre is this far outside a window can still reach into it


@dataclass
class Shape:
    style: str
    pts: np.ndarray     # (N, 2) world metres; closed rings repeat their first point last
    prio: float         # larger = more important within its style (length or area)


@dataclass
class Sources:
    roads: list[Mesh]
    metro: list[Mesh]
    land: list[Mesh]
    water: list[Mesh]
    boxes: Boxes
    tf: Transform


def grow(rect: Rect, m: float) -> Rect:
    return (rect[0] - m, rect[1] - m, rect[2] + m, rect[3] + m)


def window_mask(meshes: list[Mesh], tf: Transform, rect: Rect, res: float) -> np.ndarray:
    x0, y0, x1, y1 = rect
    w = max(1, int(round((x1 - x0) / res)))
    h = max(1, int(round((y1 - y0) / res)))
    if not meshes:
        return np.zeros((h, w), bool)
    # PIL fills every pixel a polygon touches (and a polygon edge exactly on the grid widens only one side), which
    # skews edges by up to half a pixel. Draw at 2x and keep pixels that are more than half covered: the error
    # drops to a quarter pixel. The grid origin is unchanged, so neighbouring windows stay aligned.
    fine = rasterize_mask(meshes, tf, x0, y1, res / 2, 2 * w, 2 * h)
    return fine.reshape(h, 2, w, 2).sum(axis=(1, 3)) > 2


def _on_edge(p: np.ndarray, r: Rect, eps: float = 1e-6) -> bool:
    return (abs(p[0] - r[0]) < eps or abs(p[0] - r[2]) < eps or abs(p[1] - r[1]) < eps or abs(p[1] - r[3]) < eps)


def line_features(meshes: list[Mesh], tf: Transform, cell: Rect, level: VLevel, style: str,
                  min_width: float = 0.0) -> list[Shape]:
    """Edge lines of a surface (iso-0.5 contours), clipped to the cell. min_width removes narrower parts."""
    win = grow(cell, 2 * level.res + min_width)
    mask = window_mask(meshes, tf, win, level.res)
    if min_width > 0 and mask.any():
        mask = ndimage.binary_opening(mask, structure=disk(max(1, int((min_width / level.res - 1) // 2))))
    out = []
    for ring in mask_rings(mask, win[0], win[3], level.res):
        for run in clip_polyline(ring, cell):
            s = douglas_peucker(run, level.tol)
            length = float(np.hypot(*np.diff(s, axis=0).T).sum()) if len(s) >= 2 else 0.0
            extent = float(np.ptp(s, axis=0).max()) if len(s) else 0.0
            # Junction blobs and stubs inside the cell are dropped; pieces clipped at a cell border are real roads
            # that continue next door, so they only need to pass the length check.
            on_border = len(s) > 0 and any(_on_edge(p, cell) for p in (s[0], s[-1]))
            if length >= 3 * level.tol and (on_border or extent >= max(2 * min_width, 10 * level.res)):
                out.append(Shape(style, s, length))
    return out


def area_features(src: Sources, cell: Rect, level: VLevel) -> list[Shape]:
    """Fill polygons for land (terrain minus water) and water, traced on exactly the cell (clipped there)."""
    land = window_mask(src.land, src.tf, cell, level.res)
    water = window_mask(src.water, src.tf, cell, level.res)
    out = []
    min_area = (2 * level.res) ** 2
    for style, mask in (("land", land & ~water), ("water", water)):
        for ring in mask_rings(mask, cell[0], cell[3], level.res, fill_holes=True):
            s = douglas_peucker(ring, level.tol)
            a = polygon_area(s) if len(s) >= 4 else 0.0
            if a >= min_area:
                out.append(Shape(style, s, a))
    return out


def height_style(h: float) -> str:
    if h < HEIGHT_BUCKETS[0]:
        return "block0"
    return "block1" if h < HEIGHT_BUCKETS[1] else "block2"


def block_features(corners: np.ndarray, centres: np.ndarray, heights: np.ndarray, cell: Rect,
                   level: VLevel, stats: dict | None = None) -> list[Shape]:
    """Merged building blocks whose outline centroid lies in the cell.

    Blocks whose traced outline touches the window border are truncated and dropped (counted in stats["dropped"]).

    corners: (N,4,2) world box corners; centres: (N,2); heights: (N,) metres.
    """
    win = grow(cell, level.block_margin)
    x0, y0, x1, y1 = win
    m = BOX_PICK_MARGIN
    pick = np.nonzero((centres[:, 0] > x0 - m) & (centres[:, 0] < x1 + m)
                      & (centres[:, 1] > y0 - m) & (centres[:, 1] < y1 + m))[0]
    if len(pick) == 0:
        return []
    res = level.res
    w = max(1, int(round((x1 - x0) / res)))
    h = max(1, int(round((y1 - y0) / res)))
    occ = Image.new("1", (w, h), 0)
    top = Image.new("L", (w, h), 0)
    d_occ, d_top = ImageDraw.Draw(occ), ImageDraw.Draw(top)
    for k in pick[np.argsort(heights[pick], kind="stable")]:
        poly = [((x - x0) / res, (y1 - y) / res) for x, y in corners[k]]
        d_occ.polygon(poly, fill=1)
        d_top.polygon(poly, fill=int(min(255, max(1, heights[k]))))
    mask = np.asarray(occ, bool)
    tops = np.asarray(top)
    if level.merge_gap > 0:
        mask = ndimage.binary_closing(mask, structure=disk(max(1, int(round(level.merge_gap / 2 / res))))) | mask
    mask = ndimage.binary_fill_holes(mask)
    lab, n = ndimage.label(mask)
    if n == 0:
        return []
    peak = ndimage.maximum(tops, lab, index=np.arange(1, n + 1))
    out = []
    for i, sl in enumerate(ndimage.find_objects(lab)):
        if sl is None:
            continue
        sub = lab[sl] == i + 1
        ox = x0 + sl[1].start * res
        oy = y1 - sl[0].start * res
        for ring in mask_rings(sub, ox, oy, res):
            s = douglas_peucker(ring, level.tol)
            if len(s) < 4:
                continue
            if (s[:, 0].min() <= x0 + res or s[:, 0].max() >= x1 - res
                    or s[:, 1].min() <= y0 + res or s[:, 1].max() >= y1 - res):
                if stats is not None:
                    stats["dropped"] = stats.get("dropped", 0) + 1
                continue
            a = polygon_area(s)
            c = s[:-1].mean(axis=0)
            if a < max(level.min_area, (2 * res) ** 2):
                continue
            if not (cell[0] <= c[0] < cell[2] and cell[1] <= c[1] < cell[3]):
                continue
            out.append(Shape(height_style(float(peak[i])), s, a))
    return out
