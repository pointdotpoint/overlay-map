import numpy as np

from nmtiles.render import LevelGrid
from nmtiles.render_minimap import SETS, TriIndex, make_sources, render_tile

# 2x2 tiles of 512 px at 1 m/px: tile (ix, iy) covers x in [512 ix, 512 ix + 512), y in (1024 - 512 (iy+1), 1024 - 512 iy]
GRID = LevelGrid(1.0, 0.0, 1024.0, 2, 2, 512)
NOROAD = np.zeros((0, 3, 2), np.float32)


def tri(*pts):
    return np.array([pts], np.float32)


def box(x0, y0, x1, y1):
    return np.array([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], np.float64)


def src(road=NOROAD, polys=()):
    return make_sources(road, list(polys), GRID.tile_world)


def alpha(img):
    return np.asarray(img)[:, :, 3]


def test_sets_are_in_draw_order():
    assert SETS == ("road", "bfill", "outline")


def test_tri_index_returns_overlapping_bboxes_and_nothing_far():
    rng = np.random.default_rng(1)
    c = rng.uniform(-5000, 5000, (3000, 1, 2))
    tris = (c + rng.uniform(-30, 30, (3000, 3, 2))).astype(np.float32)
    tris[0] = [[-4000, -4000], [4000, -4000], [0, 4000]]
    idx = TriIndex(tris, 256.0)
    for b in [(0, 0, 300, 300), (-1000, 2000, -400, 2600), (4900, 4900, 5200, 5200), (-9000, -9000, -8000, -8000)]:
        x0, y0, x1, y1 = b
        lo, hi = tris.min(1), tris.max(1)
        want = np.nonzero((hi[:, 0] >= x0) & (lo[:, 0] <= x1) & (hi[:, 1] >= y0) & (lo[:, 1] <= y1))[0]
        assert sorted(idx.query(*b).tolist()) == want.tolist()
    assert TriIndex(np.zeros((0, 3, 2), np.float32), 256.0).query(0, 0, 10, 10).size == 0


def test_road_triangle_paints_centroid_and_leaves_far_pixels_clear():
    out = render_tile(src(road=tri((100, 900), (200, 900), (150, 1000))), GRID, 0, 0)
    assert set(out) == {"road"}
    a = alpha(out["road"])
    assert a.shape == (512, 512) and a[int(1024 - 933), 150] == 255
    assert (np.asarray(out["road"])[91, 150, :3] == 255).all()                # white mask
    assert a[300:, 300:].max() == 0 and a[:, 400:].max() == 0


def test_footprint_gives_fill_and_outline_and_empty_tiles_are_none():
    s = src(polys=[box(100, 800, 200, 900)])
    out = render_tile(s, GRID, 0, 0)
    assert set(out) == {"bfill", "outline"}
    fill, line = (alpha(out[k]) for k in ("bfill", "outline"))
    assert fill[1024 - 850, 150] == 255 and line[1024 - 850, 150] == 0     # interior
    assert line[1024 - 850, 100] > 100                                         # outline on the edge
    assert render_tile(s, GRID, 1, 1) == {} and render_tile(src(), GRID, 0, 0) == {}


def test_outline_is_about_one_pixel_wide():
    out = render_tile(src(polys=[box(100, 800, 200, 900)]), GRID, 0, 0)
    row = alpha(out["outline"])[1024 - 850].astype(float) / 255
    assert 0.8 < row[90:112].sum() < 1.3


def test_adjacent_tiles_agree_with_one_big_render_for_fractional_vertices():
    rng = np.random.default_rng(7)
    c = rng.uniform((440, 700), (580, 1000), (60, 2))
    road = (c[:, None, :] + rng.uniform(-25, 25, (60, 3, 2))).astype(np.float32)
    polys = [box(500.2 + i * 13.7, 830.3, 520.6 + i * 13.7, 861.9) + rng.uniform(-3, 3, (4, 2)) for i in range(3)]
    polys.append(np.array([(470.3, 600.2), (555.7, 610.9), (548.1, 650.4), (480.9, 641.3)]))
    s = src(road, polys)
    l, r = render_tile(s, GRID, 0, 0), render_tile(s, GRID, 1, 0)
    big = LevelGrid(1.0, 0.0, 1024.0, 1, 1, 1024)
    whole = render_tile(make_sources(road, polys, big.tile_world), big, 0, 0)
    for name in SETS:
        left, right = alpha(l[name]).astype(int), alpha(r[name]).astype(int)
        assert left[:, 511].max() > 0 and right[:, 0].max() > 0, name        # painted on both sides of the shared edge
        top = alpha(whole[name]).astype(int)[:512]
        assert np.abs(np.hstack([left, right]) - top).max() <= 2, name        # stitched == one render: no seam


def test_render_is_deterministic():
    s = src(tri((100.3, 900.1), (200.7, 900.9), (150.5, 1000.2)), [box(300.3, 700.2, 380.8, 760.4)])
    a, b = render_tile(s, GRID, 0, 0), render_tile(s, GRID, 0, 0)
    assert {k: v.tobytes() for k, v in a.items()} == {k: v.tobytes() for k, v in b.items()}
