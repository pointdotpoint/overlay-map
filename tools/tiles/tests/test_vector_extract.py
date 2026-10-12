import numpy as np
import pytest

from nmtiles.buildings import Boxes, box_corners
from nmtiles.glb import Mesh
from nmtiles.vector_config import VLevel
from dataclasses import replace

import shapely
from shapely.geometry import Polygon

from nmtiles.vector_extract import (Sources, area_features, block_features, height_style, line_features,
                                    road_features)
from nmtiles.vector_geom import polygon_rings, split_holes
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



CELL = (0.0, 0.0, 50.0, 50.0)


def _poly(s):
    return Polygon(s.pts)


def test_road_features_strip_is_one_filled_polygon():
    shapes = road_features([strip((-20, 25), (70, 25), 10)], TF, CELL, LV)
    assert len(shapes) == 1 and shapes[0].style == "road"
    s = shapes[0]
    assert np.allclose(s.pts[0], s.pts[-1])
    assert _poly(s).area == pytest.approx(500.0, abs=1.0)
    assert s.prio == pytest.approx(_poly(s).area, rel=1e-6)
    assert s.pts.min() >= -1e-6 and s.pts.max() <= 50 + 1e-6


def test_road_width_filter_drops_narrow_roads():
    assert road_features([strip((-20, 25), (70, 25), 6)], TF, CELL, LV, min_width=8.0) == []
    assert len(road_features([strip((-20, 25), (70, 25), 10)], TF, CELL, LV, min_width=8.0)) == 1


def test_ring_road_is_split_into_hole_free_pieces():
    c, h, w = 50.0, 20.0, 6.0
    ring = [strip((c - h, c - h), (c + h, c - h), w), strip((c + h, c - h), (c + h, c + h), w),
            strip((c + h, c + h), (c - h, c + h), w), strip((c - h, c + h), (c - h, c - h), w)]
    cell = (0.0, 0.0, 100.0, 100.0)
    shapes = road_features(ring, TF, cell, LV)
    assert len(shapes) >= 2
    polys = [_poly(s) for s in shapes]
    assert all(not p.interiors for p in polys)
    expect = shapely.union_all([Polygon(m.positions[:, [0, 2]] * [1, -1]) for m in ring]).area
    assert sum(p.area for p in polys) == pytest.approx(expect, rel=1e-3)
    for i in range(len(polys)):
        for j in range(i + 1, len(polys)):
            assert polys[i].intersection(polys[j]).area < 1e-3


def test_split_holes_covers_polygon_exactly():
    poly = Polygon([(0, 0), (40, 0), (40, 30), (0, 30)], [[(10, 10), (30, 10), (30, 20), (10, 20)]])
    pieces = split_holes(poly)
    assert len(pieces) >= 2 and all(not p.interiors for p in pieces)
    assert sum(p.area for p in pieces) == pytest.approx(poly.area, rel=1e-6)
    assert shapely.union_all(pieces).symmetric_difference(poly).area < 1e-6
    assert split_holes(Polygon([(0, 0), (1, 0), (1, 1)])) [0].area == pytest.approx(0.5)


def test_split_holes_hole_at_extreme_first_coordinate():
    poly = Polygon([(0, 0), (40, 0), (40, 30), (0, 30)], [[(10, 10), (10, 20), (30, 20), (30, 10)]])
    pieces = split_holes(poly)
    assert all(not p.interiors for p in pieces)
    assert sum(p.area for p in pieces) == pytest.approx(poly.area, rel=1e-6)


def test_polygon_rings_clip_simplify_and_min_area():
    g = Polygon([(-10, -10), (60, -10), (60, 60), (-10, 60)])
    (r,) = polygon_rings(g, CELL, 0.25, 1.0)
    assert np.allclose(r[0], r[-1]) and Polygon(r).area == pytest.approx(2500.0)
    assert polygon_rings(g, CELL, 0.25, 3000.0) == []
    assert polygon_rings(Polygon(), None, 0.25, 0.0) == []


