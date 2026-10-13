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
DECODE_VERSION = 3           # bump when decode/classify logic changes: invalidates the npz (not the JSON cache)
GROUND_Z, ELEVATED_Z, ELEVATED_MAX_THICK = 15.0, 80.0, 25.0   # spec 11.6 road rule
LODS = (3, 4)               # sector LODs that carry the minimap geometry we use (spike 2: both, disjoint paths)
# SECTOR_RE also matches z = -1 sectors (exterior_x_y_-1_*, about 1.3% of the triangles). They are included on
# purpose (not verified to be surface-only; Task 12 should check for stray geometry).
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
    z: float            # instance elevation (file-local; decode_sector adds the node Position.Z before classifying)
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
        s, n = int(u["start"][i]), int(u["count"][i])
        if n % 3 or s + n > len(u["F"]):
            raise ValueError(f"corrupt minimap fill range: shape {i} start {s} count {n} of {len(u['F'])} indices")
        idx = u["F"][s:s + n].reshape(-1, 3)
        tris = (u["P"][idx] + u["C"][i, :2]).astype(np.float32)
        out.append(DecodedShape(tris, float(u["C"][i, 2]), int(u["B"]["t"][i]), int(u["B"]["f"][i])))
    return out


def classify(tris: np.ndarray, z: float = 0.0, thickness: float = ROAD_THICKNESS) -> str:
    """'road' when thick >= 3 m and (z < 15 or (z < 80 and thick < 25)) (spec 11.6), else 'stroke' (building geometry).

    thick = area / max bbox extent; z = the shape's instance elevation (C.z)."""
    t = np.asarray(tris, np.float64)
    if len(t) == 0:
        return "stroke"
    area = 0.5 * np.abs((t[:, 1, 0] - t[:, 0, 0]) * (t[:, 2, 1] - t[:, 0, 1])
                        - (t[:, 2, 0] - t[:, 0, 0]) * (t[:, 1, 1] - t[:, 0, 1])).sum()
    ext = max(np.ptp(t[:, :, 0]), np.ptp(t[:, :, 1]))
    if ext <= 0:
        return "stroke"
    thick = area / ext
    return "road" if thick >= thickness and (z < GROUND_Z or (z < ELEVATED_Z and thick < ELEVATED_MAX_THICK)) else "stroke"


def _check_identity(nd: dict) -> None:
    """Node rotation must be identity and scale 1 (true for all 12.4k nodes): world xy = node xy + local xy."""
    o, sc = nd.get("Orientation") or {}, nd.get("Scale") or {}
    q = [float(o.get(k, d)) for k, d in (("i", 0), ("j", 0), ("k", 0), ("r", 1))]
    v = [float(sc.get(k, 1)) for k in "XYZ"]
    if not (np.allclose(q, [0, 0, 0, 1], atol=1e-4) and np.allclose(v, 1, atol=1e-4)):
        raise ValueError(f"minimap node {nd.get('NodeIndex')} has non-identity transform (orientation {q}, scale {v}); "
                         "the decoder assumes identity rotation and unit scale")


def sector_nodes(sector_json: dict) -> list[tuple[tuple[float, float, float], dict]]:
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
        _check_identity(nd)
        content = embedded.get(node["encodedShapesRef"]["DepotPath"]["$value"])
        if content is None or _is_empty(content):
            continue
        pos = nd["Position"]
        out.append(((float(pos["X"]), float(pos["Y"]), float(pos.get("Z", 0.0))), content))
    return out


def decode_sector(sector_json: dict) -> tuple[np.ndarray, np.ndarray, int]:
    """World-space (road, stroke, n_nodes) for one sector. Rotation is identity and scale 1 for all nodes."""
    road, stroke, nodes = [], [], 0
    for (px, py, pz), enc in sector_nodes(sector_json):
        nodes += 1
        off = np.array([px, py], np.float32)
        for sh in decode_shapes(enc):
            if len(sh.tris) == 0:
                continue
            (road if classify(sh.tris, sh.z + pz) == "road" else stroke).append(sh.tris + off)
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


