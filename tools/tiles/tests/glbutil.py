"""Build minimal GLB files in memory for tests."""
import json
import struct

import numpy as np


def make_glb(nodes):
    """nodes: list of (name, positions (N,3), indices (M,3))."""
    bin_ = b""
    views, accessors, meshes, gnodes = [], [], [], []
    for i, (name, pos, idx) in enumerate(nodes):
        pos = np.asarray(pos, np.float32)
        idx = np.asarray(idx, np.uint32).reshape(-1)
        views.append({"buffer": 0, "byteOffset": len(bin_), "byteLength": pos.nbytes})
        bin_ += pos.tobytes()
        accessors.append({"bufferView": len(views) - 1, "componentType": 5126, "count": len(pos),
                          "type": "VEC3", "min": pos.min(0).tolist(), "max": pos.max(0).tolist()})
        views.append({"buffer": 0, "byteOffset": len(bin_), "byteLength": idx.nbytes})
        bin_ += idx.tobytes()
        accessors.append({"bufferView": len(views) - 1, "componentType": 5125, "count": len(idx), "type": "SCALAR"})
        meshes.append({"primitives": [{"attributes": {"POSITION": len(accessors) - 2}, "indices": len(accessors) - 1}]})
        gnodes.append({"name": name, "mesh": i})
    while len(bin_) % 4:
        bin_ += b"\0"
    js = {"asset": {"version": "2.0"}, "buffers": [{"byteLength": len(bin_)}], "bufferViews": views,
          "accessors": accessors, "meshes": meshes, "nodes": gnodes}
    jb = json.dumps(js).encode()
    jb += b" " * ((4 - len(jb) % 4) % 4)
    total = 12 + 8 + len(jb) + 8 + len(bin_)
    return (struct.pack("<III", 0x46546C67, 2, total) + struct.pack("<II", len(jb), 0x4E4F534A) + jb
            + struct.pack("<II", len(bin_), 0x004E4942) + bin_)


def square(x0, z0, x1, z1, y=0.0):
    """Two triangles covering glTF x in [x0,x1], z in [z0,z1] at height y."""
    pos = [(x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1)]
    return pos, [(0, 1, 2), (0, 2, 3)]
