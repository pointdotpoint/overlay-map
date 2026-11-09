"""End-to-end tile build: the vanilla 3D map's roads (3dmap_roads) and building boxes (district point clouds) -> lit building and mask tile sets -> BC7 tiles + UI atlas -> OverlayMap.archive + manifest."""
from __future__ import annotations

import argparse
import json
import os
import shutil
import re
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image

from nmtiles.encode import encode_bc7
from nmtiles.holo_atlas import build_holo_atlas
from nmtiles.holo_preview import write_holo_previews
from nmtiles.manifest import emit_manifest
from nmtiles import dogtown, lit, ncart, vanilla_buildings, vanilla_roads
from nmtiles.pack import deserialize_all, pack_archive, write_resource
from nmtiles.preview import write_previews
from nmtiles.render import level_grid
from nmtiles.render_minimap import SETS, make_sources, png_name, render_level_tiles
from nmtiles.resources import make_inkatlas_json, make_xbm_json
from nmtiles.ui_atlas import build_ui_atlas
from nmtiles.welcome_atlas import build_welcome_atlas

HERE = Path(__file__).resolve().parents[1]
REPO = HERE.parents[1]
TPL = HERE / "templates"
GLOW_TEX = 256     # glow tile texture size (other sets are 512)


COLLECT_DATA = Path(__file__).resolve().parents[3] / "r6/scripts/OverlayMap/Generated/CollectData.reds"
WORLD_MARGIN = 250.0   # metres of open map around the outermost geometry or pin


def collect_spots(path: Path) -> np.ndarray:
    """(x, y) of every collectible in the generated CollectData.reds ("C,x,y,z,record;..." strings)."""
    pts = re.findall(r"(?:^|[\";])[A-Z],(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?),-?\d+(?:\.\d+)?,", Path(path).read_text(), re.M)
    return np.array(pts, np.float64).reshape(-1, 2)


