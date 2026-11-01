import numpy as np
import pytest

from nmtiles.render import LevelGrid
from nmtiles.render_minimap import GLOW_MIN_MPP, SETS, TileSources, TriIndex, make_sources, render_tile

# 2x2 tiles of 512 px at 1 m/px: tile (ix, iy) covers x in [512 ix, 512 ix + 512), y in (1024 - 512 (iy+1), 1024 - 512 iy]
GRID = LevelGrid(1.0, 0.0, 1024.0, 2, 2, 512)
NOROAD = np.zeros((0, 3, 2), np.float32)


def tri(*pts):
    return np.array([pts], np.float32)


def box(x0, y0, x1, y1):
    return np.array([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], np.float64)


def src(road=NOROAD, polys=(), major=NOROAD):
    return make_sources(road, list(polys), GRID.tile_world, major)


def alpha(img):
    return np.asarray(img)[:, :, 3]


def test_sets_order():
    assert SETS == ("glow", "bfill", "outline", "road_minor", "road_major")


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
    assert set(out) == {"road_minor"}
    a = alpha(out["road_minor"])
    assert a.shape == (512, 512) and a[int(1024 - 933), 150] == 255
    assert (np.asarray(out["road_minor"])[91, 150, :3] == 255).all()                # white mask
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
    whole = render_tile(make_sources(road, polys, big.tile_world, NOROAD), big, 0, 0)
    for name in ("road_minor", "bfill", "outline"):      # glow needs mpp >= 2: covered below
        left, right = alpha(l[name]).astype(int), alpha(r[name]).astype(int)
        assert left[:, 511].max() > 0 and right[:, 0].max() > 0, name        # painted on both sides of the shared edge
        top = alpha(whole[name]).astype(int)[:512]
        assert np.abs(np.hstack([left, right]) - top).max() <= 2, name        # stitched == one render: no seam


def test_render_is_deterministic():
    s = src(tri((100.3, 900.1), (200.7, 900.9), (150.5, 1000.2)), [box(300.3, 700.2, 380.8, 760.4)])
    a, b = render_tile(s, GRID, 0, 0), render_tile(s, GRID, 0, 0)
    assert {k: v.tobytes() for k, v in a.items()} == {k: v.tobytes() for k, v in b.items()}


# ---- glow set: only at levels with mpp >= GLOW_MIN_MPP (L2..L5 of 0.5,1,2,4,8,16) ----
GRID2 = LevelGrid(2.0, 0.0, 2048.0, 2, 2, 512)    # tile (0,0): x in [0,1024), y in (1024,2048]; world y = 2048 - 2 * row


def src2(road=NOROAD, polys=(), major=NOROAD):
    return make_sources(road, list(polys), GRID2.tile_world, major)


def quad(x0, y0, x1, y1):
    return np.array([[(x0, y0), (x1, y0), (x1, y1)], [(x0, y0), (x1, y1), (x0, y1)]], np.float32)


def test_glow_exists_only_at_levels_with_mpp_at_least_two():
    have = []
    for mpp in [0.5, 1.0, 2.0, 4.0, 8.0, 16.0]:
        g = LevelGrid(mpp, 0.0, 1024.0 * mpp, 2, 2, 512)
        road = tri((50 * mpp, 1000 * mpp), (150 * mpp, 1000 * mpp), (100 * mpp, 900 * mpp))   # px (50..150, 24..124)
        foot = [box(200 * mpp, 800 * mpp, 300 * mpp, 900 * mpp)]
        out = render_tile(make_sources(road, foot, g.tile_world, NOROAD), g, 0, 0)
        assert {"road_minor", "bfill", "outline"} <= set(out)
        have.append("glow" in out)
    assert have == [False, False, True, True, True, True]
    assert GLOW_MIN_MPP == 2.0


def test_glow_is_a_soft_halo_around_the_road_rim():
    out = render_tile(src2(major=quad(200, 1200, 500, 1500)), GRID2, 0, 0)
    g = alpha(out["glow"]).astype(int)
    assert (np.asarray(out["glow"])[..., :3] == 255).all()                    # white mask like every other set
    row, edge = (2048 - 1350) // 2, 200 // 2                                  # road centre row, its left rim column
    assert g[row, edge] > 150                                                 # bright on the rim
    assert 0 < g[row, edge - 3] < g[row, edge - 1]                            # falls off with distance
    assert g[row, edge - 14] == 0                                             # ~28 m away: bloom has ended
    assert g[row, 175] == 0                                                   # deep interior is not glowing
    assert g.max() <= 255


def test_glow_from_roads_only():
    out = render_tile(src2(polys=[box(200, 1200, 500, 1500)]), GRID2, 0, 0)
    assert "outline" in out and "bfill" in out and "glow" not in out


def test_glow_weights_major_over_minor():
    major = alpha(render_tile(src2(major=quad(200, 1200, 500, 1500)), GRID2, 0, 0)["glow"]).astype(int)
    minor = alpha(render_tile(src2(road=quad(200, 1200, 500, 1500)), GRID2, 0, 0)["glow"]).astype(int)
    assert 0 < minor.max() < major.max() * 0.5