def _wk(*args: str, check: bool = True) -> subprocess.CompletedProcess:
    r = subprocess.run(["WolvenKit.CLI", *args], capture_output=True, text=True)
    if check and r.returncode != 0:
        raise RuntimeError(f"WolvenKit.CLI {' '.join(args[:2])} failed (rc {r.returncode}): {r.stderr[-500:] or r.stdout[-500:]}")
    return r


def list_archive(archive: Path) -> list[str]:
    r = _wk("archive", str(archive), "-l", "-r", SECTOR_RE)
    return [ln.strip() for ln in r.stdout.splitlines() if re.search(SECTOR_RE, ln.strip().replace("\\", "/"))]


def archive_key(archives: list[Path]) -> str:
    """Key of the JSON cache: the source archives' name, size and mtime."""
    h = hashlib.sha256()
    for a in sorted(archives):
        st = a.stat()
        h.update(f"{a.name}:{st.st_size}:{st.st_mtime_ns}\n".encode())
    return h.hexdigest()[:16]


def npz_key(arc_key: str) -> str:
    """Key of the final npz: archives plus everything that changes the decoded result."""
    return hashlib.sha256(f"{arc_key}|v{DECODE_VERSION}|road{ROAD_THICKNESS}/{GROUND_Z}/{ELEVATED_Z}/{ELEVATED_MAX_THICK}|lods{LODS}".encode()).hexdigest()[:16]


def json_ok(path: Path) -> bool:
    """A converted sector counts as done only if non-empty and complete (ends with the closing brace)."""
    try:
        size = path.stat().st_size
        if size == 0:
            return False
        with open(path, "rb") as fh:
            fh.seek(max(0, size - 64))
            return fh.read().rstrip().endswith(b"}")
    except OSError:
        return False


