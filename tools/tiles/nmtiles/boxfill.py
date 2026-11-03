"""Buildings from the vanilla 3D map where the minimap has none.

Some buildings are only a few unconnected edge lines in the minimap data (west Pacifica, the blocks along Dogtown's
west side, Santo Domingo's yards), so the footprint builder, which fills closed outlines, leaves them empty. The world
map draws them from its building point clouds (one box per building part, buildings.py). Every district's boxes join
the building triangles the footprints are cut from: where the minimap already has the building the union barely
changes, and boxes over a road (gantries, walkways, signs) are cut away with the road like everything else.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Callable

import numpy as np

from nmtiles import buildings
from nmtiles.dogtown import DISTRICT as DOGTOWN, box_tris

# Dogtown's boxes are added (and its minimap replaced) by dogtown.apply; the spaceport set lies off the playable map.
SKIP = (DOGTOWN, "ep1_spaceport")


def district_boxes(data_dir: Path) -> dict[str, buildings.Boxes]:
    """Every district's boxes from the 3D map's point clouds, skipped districts excluded."""
    mats = buildings.parse_materials(json.loads((data_dir / "3dmap_triangle_soup.mesh.json").read_text()))
    offsets = buildings.parse_offsets(json.loads((data_dir / "3dmap_view.ent.json").read_text()))
    return {name: buildings.decode_boxes(json.loads((data_dir / f"{mat.texture}.xbm.json").read_text()), mat, offsets[name])
            for name, mat in mats.items() if name not in SKIP}


def apply(city: dict[str, np.ndarray], boxes: dict[str, buildings.Boxes],
          log: Callable[[str], None] = print) -> dict[str, np.ndarray]:
    """city with the boxes of every non-skipped district added to its building triangles."""
    parts = [box_tris(b) for name, b in sorted(boxes.items()) if name not in SKIP and len(b)]
    out = dict(city)
    if parts:
        out["stroke"] = np.concatenate([city["stroke"]] + parts).astype(np.float32)
    log(f"boxfill: added {sum(len(p) for p in parts) // 2} 3D-map boxes from {len(parts)} districts")
    return out
