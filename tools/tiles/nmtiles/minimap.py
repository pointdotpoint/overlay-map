"""Offline extraction and decoding of the game's own minimap geometry (spec 2026-10-12 §11.1).

The minimap lives in the streaming sectors ``exterior_<x>_<y>_<z>_<lod>``: every ``MinimapDataNode`` embeds a
``minimapEncodedShapes`` resource (quantized triangle meshes). Format notes are in
``.scratch/minimap_spike/FINDINGS.md``; this module is the clean, tested port.

Pipeline (``load_city``): list sector paths in the base and EP1 archives, EP1 copies replacing base ones, extract and
convert them with WolvenKit.CLI (cached as JSON), decode every node into world-space triangles and classify each shape
as ``road`` (a thick area) or ``stroke`` (a thin line).
"""
from __future__ import annotations

import base64
import hashlib
import json
import os
import re
import shutil
import subprocess
import time
from concurrent.futures import ProcessPoolExecutor, ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

import numpy as np

ROAD_THICKNESS = 3.0        # metres: area / max bbox extent at or above this is a road, below it a stroke
LODS = (3, 4)               # sector LODs that carry the minimap geometry we use (spike 2: both, disjoint paths)
SECTOR_DIR = "base/worlds/03_night_city/_compiled/default"
SECTOR_RE = r"exterior_-?\d+_-?\d+_-?\d+_[34]\.streamingsector$"
BASE_ARCHIVE = "content/basegame_3_nightcity.archive"
EP1_ARCHIVE_GLOB = "ep1_*nightcity*.archive"

_DT_A = np.dtype([("a", "<u4"), ("n", "<u2"), ("g", "<u2")])
_DT_B = np.dtype([("t", "<u2"), ("f", "<u2")])
_DT_D = np.dtype([("d0", "<u2"), ("d1", "<u2"), ("d2", "<u2"), ("d3", "<u2")])


@dataclass
class DecodedShape:
    tris: np.ndarray    # (M, 3, 2) float32: file-local xy, instance offset already added; add the node position
    z: float            # instance elevation (file-local; add the node z)
    type: int           # B.type: a height stratum, not a class
    flag: int           # B.flag


# --------------------------------------------------------------------------------------------------- decoding

def quantize(q: np.ndarray, bias: float, scale: float) -> np.ndarray:
    """u16 quantized coordinate -> float: ``bias + q / 65535 * scale``."""
    return (bias + np.asarray(q, np.float64) / 65535.0 * scale).astype(np.float32)