def test_render_tile_splits_roads():
    s = src(road=quad(100, 600, 200, 606), major=quad(300, 700, 340, 720))   # 6 m narrow, 20 m wide
    out = render_tile(s, GRID, 0, 0)
    assert set(out) == {"road_minor", "road_major"}
    mn, mj = alpha(out["road_minor"]), alpha(out["road_major"])
    assert mn[1024 - 603, 150] == 255 and mj[1024 - 603, 150] == 0
    assert mj[1024 - 710, 320] == 255 and mn[1024 - 710, 320] == 0
    assert mn[:, 250:].max() == 0 and mj[:, :250].max() == 0


def test_glow_stitches_across_a_tile_edge_and_is_deterministic():
    polys = [box(900.0, 1700.0, 1100.0, 1760.0)]       # straddles x = 1024 (the shared tile edge)
    road = tri((900, 1800), (1100, 1810), (1000, 1900))
    s = src2(road, polys)
    l, r = render_tile(s, GRID2, 0, 0), render_tile(s, GRID2, 1, 0)
    big = LevelGrid(2.0, 0.0, 2048.0, 1, 1, 1024)
    whole = render_tile(make_sources(road, polys, big.tile_world, NOROAD), big, 0, 0)
    left, right = alpha(l["glow"]).astype(int), alpha(r["glow"]).astype(int)
    top = alpha(whole["glow"]).astype(int)[:512]
    assert left[:, 511].max() > 0 and right[:, 0].max() > 0
    assert np.abs(np.hstack([left, right]) - top).max() <= 2
    again = render_tile(s, GRID2, 0, 0)
    assert again["glow"].tobytes() == l["glow"].tobytes()


def test_margin_change_leaves_the_other_sets_identical():
    # A level with a glow set renders the other sets with a larger margin; the crop must not change them.
    from nmtiles import render_minimap as rm
    s = src2(tri((200.3, 1800.1), (600.7, 1800.9), (400.5, 2000.2)), [box(200.3, 1200.2, 500.8, 1500.4)])
    a = render_tile(s, GRID2, 0, 0)
    old = rm.GLOW_MIN_MPP
    rm.GLOW_MIN_MPP = 1e9
    try:
        b = render_tile(s, GRID2, 0, 0)
    finally:
        rm.GLOW_MIN_MPP = old
    assert "glow" in a and "glow" not in b
    for name in ("road_minor", "bfill", "outline"):
        assert a[name].tobytes() == b[name].tobytes(), name


def test_glow_gain_falls_with_level_so_far_zoom_is_not_haze():
    from nmtiles.render_minimap import GLOW_GAIN, glow_gain
    g = [glow_gain(m) for m in (2.0, 4.0, 8.0, 16.0)]
    assert g[0] == GLOW_GAIN and all(a > b for a, b in zip(g, g[1:])) and g[3] < 1.0


def test_short_minor_piece_between_collinear_major_segments_is_major():
    # 1 m/px; major 20 m wide segments with a 20 x 20 m square (width 10: minor) bridging the 20 m gap
    major = np.concatenate([quad(100, 600, 200, 620), quad(220, 600, 320, 620)])
    stub = quad(200, 600, 220, 620)
    out = render_tile(src(road=stub, major=major), GRID, 0, 0)
    mn, mj = alpha(out["road_minor"]) if "road_minor" in out else np.zeros((512, 512)), alpha(out["road_major"])
    row, col = 1024 - 610, 210
    assert mj[row, col] == 255 and mn[row, col] == 0
    assert mn.max() == 0


def test_side_street_meeting_a_major_road_stays_minor():
    major = quad(100, 600, 400, 620)                  # 300 x 20 m arterial
    side = quad(240, 620, 250, 800)                   # 10 x 180 m street, T-junction on the arterial's edge
    out = render_tile(src(road=side, major=major), GRID, 0, 0)
    mn, mj = alpha(out["road_minor"]), alpha(out["road_major"])
    assert mn[1024 - 700, 245] == 255 and mj[1024 - 700, 245] == 0
    assert mn[1024 - 625, 245] == 255 and mj[1024 - 625, 245] == 0     # right at the junction


def test_road_major_is_required():
    with pytest.raises(TypeError):
        make_sources(NOROAD, [], 256.0)
    with pytest.raises(TypeError):
        TileSources(TriIndex(NOROAD, 256.0), TriIndex(NOROAD, 256.0), [])


def test_promotion_stitches_across_tile_edges():
    major = np.concatenate([quad(400, 600, 500, 620), quad(524, 600, 624, 620)])    # gap of 24 m across x = 512
    stub = quad(500, 600, 524, 620)
    s = src(road=stub, major=major)
    l, r = render_tile(s, GRID, 0, 0), render_tile(s, GRID, 1, 0)
    big = LevelGrid(1.0, 0.0, 1024.0, 1, 1, 1024)
    whole = render_tile(make_sources(stub, [], big.tile_world, major), big, 0, 0)
    for name in ("road_major",):
        got = np.hstack([alpha(l[name]), alpha(r[name])]).astype(int)
        assert np.abs(got - alpha(whole[name]).astype(int)[:512]).max() <= 2
    assert "road_minor" not in l and "road_minor" not in r
