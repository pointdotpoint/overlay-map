#!/usr/bin/env python3
"""Pull the game's named area outlines (worldLocationAreaNotifier) out of the world streaming sectors.

Needs WolvenKit 10 (8.x cannot read these sectors): the default --wolvenkit is the wrapper that sets up .NET 10.
Extracts every non-navigation sector into <work>/raw (only when it holds none yet), keeps the ones whose bytes
mention worldLocationAreaNotifier, converts them in one call and writes <work>/areas/outlines.json: one row per
outline and node instance, {"id", "node", "debug", "sector", "poly": [[x, y], ...]} in world metres.
"""
from __future__ import annotations

import argparse
import base64
import json
import struct
import subprocess
import tempfile
from collections import defaultdict
from pathlib import Path

ARCHIVES = ("archive/pc/content/basegame_3_nightcity.archive", "archive/pc/ep1/ep1_1_nightcity.archive")
SECTOR_RE = r"^(?!.*navigation_).*\.streamingsector$"
NEEDLE = b"worldLocationAreaNotifier"
WK10 = Path.home() / ".local/share/nightmap-tools/wk10"


def decode_outline(outline: dict) -> list[tuple[float, float, float]]:
    """The cooked outline: `buffer` is uint32 count + count Vector4. `points` is often a stale unit square."""
    buf = outline.get("buffer")
    if buf:
        b = base64.b64decode(buf)
        n = struct.unpack_from("<I", b, 0)[0]
        if len(b) >= 4 + 16 * n:
            return [tuple(struct.unpack_from("<3f", b, 4 + 16 * i)) for i in range(n)]
    return [(p.get("X", 0.0), p.get("Y", 0.0), p.get("Z", 0.0)) for p in outline.get("points") or []]


def _coord(v) -> float:
    return v.get("Bits", 0) / 131072.0 if isinstance(v, dict) else float(v or 0.0)


def _pos3(p: dict) -> tuple[float, float, float]:
    if not p:
        return (0.0, 0.0, 0.0)
    return tuple(_coord(p.get(k, p.get(k.lower(), 0.0))) for k in "XYZ")


def _qrot(q: dict, x: float, y: float, z: float) -> tuple[float, float, float]:
    i, j, k, r = q.get("i", 0.0), q.get("j", 0.0), q.get("k", 0.0), q.get("r", 1.0)
    tx, ty, tz = 2 * (j * z - k * y), 2 * (k * x - i * z), 2 * (i * y - j * x)
    return (x + r * tx + (j * tz - k * ty), y + r * ty + (k * tx - i * tz), z + r * tz + (i * ty - j * tx))


def world_polygon(pts: list[tuple[float, float, float]], transform: dict, scale: dict) -> list[tuple[float, float]]:
    """Local outline points -> world (x, y): scale, rotate by the orientation quaternion, offset by the position."""
    px, py, _ = _pos3(transform.get("position") or {})
    q = transform.get("orientation") or {}
    sx, sy, sz = (scale or {}).get("X", 1.0), (scale or {}).get("Y", 1.0), (scale or {}).get("Z", 1.0)
    out = []
    for x, y, z in pts:
        vx, vy, _ = _qrot(q, x * sx, y * sy, z * sz)
        out.append((px + vx, py + vy))
    return out


def _instances(root: dict) -> dict[int, list[dict]]:
    nd = root.get("nodeData") or []
    nd = nd.get("Data", []) if isinstance(nd, dict) else nd
    by: dict[int, list[dict]] = defaultdict(list)
    for e in nd:
        idx = e.get("nodeIdx", e.get("NodeIndex"))
        if idx is not None:
            by[int(idx)].append(e)
    return by


def outlines_from_sector(doc: dict, sector: str) -> list[dict]:
    root = doc["Data"]["RootChunk"]
    by = _instances(root)
    rows = []
    for i, ref in enumerate(root.get("nodes") or []):
        n = ref.get("Data") or {}
        ids = [(no.get("Data") or {}).get("districtID", {}).get("$value", "") for no in n.get("notifiers") or []
               if (no.get("Data") or {}).get("$type") == "worldLocationAreaNotifier"]
        if not ids:
            continue
        pts = decode_outline((n.get("outline") or {}).get("Data") or {})
        debug = (n.get("debugName") or {}).get("$value", "")
        for e in by.get(i, []):
            t = e.get("transform") or {"position": e.get("Position") or {}, "orientation": e.get("Orientation") or {}}
            poly = [[round(x, 2), round(y, 2)] for x, y in world_polygon(pts, t, e.get("scale") or e.get("Scale"))]
            for did in ids:
                rows.append({"id": did or "", "node": n.get("$type", ""), "debug": debug, "sector": sector,
                             "poly": poly})
    return rows


def extract(game: Path, raw: Path, wk: Path) -> None:
    if any(raw.rglob("*.streamingsector")):
        return
    for a in ARCHIVES:
        subprocess.run([str(wk), "extract", str(game / a), "-r", SECTOR_RE, "-o", str(raw)],
                       stdout=subprocess.DEVNULL, check=True)


def convert(files: list[Path], raw: Path, wk: Path, workdir: Path) -> list[tuple[str, dict]]:
    """Convert sectors with WK10 in one call; returns (sector name, doc) pairs."""
    with tempfile.TemporaryDirectory(dir=workdir) as td:
        src, dst = Path(td) / "in", Path(td) / "out"
        src.mkdir()
        dst.mkdir()
        for f in files:
            (src / str(f.relative_to(raw)).replace("/", "__")).symlink_to(f.resolve())
        subprocess.run([str(wk), "convert", "s", str(src), "-o", str(dst)], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, check=False)
        out = []
        for j in sorted(dst.rglob("*.json")):
            try:
                out.append((j.name.replace(".json", ""), json.loads(j.read_text())))
            except ValueError:
                print(f"unreadable {j.name}", flush=True)
        return out


def matching(raw: Path, needle: bytes) -> list[Path]:
    return sorted(p for p in raw.rglob("*.streamingsector") if needle in p.read_bytes())


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--game", type=Path, default=Path.home() / "cyberpunk_symlink")
    ap.add_argument("--work", type=Path, default=Path.home() / ".cache/nightmap-sectors")
    ap.add_argument("--wolvenkit", type=Path, default=WK10)
    args = ap.parse_args(argv)
    raw, out = args.work / "raw", args.work / "areas"
    raw.mkdir(parents=True, exist_ok=True)
    out.mkdir(parents=True, exist_ok=True)
    extract(args.game, raw, args.wolvenkit)
    files = matching(raw, NEEDLE)
    print(f"{len(files)} sectors with area notifiers", flush=True)
    docs = convert(files, raw, args.wolvenkit, out)
    if len(docs) != len(files):
        print(f"warning: converted {len(docs)} of {len(files)}", flush=True)
    rows = [r for name, doc in docs for r in outlines_from_sector(doc, name)]
    (out / "outlines.json").write_text(json.dumps(rows))
    print(f"{len(rows)} outlines, {len({r['id'] for r in rows})} ids -> {out / 'outlines.json'}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
