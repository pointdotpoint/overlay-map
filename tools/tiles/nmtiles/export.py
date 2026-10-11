"""Export the vanilla 3D-map meshes to GLB with WolvenKit CLI and classify them by style."""
from __future__ import annotations

import subprocess
from pathlib import Path

MESH_REGEX = r"base\\entities\\cameras\\3dmap\\[^\\]+\.mesh$"
_EXACT = {
    "3dmap_terrain": "land",
    "3dmap_water": "water",
    "3dmap_cliffs": "cliff",
    "3dmap_roads": "road",
    "3dmap_roads_borders": "road_border",
    "3dmap_metro": "metro",
}


def style_for(stem: str) -> str | None:
    n = stem.lower()
    if n.startswith("3dmap_coll_") or n.startswith("mappin_geo") or n == "3dmap_cursor":
        return None
    return _EXACT.get(n, "building")


def export_meshes(game_dir: Path, out_dir: Path, wolvenkit: str = "WolvenKit.CLI") -> list[Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    for sub in ("content", "ep1"):
        archives = game_dir / "archive" / "pc" / sub
        if not archives.is_dir():
            continue
        subprocess.run([wolvenkit, "uncook", str(archives), "-r", MESH_REGEX, "-o", str(out_dir),
                        "-gp", str(game_dir)], check=True, stdout=subprocess.DEVNULL)
    glbs = sorted(out_dir.rglob("*.glb"))
    if not glbs:
        raise RuntimeError(f"WolvenKit exported no meshes into {out_dir}")
    return glbs
