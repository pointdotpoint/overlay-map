"""Vanilla 3D-map helpers: exporting its sources, its road mesh in world space, road widths and building-box triangles.

The module started as Dogtown's fix (Phantom Liberty re-cooked Dogtown without minimap data, so its roads and buildings
came from the 3D map); since 2026-11-05 the whole map is drawn from these sources (vanilla_roads.py,
vanilla_buildings.py).
"""
from __future__ import annotations

from pathlib import Path
from typing import Callable

import numpy as np
import shapely
from PIL import Image, ImageDraw
from scipy.ndimage import distance_transform_edt

from nmtiles.minimap import MAJOR_WIDTH_M

WIDTH_RES = 1.0         # m per pixel of the road-width raster
MAJOR_MIN_AREA = 2000.0  # m2: a wide patch smaller than this (a junction, a turning circle) is not a major road
MESH_DIR = Path("meshes/base/entities/cameras/3dmap")   # under the build dir, as nmtiles.export writes it
DATA_DIR = Path("bdata")


def split_major(tris: np.ndarray, res: float = WIDTH_RES) -> tuple[np.ndarray, np.ndarray]:
    """(minor, major): a triangle is major when the road under it is at least MAJOR_WIDTH_M wide, measured as twice
    the largest distance from any of its pixels to the road edge (the mesh has no per-road shapes to measure). Major
    patches smaller than MAJOR_MIN_AREA are junctions and turning circles of minor streets, and stay minor."""
    if not len(tris):
        return tris, tris
    lo = tris.reshape(-1, 2).min(0) - 2 * res
    hi = tris.reshape(-1, 2).max(0) + 2 * res
    w, h = (np.ceil((hi - lo) / res)).astype(int) + 1
    px = lambda t: [((x - lo[0]) / res, (hi[1] - y) / res) for x, y in t]
    mask = Image.new("1", (int(w), int(h)))
    d = ImageDraw.Draw(mask)
    for t in tris:
        d.polygon(px(t), fill=1)
    edt = distance_transform_edt(np.asarray(mask)) * res
    major = np.zeros(len(tris), bool)
    for i, t in enumerate(tris):
        p = np.array(px(t))
        x0, y0 = np.floor(p.min(0)).astype(int)
        x1, y1 = np.ceil(p.max(0)).astype(int) + 1
        tm = Image.new("1", (x1 - x0, y1 - y0))
        ImageDraw.Draw(tm).polygon([(x - x0, y - y0) for x, y in p], fill=1)
        inside = np.asarray(tm)
        major[i] = inside.any() and 2.0 * edt[y0:y1, x0:x1][inside].max() >= MAJOR_WIDTH_M
    if major.any():
        polys = shapely.polygons(np.concatenate([tris[major], tris[major][:, :1]], axis=1).astype(np.float64))
        parts = list(shapely.get_parts(shapely.union_all(shapely.buffer(polys, 0.05))))
        small = [p for p in parts if p.area < MAJOR_MIN_AREA]
        if small:
            c = tris[major].mean(axis=1)
            demote = shapely.contains_xy(shapely.union_all(small), c[:, 0], c[:, 1])
            major[np.flatnonzero(major)[demote]] = False
    return tris[~major], tris[major]


def road_tris(mesh_dir: Path) -> np.ndarray:
    """World-xy triangles of 3dmap_roads (finest LOD); the mesh turns 180 degrees about Z (heightmap.MESHES)."""
    from nmtiles.heightmap import MESHES, _mesh_tris
    flip, offset = MESHES["3dmap_roads"]
    return _mesh_tris(mesh_dir / "3dmap_roads.glb", flip, offset)[:, :, :2].astype(np.float32)


def ensure_sources(game: Path, out: Path, log: Callable[[str], None] = print) -> tuple[Path, Path]:
    """(mesh_dir, data_dir) under the build dir, exported from the game with WolvenKit when missing."""
    from nmtiles.export import export_building_data, export_meshes
    from nmtiles.minimap import wolvenkit_exe
    mesh_dir, data_dir = out / MESH_DIR, out / DATA_DIR
    if not (mesh_dir / "3dmap_roads.glb").exists():
        log(f"dogtown: exporting the 3D-map meshes into {out / 'meshes'}")
        export_meshes(game, out / "meshes", wolvenkit_exe())
    if not (data_dir / "3dmap_triangle_soup.mesh.json").exists():
        log(f"dogtown: exporting the building point clouds into {data_dir}")
        export_building_data(game, data_dir, wolvenkit_exe())
    return mesh_dir, data_dir
