"""Generate WolvenKit JSON for CBitmapTexture (BC7, 1 mip) and inkTextureAtlas resources."""
from __future__ import annotations

import base64
import copy


def bc7_layout(w: int, h: int) -> tuple[int, int]:
    row = max(1, (w + 3) // 4) * 16
    return row, row * max(1, (h + 3) // 4)


def make_xbm_json(template: dict, w: int, h: int, payload: bytes) -> dict:
    row, size = bc7_layout(w, h)
    if len(payload) != size:
        raise ValueError(f"BC7 payload is {len(payload)} bytes, expected {size} for {w}x{h}")
    j = copy.deepcopy(template)
    j["Data"]["BuildVersion"] = size   # the template stores the data size here; mirror it
    r = j["Data"]["RootChunk"]
    r["width"], r["height"] = w, h
    blob = r["renderTextureResource"]["renderResourceBlobPC"]["Data"]
    hd = blob["header"]
    hd["sizeInfo"]["width"], hd["sizeInfo"]["height"] = w, h
    mip = copy.deepcopy(hd["mipMapInfo"][0])
    mip["layout"]["rowPitch"], mip["layout"]["slicePitch"] = row, size
    mip["placement"]["offset"], mip["placement"]["size"] = 0, size
    hd["mipMapInfo"] = [mip]
    ti = hd["textureInfo"]
    ti["mipCount"], ti["sliceSize"], ti["textureDataSize"] = 1, size, size
    blob["textureData"]["Bytes"] = base64.b64encode(payload).decode("ascii")
    r["setup"]["hasMipchain"] = 0
    r["setup"]["compression"] = "TCM_QualityColor"
    return j


def make_inkatlas_json(template: dict, xbm_depot: str, parts: dict[str, tuple[int, int, int, int]],
                       w: int, h: int) -> dict:
    j = copy.deepcopy(template)
    r = j["Data"]["RootChunk"]
    proto_slot = r["slots"]["Elements"][0]
    proto_part = proto_slot["parts"][0]
    mappers = []
    for name, (left, top, right, bottom) in parts.items():
        m = copy.deepcopy(proto_part)
        m["clippingRectInUVCoords"] = {"$type": "RectF", "Left": left / w, "Top": top / h,
                                       "Right": right / w, "Bottom": bottom / h}
        m["partName"] = {"$type": "CName", "$storage": "string", "$value": name}
        mappers.append(m)
    slots = []
    for _ in range(3):   # 4K, 1080p and 720p slots all use the same texture
        s = copy.deepcopy(proto_slot)
        s["texture"]["DepotPath"]["$value"] = xbm_depot
        s["texture"]["DepotPath"]["$storage"] = "string"
        s["parts"] = copy.deepcopy(mappers)
        s["slices"] = []
        slots.append(s)
    r["slots"]["Elements"] = slots
    return j
