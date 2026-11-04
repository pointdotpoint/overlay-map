"""The lowest and highest surface in each cell of the map, for teleporting to a spot the flat map has no height for.

Sources are the vanilla 3D map: 3dmap_terrain, 3dmap_roads, 3dmap_cliffs and 3dmap_metro for the ground, and the
district point clouds (buildings.py) for roofs. They are an estimate: the city sits on platforms the 3D map does not
model, so a street can be several metres above the terrain under it. V is only sent near these heights; a ray straight
down then finds the real surface, once collision has loaded (spec 2026-10-30-overlaymap-teleport-anywhere-design.md).
A cell keeps both ends because a street beside a tower shares its cell with a roof 300 m up.

Output is a script of strings, four characters a cell, so a lookup is a string index and nothing is read from disk.
"""
from __future__ import annotations

import argparse
import base64
import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from nmtiles import buildings
from nmtiles.glb import keep_best_lod, read_glb

ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
FLOOR = -128.0            # encoded 0, and the value of a cell nothing covers
SAMPLES = 1               # samples per cell side when rasterising triangles
FINE_PER_CELL = 4         # fine cells per side of a stored cell
_MAX = len(ALPHABET) ** 2 - 1

# Mesh -> (flip, offset), from each component's transform in 3dmap_view.ent: the roads and metro turn 180 degrees about Z,
# the terrain and cliffs do not, and the cliffs sit at an offset. Worked out against heights V really stood at.
MESHES = {
    "3dmap_terrain": (False, (0.0, 0.0)),
    "3dmap_roads": (True, (0.0, 0.0)),
    "3dmap_metro": (True, (0.0, 0.0)),
    "3dmap_cliffs": (False, (-2255.0, -3050.0)),
}


@dataclass(frozen=True)
class Grid:
    x0: float
    y0: float
    cell: float
    n: int


def empty(g: Grid) -> np.ndarray:
    return np.full((g.n, g.n), np.nan, np.float32)


