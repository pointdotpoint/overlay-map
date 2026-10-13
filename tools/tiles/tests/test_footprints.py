import numpy as np

from nmtiles.footprints import Footprints, build_footprints, footprint_key


def rect(x0, y0, x1, y1):
    return np.array([[(x0, y0), (x1, y0), (x1, y1)], [(x0, y0), (x1, y1), (x0, y1)]], np.float32)


EMPTY = np.zeros((0, 3, 2), np.float32)


def area(poly):
    x, y = poly[:, 0], poly[:, 1]
    return 0.5 * abs(np.dot(x, np.roll(y, -1)) - np.dot(y, np.roll(x, -1)))


def test_building_becomes_one_clean_footprint_and_small_pieces_drop():
    b = np.concatenate([rect(10, 10, 40, 30), rect(100, 100, 105, 105)])      # 600 m2 and 25 m2
    fp = build_footprints(EMPTY, b, tile=500.0, margin=150.0, jobs=1)
    assert len(fp.polys) == 1 and abs(area(fp.polys[0]) - 600) < 40


def test_courtyard_filled_and_road_subtracted():
    ring = np.concatenate([rect(0, 0, 40, 6), rect(0, 34, 40, 40), rect(0, 6, 6, 34), rect(34, 6, 40, 34)])
    fp = build_footprints(EMPTY, ring, 500.0, 150.0, 1)
    assert len(fp.polys) == 1 and area(fp.polys[0]) > 1500                      # courtyard filled
    road = rect(-10, 15, 60, 25)                                                 # a street across the block
    fp2 = build_footprints(road, ring, 500.0, 150.0, 1)
    assert len(fp2.polys) == 2


def test_no_duplicates_across_tile_borders_and_deterministic():
    b = np.concatenate([rect(480, 10, 520, 40), rect(-30, -60, -5, -20), rect(990, 400, 1020, 430)])
    a = build_footprints(EMPTY, b, 500.0, 150.0, 1)
    c = build_footprints(EMPTY, b, 500.0, 150.0, 2)
    assert len(a.polys) == 3                                                      # each kept once, in its rep-point tile
    assert [p.tolist() for p in a.polys] == [p.tolist() for p in c.polys]


def test_key_changes_with_inputs_and_params():
    b = rect(0, 0, 10, 10)
    assert footprint_key(EMPTY, b) == footprint_key(EMPTY, b)
    assert footprint_key(EMPTY, b) != footprint_key(EMPTY, rect(0, 0, 10, 11))


def test_cache_roundtrip(tmp_path):
    fp = build_footprints(EMPTY, rect(0, 0, 30, 30), 500.0, 150.0, 1)
    fp.save(tmp_path / "f.npz", "k")
    got = Footprints.load(tmp_path / "f.npz", "k")
    assert got is not None and [p.tolist() for p in got.polys] == [p.tolist() for p in fp.polys]
    assert Footprints.load(tmp_path / "f.npz", "other") is None