def world_bounds(point_sets: list[np.ndarray], margin: float) -> tuple[float, float, float, float]:
    pts = np.concatenate([np.asarray(p, np.float64).reshape(-1, 2) for p in point_sets if len(p)])
    return (float(pts[:, 0].min()) - margin, float(pts[:, 1].min()) - margin,
            float(pts[:, 0].max()) + margin, float(pts[:, 1].max()) + margin)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--game", type=Path, default=Path.home() / "cyberpunk_symlink")
    ap.add_argument("--out", type=Path, default=HERE / "build")
    ap.add_argument("--levels", default="0.5,1,2,4,8,16")
    ap.add_argument("--skip-export", action="store_true", help="accepted for compatibility; the build no longer reads 3D-map meshes")
    ap.add_argument("--jobs", type=int, default=4, help="workers for every process pool (BC7 encoding uses min(jobs, 2))")
    ap.add_argument("--game-version", default="2.5")   # the game version the tiles are built from
    ap.add_argument("--ui-only", action="store_true", help="re-render only the UI and holo atlases into the last build's workspace and repack")
    args = ap.parse_args(argv)
    if args.ui_only:
        return ui_only(args.out, args.jobs)
    t_start = time.time()
    os.nice(19)
    game = args.game.resolve()
    out = args.out
    # Everything is drawn from the vanilla world map's own data, so the map matches it (review 2026-11-05).
    mesh_dir, data_dir = dogtown.ensure_sources(game, out)
    none = np.zeros((0, 3, 2), np.float32)
    city = vanilla_roads.apply_from_mesh({"road": none, "road_major": none, "stroke": none}, mesh_dir)
    boxes = lit.lit_boxes(vanilla_buildings.district_boxes(data_dir))
    if not len(boxes):
        raise SystemExit("error: no building boxes were loaded")
    # The world also covers every collectible pin (some lie off the coast, past every road and building) plus a margin,
    # or the map would reject those pins and stop panning short of them.
    bounds = world_bounds([boxes.quads.reshape(-1, 2), city["road"].reshape(-1, 2), city["road_major"].reshape(-1, 2),
                           collect_spots(COLLECT_DATA)], margin=WORLD_MARGIN)
    print(f"road tris={len(city['road'])} major={len(city['road_major'])} building boxes={len(boxes)} "
          f"bounds={bounds}", flush=True)

    net = ncart.Network.from_game(mesh_dir / "3dmap_metro.glb")
    print(f"ncart: {len(net.lines)} lines, {len(net.connectors)} station connectors", flush=True)
    png_dir = out / "png"
    shutil.rmtree(png_dir, ignore_errors=True)
    png_dir.mkdir(parents=True)
    levels = []
    set_pngs: dict[str, dict[tuple[int, int, int], Path]] = {s: {} for s in SETS}
    for li, mpp in enumerate(float(x) for x in args.levels.split(",")):
        t_lv = time.time()
        grid = level_grid(bounds, mpp)
        src = make_sources(city["road"], boxes, max(grid.tile_world, 256.0), city["road_major"])
        src.metro = ncart.level_paths(net, mpp)
        tiles = render_level_tiles(src, grid, li, png_dir, args.jobs)
        del src
        for s, cells in tiles.items():
            for ix, iy in cells:
                set_pngs[s][(li, ix, iy)] = png_dir / png_name(s, li, ix, iy)
        levels.append({"mpp": mpp, "origin_x": grid.origin_x, "origin_top": grid.origin_top,
                       "nx": grid.nx, "ny": grid.ny, "tiles": tiles})
        print(f"level {li}: {mpp} m/px grid {grid.nx}x{grid.ny} tiles " +
              " ".join(f"{s}={len(tiles.get(s, []))}" for s in SETS) + f" ({time.time() - t_lv:.0f}s)", flush=True)
    print("tiles per set: " + " ".join(f"{s}={len(set_pngs[s])}" for s in SETS), flush=True)

    # Glow tiles are soft: ship them at half resolution (the runtime stretches every tile image to 512 units).
    for p in set_pngs["glow"].values():
        Image.open(p).resize((GLOW_TEX, GLOW_TEX), Image.BOX).save(p, compress_level=3)
    for p in write_previews(levels, set_pngs, out):
        print(f"preview {p}")

    ui_img, ui_parts = build_ui_atlas()
    ui_png = png_dir / "ui.png"
    ui_img.save(ui_png)

    holo_img, holo_parts = build_holo_atlas()
    holo_png = png_dir / "holo.png"
    holo_img.save(holo_png)
    for p in write_holo_previews(levels, set_pngs, out):
        print(f"preview {p}")

    all_pngs = [p for s in SETS for p in set_pngs[s].values()]
    wel_img, wel_parts = build_welcome_atlas()
    wel_png = png_dir / "welcome.png"
    wel_img.save(wel_png)
    payloads = encode_bc7(all_pngs + [ui_png, holo_png, wel_png], out / "dds", min(args.jobs, 2))
    xbm_t = json.loads((TPL / "tile.xbm.json").read_text())
    atl_t = json.loads((TPL / "atlas.inkatlas.json").read_text())
    ws = out / "workspace"
    shutil.rmtree(ws, ignore_errors=True)
    for s in SETS:
        for (li, ix, iy), p in set_pngs[s].items():
            base = f"overlaymap\\tiles\\{s}\\L{li}\\t_{ix}_{iy}"
            tex = GLOW_TEX if s == "glow" else 512
            write_resource(ws, base + ".xbm", make_xbm_json(xbm_t, tex, tex, payloads[p]))
            write_resource(ws, base + ".inkatlas",
                           make_inkatlas_json(atl_t, base + ".xbm", {"full": (0, 0, tex, tex)}, tex, tex))
    write_resource(ws, "overlaymap\\ui\\ui.xbm", make_xbm_json(xbm_t, 1024, 1024, payloads[ui_png]))
    write_resource(ws, "overlaymap\\ui\\ui.inkatlas",
                   make_inkatlas_json(atl_t, "overlaymap\\ui\\ui.xbm", ui_parts, 1024, 1024))
    write_resource(ws, "overlaymap\\ui\\holo.xbm", make_xbm_json(xbm_t, holo_img.width, holo_img.height, payloads[holo_png]))
    write_resource(ws, "overlaymap\\ui\\holo.inkatlas",
                   make_inkatlas_json(atl_t, "overlaymap\\ui\\holo.xbm", holo_parts, holo_img.width, holo_img.height))
    write_resource(ws, "overlaymap\\ui\\welcome.xbm", make_xbm_json(xbm_t, wel_img.width, wel_img.height, payloads[wel_png]))
    write_resource(ws, "overlaymap\\ui\\welcome.inkatlas",
                   make_inkatlas_json(atl_t, "overlaymap\\ui\\welcome.xbm", wel_parts, wel_img.width, wel_img.height))

    deserialize_all(ws)
    archive = pack_archive(ws, REPO / "archive" / "pc" / "mod" / "OverlayMap.archive")
    manifest = REPO / "r6" / "scripts" / "OverlayMap" / "Generated" / "TileManifest.reds"
    manifest.parent.mkdir(parents=True, exist_ok=True)
    manifest.write_text(emit_manifest(levels, bounds, args.game_version, SETS))
    mb = archive.stat().st_size / 1e6
    print(f"archive {archive} {mb:.1f} MB; manifest {manifest}")
    print(f"total wall time {time.time() - t_start:.0f}s")
    if mb > 250:
        print("WARNING: archive exceeds the 250 MB target; rebuild with the finest level at 0.75 m/px (spec 11.2)")
    return 0


