#!/usr/bin/env python3
"""Derive a hand-made area outline: the convex hull of every sector node whose debug name contains --match.

  hull.py --match landfill_pile [--work ~/.cache/nightmap-sectors]
Reads sectors from <work>/raw (run scan.py first), converts the ones whose bytes contain the match with WolvenKit 10
and prints the hull as JSON, the point count, the centroid and the area in km2. Writes nothing; paste the hull into
custom_areas.json after checking it on a gen.py --preview render.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from scan import WK10, _instances, _pos3, convert, matching  # noqa: E402


def convex_hull(pts: list[tuple[float, float]]) -> list[tuple[float, float]]:
    """Andrew's monotone chain: counter-clockwise, collinear points dropped, first point not repeated."""
    p = sorted(set(pts))
    if len(p) <= 2:
        return p

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower: list[tuple[float, float]] = []
    for q in p:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], q) <= 0:
            lower.pop()
        lower.append(q)
    upper: list[tuple[float, float]] = []
    for q in reversed(p):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], q) <= 0:
            upper.pop()
        upper.append(q)
    return lower[:-1] + upper[:-1]


def fnv1a64(s: str) -> int:
    h = 0xCBF29CE484222325
    for b in s.encode():
        h = ((h ^ b) * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return h


def node_positions(doc: dict, match: str) -> list[tuple[float, float]]:
    """World (x, y) of every node instance whose debug name or prefab path (nodeRef) contains the match.

    Prefab paths live in the sector's nodeRefs; an instance's globalNodeId.hash is FNV1a64 of its path."""
    root = doc["Data"]["RootChunk"]
    nodes = root.get("nodes") or []
    refs = {fnv1a64(r.get("$value", "")) for r in root.get("nodeRefs") or [] if match in r.get("$value", "")}
    out = []
    for i, es in sorted(_instances(root).items()):
        n = (nodes[i].get("Data") or {}) if i < len(nodes) else {}
        by_name = match in (n.get("debugName") or {}).get("$value", "")
        for e in es:
            if by_name or int((e.get("globalNodeId") or {}).get("hash", 0)) in refs:
                x, y, _ = _pos3((e.get("transform") or {}).get("position") or e.get("Position") or {})
                out.append((x, y))
    return out


def centroid_area(poly: list[tuple[float, float]]) -> tuple[tuple[float, float], float]:
    a = cx = cy = 0.0
    for k in range(len(poly)):
        (x1, y1), (x2, y2) = poly[k], poly[(k + 1) % len(poly)]
        c = x1 * y2 - x2 * y1
        a += c
        cx += (x1 + x2) * c
        cy += (y1 + y2) * c
    if abs(a) < 1e-9:
        return (sum(x for x, _ in poly) / len(poly), sum(y for _, y in poly) / len(poly)), 0.0
    return (cx / (3 * a), cy / (3 * a)), abs(a) / 2


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--match", required=True)
    ap.add_argument("--work", type=Path, default=Path.home() / ".cache/nightmap-sectors")
    ap.add_argument("--wolvenkit", type=Path, default=WK10)
    ap.add_argument("--dump", type=Path, help="also write the raw matched points here (for review)")
    args = ap.parse_args(argv)
    raw = args.work / "raw"
    files = matching(raw, args.match.encode())
    print(f"{len(files)} sectors contain {args.match!r}", flush=True)
    pts = [p for _, doc in convert(files, raw, args.wolvenkit, args.work) for p in node_positions(doc, args.match)]
    if not pts:
        print("no matching nodes", flush=True)
        return 1
    if args.dump:
        args.dump.write_text(json.dumps(pts))
    hull = convex_hull(pts)
    (cx, cy), area = centroid_area(hull)
    print(json.dumps([[round(x, 1), round(y, 1)] for x, y in hull]))
    print(f"points {len(pts)}  hull {len(hull)}  centroid [{cx:.1f}, {cy:.1f}]  area {area / 1e6:.3f} km2")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