def test_road_pieces_meet_exactly_at_shared_cell_edge():
    road = [strip((-20, 25), (120, 25), 10)]
    a = road_features(road, TF, (0.0, 0.0, 50.0, 50.0), LV)
    b = road_features(road, TF, (50.0, 0.0, 100.0, 50.0), LV)
    assert len(a) == 1 and len(b) == 1
    assert a[0].pts[:, 0].max() == pytest.approx(50.0, abs=1e-6)
    assert b[0].pts[:, 0].min() == pytest.approx(50.0, abs=1e-6)
    assert _poly(a[0]).area + _poly(b[0]).area == pytest.approx(500.0 + 500.0, abs=2.0)


def test_water_minus_land_clipped_to_cell():
    src = Sources([], [], [quad(-100, -100, 25, 200)], [quad(-100, -100, 200, 200)], boxes([0, 0, 1, 1, 1, 0]), TF)
    shapes = area_features(src, CELL, LV)
    water = [s for s in shapes if s.style == "water"]
    assert len(shapes) == 1 and len(water) == 1          # land is not extracted
    assert _poly(water[0]).area == pytest.approx(25 * 50, abs=1.0) and water[0].pts[:, 0].min() == pytest.approx(25.0)
    for s in shapes:
        assert np.allclose(s.pts[0], s.pts[-1])
        assert s.pts.min() >= -1e-9 and s.pts.max() <= 50 + 1e-9


def _blocks(rows, cell=CELL, level=LV, stats=None):
    b = boxes(*rows)
    corners = box_corners(b)
    return block_features(corners, corners.mean(axis=1), np.asarray(b.dz), cell, level, stats)


def test_blocks_merge_within_gap():
    lv = replace(LV, merge_gap=4.0)
    assert len(_blocks([[20, 25, 10, 10, 10, 0], [32, 25, 10, 10, 10, 0]], level=lv)) == 1       # 2 m apart
    assert len(_blocks([[20, 25, 10, 10, 10, 0], [40, 25, 10, 10, 10, 0]], level=lv)) == 2       # 10 m apart


def test_opening_removes_thin_slab():
    lv = replace(LV, merge_gap=2.0, open_width=3.0)
    out = _blocks([[25, 25, 10, 10, 10, 0], [40, 25, 20, 1, 10, 0]], level=lv)     # slab x 30..50, 1 m thin
    assert len(out) == 1
    assert _poly(out[0]).area == pytest.approx(100.0, abs=5.0)
    assert out[0].pts[:, 0].max() < 32


def test_block_height_bucket_is_max_of_merged_boxes():
    out = _blocks([[20, 25, 8, 8, 20, 0], [28, 25, 8, 8, 90, 0]])
    assert len(out) == 1 and out[0].style == "block2"
    assert np.allclose(out[0].pts[0], out[0].pts[-1])
    lone = _blocks([[20, 25, 8, 8, 20, 0]])
    assert [s.style for s in lone] == ["block0"]


def test_block_owned_only_by_centroid_cell():
    rows = [[60, 25, 8, 8, 10, 0]]          # centre in the neighbour cell
    assert _blocks(rows, (0.0, 0.0, 50.0, 50.0)) == []
    assert len(_blocks(rows, (50.0, 0.0, 100.0, 50.0))) == 1


def test_block_min_area_filter():
    lv = replace(LV, min_area=100.0)
    assert _blocks([[25, 25, 6, 6, 10, 0]], level=lv) == []
    assert len(_blocks([[25, 25, 12, 12, 10, 0]], level=lv)) == 1


def test_height_style_buckets():
    assert (height_style(5), height_style(30), height_style(79.9), height_style(80)) == ("block0", "block1", "block1", "block2")


def test_block_touching_window_border_is_dropped():
    stats = {}
    assert _blocks([[25, 25, 140, 8, 10, 0]], stats=stats) == []          # runs off both window sides
    assert stats["dropped"] == 1
    assert len(_blocks([[25, 25, 8, 8, 10, 0]])) == 1


def test_metro_line_features_still_trace_edges():
    shapes = line_features([strip((-20, 25), (70, 25), 10)], TF, CELL, LV, "metro")
    assert len(shapes) == 2 and all(s.style == "metro" for s in shapes)