def _convert_once(src: str, out: Path) -> bool:
    name = Path(src).name + ".json"
    tmp = out / f".tmp_{name}"
    shutil.rmtree(tmp, ignore_errors=True)
    tmp.mkdir()                                       # `convert s` needs an existing output dir
    try:
        r = _wk("convert", "s", src, "-o", str(tmp), check=False)
        produced = tmp / name
        if r.returncode != 0 or not json_ok(produced):
            return False
        os.replace(produced, out / name)              # atomic: the final name only ever holds a complete file
        return True
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def _convert_one(args: tuple[str, str]) -> bool:
    src, out_dir = args
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    if json_ok(out / (Path(src).name + ".json")):
        return True
    return _convert_once(src, out) or _convert_once(src, out)      # one retry


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
    ep1_arcs = sorted((game_dir / "archive/pc/ep1").glob(EP1_ARCHIVE_GLOB))   # sorted: extraction order is deterministic
    if not base_arc.exists():
        raise FileNotFoundError(f"base archive not found: {base_arc}")
    if not ep1_arcs:
        raise FileNotFoundError(f"no EP1 archives ({EP1_ARCHIVE_GLOB}) under {game_dir / 'archive/pc/ep1'}; "
                                "refusing to build a base-only city")
    key = archive_key([base_arc, *ep1_arcs])

    cache_dir.mkdir(parents=True, exist_ok=True)
    key_file, npz = cache_dir / "key.txt", cache_dir / "minimap_city.npz"
    if not key_file.exists() or key_file.read_text().strip() != key:
        log(f"cache key changed ({key}); clearing {cache_dir}")
        for child in cache_dir.iterdir():
            shutil.rmtree(child) if child.is_dir() else child.unlink()
        key_file.write_text(key + "\n")
    nkey_file = cache_dir / "npz_key.txt"
    nkey = npz_key(key)
    if npz.exists() and (not nkey_file.exists() or nkey_file.read_text().strip() != nkey):
        log("decode parameters changed; rebuilding npz from the JSON cache")
        npz.unlink()
    if npz.exists():
        z = np.load(npz)
        log(f"cached {npz.name}: road {len(z['road'])} stroke {len(z['stroke'])}")
        return {"road": z["road"], "stroke": z["stroke"]}

    base_list = list_archive(base_arc)
    ep1_list = [p for a in ep1_arcs for p in list_archive(a)]
    if not base_list or not ep1_list:
        raise RuntimeError(f"sector listing failed: base {len(base_list)}, ep1 {len(ep1_list)} sectors")
    sectors = resolve_sectors(base_list, ep1_list)
    log(f"sectors: base {len(base_list)}, ep1 {len(ep1_list)} -> {len(sectors)} unique "
        f"({sum(v[0] == 'ep1' for v in sectors.values())} from ep1)")

    json_dirs = {s: cache_dir / f"json_{s}" for s in ("base", "ep1")}
    for d in json_dirs.values():
        d.mkdir(exist_ok=True)
    todo = {s: [n for n, (src, _) in sectors.items() if src == s and not json_ok(json_dirs[s] / f"{n}.json")]
            for s in ("base", "ep1")}

    # extract the needed CR2W sectors (one WolvenKit call per archive), then convert them in parallel
    jobs, failed = [], []
    for s, archives in (("base", [base_arc]), ("ep1", ep1_arcs)):
        if not todo[s]:
            continue
        sec_dir = cache_dir / f"sec_{s}"
        sec_dir.mkdir(exist_ok=True)
        need = "|".join(re.escape(n[:-len(".streamingsector")]).replace("/", r"[/\\]") for n in todo[s])
        for a in archives:
            log(f"extracting {len(todo[s])} {s} sectors from {a.name}")
            _wk("extract", str(a), "-r", rf"default[/\\]({need})\.streamingsector$", "-o", str(sec_dir))
        for n in todo[s]:
            if (sec_dir / SECTOR_DIR / n).exists():
                jobs.append((n, str(sec_dir / SECTOR_DIR / n), str((json_dirs[s] / n).parent)))
            else:
                failed.append(f"{s}:{n} (not extracted)")
    if jobs:
        log(f"converting {len(jobs)} sectors with {workers} workers")
        done = 0
        with ThreadPoolExecutor(workers) as ex:
            for (n, _, _), ok in zip(jobs, ex.map(_convert_one, [(j[1], j[2]) for j in jobs])):
                done += 1
                if not ok:
                    failed.append(f"{n} (convert failed twice)")
                if done % 50 == 0:
                    log(f"  converted {done}/{len(jobs)}  ({time.time() - t0:.0f}s)")

    files = [str(json_dirs[src] / f"{n}.json") for n, (src, _) in sorted(sectors.items())]
    failed += [f"{f} (missing)" for f in files if not json_ok(Path(f))]
    if failed:
        raise RuntimeError(f"{len(failed)} sectors failed; not writing the npz:\n  " + "\n  ".join(sorted(set(failed))))
    road, stroke, nodes = [], [], 0
    with ProcessPoolExecutor(workers) as ex:
        for r, s, n in ex.map(_decode_file, files, chunksize=4):
            road.append(r)
            stroke.append(s)
            nodes += n
    out = {"road": np.concatenate(road).astype(np.float32), "stroke": np.concatenate(stroke).astype(np.float32)}
    tmp = cache_dir / "minimap_city.tmp.npz"
    np.savez_compressed(tmp, **out)
    os.replace(tmp, npz)
    nkey_file.write_text(nkey + "\n")
    log(f"sectors {len(files)}, nodes {nodes}, road tris {len(out['road'])}, stroke tris {len(out['stroke'])}, "
        f"npz {npz.stat().st_size / 1e6:.1f} MB, {time.time() - t0:.0f}s")
    return out
