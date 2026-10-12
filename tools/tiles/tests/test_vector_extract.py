import numpy as np
import pytest

from nmtiles.buildings import Boxes, box_corners
from nmtiles.glb import Mesh
from nmtiles.vector_config import VLevel
from nmtiles.vector_extract import Sources, area_features, block_features, height_style, line_features
from nmtiles.world import Transform

TF = Transform(1.0, -1.0, 0.0, 0.0)                 # world = (gx, -gz)
LV = VLevel("T", 0.5, 1.0, 0.25, 50.0, 0.5, 0.0, 2.0, 0.0, 20.0)


def quad(x0, y0, x1, y1, name="q"):
    pos = np.array([[x0, 0, -y0], [x1, 0, -y0], [x1, 0, -y1], [x0, 0, -y1]], float)
    return Mesh(name, pos, np.array([[0, 1, 2], [0, 2, 3]]))


def strip(p0, p1, width, name="road"):
    d = np.array(p1, float) - np.array(p0, float)
    n = np.array([-d[1], d[0]]) / np.hypot(*d) * width / 2
    c = [np.array(p0) + n, np.array(p1) + n, np.array(p1) - n, np.array(p0) - n]
    pos = np.array([[x, 0, -y] for x, y in c], float)
    return Mesh(name, pos, np.array([[0, 1, 2], [0, 2, 3]]))


def boxes(*rows):
    a = np.array(rows, float)   # cx, cy, dx, dy, dz, yaw
    return Boxes(a[:, 0], a[:, 1], a[:, 2], a[:, 3], a[:, 4], a[:, 5])


def test_road_strip_gives_two_edges_across_the_cell():
    cell = (0.0, 0.0, 50.0, 50.0)
    shapes = line_features([strip((-20, 25), (70, 25), 10)], TF, cell, LV, "road")
    assert len(shapes) == 2 and all(s.style == "road" for s in shapes)
    ys = sorted(float(np.mean(s.pts[:, 1])) for s in shapes)
    assert ys[0] == pytest.approx(20.0, abs=0.3) and ys[1] == pytest.approx(30.0, abs=0.3)
    for s in shapes:
        assert s.pts[:, 0].min() == pytest.approx(0.0) and s.pts[:, 0].max() == pytest.approx(50.0)
        assert s.prio == pytest.approx(50.0, abs=0.5)


def test_road_width_filter_drops_narrow_roads():
    cell = (0.0, 0.0, 50.0, 50.0)
    assert line_features([strip((-20, 25), (70, 25), 6)], TF, cell, LV, "road", min_width=8.0) == []
    assert len(line_features([strip((-20, 25), (70, 25), 10)], TF, cell, LV, "road", min_width=8.0)) == 2


def test_road_edges_meet_exactly_at_shared_cell_edge():
    road = [strip((-20, 0), (120, 50), 8)]
    a = line_features(road, TF, (0.0, 0.0, 50.0, 50.0), LV, "road")
    b = line_features(road, TF, (50.0, 0.0, 100.0, 50.0), LV, "road")
    ends_a = sorted(round(float(p[1]), 6) for s in a for p in (s.pts[0], s.pts[-1]) if abs(p[0] - 50.0) < 1e-9)
    ends_b = sorted(round(float(p[1]), 6) for s in b for p in (s.pts[0], s.pts[-1]) if abs(p[0] - 50.0) < 1e-9)
    assert len(ends_a) == 2 and ends_a == ends_b


def test_land_minus_water_clipped_to_cell():
    src = Sources([], [], [quad(-100, -100, 200, 200)], [quad(-100, -100, 25, 200)], boxes([0, 0, 1, 1, 1, 0]), TF)
    cell = (0.0, 0.0, 50.0, 50.0)
    shapes = area_features(src, cell, LV)
    land = [s for s in shapes if s.style == "land"]
    water = [s for s in shapes if s.style == "water"]
    assert len(land) == 1 and len(water) == 1
    assert land[0].prio == pytest.approx(25 * 50, rel=0.02) and water[0].prio == pytest.approx(25 * 50, rel=0.02)
    for s in shapes:
        assert np.allclose(s.pts[0], s.pts[-1])
        assert s.pts[:, 0].min() >= -1e-9 and s.pts[:, 0].max() <= 50 + 1e-9


def _blocks(rows, cell, level=LV):
    b = boxes(*rows)
    corners = box_corners(b)
    return block_features(corners, corners.mean(axis=1), np.asarray(b.dz), cell, level)


def test_blocks_merge_within_gap_and_bucket_by_height():
    cell = (0.0, 0.0, 50.0, 50.0)
    out = _blocks([[20, 25, 8, 8, 10, 0], [29, 25, 8, 8, 100, 0]], cell)      # 1 m apart, gap 2 m
    assert len(out) == 1 and out[0].style == "block2"
    assert np.allclose(out[0].pts[0], out[0].pts[-1])
    apart = _blocks([[10, 25, 8, 8, 10, 0], [30, 25, 8, 8, 10, 0]], cell)     # 12 m apart
    assert len(apart) == 2 and {s.style for s in apart} == {"block0"}


def test_block_owned_only_by_centroid_cell():
    rows = [[60, 25, 8, 8, 10, 0]]          # centre in the neighbour cell
    assert _blocks(rows, (0.0, 0.0, 50.0, 50.0)) == []
    assert len(_blocks(rows, (50.0, 0.0, 100.0, 50.0))) == 1


def test_block_min_area_filter():
    lv = VLevel("T", 0.5, 1.0, 0.25, 50.0, 0.5, 0.0, 2.0, 100.0, 20.0)
    assert _blocks([[25, 25, 6, 6, 10, 0]], (0.0, 0.0, 50.0, 50.0), lv) == []
    assert len(_blocks([[25, 25, 12, 12, 10, 0]], (0.0, 0.0, 50.0, 50.0), lv)) == 1


def test_height_style_buckets():
    assert (height_style(5), height_style(30), height_style(79.9), height_style(80)) == ("block0", "block1", "block1", "block2")
