"""Dogtown from the vanilla 3D map.

Phantom Liberty re-cooked Dogtown's streaming sectors without any MinimapDataNode, and the base-game copies they
replace still hold the old Combat Zone layout. The only Dogtown geometry that matches the game is the vanilla 3D map:
the ``ep1_dogtown`` building point cloud (buildings.py) and the ``3dmap_roads`` mesh. Inside the district (a region
grown from its building boxes), the minimap triangles are dropped and the boxes join the building triangles the
footprints are cut from. The road mesh supplies every road of the city, Dogtown's included (vanilla_roads.py).
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Callable

import numpy as np
import shapely
from PIL import Image, ImageDraw
from scipy.ndimage import distance_transform_edt

from nmtiles import buildings
from nmtiles.minimap import MAJOR_WIDTH_M

DISTRICT = "ep1_dogtown"
REGION_BUFFER = 25.0    # m around each building box: covers the streets between them and the one along the wall
REGION_CLOSE = 60.0     # m closing: joins the blocks across the widest boulevard and plaza
WIDTH_RES = 1.0         # m per pixel of the road-width raster
MAJOR_MIN_AREA = 2000.0  # m2: a wide patch smaller than this (a junction, a turning circle) is not a major road
MESH_DIR = Path("meshes/base/entities/cameras/3dmap")   # under the build dir, as nmtiles.export writes it
DATA_DIR = Path("bdata")


def box_tris(b: buildings.Boxes) -> np.ndarray:
    """(2N,3,2) float32: two triangles per box footprint."""
    c = buildings.box_corners(b)
    return np.concatenate([c[:, [0, 1, 2]], c[:, [0, 2, 3]]]).astype(np.float32)


def region(b: buildings.Boxes):
    """The district as a shapely geometry: the box footprints grown by REGION_BUFFER, closed, holes filled."""
    polys = shapely.polygons(buildings.box_corners(b))
    g = shapely.union_all(shapely.buffer(polys, REGION_BUFFER, quad_segs=2))
    r = REGION_CLOSE / 2
    g = g.buffer(r, join_style="mitre").buffer(-r, join_style="mitre")
    return shapely.union_all([shapely.Polygon(p.exterior) for p in shapely.get_parts(g)
                              if p.geom_type == "Polygon" and not p.is_empty])


def drop_inside(tris: np.ndarray, g) -> np.ndarray:
    """The triangles whose centre lies outside g."""
    if not len(tris):
        return tris
    c = tris.mean(axis=1)
    return tris[~shapely.contains_xy(g, c[:, 0], c[:, 1])]


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


def district_boxes(data_dir: Path) -> buildings.Boxes:
    mesh = json.loads((data_dir / "3dmap_triangle_soup.mesh.json").read_text())
    mat = buildings.parse_materials(mesh)[DISTRICT]
    offset = buildings.parse_offsets(json.loads((data_dir / "3dmap_view.ent.json").read_text()))[DISTRICT]
    return buildings.decode_boxes(json.loads((data_dir / f"{mat.texture}.xbm.json").read_text()), mat, offset)


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


def apply(city: dict[str, np.ndarray], mesh_dir: Path, data_dir: Path,
          log: Callable[[str], None] = print) -> dict[str, np.ndarray]:
    """city with Dogtown's minimap triangles replaced by the 3D map's building boxes. Its roads, like every other
    road, come from the 3D map's road mesh (vanilla_roads), which runs after this."""
    boxes = district_boxes(data_dir)
    g = region(boxes)
    out = {k: drop_inside(v, g) for k, v in city.items()}
    dropped = {k: len(city[k]) - len(out[k]) for k in city}
    out["stroke"] = np.concatenate([out["stroke"], box_tris(boxes)])
    log(f"dogtown: region {g.area / 1e6:.2f} km2; dropped minimap {dropped}; added {len(boxes)} boxes")
    return out
