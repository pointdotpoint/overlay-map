"""Minimal glTF-binary reader (positions + triangle indices), numpy only."""
from __future__ import annotations

import json
import re
import struct
from dataclasses import dataclass
from pathlib import Path

import numpy as np

_COMP = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
_NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
_LOD = re.compile(r"^(?P<base>.*)_LOD_(?P<lod>\d+)$")


@dataclass
class Mesh:
    name: str
    positions: np.ndarray  # (N,3) float64, glTF space (Y up)
    triangles: np.ndarray  # (M,3) int64


def _accessor(js: dict, bin_: bytes, idx: int) -> np.ndarray:
    a = js["accessors"][idx]
    view = js["bufferViews"][a["bufferView"]]
    dtype = np.dtype(_COMP[a["componentType"]])
    n = _NCOMP[a["type"]]
    start = view.get("byteOffset", 0) + a.get("byteOffset", 0)
    item = dtype.itemsize * n
    stride = view.get("byteStride") or item
    if stride != item:
        raw = np.frombuffer(bin_, np.uint8, count=stride * a["count"], offset=start).reshape(a["count"], stride)
        return raw[:, :item].copy().view(dtype).reshape(a["count"], n)
    return np.frombuffer(bin_, dtype, count=a["count"] * n, offset=start).reshape(a["count"], n)


def read_glb(path: Path | str) -> list[Mesh]:
    data = Path(path).read_bytes()
    if len(data) < 20 or struct.unpack_from("<I", data, 0)[0] != 0x46546C67:
        raise ValueError(f"{path}: not a GLB file")
    jlen, _ = struct.unpack_from("<II", data, 12)
    js = json.loads(data[20:20 + jlen])
    off = 20 + jlen
    blen, _ = struct.unpack_from("<II", data, off)
    bin_ = data[off + 8: off + 8 + blen]
    meshes: list[Mesh] = []
    for node in js.get("nodes", []):
        if "mesh" not in node:
            continue
        if any(k in node for k in ("matrix", "translation", "rotation", "scale")):
            raise ValueError(f"{path}: node {node.get('name')} has a transform (unsupported)")
        gm = js["meshes"][node["mesh"]]
        for prim in gm["primitives"]:
            if prim.get("mode", 4) != 4:
                continue
            pos = _accessor(js, bin_, prim["attributes"]["POSITION"]).astype(np.float64)
            if "indices" in prim:
                tri = _accessor(js, bin_, prim["indices"]).astype(np.int64).reshape(-1, 3)
            else:
                tri = np.arange(len(pos), dtype=np.int64).reshape(-1, 3)
            meshes.append(Mesh(node.get("name", gm.get("name", "")), pos, tri))
    return meshes


def _base_lod(name: str) -> tuple[str, int]:
    m = _LOD.match(name)
    return (m["base"], int(m["lod"])) if m else (name, 0)


def keep_best_lod(meshes: list[Mesh]) -> list[Mesh]:
    """Keep only the finest LOD per submesh (names like submesh_00_LOD_1)."""
    best: dict[str, int] = {}
    for m in meshes:
        base, lod = _base_lod(m.name)
        best[base] = min(best.get(base, lod), lod)
    return [m for m in meshes if _base_lod(m.name)[1] == best[_base_lod(m.name)[0]]]