def fill_ranges(d: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Decode the D records (structured ``_DT_D``) to per-shape fill-index (start, count).

    Normal packing: ``start = d0 | (d1 & 7) << 16``, ``count = (d2 >> 6) | d3 << 10``.
    Compact packing (when ``d2 >> 6 == 0`` and ``d3 > 0``): ``start = (d1 >> 3) | (d2 & 63) << 13``, ``count = d3 >> 3``.
    """
    d0, d1, d2, d3 = (d[k].astype(np.int64) for k in ("d0", "d1", "d2", "d3"))
    compact = ((d2 >> 6) == 0) & (d3 > 0)
    start = np.where(compact, (d1 >> 3) | ((d2 & 63) << 13), d0 | ((d1 & 7) << 16))
    count = np.where(compact, d3 >> 3, (d2 >> 6) | (d3 << 10))
    return start, count


def _buffer(root: dict) -> bytes:
    buf = root["Buffer"]
    return base64.b64decode(buf["Bytes"] if isinstance(buf, dict) else buf)


def _is_empty(root: dict) -> bool:
    """Empty placeholder resources have a non-finite quantization scale ('-inf') and no points."""
    qs = root.get("QuantizationScale") or {}
    try:
        finite = all(np.isfinite(float(qs[k])) for k in ("X", "Y"))
    except (KeyError, TypeError, ValueError):
        finite = False
    return (not finite) or root.get("NumBorderPoints", 0) == 0


def _unpack(root: dict) -> dict:
    b = _buffer(root)
    nb, nf, ns, nk, nu, no = (int(root[k]) for k in ("NumBorderPoints", "NumFillPoints", "NumShapes",
                                                     "NumSpatialBuckets", "NumUniqueGeometry", "NumOwners"))
    pos = 0

    def take(dt, n):
        nonlocal pos
        a = np.frombuffer(b, dtype=dt, count=n, offset=pos)
        pos += a.itemsize * n
        return a

    a = take(_DT_A, ns)
    bflags = take(_DT_B, ns)
    c = take(np.dtype("<f4"), ns * 3).reshape(ns, 3)
    take(np.dtype("<u2"), nk * 2)                                # bucket start/count
    take(np.dtype("<f4"), nk * 8)                                # bucket boxes
    d = take(_DT_D, ns)
    take(np.dtype("<u2"), nu * 6)                                # unique-geometry bboxes
    p = take(np.dtype("<u2"), nb * 2).reshape(nb, 2)
    f = take(np.dtype("<u2"), nf)
    take(np.dtype("<u4"), no * 2)                                # owners (hashes)
    if pos != len(b):
        raise ValueError(f"minimap buffer size mismatch: parsed {pos} of {len(b)} bytes")
    qb, qs = root["QuantizationBias"], root["QuantizationScale"]
    pf = np.stack([quantize(p[:, 0], float(qb["X"]), float(qs["X"])),
                   quantize(p[:, 1], float(qb["Y"]), float(qs["Y"]))], axis=1) if nb else np.zeros((0, 2), np.float32)
    start, count = fill_ranges(d)
    return dict(B=bflags, C=c, P=pf, F=f, start=start, count=count)


def decode_shapes(root: dict) -> list[DecodedShape]:
    """Decode one ``minimapEncodedShapes`` RootChunk. Empty resources give ``[]``; shapes with no triangles are kept."""
    if _is_empty(root):
        return []
    u = _unpack(root)
    out = []
    for i in range(len(u["C"])):
        s, n = int(u["start"][i]), int(u["count"][i]) // 3 * 3
        idx = u["F"][s:s + n].reshape(-1, 3)
        tris = (u["P"][idx] + u["C"][i, :2]).astype(np.float32)
        out.append(DecodedShape(tris, float(u["C"][i, 2]), int(u["B"]["t"][i]), int(u["B"]["f"][i])))
    return out


def classify(tris: np.ndarray, thickness: float = ROAD_THICKNESS) -> str:
    """'road' when thickness (area / max bbox extent) >= 3 m, else 'stroke'."""
    t = np.asarray(tris, np.float64)
    if len(t) == 0:
        return "stroke"
    area = 0.5 * np.abs((t[:, 1, 0] - t[:, 0, 0]) * (t[:, 2, 1] - t[:, 0, 1])
                        - (t[:, 2, 0] - t[:, 0, 0]) * (t[:, 1, 1] - t[:, 0, 1])).sum()
    ext = max(np.ptp(t[:, :, 0]), np.ptp(t[:, :, 1]))
    return "road" if ext > 0 and area / ext >= thickness else "stroke"


def sector_nodes(sector_json: dict) -> list[tuple[tuple[float, float], dict]]:
    """``(position_xy, encoded_root)`` for every exterior MinimapDataNode with embedded data.

    Skips interiors (``allInteriorShapes``), soft refs with no embedded file and empty (scale = -inf) resources.
    """
    data = sector_json["Data"]
    root = data["RootChunk"]
    embedded = {e["FileName"]["$value"]: e["Content"] for e in data.get("EmbeddedFiles", [])}
    nodes = {i: n["Data"] for i, n in enumerate(root["nodes"]) if n["Data"]["$type"] == "MinimapDataNode"}
    out = []
    for nd in root["nodeData"]["Data"]:
        node = nodes.get(nd["NodeIndex"])
        if node is None or node.get("allInteriorShapes"):
            continue
        content = embedded.get(node["encodedShapesRef"]["DepotPath"]["$value"])
        if content is None or _is_empty(content):
            continue
        out.append(((float(nd["Position"]["X"]), float(nd["Position"]["Y"])), content))
    return out


def decode_sector(sector_json: dict) -> tuple[np.ndarray, np.ndarray, int]:
    """World-space (road, stroke, n_nodes) for one sector. Rotation is identity and scale 1 for all nodes."""
    road, stroke, nodes = [], [], 0
    for (px, py), enc in sector_nodes(sector_json):
        nodes += 1
        off = np.array([px, py], np.float32)
        for sh in decode_shapes(enc):
            if len(sh.tris) == 0:
                continue
            (road if classify(sh.tris) == "road" else stroke).append(sh.tris + off)
    cat = lambda xs: np.concatenate(xs).astype(np.float32) if xs else np.zeros((0, 3, 2), np.float32)
    return cat(road), cat(stroke), nodes


# --------------------------------------------------------------------------------------- sector list / precedence

def resolve_sectors(base: list[str], ep1: list[str]) -> dict[str, tuple[str, str]]:
    """Map sector path relative to ``SECTOR_DIR`` (e.g. ``exterior_0_0_0_3.streamingsector`` or
    ``ep1/exterior_...``) -> (source, archive path). An EP1 copy of a path replaces the base one. The same file name
    in two directories is two different sectors (EP1 adds ``default/ep1/`` siblings), so the key is the full path."""
    out = {}
    for src, paths in (("base", base), ("ep1", ep1)):
        for p in paths:
            p = p.replace("\\", "/").strip()
            if p:
                out[p.split("/default/", 1)[1] if "/default/" in p else p.rsplit("/", 1)[-1]] = (src, p)
    return out


def _wk(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["WolvenKit.CLI", *args], capture_output=True, text=True)


def list_archive(archive: Path) -> list[str]:
    r = _wk("archive", str(archive), "-l", "-r", SECTOR_RE)
    return [ln.strip() for ln in r.stdout.splitlines() if re.search(SECTOR_RE, ln.strip().replace("\\", "/"))]


def archive_key(archives: list[Path]) -> str:
    h = hashlib.sha256()
    for a in sorted(archives):
        st = a.stat()
        h.update(f"{a.name}:{st.st_size}:{st.st_mtime_ns}\n".encode())
    return h.hexdigest()[:16]


def _convert_one(args: tuple[str, str]) -> bool:
    src, out_dir = args
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)           # `convert s` needs an existing output dir
    name = Path(src).name + ".json"
    if (out / name).exists():
        return True
    _wk("convert", "s", src, "-o", str(out))
    return (out / name).exists()


def _decode_file(path: str) -> tuple[np.ndarray, np.ndarray, int]:
    with open(path) as fh:
        return decode_sector(json.load(fh))


# ------------------------------------------------------------------------------------------------ load_city

def load_city(game_dir: Path, cache_dir: Path, log: Callable[[str], None] = print,
              workers: int | None = None) -> dict[str, np.ndarray]:
    """All minimap triangles of the city in world xy: ``{"road": (N,3,2), "stroke": (K,3,2)}`` float32.

    ``cache_dir`` holds ``json_base/`` + ``json_ep1/`` (converted sectors), ``sec_*/`` (extracted CR2W) and
    ``minimap_city.npz``; everything is keyed by the source archives' size + mtime and rebuilt when they change.
    """
    t0 = time.time()
    game_dir, cache_dir = Path(game_dir), Path(cache_dir)
    workers = workers or os.cpu_count() or 4
    base_arc = game_dir / "archive/pc" / BASE_ARCHIVE
    ep1_arcs = sorted((game_dir / "archive/pc/ep1").glob(EP1_ARCHIVE_GLOB))
    key = archive_key([base_arc, *ep1_arcs])

    cache_dir.mkdir(parents=True, exist_ok=True)
    key_file, npz = cache_dir / "key.txt", cache_dir / "minimap_city.npz"
    if not key_file.exists() or key_file.read_text().strip() != key:
        log(f"cache key changed ({key}); clearing {cache_dir}")
        for child in cache_dir.iterdir():
            shutil.rmtree(child) if child.is_dir() else child.unlink()
        key_file.write_text(key + "\n")
    if npz.exists():
        z = np.load(npz)
        log(f"cached {npz.name}: road {len(z['road'])} stroke {len(z['stroke'])}")
        return {"road": z["road"], "stroke": z["stroke"]}

    base_list = list_archive(base_arc)
    ep1_list = [p for a in ep1_arcs for p in list_archive(a)]
    sectors = resolve_sectors(base_list, ep1_list)
    log(f"sectors: base {len(base_list)}, ep1 {len(ep1_list)} -> {len(sectors)} unique "
        f"({sum(v[0] == 'ep1' for v in sectors.values())} from ep1)")

    json_dirs = {s: cache_dir / f"json_{s}" for s in ("base", "ep1")}
    for d in json_dirs.values():
        d.mkdir(exist_ok=True)
    todo = {s: [n for n, (src, _) in sectors.items() if src == s and not (json_dirs[s] / f"{n}.json").exists()]
            for s in ("base", "ep1")}

    # extract the needed CR2W sectors (one WolvenKit call per archive), then convert them in parallel
    jobs = []
    for s, archives in (("base", [base_arc]), ("ep1", ep1_arcs)):
        if not todo[s]:
            continue
        sec_dir = cache_dir / f"sec_{s}"
        sec_dir.mkdir(exist_ok=True)
        need = "|".join(re.escape(n[:-len(".streamingsector")]).replace("/", r"[/\\]") for n in todo[s])
        for a in archives:
            log(f"extracting {len(todo[s])} {s} sectors from {a.name}")
            _wk("extract", str(a), "-r", rf"default[/\\]({need})\.streamingsector$", "-o", str(sec_dir))
        jobs += [(str(sec_dir / SECTOR_DIR / n), str((json_dirs[s] / n).parent)) for n in todo[s]
                 if (sec_dir / SECTOR_DIR / n).exists()]
    if jobs:
        log(f"converting {len(jobs)} sectors with {workers} workers")
        done = 0
        with ThreadPoolExecutor(workers) as ex:
            for ok in ex.map(_convert_one, jobs):
                done += 1
                if not ok:
                    log("convert failed for one sector")
                if done % 50 == 0:
                    log(f"  converted {done}/{len(jobs)}  ({time.time() - t0:.0f}s)")

    files = [str(json_dirs[src] / f"{n}.json") for n, (src, _) in sorted(sectors.items())]
    files = [f for f in files if os.path.exists(f)]
    if len(files) != len(sectors):
        log(f"WARNING: {len(sectors) - len(files)} sectors missing after conversion")
    road, stroke, nodes = [], [], 0
    with ProcessPoolExecutor(workers) as ex:
        for r, s, n in ex.map(_decode_file, files, chunksize=4):
            road.append(r)
            stroke.append(s)
            nodes += n
    out = {"road": np.concatenate(road).astype(np.float32), "stroke": np.concatenate(stroke).astype(np.float32)}
    np.savez_compressed(npz, **out)
    log(f"sectors {len(files)}, nodes {nodes}, road tris {len(out['road'])}, stroke tris {len(out['stroke'])}, "
        f"npz {npz.stat().st_size / 1e6:.1f} MB, {time.time() - t0:.0f}s")
    return out
