"""Clean building footprint polygons from the minimap's building geometry (spec 11.6), computed once city-wide.

Per 500 m tile (150 m margin): union of building triangles buffered 0.3, closing 4, exteriors only, minus the road union
buffered 0.5, opening 3, simplify 0.6, exteriors, drop pieces < 60 m2. A polygon is kept only by the tile whose core
contains its representative point, so tile seams neither duplicate nor drop footprints.
"""
from __future__ import annotations

import hashlib
import multiprocessing as mp
import os
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import shapely

PARAMS = dict(buf=0.3, close=4.0, road_buf=0.5, road_tri_buf=0.05, open=3.0, simplify=0.6, min_area=60.0)
TILE, MARGIN = 500.0, 150.0
VERSION = 2
MAX_MARGIN = 1200.0     # adaptive window growth cap (m); blocks beyond this are still repaired by the city-wide union
EDGE_TOUCH = 5.0         # a footprint this close to its window border may have been truncated


@dataclass
class Footprints:
    polys: list[np.ndarray]          # each (n, 2) float64 closed-ring-less exterior, world xy

    def save(self, path: Path, key: str) -> None:
        lens = np.array([len(p) for p in self.polys], np.int64)
        pts = np.concatenate(self.polys) if self.polys else np.zeros((0, 2))
        tmp = path.with_name(path.stem + ".tmp.npz")
        np.savez_compressed(tmp, key=np.array(key), lens=lens, pts=pts)
        os.replace(tmp, path)

    @staticmethod
    def load(path: Path, key: str) -> "Footprints | None":
        if not path.exists():
            return None
        z = np.load(path)
        if str(z["key"]) != key:
            return None
        return Footprints(np.split(z["pts"], np.cumsum(z["lens"])[:-1]) if len(z["lens"]) else [])


def footprint_key(road: np.ndarray, building: np.ndarray) -> str:
    h = hashlib.sha256(f"v{VERSION}|{PARAMS}|{TILE}|{MARGIN}|{shapely.__version__}".encode())
    for a in (road, building):
        h.update(str(a.shape).encode())
        h.update(np.ascontiguousarray(a).tobytes())
    return h.hexdigest()[:16]


def _polys(tris: np.ndarray) -> np.ndarray:
    t = tris.astype(np.float64)
    ring = np.concatenate([t, t[:, :1]], axis=1)
    p = shapely.polygons(ring)
    return p[shapely.is_valid(p) & (shapely.area(p) > 1e-6)]


def _union(tris: np.ndarray, buf: float):
    p = _polys(tris)
    return shapely.union_all(shapely.buffer(p, buf, quad_segs=2)) if len(p) else None


def _morph(g, w: float):
    """w > 0 closing, w < 0 opening (mitre joins)."""
    r = abs(w) / 2
    if w > 0:
        return g.buffer(r, join_style="mitre").buffer(-r, join_style="mitre")
    return g.buffer(-r, join_style="mitre").buffer(r, join_style="mitre")


def _exteriors(g):
    parts = [p for p in shapely.get_parts(g) if p.geom_type == "Polygon" and not p.is_empty]
    return shapely.union_all([shapely.Polygon(p.exterior) for p in parts]) if parts else None


def clean_window(road_tris: np.ndarray, bld_tris: np.ndarray) -> list:
    """The footprint polygons (shapely) of one window, steps 1 to 8."""
    bld = _union(bld_tris, PARAMS["buf"])
    if bld is None:
        return []
    bld = _exteriors(_morph(bld, PARAMS["close"]))
    if len(road_tris):
        road = _union(road_tris, PARAMS["road_tri_buf"])
        if road is not None:
            bld = bld.difference(road.buffer(PARAMS["road_buf"]))
    if bld.is_empty:
        return []
    bld = _exteriors(_morph(bld, -PARAMS["open"]).simplify(PARAMS["simplify"]))
    if bld is None:
        return []
    return [p for p in shapely.get_parts(bld) if p.geom_type == "Polygon" and p.area >= PARAMS["min_area"]]


