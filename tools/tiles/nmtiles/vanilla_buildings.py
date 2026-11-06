"""Buildings from the vanilla world map's building boxes, city-wide.

The vanilla world map draws every building from its district point clouds: one box per building part (buildings.py).
The minimap data the map used before merged whole blocks into large outlines, filled ground the vanilla map leaves
empty and left dense blocks bare (review 2026-11-05). Every building now comes from those boxes, so the buildings
match the vanilla map, including where it has few. lit.py draws them as a lit 3D city seen from above.
"""
from __future__ import annotations

import json
from pathlib import Path

from nmtiles import buildings

SKIP = ("ep1_spaceport",)      # off the playable map


def district_boxes(data_dir: Path) -> dict[str, buildings.Boxes]:
    """Every district's boxes from the 3D map's point clouds."""
    mats = buildings.parse_materials(json.loads((data_dir / "3dmap_triangle_soup.mesh.json").read_text()))
    offsets = buildings.parse_offsets(json.loads((data_dir / "3dmap_view.ent.json").read_text()))
    return {name: buildings.decode_boxes(json.loads((data_dir / f"{mat.texture}.xbm.json").read_text()), mat, offsets[name])
            for name, mat in mats.items() if name not in SKIP}