def write_ui(ws: Path, png_dir: Path, dds: Path, jobs: int) -> None:
    """The UI and holo atlases: render, encode and write their resources into the workspace."""
    ui_img, ui_parts = build_ui_atlas()
    ui_png = png_dir / "ui.png"
    ui_img.save(ui_png)
    holo_img, holo_parts = build_holo_atlas()
    holo_png = png_dir / "holo.png"
    holo_img.save(holo_png)
    wel_img, wel_parts = build_welcome_atlas()
    wel_png = png_dir / "welcome.png"
    wel_img.save(wel_png)
    payloads = encode_bc7([ui_png, holo_png, wel_png], dds, min(jobs, 2))
    xbm_t = json.loads((TPL / "tile.xbm.json").read_text())
    atl_t = json.loads((TPL / "atlas.inkatlas.json").read_text())
    write_resource(ws, "overlaymap\\ui\\welcome.xbm", make_xbm_json(xbm_t, wel_img.width, wel_img.height, payloads[wel_png]))
    write_resource(ws, "overlaymap\\ui\\welcome.inkatlas",
                   make_inkatlas_json(atl_t, "overlaymap\\ui\\welcome.xbm", wel_parts, wel_img.width, wel_img.height))
    write_resource(ws, "overlaymap\\ui\\ui.xbm", make_xbm_json(xbm_t, 1024, 1024, payloads[ui_png]))
    write_resource(ws, "overlaymap\\ui\\ui.inkatlas", make_inkatlas_json(atl_t, "overlaymap\\ui\\ui.xbm", ui_parts, 1024, 1024))
    write_resource(ws, "overlaymap\\ui\\holo.xbm", make_xbm_json(xbm_t, holo_img.width, holo_img.height, payloads[holo_png]))
    write_resource(ws, "overlaymap\\ui\\holo.inkatlas",
                   make_inkatlas_json(atl_t, "overlaymap\\ui\\holo.xbm", holo_parts, holo_img.width, holo_img.height))


def ui_only(out: Path, jobs: int) -> int:
    """Repack the archive with fresh UI atlases, keeping the tiles a full build left in out/workspace."""
    ws = out / "workspace"
    if not (ws / "overlaymap" / "tiles").is_dir():
        raise SystemExit(f"error: no tiles in {ws}; run a full build first")
    png_dir = out / "png"
    png_dir.mkdir(parents=True, exist_ok=True)
    write_ui(ws, png_dir, out / "dds", jobs)
    deserialize_all(ws)
    archive = pack_archive(ws, REPO / "archive" / "pc" / "mod" / "OverlayMap.archive")
    print(f"archive {archive} {archive.stat().st_size / 1e6:.1f} MB (UI atlases only)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
