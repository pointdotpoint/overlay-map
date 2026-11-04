"""Rebuild only the hologram overlay atlas and repack OverlayMap.archive, reusing the last full build's workspace.

The full build (nmtiles.build) re-renders every map tile; this skips that when only holo_atlas.py changed.
Run from tools/tiles: python -m nmtiles.holo_repack
"""
from __future__ import annotations

import json
import sys

from nmtiles.build import HERE, REPO, TPL
from nmtiles.encode import encode_bc7
from nmtiles.holo_atlas import build_holo_atlas
from nmtiles.pack import deserialize_all, pack_archive, write_resource
from nmtiles.resources import make_inkatlas_json, make_xbm_json


def main() -> int:
    out = HERE / "build"
    ws = out / "workspace"
    ui = ws / "overlaymap" / "ui"
    if not (ws / "overlaymap" / "tiles").is_dir() or not ui.is_dir():
        raise SystemExit(f"error: no workspace from a full build under {ws}; run python -m nmtiles.build first")
    img, parts = build_holo_atlas()
    png = out / "png" / "holo.png"
    png.parent.mkdir(parents=True, exist_ok=True)
    img.save(png)
    payloads = encode_bc7([png], out / "dds", 1)
    xbm_t = json.loads((TPL / "tile.xbm.json").read_text())
    atl_t = json.loads((TPL / "atlas.inkatlas.json").read_text())
    for name in ("holo.xbm", "holo.inkatlas"):
        (ui / name).unlink(missing_ok=True)
    write_resource(ws, "overlaymap\\ui\\holo.xbm", make_xbm_json(xbm_t, img.width, img.height, payloads[png]))
    write_resource(ws, "overlaymap\\ui\\holo.inkatlas",
                   make_inkatlas_json(atl_t, "overlaymap\\ui\\holo.xbm", parts, img.width, img.height))
    deserialize_all(ws)
    archive = pack_archive(ws, REPO / "archive" / "pc" / "mod" / "OverlayMap.archive")
    print(f"archive {archive} {archive.stat().st_size / 1e6:.1f} MB (holo atlas parts: {', '.join(sorted(parts))})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
