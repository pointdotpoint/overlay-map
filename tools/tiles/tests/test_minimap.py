import base64
import json
from pathlib import Path

import numpy as np

from nmtiles.minimap import (_DT_D, classify, decode_shapes, fill_ranges, quantize, resolve_sectors,
                             sector_nodes)

SAMPLE = Path(__file__).parent / "data" / "minimap_sample.json"


def _root():
    return json.loads(SAMPLE.read_text())["Data"]["RootChunk"]


def test_fixture_decodes_consistently():
    root = _root()
    shapes = decode_shapes(root)
    assert len(shapes) == root["NumShapes"]
    # re-derive the fill ranges from the raw buffer
    from nmtiles.minimap import _unpack
    u = _unpack(root)
    nb, nf = root["NumBorderPoints"], root["NumFillPoints"]
    assert u["F"].max() < nb
    spans = sorted(zip(u["start"].tolist(), u["count"].tolist()))
    pos = 0
    for s, c in spans:
        assert s == pos
        pos += c
    assert pos == nf
    assert sum(len(s.tris) for s in shapes) == nf // 3
    assert all(s.tris.shape[1:] == (3, 2) for s in shapes)


def test_d_record_packings():
    d = np.zeros(2, _DT_D)
    # normal: start = d0 | (d1 & 7) << 16, count = (d2 >> 6) | d3 << 10
    d[0] = (0x1234, 0x0003, (5 << 6) | 7, 0x0000)
    d[1] = (0x0001, 0x0001, (2 << 6), 3)             # d2>>6 != 0 -> still normal
    start, count = fill_ranges(d)
    assert start[0] == 0x1234 | (3 << 16) and count[0] == 5
    assert start[1] == 1 | (1 << 16) and count[1] == 2 | (3 << 10)
    # compact: d2>>6 == 0 and d3 > 0 -> start = (d1 >> 3) | (d2 & 63) << 13, count = d3 >> 3
    c = np.zeros(1, _DT_D)
    c[0] = (0xFFFF, (7 << 3) | 5, 9, 6 << 3)
    start, count = fill_ranges(c)
    assert start[0] == 7 | (9 << 13) and count[0] == 6


def test_quantization_endpoints():
    q = quantize(np.array([0, 65535]), bias=-5.5, scale=13.0)
    assert q[0] == np.float32(-5.5)
    assert abs(q[1] - 7.5) < 1e-5


def test_classify_thickness():
    def rect(w, h):
        a, b, c, d = (0, 0), (w, 0), (w, h), (0, h)
        return np.array([[a, b, c], [a, c, d]], np.float32)
    assert classify(rect(10, 40)) == "road"
    assert classify(rect(0.8, 12)) == "stroke"
    assert classify(np.zeros((0, 3, 2), np.float32)) == "stroke"


def _enc(scale=1.0, nb=3):
    return {"$type": "minimapEncodedShapes", "QuantizationScale": {"X": scale, "Y": scale}, "NumBorderPoints": nb,
            "Buffer": {"Bytes": base64.b64encode(b"").decode()}}


def test_sector_nodes_filters():
    def node(i, interior=False, path="a.minimapshapes"):
        return {"Data": {"$type": "MinimapDataNode", "allInteriorShapes": interior,
                         "encodedShapesRef": {"DepotPath": {"$value": path}}}}

    def nd(i, x):
        return {"NodeIndex": i, "Position": {"X": x, "Y": 2.0, "Z": 0.0}}

    sector = {"Data": {
        "RootChunk": {"nodes": [node(0, path="a"), node(1, interior=True, path="b"), node(2, path="missing"),
                                {"Data": {"$type": "worldMeshNode"}}, node(4, path="c")],
                      "nodeData": {"Data": [nd(0, 128.0), nd(1, 256.0), nd(2, 384.0), nd(3, 0.0), nd(4, 512.0)]}},
        "EmbeddedFiles": [{"FileName": {"$value": "a"}, "Content": _enc()},
                          {"FileName": {"$value": "b"}, "Content": _enc()},
                          {"FileName": {"$value": "c"}, "Content": {**_enc(), "QuantizationScale": {"X": "-inf", "Y": "-inf"}}}]}}
    out = sector_nodes(sector)
    assert [p for p, _ in out] == [(128.0, 2.0)]    # interior, soft ref, non-minimap node and -inf scale skipped


def test_ep1_precedence():
    base = [r"base\worlds\x\exterior_0_0_0_3.streamingsector", r"base\worlds\x\exterior_1_0_0_3.streamingsector"]
    ep1 = [r"base\worlds\x\exterior_0_0_0_3.streamingsector", r"base\worlds\x\exterior_2_0_0_3.streamingsector"]
    r = resolve_sectors(base, ep1)
    assert r["exterior_0_0_0_3.streamingsector"][0] == "ep1"
    assert r["exterior_1_0_0_3.streamingsector"][0] == "base"
    assert r["exterior_2_0_0_3.streamingsector"][0] == "ep1"
    assert len(r) == 3


def test_same_name_in_ep1_subdir_is_a_separate_sector():
    base = [r"base\worlds\03_night_city\_compiled\default\exterior_0_0_0_3.streamingsector"]
    ep1 = [r"base\worlds\03_night_city\_compiled\default\exterior_0_0_0_3.streamingsector",
           r"base\worlds\03_night_city\_compiled\default\ep1\exterior_0_0_0_3.streamingsector"]
    r = resolve_sectors(base, ep1)
    assert set(r) == {"exterior_0_0_0_3.streamingsector", "ep1/exterior_0_0_0_3.streamingsector"}
    assert r["exterior_0_0_0_3.streamingsector"][0] == "ep1"
