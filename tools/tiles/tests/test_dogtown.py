import numpy as np
import shapely

from nmtiles.buildings import Boxes
from nmtiles.dogtown import box_tris, drop_inside, region, split_major
from nmtiles.minimap import MAJOR_WIDTH_M


def _boxes(cx, cy, d=10.0):
    n = len(cx)
    return Boxes(np.array(cx, float), np.array(cy, float), np.full(n, d), np.full(n, d), np.full(n, 5.0), np.zeros(n))


def _strip(x0, x1, y0, y1):
    return np.array([[(x0, y0), (x1, y0), (x1, y1)], [(x0, y0), (x1, y1), (x0, y1)]], np.float32)


def test_box_tris_cover_each_box_with_two_triangles():
    t = box_tris(_boxes([0.0, 100.0], [0.0, 0.0]))
    assert t.shape == (4, 3, 2)
    u, v = t[:, 1] - t[:, 0], t[:, 2] - t[:, 0]
    area = 0.5 * np.abs(u[:, 0] * v[:, 1] - u[:, 1] * v[:, 0]).sum()
    assert abs(area - 200.0) < 1e-6


def test_region_covers_the_district_and_its_streets_but_not_far_away():
    # a 200 m block of buildings every 20 m: the streets between them are inside the district
    xs, ys = np.meshgrid(np.arange(0, 201, 20.0), np.arange(0, 201, 20.0))
    g = region(_boxes(xs.ravel(), ys.ravel()))
    assert g.contains(shapely.Point(110, 110))     # street between buildings
    assert g.contains(shapely.Point(-20, 100))     # just outside the outer row (the wall's street)
    assert not g.contains(shapely.Point(400, 100))


def test_region_fills_an_empty_plaza_in_the_middle():
    ring = [(np.cos(a) * 150, np.sin(a) * 150) for a in np.linspace(0, 2 * np.pi, 80, endpoint=False)]
    g = region(_boxes([p[0] for p in ring], [p[1] for p in ring]))
    assert g.contains(shapely.Point(0, 0))


def test_drop_inside_keeps_only_triangles_whose_centre_is_outside():
    g = shapely.box(0, 0, 100, 100)
    tris = np.concatenate([_strip(10, 20, 10, 20), _strip(200, 210, 0, 10)])
    out = drop_inside(tris, g)
    assert len(out) == 2 and out[:, :, 0].min() >= 200
    assert drop_inside(np.zeros((0, 3, 2), np.float32), g).shape == (0, 3, 2)


def test_split_major_by_road_width():
    wide = _strip(0, 300, 0, 30)          # 30 m boulevard
    narrow = _strip(0, 300, 100, 106)     # 6 m lane
    minor, major = split_major(np.concatenate([wide, narrow]))
    assert len(major) == 2 and major[:, :, 1].max() <= 30.5
    assert len(minor) == 2 and minor[:, :, 1].min() >= 99.5
    assert 6.0 < MAJOR_WIDTH_M < 30.0


def test_a_wide_junction_between_lanes_stays_minor():
    lanes = np.concatenate([_strip(0, 100, 0, 8), _strip(130, 230, 0, 8)])
    junction = _strip(100, 130, -11, 19)      # 30 x 30 m crossing: wide, but no road of its own
    minor, major = split_major(np.concatenate([lanes, junction]))
    assert len(major) == 0 and len(minor) == 6
