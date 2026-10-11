"""End-to-end tile build: meshes -> styled raster levels -> BC7 tiles + UI atlas -> NightMap.archive + manifest."""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

import numpy as np

from nmtiles.buildings import load_boxes
from nmtiles.encode import encode_bc7
from nmtiles.export import export_building_data, export_meshes, style_for
from nmtiles.glb import keep_best_lod, read_glb
from nmtiles.manifest import emit_manifest
from nmtiles.pack import deserialize_all, pack_archive, write_resource
from nmtiles.preview import write_previews
from nmtiles.render import level_grid, render_level, slice_tiles
from nmtiles.resources import make_inkatlas_json, make_xbm_json
from nmtiles.ui_atlas import build_ui_atlas
from nmtiles.world import Transform

HERE = Path(__file__).resolve().parents[1]
REPO = HERE.parents[1]
TPL = HERE / "templates"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--game", type=Path, default=Path.home() / "cyberpunk_symlink")
    ap.add_argument("--out", type=Path, default=HERE / "build")
    ap.add_argument("--levels", default="2,4,8,16")
    ap.add_argument("--skip-export", action="store_true", help="reuse build/meshes and build/bdata")
    ap.add_argument("--game-version", default="2.31")
    args = ap.parse_args(argv)
    game = args.game.resolve()
    out = args.out
    mesh_dir = out / "meshes"
    bdata_dir = out / "bdata"
    if not args.skip_export:
        shutil.rmtree(mesh_dir, ignore_errors=True)
        export_meshes(game, mesh_dir)
        export_building_data(game, bdata_dir)

    styled: dict[str, list] = {}
    for p in sorted(mesh_dir.rglob("*.glb")):
        style = style_for(p.stem)
        if style:
            styled.setdefault(style, []).extend(keep_best_lod(read_glb(p)))
    boxes = load_boxes(bdata_dir)     # world-space already: never goes through the mesh Transform
    tf = Transform.load(HERE / "calibration.json")
    world = np.vstack([tf.apply(m.positions) for s in ("land", "road") for m in styled.get(s, [])])
    bounds = (float(world[:, 0].min()), float(world[:, 1].min()), float(world[:, 0].max()), float(world[:, 1].max()))
    print(f"styles={ {k: len(v) for k, v in styled.items()} } boxes={len(boxes)} bounds={bounds} transform={tf}")

    png_dir = out / "png"
    shutil.rmtree(png_dir, ignore_errors=True)
    png_dir.mkdir(parents=True)
    levels, tile_pngs = [], []
    for li, mpp in enumerate(float(x) for x in args.levels.split(",")):
        grid = level_grid(bounds, mpp)
        tiles = slice_tiles(render_level(styled, tf, grid, boxes), grid)
        for (ix, iy), img in tiles.items():
            p = png_dir / f"L{li}_t_{ix}_{iy}.png"
            img.save(p)
            tile_pngs.append((li, ix, iy, p))
        levels.append({"mpp": mpp, "origin_x": grid.origin_x, "origin_top": grid.origin_top,
                       "nx": grid.nx, "ny": grid.ny, "tiles": sorted(tiles)})
        print(f"level {li}: {mpp} m/px grid {grid.nx}x{grid.ny} tiles={len(tiles)}", flush=True)

    for p in write_previews(levels, tile_pngs, out):
        print(f"preview {p}")

    ui_img, ui_parts = build_ui_atlas()
    ui_png = png_dir / "ui.png"
    ui_img.save(ui_png)

    payloads = encode_bc7([p for *_, p in tile_pngs] + [ui_png], out / "dds")
    xbm_t = json.loads((TPL / "tile.xbm.json").read_text())
    atl_t = json.loads((TPL / "atlas.inkatlas.json").read_text())
    ws = out / "workspace"
    shutil.rmtree(ws, ignore_errors=True)
    for li, ix, iy, p in tile_pngs:
        base = f"nightmap\\tiles\\L{li}\\t_{ix}_{iy}"
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
    manifest.write_text(emit_manifest(levels, bounds, args.game_version))
    mb = archive.stat().st_size / 1e6
    print(f"archive {archive} {mb:.1f} MB; manifest {manifest}")
    if mb > 60:
        print("WARNING: archive exceeds the 60 MB target")
    return 0


if __name__ == "__main__":
    sys.exit(main())
