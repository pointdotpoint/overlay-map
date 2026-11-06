"""Roads from the vanilla world map's road mesh, city-wide.

The vanilla world map draws its roads from one mesh, ``3dmap_roads``. The minimap data the rest of the map comes from
disagrees with it in places: at Border Crossing the minimap tags the highway through the checkpoint as wall lines, so
the road broke off there; parts of Pacifica have no minimap roads at all; and widths differ. Measured 2026-11-05 at
4 m/px, about 15% of each set's road area is missing from the other. Every road triangle therefore comes from the
mesh, so the road network matches the vanilla map exactly. Buildings come from vanilla_buildings.py.
"""
from __future__ import annotations

from pathlib import Path
from typing import Callable

import numpy as np

from nmtiles.dogtown import road_tris, split_major


def apply(city: dict[str, np.ndarray], roads: np.ndarray,
          log: Callable[[str], None] = print) -> dict[str, np.ndarray]:
    """city with both road sets replaced by ``roads`` (world-xy triangles), split into minor and major by width."""
    roads = np.asarray(roads, np.float32)
    minor, major = split_major(roads)
    out = dict(city)
    out["road"], out["road_major"] = minor.astype(np.float32), major.astype(np.float32)
    log(f"vanilla roads: mesh roads minor {len(minor)} major {len(major)} "
        f"(replacing {len(city['road'])} + {len(city['road_major'])} road triangles)")
    return out


def apply_from_mesh(city: dict[str, np.ndarray], mesh_dir: Path,
                    log: Callable[[str], None] = print) -> dict[str, np.ndarray]:
    return apply(city, road_tris(mesh_dir), log)
