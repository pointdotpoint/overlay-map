"""Fit the mesh->world transform from in-game fast-travel positions (they sit beside roads)."""
from __future__ import annotations

import argparse
import math
import re
import sys
from pathlib import Path

import numpy as np
from scipy.ndimage import distance_transform_edt

from nmtiles.export import style_for
from nmtiles.glb import Mesh, keep_best_lod, read_glb
from nmtiles.render import rasterize_mask
from nmtiles.world import Transform

GATE_METERS = 15.0
_LINE = re.compile(r"\[OverlayMap\] CALIB\|(?P<name>[^|]*)\|(?P<x>-?[\d.]+)\|(?P<y>-?[\d.]+)\|(?P<z>-?[\d.]+)")
_SIGNS = [(1.0, -1.0), (1.0, 1.0), (-1.0, -1.0), (-1.0, 1.0)]


def parse_gamelog(text: str) -> list[tuple[str, float, float]]:
    found: dict[str, tuple[float, float]] = {}
    for line in text.splitlines():
        m = _LINE.search(line)
        if m:
            found.pop(m["name"], None)
            found[m["name"]] = (float(m["x"]), float(m["y"]))
    return [(n, x, y) for n, (x, y) in found.items()]


def fit(points_xy: np.ndarray, road_meshes: list[Mesh], search: float = 50.0, step: float = 2.0,
        mpp: float = 2.0) -> tuple[Transform, float]:
    best_tf, best_med = Transform(), math.inf
    offs = np.arange(-search, search + step / 2, step)
    for sx, sy in _SIGNS:
        base = Transform(sx, sy, 0.0, 0.0)
        world = np.vstack([base.apply(m.positions) for m in road_meshes])
        pad = search + 50.0
        minx = min(world[:, 0].min(), points_xy[:, 0].min()) - pad
        maxx = max(world[:, 0].max(), points_xy[:, 0].max()) + pad
        miny = min(world[:, 1].min(), points_xy[:, 1].min()) - pad
        maxy = max(world[:, 1].max(), points_xy[:, 1].max()) + pad
        w, h = int(math.ceil((maxx - minx) / mpp)), int(math.ceil((maxy - miny) / mpp))
        mask = rasterize_mask(road_meshes, base, minx, maxy, mpp, w, h)
        dist = distance_transform_edt(~mask) * mpp
        for dx in offs:
            for dy in offs:
                # mesh shifted by (dx,dy) == points shifted by (-dx,-dy)
                col = np.clip(((points_xy[:, 0] - dx - minx) / mpp).astype(int), 0, w - 1)
                row = np.clip(((maxy - (points_xy[:, 1] - dy)) / mpp).astype(int), 0, h - 1)
                med = float(np.median(dist[row, col]))
                if med < best_med:
                    best_med, best_tf = med, Transform(sx, sy, float(dx), float(dy))
    return best_tf, best_med


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--gamelog", type=Path,
                    default=Path.home() / "cyberpunk_symlink/bin/x64/plugins/cyber_engine_tweaks/gamelog.log")
    ap.add_argument("--meshes", type=Path, default=Path("build/meshes"))
    ap.add_argument("--out", type=Path, default=Path("calibration.json"))
    args = ap.parse_args(argv)
    pts = parse_gamelog(args.gamelog.read_text(errors="replace"))
    if len(pts) < 10:
        print(f"need >= 10 CALIB points, found {len(pts)} (Alt+\\ in game with Debug on)")
        return 1
    roads = [m for p in sorted(args.meshes.rglob("*.glb")) if style_for(p.stem) in ("road", "road_border")
             for m in keep_best_lod(read_glb(p))]
    tf, med = fit(np.array([[x, y] for _, x, y in pts]), roads)
    print(f"points={len(pts)} best={tf} median_road_distance={med:.1f} m (gate {GATE_METERS} m)")
    if med > GATE_METERS:
        print("CALIBRATION FAILED: fast-travel points do not sit near the roads under any tried transform")
        return 1
    tf.save(args.out)
    print(f"wrote {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
