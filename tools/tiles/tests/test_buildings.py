import base64
import json
import math
from pathlib import Path

import numpy as np

from nmtiles.buildings import (Boxes, DistrictMaterial, box_corners, decode_boxes, parse_materials,
                               parse_offsets)

FIX = Path(__file__).parent / "fixtures"


def _fixture(name):
    return json.loads((FIX / name).read_text())


def test_parse_materials_reads_real_values_and_skips_incomplete():
    mats = parse_materials(_fixture("triangle_soup_trim.mesh.json"))
    cc = mats["city_center"]
    assert cc.texture == "city_center_data"
    assert cc.trans_min == (-770.609192, -530.549133, -40.6581497)
    assert cc.trans_max == (1316.82483, 649.75531, 642.893127)
    assert math.isclose(cc.cube_size, 168.289993, rel_tol=1e-6)
    assert math.isclose(mats["westbrook"].cube_size, 197.0)
    assert "ep1_dogtown" in mats and "ep1_spaceport" in mats
    assert "sw5" not in mats          # no TransMin/TransMax


def test_parse_offsets_converts_fixed_point_and_strips_data_suffix():
    off = parse_offsets(_fixture("3dmap_view_trim.ent.json"))
    assert off["city_center"] == (-2116.63720703125, 106.50759887695312)
    assert math.isclose(off["westbrook"][0], -97.21, abs_tol=0.01)
    assert math.isclose(off["pacifica"][1], -2368.16, abs_tol=0.01)   # component "pacifica_data0633"
    assert off["ep1_spaceport"] == (-4200.0, 200.0)
    assert abs(off["ep1_dogtown"][0]) < 1e-3
    assert "target_point" not in off and "pacifica_transform" not in off


def _tex_json(px: np.ndarray) -> dict:
    """px: (rows, cols, 4) floats in 0..1 -> convert-s-shaped dict."""
    u16 = np.round(px * 65535).astype("<u2")
    raw = u16.tobytes() + b"\0" * 16          # trailing padding must be ignored
    return {"Data": {"RootChunk": {
        "height": px.shape[0], "width": px.shape[1],
        "renderTextureResource": {"renderResourceBlobPC": {"Data": {"textureData": {
            "Bytes": base64.b64encode(raw).decode()}}}}}}}


def _synthetic():
    # N = 2: 2 rows x 6 columns; sections at columns 0-1 (pos), 2-3 (rot), 4-5 (size)
    px = np.zeros((2, 6, 4))
    yaw = math.radians(90.0)
    for r in range(2):
        for c in range(2):
            px[r, c] = (0.5, 0.25, 0.1, 1.0)                       # pos, valid
            qz, qw = math.sin(yaw / 2), math.cos(yaw / 2)
            px[r, 2 + c] = (0.5, 0.5, (qz + 1) / 2, (qw + 1) / 2)   # q = (0,0,qz,qw)
            px[r, 4 + c] = (0.1, 0.05, 0.2, 1.0)                    # size / cube
    px[0, 0] = (0.0, 1.0, 0.0, 1.0)      # a box at TransMin.x, TransMax.y
    px[1, 1, 3] = 0.0                    # invalid box
    return px


def test_decode_boxes_centres_yaw_dims_and_invalid_skip():
    mat = DistrictMaterial("d_data", (0.0, 100.0, -10.0), (200.0, 300.0, 50.0), 100.0)
    b = decode_boxes(_tex_json(_synthetic()), mat, (1000.0, -500.0))
    assert len(b) == 3                                  # 4 pixels - 1 invalid
    # first pixel: pos = (0, 300, -10) + offset
    assert np.allclose(sorted(zip(b.cx, b.cy))[0], (1000.0, -200.0), atol=0.01)
    other = [(x, y) for x, y in zip(b.cx, b.cy) if abs(x - 1100.0) < 0.01]
    assert len(other) == 2 and np.allclose(other[0][1], -500.0 + 100.0 + 0.25 * 200.0, atol=0.01)
    assert np.allclose(b.yaw, math.radians(90.0), atol=1e-3)
    assert np.allclose(b.dx, 10.0, atol=0.01) and np.allclose(b.dy, 5.0, atol=0.01)
    assert np.allclose(b.dz, 20.0, atol=0.01)


def test_box_corners_yaw_90_swaps_axes():
    b0 = Boxes(*(np.array([v]) for v in (10.0, 20.0, 8.0, 2.0, 5.0, 0.0)))
    b1 = Boxes(*(np.array([v]) for v in (10.0, 20.0, 8.0, 2.0, 5.0, math.pi / 2)))
    c0, c1 = box_corners(b0)[0], box_corners(b1)[0]
    assert np.ptp(c0[:, 0]) == 8.0 and np.ptp(c0[:, 1]) == 2.0
    assert np.isclose(np.ptp(c1[:, 0]), 2.0) and np.isclose(np.ptp(c1[:, 1]), 8.0)
    assert np.allclose(c1.mean(axis=0), (10.0, 20.0))


def test_box_corners_yaw_45_rotates_counter_clockwise():
    b = Boxes(*(np.array([v]) for v in (0.0, 0.0, 10.0, 2.0, 5.0, math.pi / 4)))
    c = box_corners(b)[0]
    # corner order is (-,-), (+,-), (+,+), (-,+); (+,-) starts at (+5,-1) on the +X side
    cs = math.cos(math.pi / 4)
    assert np.allclose(c[1], (5 * cs + 1 * cs, 5 * cs - 1 * cs))
    assert c[1][1] > 0 and c[1][0] > 0      # +X end swings towards +Y (north)


def test_load_boxes_raises_when_a_drawn_district_is_missing(tmp_path):
    import pytest
    from nmtiles.buildings import BuildingDataError, load_boxes
    (tmp_path / "3dmap_triangle_soup.mesh.json").write_text((FIX / "triangle_soup_trim.mesh.json").read_text())
    (tmp_path / "3dmap_view.ent.json").write_text((FIX / "3dmap_view_trim.ent.json").read_text())
    with pytest.raises(BuildingDataError, match="city_center"):     # no data textures exported
        load_boxes(tmp_path, log=lambda _m: None)
