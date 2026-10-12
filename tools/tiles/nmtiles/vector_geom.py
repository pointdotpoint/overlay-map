"""Geometry primitives for the vector layer: simplification, clipping, mask contours."""
from __future__ import annotations

import contourpy
import numpy as np
import shapely
from scipy import ndimage
from shapely.geometry import Polygon

SPLIT_DEPTH = 16


def douglas_peucker(pts: np.ndarray, tol: float) -> np.ndarray:
    """Simplify a polyline (or a closed ring whose first point equals its last) within tol."""
    pts = np.asarray(pts, float)
    n = len(pts)
    if n < 3:
        return pts.copy()
    if np.allclose(pts[0], pts[-1]):
        d = np.hypot(*(pts - pts[0]).T)
        k = int(np.argmax(d))
        if k == 0:
            return pts[:1].copy()
        a = douglas_peucker(pts[: k + 1], tol)
        b = douglas_peucker(pts[k:], tol)
        return np.vstack([a, b[1:]])
    keep = np.zeros(n, bool)
    keep[0] = keep[-1] = True
    stack = [(0, n - 1)]
    while stack:
        i, j = stack.pop()
        if j <= i + 1:
            continue
        seg = pts[j] - pts[i]
        length = float(np.hypot(*seg))
        rel = pts[i + 1:j] - pts[i]
        if length == 0.0:
            d = np.hypot(rel[:, 0], rel[:, 1])
        else:
            d = np.abs(seg[0] * rel[:, 1] - seg[1] * rel[:, 0]) / length
        m = int(np.argmax(d))
        if d[m] > tol:
            k = i + 1 + m
            keep[k] = True
            stack.append((i, k))
            stack.append((k, j))
    return pts[keep]


def _clip_segment(a: np.ndarray, b: np.ndarray, rect: tuple) -> tuple | None:
    """Liang-Barsky: (p, q, t0, t1) for the visible part of segment a-b, or None."""
    x0, y0, x1, y1 = rect
    dx, dy = b[0] - a[0], b[1] - a[1]
    t0, t1 = 0.0, 1.0
    for p, q in ((-dx, a[0] - x0), (dx, x1 - a[0]), (-dy, a[1] - y0), (dy, y1 - a[1])):
        if p == 0:
            if q < 0:
                return None
            continue
        t = q / p
        if p < 0:
            if t > t1:
                return None
            t0 = max(t0, t)
        else:
            if t < t0:
                return None
            t1 = min(t1, t)
    if t0 > t1:
        return None
    return np.array([a[0] + t0 * dx, a[1] + t0 * dy]), np.array([a[0] + t1 * dx, a[1] + t1 * dy]), t0, t1


def clip_polyline(pts: np.ndarray, rect: tuple) -> list[np.ndarray]:
    """Clip a polyline to rect (min_x, min_y, max_x, max_y); returns the inside runs (each >= 2 points)."""
    runs: list[np.ndarray] = []
    cur: list[np.ndarray] = []

    def flush() -> None:
        if len(cur) >= 2:
            runs.append(np.array(cur))

    for a, b in zip(pts[:-1], pts[1:]):
        seg = _clip_segment(a, b, rect)
        if seg is None:
            flush()
            cur = []
            continue
        p, q, t0, t1 = seg
        if t0 > 0.0 or not cur:
            flush()
            cur = [p]
        cur.append(q)
        if t1 < 1.0:
            flush()
            cur = []
    flush()
    return runs


def mask_rings(mask: np.ndarray, x0: float, y_top: float, res: float, fill_holes: bool = False) -> list[np.ndarray]:
    """Closed iso-0.5 contours of a boolean mask in world metres.

    Pixel (row, col) covers x [x0 + col*res, x0 + (col+1)*res] and y [y_top - (row+1)*res, y_top - row*res].
    The mask is zero-padded, so every contour closes and a mask touching the window edge yields a ring on
    that edge exactly.
    """
    if not mask.any():
        return []
    m = ndimage.binary_fill_holes(mask) if fill_holes else mask
    z = np.pad(m.astype(np.float32), 1)
    gen = contourpy.contour_generator(z=z, line_type=contourpy.LineType.Separate)
    rings = []
    for line in gen.lines(0.5):
        col = line[:, 0] - 1.0
        row = line[:, 1] - 1.0
        r = np.column_stack((x0 + (col + 0.5) * res, y_top - (row + 0.5) * res))
        if not np.allclose(r[0], r[-1]):
            r = np.vstack([r, r[:1]])
        rings.append(r)
    return rings


def polygon_area(ring: np.ndarray) -> float:
    x, y = ring[:, 0], ring[:, 1]
    return float(abs(np.dot(x[:-1], y[1:]) - np.dot(x[1:], y[:-1])) / 2.0)


def disk(r: int) -> np.ndarray:
    yy, xx = np.ogrid[-r:r + 1, -r:r + 1]
    return xx * xx + yy * yy <= r * r


# ---- exact polygon geometry (spec 2026-10-12 §10.1) ----

def _polys(g) -> list[Polygon]:
    """Polygons of any geometry (multi, collection), in a deterministic order."""
    if g is None or g.is_empty:
        return []
    out = [p for p in getattr(g, "geoms", [g]) if p.geom_type == "Polygon" and not p.is_empty]
    out += [q for p in getattr(g, "geoms", []) if p.geom_type == "GeometryCollection" for q in _polys(p)]
    return sorted(out, key=lambda p: (round(p.bounds[0], 3), round(p.bounds[1], 3), -p.area))


def explode_polygons(g) -> list[Polygon]:
    return _polys(g)


def split_holes(poly: Polygon, depth: int = 0) -> list[Polygon]:
    """Cover poly exactly with hole-free polygons: bisect the bounds along the longer side through the first hole."""
    if not poly.interiors:
        return [poly]
    if depth >= SPLIT_DEPTH:
        return [Polygon(poly.exterior)]
    x0, y0, x1, y1 = poly.bounds
    hole = poly.interiors[0]
    hx0, hy0, hx1, hy1 = hole.bounds
    vertical = (x1 - x0) >= (y1 - y0)
    lo, hi = (hx0, hx1) if vertical else (hy0, hy1)
    cut = hole.coords[0][0 if vertical else 1]
    if cut - lo < 1e-9 or hi - cut < 1e-9:       # the first vertex is an extreme: cutting there would miss the hole
        cut = (lo + hi) / 2.0
    halves = ((shapely.box(x0, y0, cut, y1), shapely.box(cut, y0, x1, y1)) if vertical
              else (shapely.box(x0, y0, x1, cut), shapely.box(x0, cut, x1, y1)))
    out: list[Polygon] = []
    for half in halves:
        for q in _polys(poly.intersection(half)):
            out += split_holes(q, depth + 1)
    return out


def polygon_rings(geom, clip, tol: float, min_area: float) -> list[np.ndarray]:
    """geom clipped to a rectangle, simplified, split into hole-free pieces; closed (N,2) rings, small pieces dropped."""
    if geom is None or geom.is_empty:
        return []
    if clip is not None:
        geom = geom.intersection(shapely.box(*clip))
    if geom.is_empty:
        return []
    if tol > 0:
        geom = geom.simplify(tol)
    rings = []
    for p in _polys(geom):
        for q in split_holes(p):
            if q.area >= min_area and q.area > 0:
                rings.append(np.asarray(q.exterior.coords, float))
    return rings
