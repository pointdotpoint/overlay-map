"""Building boxes from the vanilla 3D-map point clouds (world-space, metres; X east, Y north).

Each district has a data texture (N rows x 3N columns, RGBA16 UNORM) holding one cube per pixel:
section 0 = position, section 1 = rotation quaternion, section 2 = full box size. Parameters come from the
local material instances of 3dmap_triangle_soup.mesh and per-district offsets from 3dmap_view.ent, both
read from WolvenKit `convert s` JSON.
"""
from __future__ import annotations

import base64
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

import numpy as np

DRAW_DISTRICTS = ("city_center", "heywood", "santo_domingo", "westbrook", "watson", "pacifica", "ep1_dogtown")
_FIXED_POINT_ONE = 131072.0       # WorldPosition FixedPoint: Bits / 2**17 metres
_DATA_COMPONENT = re.compile(r"^(?P<district>.+?)_data\d*$")


@dataclass(frozen=True)
class DistrictMaterial:
    texture: str        # data texture stem, e.g. "city_center_data"
    trans_min: tuple[float, float, float]
    trans_max: tuple[float, float, float]
    cube_size: float


@dataclass
class Boxes:
    cx: np.ndarray
    cy: np.ndarray
    dx: np.ndarray      # full footprint size along the box's local X
    dy: np.ndarray
    dz: np.ndarray      # full height
    yaw: np.ndarray     # radians, counter-clockwise from +X

    def __len__(self) -> int:
        return len(self.cx)

    @staticmethod
    def concat(parts: list["Boxes"]) -> "Boxes":
        if not parts:
            return Boxes(*(np.zeros(0) for _ in range(6)))
        return Boxes(*(np.concatenate([getattr(p, f) for p in parts])
                       for f in ("cx", "cy", "dx", "dy", "dz", "yaw")))


def _root(js: dict) -> dict:
    return js["Data"]["RootChunk"]


def _values(material: dict) -> dict:
    """Flatten the CMaterialInstance `values` list ([{"$type":..., Name: value}, ...]) into {Name: value}."""
    out = {}
    for item in material.get("values", []):
        for k, v in item.items():
            if k != "$type":
                out[k] = v
    return out


def parse_materials(mesh_json: dict) -> dict[str, DistrictMaterial]:
    """District name -> point-cloud parameters; materials lacking a data texture or bounds are left out."""
    root = _root(mesh_json)
    materials = root["localMaterialBuffer"]["materials"]
    result: dict[str, DistrictMaterial] = {}
    for entry in root["materialEntries"]:
        if not entry.get("isLocalInstance"):
            continue
        vals = _values(materials[entry["index"]])
        if not all(k in vals for k in ("WorldPosTex", "TransMin", "TransMax", "CubeSize")):
            continue
        path = vals["WorldPosTex"]["DepotPath"]["$value"]
        tex = path.replace("/", "\\").rsplit("\\", 1)[-1].removesuffix(".xbm")
        lo, hi = vals["TransMin"], vals["TransMax"]
        result[entry["name"]["$value"]] = DistrictMaterial(
            tex, (lo["X"], lo["Y"], lo["Z"]), (hi["X"], hi["Y"], hi["Z"]), float(vals["CubeSize"]))
    return result


def parse_offsets(ent_json: dict) -> dict[str, tuple[float, float]]:
    """District name -> local XY offset of its `<district>_data*` mesh component (rotation is identity)."""
    offsets: dict[str, tuple[float, float]] = {}
    for comp in _root(ent_json)["components"]:
        if comp.get("$type") != "entMeshComponent":
            continue
        m = _DATA_COMPONENT.match(comp["name"]["$value"])
        if not m:
            continue
        pos = comp["localTransform"]["Position"]
        offsets[m["district"]] = (pos["x"]["Bits"] / _FIXED_POINT_ONE, pos["y"]["Bits"] / _FIXED_POINT_ONE)
    return offsets


def decode_boxes(tex_json: dict, mat: DistrictMaterial, offset: tuple[float, float]) -> Boxes:
    t = _root(tex_json)
    n, w = int(t["height"]), int(t["width"])
    if w != 3 * n:
        raise ValueError(f"data texture is {n}x{w}, expected N x 3N")
    raw = base64.b64decode(t["renderTextureResource"]["renderResourceBlobPC"]["Data"]["textureData"]["Bytes"])
    px = np.frombuffer(raw[: n * w * 8], dtype="<u2").reshape(n, w, 4).astype(np.float64) / 65535.0
    pos, rot, size = px[:, :n], px[:, n:2 * n], px[:, 2 * n:]
    valid = pos[..., 3] > 0.5
    lo, hi = np.array(mat.trans_min), np.array(mat.trans_max)
    p = (lo + pos[..., :3] * (hi - lo))[valid]
    q = rot[valid] * 2.0 - 1.0                      # (x, y, z, w); effectively a pure yaw
    dims = size[valid][:, :3] * mat.cube_size
    return Boxes(p[:, 0] + offset[0], p[:, 1] + offset[1], dims[:, 0], dims[:, 1], dims[:, 2],
                 2.0 * np.arctan2(q[:, 2], q[:, 3]))


def box_corners(b: Boxes) -> np.ndarray:
    """(N,4,2) world-space corners, counter-clockwise."""
    c, s = np.cos(b.yaw), np.sin(b.yaw)
    out = np.empty((len(b), 4, 2))
    for k, (i, j) in enumerate(((-1, -1), (1, -1), (1, 1), (-1, 1))):
        lx, ly = i * b.dx / 2.0, j * b.dy / 2.0
        out[:, k, 0] = b.cx + c * lx - s * ly
        out[:, k, 1] = b.cy + s * lx + c * ly
    return out


def load_boxes(data_dir: Path, log: Callable[[str], None] = print) -> Boxes:
    """Decode every drawable district from the `convert s` JSON in data_dir (flat directory)."""
    mesh_json = json.loads((data_dir / "3dmap_triangle_soup.mesh.json").read_text())
    mats = parse_materials(mesh_json)
    for entry in _root(mesh_json)["materialEntries"]:
        if entry["name"]["$value"] not in mats:
            log(f"buildings: skipping material {entry['name']['$value']}: no data texture or bounds")
    offsets = parse_offsets(json.loads((data_dir / "3dmap_view.ent.json").read_text()))
    parts: list[Boxes] = []
    for name in sorted(set(mats) | set(offsets)):  # offsets-only names are logged below
        if name not in DRAW_DISTRICTS:
            log(f"buildings: skipping district {name} (not in the drawn set)")
            continue
        if name not in mats or name not in offsets:
            log(f"buildings: skipping district {name}: missing {'material' if name not in mats else 'offset'}")
            continue
        tex_path = data_dir / f"{mats[name].texture}.xbm.json"
        if not tex_path.exists():
            log(f"buildings: skipping district {name}: {tex_path.name} not exported")
            continue
        b = decode_boxes(json.loads(tex_path.read_text()), mats[name], offsets[name])
        log(f"buildings: {name}: {len(b)} boxes (offset {offsets[name]})")
        parts.append(b)
    for name in sorted(set(DRAW_DISTRICTS) - set(mats) - set(offsets)):
        log(f"buildings: district {name} not found in the game data")
    return Boxes.concat(parts)
