"""End-to-end tile build: minimap buildings + the 3D map's roads (+ Dogtown's buildings from the 3D map) -> footprints -> colourless mask tile sets -> BC7 tiles + UI atlas -> OverlayMap.archive + manifest."""
from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image

from nmtiles.encode import encode_bc7
from nmtiles.holo_atlas import build_holo_atlas
from nmtiles.holo_preview import write_holo_previews
from nmtiles.manifest import emit_manifest
from nmtiles import boxfill, dogtown, ncart, vanilla_roads
from nmtiles.footprints import load_or_build
from nmtiles.minimap import load_city
from nmtiles.pack import deserialize_all, pack_archive, write_resource
from nmtiles.preview import write_previews
from nmtiles.render import level_grid
from nmtiles.render_minimap import SETS, make_sources, png_name, render_level_tiles
from nmtiles.resources import make_inkatlas_json, make_xbm_json
from nmtiles.ui_atlas import build_ui_atlas

HERE = Path(__file__).resolve().parents[1]
REPO = HERE.parents[1]
TPL = HERE / "templates"
GLOW_TEX = 256     # glow tile texture size (other sets are 512)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--game", type=Path, default=Path.home() / "cyberpunk_symlink")
    ap.add_argument("--out", type=Path, default=HERE / "build")
    ap.add_argument("--levels", default="0.5,1,2,4,8,16")
    ap.add_argument("--skip-export", action="store_true", help="accepted for compatibility; the build no longer reads 3D-map meshes")
    ap.add_argument("--jobs", type=int, default=4, help="workers for every process pool (BC7 encoding uses min(jobs, 2))")
    ap.add_argument("--game-version", default="2.31")
    ap.add_argument("--ui-only", action="store_true", help="re-render only the UI and holo atlases into the last build's workspace and repack")
    args = ap.parse_args(argv)
    if args.ui_only:
        return ui_only(args.out, args.jobs)
    t_start = time.time()
    os.nice(19)
    game = args.game.resolve()
    out = args.out
    city = load_city(game, out / "minimap_cache", workers=args.jobs)
    mesh_dir, data_dir = dogtown.ensure_sources(game, out)
    city = dogtown.apply(city, mesh_dir, data_dir)
    city = vanilla_roads.apply_from_mesh(city, mesh_dir)
    city = boxfill.apply(city, boxfill.district_boxes(data_dir))
    fp = load_or_build(city["road"], city["stroke"], out / "minimap_cache" / "footprints.npz", args.jobs,
                         road_major=city["road_major"])
    if not fp.polys:
        raise SystemExit("error: no building footprints were produced")
    pts = np.concatenate(fp.polys + [city["road"].reshape(-1, 2), city["road_major"].reshape(-1, 2)])
    bounds = (float(pts[:, 0].min()), float(pts[:, 1].min()), float(pts[:, 0].max()), float(pts[:, 1].max()))
    del pts
    print(f"road tris={len(city['road'])} major={len(city['road_major'])} building tris={len(city['stroke'])} footprints={len(fp.polys)} "
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
        src = make_sources(city["road"], fp.polys, max(grid.tile_world, 256.0), city["road_major"])
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
    payloads = encode_bc7(all_pngs + [ui_png, holo_png], out / "dds", min(args.jobs, 2))
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
    payloads = encode_bc7([ui_png, holo_png], dds, min(jobs, 2))
    xbm_t = json.loads((TPL / "tile.xbm.json").read_text())
    atl_t = json.loads((TPL / "atlas.inkatlas.json").read_text())
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