_JOB: tuple | None = None


def _low_priority() -> None:
    os.nice(19)


def _tile(cell: tuple[int, int]) -> list[np.ndarray]:
    road_idx, bld_idx, ox, oy, tile, margin = _JOB
    ix, iy = cell
    x0, y0 = ox + ix * tile, oy + iy * tile
    while True:
        w = (x0 - margin, y0 - margin, x0 + tile + margin, y0 + tile + margin)
        b = bld_idx.tris[bld_idx.query(*w)]
        if not len(b):
            return []
        r = road_idx.tris[road_idx.query(*w)]
        owned, grow = [], False
        for p in clean_window(r, b):
            rp = p.representative_point()
            if x0 <= rp.x < x0 + tile and y0 <= rp.y < y0 + tile:
                owned.append(p)
                bx0, by0, bx1, by1 = p.bounds
                grow |= (bx0 < w[0] + EDGE_TOUCH or by0 < w[1] + EDGE_TOUCH
                         or bx1 > w[2] - EDGE_TOUCH or by1 > w[3] - EDGE_TOUCH)
        if grow and margin * 2 <= MAX_MARGIN:
            margin *= 2            # an owned footprint reaches the window border: redo with a larger window
            continue
        return [np.asarray(p.exterior.coords)[:-1] for p in owned]


def merge_city(polys: list[np.ndarray]) -> list[np.ndarray]:
    """City-wide union of the per-tile footprints (repairs duplicates and cuts at tile borders), then steps 3, 7, 8."""
    if not polys:
        return []
    g = shapely.union_all([shapely.Polygon(p) for p in polys])
    g = _exteriors(g.simplify(PARAMS["simplify"]))
    parts = [p for p in shapely.get_parts(g) if p.geom_type == "Polygon" and p.area >= PARAMS["min_area"]]
    parts.sort(key=lambda p: (round(p.bounds[0], 3), round(p.bounds[1], 3), round(p.area, 3)))
    return [np.asarray(p.exterior.coords)[:-1] for p in parts]


def build_footprints(road: np.ndarray, building: np.ndarray, tile: float = TILE, margin: float = MARGIN,
                     jobs: int = 4) -> Footprints:
    """All footprints of the city, in a deterministic order (by tile row-major, then by shapely order)."""
    global _JOB
    from nmtiles.render_minimap import TriIndex
    if not len(building):
        return Footprints([])
    lo = building.reshape(-1, 2).min(0).astype(np.float64)
    hi = building.reshape(-1, 2).max(0).astype(np.float64)
    ox, oy = math_floor(lo[0], tile), math_floor(lo[1], tile)
    nx, ny = int(np.ceil((hi[0] - ox) / tile)) + 1, int(np.ceil((hi[1] - oy) / tile)) + 1
    bld_idx = TriIndex(building, max(tile, 250.0))
    road_idx = TriIndex(road, max(tile, 250.0))
    _JOB = (road_idx, bld_idx, ox, oy, tile, margin)
    cells = [(ix, iy) for iy in range(ny) for ix in range(nx)]
    polys: list[np.ndarray] = []
    try:
        if jobs <= 1:
            results = map(_tile, cells)
            for r in results:
                polys += r
        else:
            with mp.get_context("fork").Pool(jobs, initializer=_low_priority) as pool:
                for r in pool.imap(_tile, cells, chunksize=2):      # imap keeps cell order: deterministic
                    polys += r
    finally:
        _JOB = None
    return Footprints(merge_city(polys))


def math_floor(v: float, step: float) -> float:
    return float(np.floor(v / step) * step)


def load_or_build(road: np.ndarray, building: np.ndarray, cache: Path, jobs: int, log=print) -> Footprints:
    key = footprint_key(road, building)
    fp = Footprints.load(cache, key)
    if fp is not None:
        log(f"footprints: cached {len(fp.polys)}")
        return fp
    fp = build_footprints(road, building, jobs=jobs)
    fp.save(cache, key)
    log(f"footprints: built {len(fp.polys)}")
    return fp
