"""Export the vanilla 3D-map meshes to GLB with WolvenKit CLI and classify them by style."""
from __future__ import annotations

import shutil
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
# Local-space props placed at the origin: not usable as map geometry (buildings come from the point clouds).
_LOCAL_PROPS = {
    "3dmap_triangle_soup", "3dmap_ext_monument_av_building_b", "3dmap_obelisk", "3dmap_statue_splash_a",
    "cz_cz_building_h_icosphere", "monument_ave_pyramid", "northoak_sign_a", "rcr_park_ferris_wheel",
}
# Building point-cloud sources: district materials, district offsets and the per-district data textures.
BUILDING_REGEX = (r"base\\entities\\cameras\\3dmap\\(3dmap_triangle_soup\.mesh|3dmap_view\.ent)$"
                  r"|base\\fx\\textures\\3dmap\\static\\[^\\]+_data\.xbm$")
BUILDING_JSON_REGEX = r"(3dmap_triangle_soup\.mesh|3dmap_view\.ent|[^\\/]+_data\.xbm)$"


def style_for(stem: str) -> str | None:
    n = stem.lower()
    if n.startswith("3dmap_coll_") or n.startswith("mappin_geo") or n == "3dmap_cursor":
        return None
    if n in _LOCAL_PROPS:
        return None
    style = _EXACT.get(n)
    if style is None:
        print(f"export: no style for mesh {stem}; skipped", flush=True)
    return style


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


def export_building_data(game_dir: Path, out_dir: Path, wolvenkit: str = "WolvenKit.CLI") -> Path:
    """Extract the building point-cloud sources (ep1 wins over base) and serialize them to flat JSON in out_dir."""
    raw = out_dir.parent / (out_dir.name + "_raw")
    shutil.rmtree(raw, ignore_errors=True)
    shutil.rmtree(out_dir, ignore_errors=True)
    raw.mkdir(parents=True)
    out_dir.mkdir(parents=True)
    for sub in ("content", "ep1"):
        archives = game_dir / "archive" / "pc" / sub
        if archives.is_dir():
            subprocess.run([wolvenkit, "extract", str(archives), "-r", BUILDING_REGEX, "-o", str(raw),
                            "-gp", str(game_dir)], check=True, stdout=subprocess.DEVNULL)
    subprocess.run([wolvenkit, "convert", "s", str(raw), "-r", BUILDING_JSON_REGEX, "-o", str(out_dir)],
                   check=True, stdout=subprocess.DEVNULL)
    for needed in ("3dmap_triangle_soup.mesh.json", "3dmap_view.ent.json"):
        if not (out_dir / needed).exists():
            raise RuntimeError(f"WolvenKit did not produce {needed} in {out_dir}")
    return out_dir