def add_triangles(tops: np.ndarray, g: Grid, tris: np.ndarray) -> None:
    """Raise each cell to the highest height sampled inside it. tris is (N,3,3) world X, Y, Z."""
    step = g.cell / SAMPLES
    for t in tris:
        (ax, ay, az), (bx, by, bz), (cx, cy, cz) = t
        den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if den == 0.0:
            continue
        i0 = max(int(np.floor((min(ax, bx, cx) - g.x0) / step)), 0)
        i1 = min(int(np.ceil((max(ax, bx, cx) - g.x0) / step)), g.n * SAMPLES - 1)
        j0 = max(int(np.floor((min(ay, by, cy) - g.y0) / step)), 0)
        j1 = min(int(np.ceil((max(ay, by, cy) - g.y0) / step)), g.n * SAMPLES - 1)
        if i1 < i0 or j1 < j0:
            continue
        xs = g.x0 + (np.arange(i0, i1 + 1) + 0.5) * step
        ys = g.y0 + (np.arange(j0, j1 + 1) + 0.5) * step
        px, py = np.meshgrid(xs, ys)
        u = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) / den
        v = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) / den
        w = 1.0 - u - v
        inside = (u >= -1e-6) & (v >= -1e-6) & (w >= -1e-6)
        if not inside.any():
            continue
        z = (u * az + v * bz + w * cz)[inside]
        row = np.searchsorted(ys, py[inside]) + j0
        col = np.searchsorted(xs, px[inside]) + i0
        np.fmax.at(tops, (row // SAMPLES, col // SAMPLES), z.astype(np.float32))


def add_boxes(tops: np.ndarray, g: Grid, cx: np.ndarray, cy: np.ndarray, dx: np.ndarray, dy: np.ndarray,
              yaw: np.ndarray, top: np.ndarray) -> None:
    """Raise the cells whose centre or samples fall under each rotated box."""
    step = g.cell / SAMPLES
    for x, y, w, h, a, z in zip(cx, cy, dx, dy, yaw, top):
        c, s = np.cos(a), np.sin(a)
        ex, ey = (abs(c) * w + abs(s) * h) / 2.0, (abs(s) * w + abs(c) * h) / 2.0
        i0, i1 = max(int((x - ex - g.x0) // step), 0), min(int((x + ex - g.x0) // step), g.n * SAMPLES - 1)
        j0, j1 = max(int((y - ey - g.y0) // step), 0), min(int((y + ey - g.y0) // step), g.n * SAMPLES - 1)
        if i1 < i0 or j1 < j0:
            continue
        xs = g.x0 + (np.arange(i0, i1 + 1) + 0.5) * step - x
        ys = g.y0 + (np.arange(j0, j1 + 1) + 0.5) * step - y
        px, py = np.meshgrid(xs, ys)
        under = (np.abs(c * px + s * py) <= w / 2.0 + step / 2.0) & (np.abs(-s * px + c * py) <= h / 2.0 + step / 2.0)
        if not under.any():
            continue
        rows, cols = np.nonzero(under)
        np.fmax.at(tops, ((rows + j0) // SAMPLES, (cols + i0) // SAMPLES), float(z))


def encode(z: float) -> str:
    v = min(max(int(np.ceil(z - FLOOR)), 0), _MAX)
    return ALPHABET[v // len(ALPHABET)] + ALPHABET[v % len(ALPHABET)]


def decode(s: str) -> float:
    return ALPHABET.index(s[0]) * len(ALPHABET) + ALPHABET.index(s[1]) + FLOOR


def reduce(fine: np.ndarray, per_cell: int) -> tuple[np.ndarray, np.ndarray]:
    """The lowest and highest fine sample in each cell."""
    n = fine.shape[0] // per_cell
    cells = fine.reshape(n, per_cell, n, per_cell).transpose(0, 2, 1, 3).reshape(n, n, per_cell * per_cell)
    return cells.min(axis=2), cells.max(axis=2)


def pack(lo: np.ndarray, hi: np.ndarray, chunk: int) -> dict[tuple[int, int], str]:
    """(chunk column, chunk row) -> its cells row by row, low then high. Open sea (nothing above 0) is left out."""
    n = lo.shape[0]
    out: dict[tuple[int, int], str] = {}
    for cy in range(0, n // chunk):
        for cx in range(0, n // chunk):
            l = lo[cy * chunk:(cy + 1) * chunk, cx * chunk:(cx + 1) * chunk].ravel()
            h = hi[cy * chunk:(cy + 1) * chunk, cx * chunk:(cx + 1) * chunk].ravel()
            if not np.nanmax(np.append(h, FLOOR)) > 0.0:
                continue
            out[(cx, cy)] = "".join(encode(FLOOR if np.isnan(a) else float(a)) + encode(FLOOR if np.isnan(b) else float(b))
                                    for a, b in zip(l, h))
    return out


def to_reds(g: Grid, chunks: dict[tuple[int, int], str], chunk: int) -> str:
    per_side = g.n // chunk
    lines = ["module OverlayMap", "",
             "// Generated by tools/tiles/nmtiles/heightmap.py. Do not edit.",
             "public abstract class NMHeightData {",
             f"    public static func X0() -> Float {{ return {g.x0:.1f}; }}",
             f"    public static func Y0() -> Float {{ return {g.y0:.1f}; }}",
             f"    public static func Cell() -> Float {{ return {g.cell:.1f}; }}",
             f"    public static func ChunkCells() -> Int32 {{ return {chunk}; }}",
             f"    public static func Chunks() -> Int32 {{ return {per_side}; }}",
             f"    public static func Floor() -> Float {{ return {FLOOR:.1f}; }}",
             f'    public static func Alphabet() -> String {{ return "{ALPHABET}"; }}',
             "",
             "    public static func Chunk(index: Int32) -> String {",
             "        switch index {"]
    for (cx, cy), s in sorted(chunks.items(), key=lambda kv: kv[0][1] * per_side + kv[0][0]):
        lines.append(f'            case {cy * per_side + cx}: return "{s}";')
    lines += ["        }", '        return "";', "    }", "}", ""]
    return "\n".join(lines)


def _mesh_tris(path: Path, flip: bool, offset: tuple[float, float]) -> np.ndarray:
    parts = []
    for m in keep_best_lod(read_glb(path)):
        p = m.positions
        sign = -1.0 if flip else 1.0
        w = np.column_stack((sign * p[:, 0] + offset[0], -sign * p[:, 2] + offset[1], p[:, 1]))
        parts.append(w[m.triangles])
    return np.concatenate(parts)


def _box_tops(data_dir: Path) -> list[tuple[np.ndarray, ...]]:
    """(cx, cy, dx, dy, yaw, top) for each district. Box Z is the centre, checked against heights V stood at."""
    root = lambda js: js["Data"]["RootChunk"]
    mats = buildings.parse_materials(json.loads((data_dir / "3dmap_triangle_soup.mesh.json").read_text()))
    offsets = buildings.parse_offsets(json.loads((data_dir / "3dmap_view.ent.json").read_text()))
    out = []
    for name, m in sorted(mats.items()):
        tex = data_dir / f"{m.texture}.xbm.json"
        if not tex.exists():
            continue
        t = root(json.loads(tex.read_text()))
        n, w = int(t["height"]), int(t["width"])
        raw = base64.b64decode(t["renderTextureResource"]["renderResourceBlobPC"]["Data"]["textureData"]["Bytes"])
        px = np.frombuffer(raw[: n * w * 8], dtype="<u2").reshape(n, w, 4).astype(np.float64) / 65535.0
        pos, rot, size = px[:, :n], px[:, n:2 * n], px[:, 2 * n:]
        valid = pos[..., 3] > 0.5
        lo, hi = np.array(m.trans_min), np.array(m.trans_max)
        p = (lo + pos[..., :3] * (hi - lo))[valid]
        q = rot[valid] * 2.0 - 1.0
        d = size[valid][:, :3] * m.cube_size
        off = offsets.get(name, (0.0, 0.0))
        out.append((p[:, 0] + off[0], p[:, 1] + off[1], d[:, 0], d[:, 1], 2.0 * np.arctan2(q[:, 2], q[:, 3]),
                    p[:, 2] + d[:, 2] / 2.0))
    return out


def build(mesh_dir: Path, data_dir: Path, g: Grid) -> np.ndarray:
    tops = empty(g)
    for name, (flip, offset) in MESHES.items():
        add_triangles(tops, g, _mesh_tris(mesh_dir / f"{name}.glb", flip, offset))
    for cx, cy, dx, dy, yaw, top in _box_tops(data_dir):
        add_boxes(tops, g, cx, cy, dx, dy, yaw, top)
    return tops


def main(argv: list[str] | None = None) -> int:
    here = Path(__file__).resolve().parents[1]
    ap = argparse.ArgumentParser(description="Bake OverlayMap's teleport height map.")
    ap.add_argument("--meshes", type=Path, default=here / "build/meshes/base/entities/cameras/3dmap")
    ap.add_argument("--data", type=Path, default=here / "build/bdata")
    ap.add_argument("--out", type=Path, default=here.parents[1] / "r6/scripts/OverlayMap/Generated/HeightData.reds")
    args = ap.parse_args(argv)
    fine = Grid(x0=-8000.0, y0=-8000.0, cell=8.0, n=2000)
    g = Grid(fine.x0, fine.y0, fine.cell * FINE_PER_CELL, fine.n // FINE_PER_CELL)
    chunk = 25
    tops = build(args.meshes, args.data, fine)
    lo, hi = reduce(np.nan_to_num(tops, nan=FLOOR), FINE_PER_CELL)
    chunks = pack(lo, hi, chunk)
    args.out.write_text(to_reds(g, chunks, chunk))
    print(f"{len(chunks)} chunks, {args.out.stat().st_size / 1024:.0f} KB -> {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
