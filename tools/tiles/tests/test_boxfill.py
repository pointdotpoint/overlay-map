import numpy as np

from nmtiles import boxfill
from nmtiles.buildings import Boxes
from nmtiles.footprints import clean_window


def boxes(*rects):
    """Axis-aligned boxes from (cx, cy, dx, dy)."""
    a = np.array(rects, np.float64).reshape(-1, 4)
    n = len(a)
    return Boxes(a[:, 0], a[:, 1], a[:, 2], a[:, 3], np.full(n, 10.0), np.zeros(n))


def empty_city():
    z = np.zeros((0, 3, 2), np.float32)
    return {"road": z, "road_major": z, "stroke": z}


def test_boxes_of_the_filled_districts_join_the_building_triangles():
    city = empty_city()
    out = boxfill.apply(city, {"pacifica": boxes((0, 0, 20, 30)), "watson": boxes((100, 0, 10, 10), (200, 0, 10, 10))})
    assert len(out["stroke"]) == 2 * 3                      # two triangles per box
    assert out["road"] is city["road"] and out["road_major"] is city["road_major"]


def test_dogtown_and_the_spaceport_are_not_added():
    # Dogtown's boxes are added by dogtown.apply; the spaceport set lies off the playable map.
    out = boxfill.apply(empty_city(), {"ep1_dogtown": boxes((0, 0, 20, 20)), "ep1_spaceport": boxes((0, 0, 20, 20))})
    assert len(out["stroke"]) == 0


def test_a_building_only_in_the_3d_map_gets_a_footprint_and_one_over_a_road_does_not():
    # The minimap has nothing here; the 3D map has a 30 x 40 m building beside a road and a gantry box across it.
    road = np.array([[(-100, 50), (100, 50), (100, 70)], [(-100, 50), (100, 70), (-100, 70)]], np.float32)
    city = {"road": road, "road_major": np.zeros((0, 3, 2), np.float32), "stroke": np.zeros((0, 3, 2), np.float32)}
    out = boxfill.apply(city, {"pacifica": boxes((0, 0, 30, 40), (0, 60, 8, 20))})
    polys = clean_window(out["road"], out["stroke"])
    assert len(polys) == 1 and abs(polys[0].area - 1200) < 60
    assert polys[0].bounds[3] < 50                          # nothing left on the road
