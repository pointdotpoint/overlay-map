"""End-to-end tile build: minimap + 3D-map meshes -> colourless mask tile sets -> BC7 tiles + UI atlas -> NightMap.archive + manifest."""
from __future__ import annotations

import argparse
import json
import shutil
import sys
import time
from pathlib import Path

import numpy as np

from nmtiles.buildings import Boxes
from nmtiles.encode import encode_bc7
from nmtiles.export import export_building_data, export_meshes, style_for
from nmtiles.glb import keep_best_lod, read_glb
from nmtiles.manifest import emit_manifest
from nmtiles.minimap import load_city
from nmtiles.pack import deserialize_all, pack_archive, write_resource
from nmtiles.preview import write_previews
from nmtiles.render import level_grid
from nmtiles.render_minimap import SETS, make_sources, png_name, render_level_tiles
from nmtiles.resources import make_inkatlas_json, make_xbm_json
from nmtiles.ui_atlas import build_ui_atlas
from nmtiles.world import Transform

HERE = Path(__file__).resolve().parents[1]
REPO = HERE.parents[1]
TPL = HERE / "templates"


def require_boxes(boxes: Boxes) -> Boxes:
    if len(boxes) == 0:
        raise SystemExit("error: no building boxes were loaded; the tiles would have no buildings")
    return boxes


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--game", type=Path, default=Path.home() / "cyberpunk_symlink")
    ap.add_argument("--out", type=Path, default=HERE / "build")
    ap.add_argument("--levels", default="0.5,1,2,4,8,16")
    ap.add_argument("--skip-export", action="store_true", help="reuse build/meshes and build/bdata")
    ap.add_argument("--game-version", default="2.31")
    args = ap.parse_args(argv)
    t_start = time.time()
    game = args.game.resolve()
    out = args.out
    mesh_dir = out / "meshes"
    bdata_dir = out / "bdata"
    if not args.skip_export:
        shutil.rmtree(mesh_dir, ignore_errors=True)
        export_meshes(game, mesh_dir)
        export_building_data(game, bdata_dir)

    if args.skip_export and not (bdata_dir / "3dmap_view.ent.json").exists():
        raise SystemExit(f"error: --skip-export but {bdata_dir} has no building data; "
                         f"run once without --skip-export (export_building_data fills it)")
    styled: dict[str, list] = {}
    for p in sorted(mesh_dir.rglob("*.glb")):
        style = style_for(p.stem)
        if style:
            styled.setdefault(style, []).extend(keep_best_lod(read_glb(p)))
    tf = Transform.load(HERE / "calibration.json")
    world = np.vstack([tf.apply(m.positions) for s in ("land", "road") for m in styled.get(s, [])])
    city = load_city(game, out / "minimap_cache")
    mm = np.concatenate([city["road"].reshape(-1, 2), city["stroke"].reshape(-1, 2)])
    bounds = (float(min(world[:, 0].min(), mm[:, 0].min())), float(min(world[:, 1].min(), mm[:, 1].min())),
              float(max(world[:, 0].max(), mm[:, 0].max())), float(max(world[:, 1].max(), mm[:, 1].max())))
    del world, mm
    print(f"styles={ {k: len(v) for k, v in styled.items()} } road tris={len(city['road'])} stroke tris={len(city['stroke'])} "
          f"bounds={bounds} transform={tf}", flush=True)

    png_dir = out / "png"
    shutil.rmtree(png_dir, ignore_errors=True)
    png_dir.mkdir(parents=True)
    levels = []
    set_pngs: dict[str, dict[tuple[int, int, int], Path]] = {s: {} for s in SETS}
    for li, mpp in enumerate(float(x) for x in args.levels.split(",")):
        t_lv = time.time()
        grid = level_grid(bounds, mpp)
        src = make_sources(city, styled, tf, max(grid.tile_world, 256.0))
        tiles = render_level_tiles(src, grid, li, png_dir)
        del src
        for s, cells in tiles.items():
            for ix, iy in cells:
                set_pngs[s][(li, ix, iy)] = png_dir / png_name(s, li, ix, iy)
        levels.append({"mpp": mpp, "origin_x": grid.origin_x, "origin_top": grid.origin_top,
                       "nx": grid.nx, "ny": grid.ny, "tiles": tiles})
        print(f"level {li}: {mpp} m/px grid {grid.nx}x{grid.ny} tiles " +
              " ".join(f"{s}={len(tiles.get(s, []))}" for s in SETS) + f" ({time.time() - t_lv:.0f}s)", flush=True)
    print("tiles per set: " + " ".join(f"{s}={len(set_pngs[s])}" for s in SETS), flush=True)

    for p in write_previews(levels, set_pngs, out):
        print(f"preview {p}")

    ui_img, ui_parts = build_ui_atlas()
    ui_png = png_dir / "ui.png"
    ui_img.save(ui_png)

    all_pngs = [p for s in SETS for p in set_pngs[s].values()]
    payloads = encode_bc7(all_pngs + [ui_png], out / "dds")
    xbm_t = json.loads((TPL / "tile.xbm.json").read_text())
    atl_t = json.loads((TPL / "atlas.inkatlas.json").read_text())
    ws = out / "workspace"
    shutil.rmtree(ws, ignore_errors=True)
    for s in SETS:
        for (li, ix, iy), p in set_pngs[s].items():
            base = f"nightmap\\tiles\\{s}\\L{li}\\t_{ix}_{iy}"
            write_resource(ws, base + ".xbm", make_xbm_json(xbm_t, 512, 512, payloads[p]))
            write_resource(ws, base + ".inkatlas",
                           make_inkatlas_json(atl_t, base + ".xbm", {"full": (0, 0, 512, 512)}, 512, 512))
    write_resource(ws, "nightmap\\ui\\ui.xbm", make_xbm_json(xbm_t, 1024, 1024, payloads[ui_png]))
    write_resource(ws, "nightmap\\ui\\ui.inkatlas",
                   make_inkatlas_json(atl_t, "nightmap\\ui\\ui.xbm", ui_parts, 1024, 1024))

    deserialize_all(ws)
    archive = pack_archive(ws, REPO / "archive" / "pc" / "mod" / "NightMap.archive")
    manifest = REPO / "r6" / "scripts" / "NightMap" / "Generated" / "TileManifest.reds"
    manifest.parent.mkdir(parents=True, exist_ok=True)
    manifest.write_text(emit_manifest(levels, bounds, args.game_version, SETS))
    mb = archive.stat().st_size / 1e6
    print(f"archive {archive} {mb:.1f} MB; manifest {manifest}")
    print(f"total wall time {time.time() - t_start:.0f}s")
    if mb > 250:
        print("WARNING: archive exceeds the 250 MB target; rebuild with the finest level at 0.75 m/px (spec 11.2)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
