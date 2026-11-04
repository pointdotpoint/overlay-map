import base64
import json
from pathlib import Path

import numpy as np

import pytest

from nmtiles.minimap import (_DT_D, _check_identity, _node_index, wolvenkit_exe, MAJOR_WIDTH_M, classify, classify_width, decode_sector, decode_shapes, fill_ranges, quantize, resolve_sectors,
                             sector_nodes, shadowed_base, decode_with_fallback)

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
    # d3 == 0 with d2>>6 == 0 is NOT compact (guard): normal packing, here an empty range at start 3
    g = np.zeros(1, _DT_D)
    g[0] = (3, 0, 3, 0)
    start, count = fill_ranges(g)
    assert start[0] == 3 and count[0] == 0


def test_quantization_endpoints():
    q = quantize(np.array([0, 65535]), bias=-5.5, scale=13.0)
    assert q[0] == np.float32(-5.5)
    assert abs(q[1] - 7.5) < 1e-5


def rect(w, h):
    return np.array([[(0, 0), (w, 0), (w, h)], [(0, 0), (w, h), (0, h)]], np.float32)


def test_classify_uses_elevation_per_spec_11_6():
    assert classify(rect(10, 40), z=5) == "road"
    assert classify(rect(10, 40), z=50) == "road"          # elevated but narrow: freeway
    assert classify(rect(40, 60), z=50) == "stroke"        # elevated and wide: a rooftop plate
    assert classify(rect(10, 40), z=120) == "stroke"       # too high
    assert classify(rect(40, 60), z=5) == "road"


def test_classify_road_surface_flag_overrides_elevation():
    # B.flag 7 marks road surfaces. Wide elevated flag-7 shapes are highway bridges and overpasses (dropping them as
    # rooftops striped the highways with building footprints); wide elevated flag-1 shapes are rooftops.
    assert classify(rect(40, 60), z=50, flag=7) == "road"
    assert classify(rect(10, 40), z=120, flag=7) == "road"
    assert classify(rect(40, 60), z=50, flag=1) == "stroke"
    assert classify(rect(0.8, 12), z=5, flag=7) == "stroke"   # still too thin to be a road area


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
    assert [p for p, _ in out] == [(128.0, 2.0, 0.0)]    # interior, soft ref, non-minimap node and -inf scale skipped


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


def synth_root(tri_q, c_xyz, d=(0, 0, 3 << 6, 0)):
    """One shape, one triangle; quantization bias 0 / scale 65535 so quantized coordinates are metres."""
    P = np.array(tri_q, "<u2").reshape(-1, 2)
    buf = (np.array([(0, 1, 0)], [("a", "<u4"), ("n", "<u2"), ("g", "<u2")]).tobytes()      # A
           + np.array([(2, 1)], "<u2").tobytes()                                            # B
           + np.array(c_xyz, "<f4").tobytes()                                               # C
           + np.array(d, "<u2").tobytes()                                                   # D
           + P.tobytes() + np.array([0, 1, 2], "<u2").tobytes())                            # P, F
    return {"NumBorderPoints": len(P), "NumFillPoints": 3, "NumShapes": 1, "NumSpatialBuckets": 0,
            "NumUniqueGeometry": 0, "NumOwners": 0, "QuantizationBias": {"X": 0.0, "Y": 0.0},
            "QuantizationScale": {"X": 65535.0, "Y": 65535.0}, "Buffer": {"Bytes": base64.b64encode(buf).decode()}}


def test_instance_offset_and_node_translation():
    root = synth_root([(0, 0), (10, 0), (0, 10)], (10.0, 20.0, 5.0))
    (sh,) = decode_shapes(root)
    assert sh.z == 5.0 and (sh.type, sh.flag) == (2, 1)
    np.testing.assert_allclose(sh.tris[0], [(10, 20), (20, 20), (10, 30)])             # C.xy added
    sector = {"Data": {"RootChunk": {
        "nodes": [{"Data": {"$type": "MinimapDataNode", "allInteriorShapes": False,
                            "encodedShapesRef": {"DepotPath": {"$value": "a"}}}}],
        "nodeData": {"Data": [{"NodeIndex": 0, "Position": {"X": 100.0, "Y": 200.0, "Z": 0.0}}]}},
        "EmbeddedFiles": [{"FileName": {"$value": "a"}, "Content": root}]}}
    road, major, stroke, nodes = decode_sector(sector)
    assert nodes == 1 and len(stroke) == 0 and len(major) == 0
    np.testing.assert_allclose(road[0], [(110, 220), (120, 220), (110, 230)])        # node position added, thickness 5 -> road
    # thin triangle -> stroke; a shape with zero triangles is dropped
    thin = synth_root([(0, 0), (20, 0), (0, 1)], (0.0, 0.0, 0.0))
    sector["Data"]["EmbeddedFiles"][0]["Content"] = thin
    road, major, stroke, _ = decode_sector(sector)
    assert len(road) + len(major) == 0 and len(stroke) == 1
    sector["Data"]["EmbeddedFiles"][0]["Content"] = synth_root([(0, 0), (20, 0), (0, 1)], (0.0, 0.0, 0.0), d=(0, 0, 0, 0))
    road, major, stroke, _ = decode_sector(sector)
    assert len(road) == 0 and len(stroke) == 0
    # non-identity node transform is an error
    sector["Data"]["EmbeddedFiles"][0]["Content"] = root
    sector["Data"]["RootChunk"]["nodeData"]["Data"][0]["Scale"] = {"X": 2.0, "Y": 1.0, "Z": 1.0}
    with pytest.raises(ValueError, match="non-identity"):
        decode_sector(sector)


