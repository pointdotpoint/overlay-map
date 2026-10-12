"""Per-cell vector features (spec 2026-10-12 §4.1-4.2, §10): exact polygon roads, land/water and building blocks
(shapely), plus raster-traced metro edge lines.

Metro: cell origins, window margins and raster resolution are whole multiples of each other, so neighbouring
cells see identical pixel grids and trace identical contours along their shared edges.
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import shapely
from scipy import ndimage
from shapely.geometry import Polygon

from nmtiles.buildings import Boxes
from nmtiles.glb import Mesh
from nmtiles.render import rasterize_mask
from nmtiles.vector_config import HEIGHT_BUCKETS, VLevel
from nmtiles.vector_geom import _polys, clip_polyline, disk, douglas_peucker, mask_rings, polygon_area, polygon_rings
from nmtiles.world import Transform

Rect = tuple[float, float, float, float]   # (min_x, min_y, max_x, max_y), world metres
BOX_PICK_MARGIN = 150.0                     # boxes whose centre is this far outside a window can still reach into it


@dataclass
class Shape:
    style: str
    pts: np.ndarray     # (N, 2) world metres; closed rings repeat their first point last
    prio: float         # larger = more important within its style (length for metro, area for fills)


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


_TRI_CACHE: dict = {}   # (id(mesh), id(tf)) -> (mesh, tf, tris (M,3,2), lo (M,2), hi (M,2)); warmed before forking


def _tris(mesh: Mesh, tf: Transform):
    key = (id(mesh), id(tf))
    hit = _TRI_CACHE.get(key)
    if hit is None:
        xy = np.asarray(tf.apply(mesh.positions), float)[:, :2]
        tri = xy[np.asarray(mesh.triangles)] if len(mesh.triangles) else np.zeros((0, 3, 2))
        hit = (mesh, tf, tri, tri.min(axis=1), tri.max(axis=1))
        _TRI_CACHE[key] = hit
    return hit


def warm_sources(src: "Sources") -> None:
    """Pre-compute world-space triangles so forked workers share them."""
    for meshes in (src.roads, src.land, src.water):
        for m in meshes:
            _tris(m, src.tf)


def tri_union(meshes: list[Mesh], tf: Transform, rect: Rect):
    """Exact union of the mesh triangles whose bounding box touches rect (world metres, xy)."""
    polys = []
    for m in meshes:
        _, _, tri, lo, hi = _tris(m, tf)
        sel = (hi[:, 0] >= rect[0]) & (lo[:, 0] <= rect[2]) & (hi[:, 1] >= rect[1]) & (lo[:, 1] <= rect[3])
        if sel.any():
            polys.append(shapely.polygons(tri[sel]))
    if not polys:
        return shapely.Polygon()
    p = np.concatenate(polys)
    p = p[shapely.area(p) > 1e-6]
    return shapely.union_all(p, grid_size=0.01) if len(p) else shapely.Polygon()


def _shapes(style: str, geom, cell: Rect, level: VLevel) -> list[Shape]:
    rings = polygon_rings(geom, cell, level.tol, (2 * level.tol) ** 2)
    return [Shape(style, r, polygon_area(r)) for r in rings]


def road_features(meshes: list[Mesh], tf: Transform, cell: Rect, level: VLevel, min_width: float = 0.0) -> list[Shape]:
    """Filled road surfaces clipped to the cell. min_width removes narrower parts (opening on the grown window)."""
    u = tri_union(meshes, tf, grow(cell, min_width + 2 * level.tol))
    if u.is_empty:
        return []
    if min_width > 0:
        u = u.buffer(-min_width / 2, join_style="mitre").buffer(min_width / 2, join_style="mitre")
    return _shapes("road", u, cell, level)


def area_features(src: Sources, cell: Rect, level: VLevel) -> list[Shape]:
    """Exact water fill (water mesh minus land mesh) clipped to the cell. Land is not drawn (fix round 1)."""
    water = tri_union(src.water, src.tf, cell)
    if water.is_empty:
        return []
    land = tri_union(src.land, src.tf, cell)
    if not land.is_empty:
        water = water.difference(land)
    return _shapes("water", water, cell, level)


def owner_point(pts: np.ndarray) -> tuple[float, float]:
    """The point deciding which cell owns a closed block ring."""
    c = shapely.Polygon(pts).centroid
    return float(c.x), float(c.y)


def height_style(h: float) -> str:
    if h < HEIGHT_BUCKETS[0]:
        return "block0"
    return "block1" if h < HEIGHT_BUCKETS[1] else "block2"


def block_features(corners: np.ndarray, centres: np.ndarray, heights: np.ndarray, cell: Rect,
                   level: VLevel, stats: dict | None = None) -> list[Shape]:
    """Merged building blocks whose centroid lies in the cell (exact polygon union, closing, opening).

    Blocks touching the window border are truncated and dropped (counted in stats["dropped"]).

    corners: (N,4,2) world box corners; centres: (N,2); heights: (N,) metres.
    """
    win = grow(cell, level.block_margin)
    x0, y0, x1, y1 = win
    m = BOX_PICK_MARGIN
    pick = np.nonzero((centres[:, 0] > x0 - m) & (centres[:, 0] < x1 + m)
                      & (centres[:, 1] > y0 - m) & (centres[:, 1] < y1 + m))[0]
    if len(pick) == 0:
        return []
    feet = shapely.polygons(corners[pick])
    feet = feet[shapely.area(feet) > 1e-6]
    if len(feet) == 0:
        return []
    h = np.asarray(heights, float)[pick][shapely.area(shapely.polygons(corners[pick])) > 1e-6]
    g = shapely.union_all(feet, grid_size=0.01)
    gap, ow = level.merge_gap, level.open_width
    if gap > 0:
        g = g.buffer(gap / 2, join_style="mitre").buffer(-gap / 2, join_style="mitre")
    if ow > 0:
        g = g.buffer(-ow / 2, join_style="mitre").buffer(ow / 2, join_style="mitre")
    tree = shapely.STRtree(feet)
    eps = 1e-6
    out = []
    for p in _polys(g):
        ext = Polygon(p.exterior)
        s = ext.simplify(level.tol)
        if s.is_empty or s.geom_type != "Polygon":
            continue
        bx0, by0, bx1, by1 = s.bounds
        if bx0 <= x0 + eps or bx1 >= x1 - eps or by0 <= y0 + eps or by1 >= y1 - eps:
            if stats is not None:
                stats["dropped"] = stats.get("dropped", 0) + 1
            continue
        if s.area < max(level.min_area, (2 * level.tol) ** 2):
            continue
        ring = np.asarray(s.exterior.coords, float)
        cx, cy = owner_point(ring)
        if not (cell[0] <= cx < cell[2] and cell[1] <= cy < cell[3]):
            continue
        hit = tree.query(ext, predicate="intersects")
        top = float(h[hit].max()) if len(hit) else float(h.max())
        out.append(Shape(height_style(top), ring, float(s.area)))
    return out