def test_compact_d_record_decodes_through_buffer():
    # compact packing: start = (d1>>3) | (d2&63)<<13 = 0, count = d3>>3 = 3
    root = synth_root([(0, 0), (10, 0), (0, 10)], (0.0, 0.0, 0.0), d=(0xFFFF, 0, 0, 3 << 3))
    (sh,) = decode_shapes(root)
    assert len(sh.tris) == 1


def test_corrupt_fill_range_raises():
    with pytest.raises(ValueError, match="fill range"):
        decode_shapes(synth_root([(0, 0), (10, 0), (0, 10)], (0.0, 0.0, 0.0), d=(0, 0, 9 << 6, 0)))


def test_node_z_is_added_before_classifying():
    # thick plate (area 1800 / extent 60 = 30 m, >= 25) at local z 5: a ground road at node Z 0, a rooftop plate at Z 64
    root = synth_root([(0, 0), (60, 0), (0, 60)], (0.0, 0.0, 5.0))

    def sector(node_z):
        return {"Data": {"RootChunk": {
            "nodes": [{"Data": {"$type": "MinimapDataNode", "allInteriorShapes": False,
                                "encodedShapesRef": {"DepotPath": {"$value": "a"}}}}],
            "nodeData": {"Data": [{"NodeIndex": 0, "Position": {"X": 0.0, "Y": 0.0, "Z": node_z}}]}},
            "EmbeddedFiles": [{"FileName": {"$value": "a"}, "Content": root}]}}

    road, major, stroke, _ = decode_sector(sector(0.0))
    assert len(road) + len(major) == 1 and len(stroke) == 0   # width 30 m: a major road
    road, major, stroke, _ = decode_sector(sector(64.0))
    assert len(road) + len(major) == 0 and len(stroke) == 1


def _rect(w, h):
    return np.array([[(0, 0), (w, 0), (w, h)], [(0, 0), (w, h), (0, h)]], np.float32)


def test_classify_width_wide_vs_narrow():
    assert abs(classify_width(_rect(40, 20)) - 20.0) < 0.5
    assert abs(classify_width(_rect(40, 6)) - 6.0) < 0.5
    assert classify_width(np.zeros((0, 3, 2), np.float32)) == 0.0


def test_decode_sector_keeps_major_and_minor_roads_apart():
    def sector(root):
        return {"Data": {"RootChunk": {
            "nodes": [{"Data": {"$type": "MinimapDataNode", "allInteriorShapes": False,
                                "encodedShapesRef": {"DepotPath": {"$value": "a"}}}}],
            "nodeData": {"Data": [{"NodeIndex": 0, "Position": {"X": 0.0, "Y": 0.0, "Z": 0.0}}]}},
            "EmbeddedFiles": [{"FileName": {"$value": "a"}, "Content": root}]}}
    wide = synth_root([(0, 0), (60, 0), (0, 60)], (0.0, 0.0, 0.0))      # width 30 m (ground)
    narrow = synth_root([(0, 0), (20, 0), (0, 10)], (0.0, 0.0, 0.0))    # width 5 m
    road, major, stroke, _ = decode_sector(sector(wide))
    assert len(road) == 0 and len(major) == 1 and len(stroke) == 0
    road, major, stroke, _ = decode_sector(sector(narrow))
    assert len(road) == 1 and len(major) == 0 and len(stroke) == 0
    assert 5.0 < MAJOR_WIDTH_M < 30.0


def test_wolvenkit10_schema_sector_decodes():
    """Trimmed real WolvenKit 10 output: nodeData uses a string nodeIdx, transform.position / orientation and scale."""
    import json
    from pathlib import Path
    sector = json.loads((Path(__file__).parent / "fixtures" / "sector_wk10_trim.json").read_text())
    nd = sector["Data"]["RootChunk"]["nodeData"]["Data"][0]
    assert isinstance(nd["nodeIdx"], str) and "NodeIndex" not in nd and "Position" not in nd
    road, major, stroke, nodes = decode_sector(sector)
    assert nodes == 1 and len(road) + len(major) + len(stroke) > 0
    pos = nd["transform"]["position"]
    allv = np.concatenate([road, major, stroke]).reshape(-1, 2)
    assert abs(allv[:, 0].mean() - pos["X"]) < 600 and abs(allv[:, 1].mean() - pos["Y"]) < 600      # offset applied


def test_wolvenkit10_node_lookup_and_transform_check():
    nd = {"nodeIdx": "7", "transform": {"position": {"X": 1.0, "Y": 2.0, "Z": 3.0, "W": 0},
                                        "orientation": {"i": 0, "j": 0, "k": 0, "r": 1}}, "scale": {"X": 1, "Y": 1, "Z": 1}}
    assert _node_index(nd) == 7 and _node_index({"NodeIndex": 4}) == 4
    _check_identity(nd)
    nd["transform"]["orientation"] = {"i": 0, "j": 0, "k": 0.7, "r": 0.7}
    with pytest.raises(ValueError, match="non-identity"):
        _check_identity(nd)
    nd["transform"]["orientation"] = {"i": 0, "j": 0, "k": 0, "r": 1}
    nd["scale"] = {"X": 2, "Y": 1, "Z": 1}
    with pytest.raises(ValueError, match="non-identity"):
        _check_identity(nd)


def test_wolvenkit_executable_comes_from_env(monkeypatch):
    monkeypatch.delenv("OVERLAYMAP_WOLVENKIT", raising=False)
    assert wolvenkit_exe() == "WolvenKit.CLI"
    monkeypatch.setenv("OVERLAYMAP_WOLVENKIT", "~/x/wk10")
    assert wolvenkit_exe().endswith("/x/wk10") and not wolvenkit_exe().startswith("~")


def test_convert_dir_keeps_only_complete_outputs(tmp_path, monkeypatch):
    from nmtiles import minimap
    src, out = tmp_path / "src", tmp_path / "out"
    src.mkdir(); out.mkdir()

    def fake(*args, check=True):
        o = Path(args[args.index("-o") + 1])
        (o / "a.streamingsector.json").write_text('{"x": 1}')
        (o / "b.streamingsector.json").write_text("")          # WolvenKit 8: 0 bytes, rc 0
        return None
    monkeypatch.setattr(minimap, "_wk", fake)
    kept = minimap._convert_dir(src, out, {"a.streamingsector", "b.streamingsector"})
    assert kept == 1 and (out / "a.streamingsector.json").exists() and not (out / "b.streamingsector.json").exists()
    assert not (out / ".tmp_batch").exists()


def test_shadowed_base_lists_base_copies_an_ep1_copy_replaces():
    base = [r"base\worlds\x\default\exterior_0_0_0_3.streamingsector", r"base\worlds\x\default\exterior_1_0_0_3.streamingsector"]
    ep1 = [r"base\worlds\x\default\exterior_0_0_0_3.streamingsector", r"base\worlds\x\default\ep1\exterior_1_0_0_3.streamingsector"]
    assert shadowed_base(base, ep1) == {"exterior_0_0_0_3.streamingsector": base[0].replace("\\", "/")}


def _one_node_sector(root):
    return {"Data": {"RootChunk": {
        "nodes": [{"Data": {"$type": "MinimapDataNode", "allInteriorShapes": False,
                            "encodedShapesRef": {"DepotPath": {"$value": "a"}}}}],
        "nodeData": {"Data": [{"NodeIndex": 0, "Position": {"X": 0.0, "Y": 0.0, "Z": 0.0}}]}},
        "EmbeddedFiles": [{"FileName": {"$value": "a"}, "Content": root}]}}


_EMPTY_SECTOR = {"Data": {"RootChunk": {"nodes": [], "nodeData": {"Data": []}}, "EmbeddedFiles": []}}


def test_ep1_copy_without_minimap_nodes_falls_back_to_the_base_copy():
    # Phantom Liberty re-cooked 22 sectors with no MinimapDataNode at all (Kabuki, Vista del Rey, Dogtown...)
    base = _one_node_sector(synth_root([(0, 0), (20, 0), (0, 10)], (0.0, 0.0, 0.0)))
    road, major, stroke, n = decode_with_fallback(_EMPTY_SECTOR, lambda: base)
    assert n == 1 and len(road) == 1


def test_ep1_copy_with_minimap_nodes_wins_over_the_base_copy():
    ep1 = _one_node_sector(synth_root([(0, 0), (60, 0), (0, 60)], (0.0, 0.0, 0.0)))
    base = _one_node_sector(synth_root([(0, 0), (20, 0), (0, 10)], (0.0, 0.0, 0.0)))
    road, major, stroke, n = decode_with_fallback(ep1, lambda: base)
    assert len(major) == 1 and len(road) == 0
    assert decode_with_fallback(_EMPTY_SECTOR, None)[3] == 0
