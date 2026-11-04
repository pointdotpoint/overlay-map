import numpy as np
import pytest

from nmtiles.render import LevelGrid
from nmtiles.render_minimap import DOT_PITCH_PX, FILL_BASE, GLOW_MIN_MPP, GLOW_RADIUS, SETS, TileSources, TriIndex, dot_pattern, make_sources, render_tile

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
    assert SETS == ("glow", "bfill", "outline", "road", "metro")


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
    assert set(out) == {"road", "glow"}                  # roads glow at every level
    a = alpha(out["road"])
    assert a.shape == (512, 512) and a[int(1024 - 933), 150] == 255
    assert (np.asarray(out["road"])[91, 150, :3] == 255).all()                # white mask
    assert a[300:, 300:].max() == 0 and a[:, 400:].max() == 0


def test_footprint_gives_fill_and_outline_and_empty_tiles_are_none():
    s = src(polys=[box(100, 800, 200, 900)])
    out = render_tile(s, GRID, 0, 0)
    assert set(out) == {"bfill", "outline"}
    fill, line = (alpha(out[k]) for k in ("bfill", "outline"))
    assert fill[1024 - 850, 150] >= round(FILL_BASE * 255) - 1 and line[1024 - 850, 150] == 0     # interior
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
    for name in ("road", "bfill", "outline"):      # glow needs mpp >= 2: covered below
        left, right = alpha(l[name]).astype(int), alpha(r[name]).astype(int)
        assert left[:, 511].max() > 0 and right[:, 0].max() > 0, name        # painted on both sides of the shared edge
        top = alpha(whole[name]).astype(int)[:512]
        assert np.abs(np.hstack([left, right]) - top).max() <= 2, name        # stitched == one render: no seam


def test_render_is_deterministic():
    s = src(tri((100.3, 900.1), (200.7, 900.9), (150.5, 1000.2)), [box(300.3, 700.2, 380.8, 760.4)])
    a, b = render_tile(s, GRID, 0, 0), render_tile(s, GRID, 0, 0)
    assert {k: v.tobytes() for k, v in a.items()} == {k: v.tobytes() for k, v in b.items()}


# ---- glow set: at every level, drawn at the camera's own level (no upscaling), so the halo stays tight on screen ----
GRID2 = LevelGrid(2.0, 0.0, 2048.0, 2, 2, 512)    # tile (0,0): x in [0,1024), y in (1024,2048]; world y = 2048 - 2 * row


def src2(road=NOROAD, polys=(), major=NOROAD):
    return make_sources(road, list(polys), GRID2.tile_world, major)


def quad(x0, y0, x1, y1):
    return np.array([[(x0, y0), (x1, y0), (x1, y1)], [(x0, y0), (x1, y1), (x0, y1)]], np.float32)


def test_glow_exists_at_every_level_and_stays_tight():
    # The glow is drawn at the camera's own level, so it must exist at every level, and its halo must hug the road:
    # a few pixels past the rim it is gone, so the dark background between roads stays dark.
    for mpp in [0.5, 1.0, 2.0, 4.0, 8.0, 16.0]:
        g = LevelGrid(mpp, 0.0, 1024.0 * mpp, 2, 2, 512)
        road = quad(100 * mpp, 600 * mpp, 200 * mpp, 900 * mpp)                 # px columns 100..200, rows 124..424
        foot = [box(300 * mpp, 800 * mpp, 400 * mpp, 900 * mpp)]
        out = render_tile(make_sources(road, foot, g.tile_world, NOROAD), g, 0, 0)
        assert {"road", "bfill", "outline", "glow"} <= set(out), mpp
        a = alpha(out["glow"]).astype(int)
        row = 274 * a.shape[0] // 512
        rim = 100 * a.shape[1] // 512
        reach = int(np.ceil((GLOW_RADIUS * 4 + 2) * a.shape[1] / 512))
        assert a[row, rim] > 10, mpp                                          # the rim glows
        assert a[row, max(rim - reach, 0)] == 0, mpp                           # and the halo ends within ~4 sigma
    assert GLOW_MIN_MPP <= 0.5


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


def test_glow_is_the_same_for_every_road():
    # One road style like the vanilla minimap: a narrow (minor) piece glows exactly like a wide (major) one.
    major = alpha(render_tile(src2(major=quad(200, 1200, 500, 1500)), GRID2, 0, 0)["glow"]).astype(int)
    minor = alpha(render_tile(src2(road=quad(200, 1200, 500, 1500)), GRID2, 0, 0)["glow"]).astype(int)
    assert major.max() > 0 and np.array_equal(major, minor)


def test_render_tile_merges_roads_into_one_set():
    s = src(road=quad(100, 600, 200, 606), major=quad(300, 700, 340, 720))   # 6 m narrow, 20 m wide
    out = render_tile(s, GRID, 0, 0)
    assert set(out) == {"road", "glow"}                  # one road set (plus its glow), no major/minor split
    r = alpha(out["road"])
    assert r[1024 - 603, 150] == 255 and r[1024 - 710, 320] == 255


def test_no_stripe_where_a_narrow_piece_meets_a_wide_one():
    # The striping bug: one highway made of pieces whose measured widths fall either side of MAJOR_WIDTH_M drew as
    # alternating light/dark bands with a glow line across every joint. Merged, the joint is invisible.
    wide = quad(100, 1500, 300, 1540)                  # 40 m wide piece (major)
    narrow = quad(300, 1500, 500, 1540)                # same road continued, classified minor
    out = render_tile(src2(road=narrow, major=wide), GRID2, 0, 0)
    r = alpha(out["road"]).astype(int)
    row = (2048 - 1520) // 2
    assert (r[row, 60:240] == 255).all()               # x 120..480 m: continuous across the joint at x = 300
    g = alpha(out["glow"]).astype(int)
    assert g[row, 150] == g[row, 100] == 0             # no glow inside the road, at the joint or away from it


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
    for name in ("road", "bfill", "outline"):
        assert a[name].tobytes() == b[name].tobytes(), name


def test_glow_gain_falls_with_level_so_far_zoom_is_not_haze():
    from nmtiles.render_minimap import GLOW_GAIN, glow_gain
    g = [glow_gain(m) for m in (2.0, 4.0, 8.0, 16.0)]
    assert g[0] == GLOW_GAIN and all(a > b for a, b in zip(g, g[1:])) and abs(g[3] - GLOW_GAIN / 8) < 1e-9
    assert glow_gain(0.5) == glow_gain(1.0) == GLOW_GAIN               # street levels glow like 2 m/px


def test_road_major_is_required():
    with pytest.raises(TypeError):
        make_sources(NOROAD, [], 256.0)
    with pytest.raises(TypeError):
        TileSources(TriIndex(NOROAD, 256.0), TriIndex(NOROAD, 256.0), [])


def test_dot_pattern_is_seamless():
    assert np.array_equal(dot_pattern(0, 0, 520)[:512, 512], dot_pattern(1, 0, 512)[:, 0])


def test_dot_pattern_pitch():
    d = dot_pattern(0, 0, 64)
    assert DOT_PITCH_PX == 8
    assert [int(v) for v in d[0, :16]] == [1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0]
    assert [int(v) for v in d[8, :16]] == [0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 0]


def test_bfill_has_floor_and_dots():
    out = render_tile(src(polys=[box(-10, 500, 600, 1100)]), GRID, 0, 0)
    a = alpha(out["bfill"])
    assert a.min() == pytest.approx(FILL_BASE * 255, abs=1) and a.max() == 255


def test_diagonal_outline_is_smooth_when_magnified():
    # A building edge at a shallow angle: per column, the line's coverage (its brightness) must stay even and its
    # coverage-weighted centre must follow a straight line, or the edge reads as beads and stair steps once the map
    # shows each texel 5x enlarged at the closest zoom.
    poly = np.array([(50.0, 700.0), (450.0, 840.0), (450.0, 600.0), (50.0, 600.0)])
    a = alpha(render_tile(src(polys=[poly]), GRID, 0, 0)["outline"]).astype(float)
    cols = np.arange(80, 420)
    band = a[100:340, cols]                                    # rows around the slanted edge only
    y = (band * np.arange(100, 340)[:, None]).sum(0) / band.sum(0)
    resid = y - np.polyval(np.polyfit(cols, y, 1), cols)
    width = band.sum(0) / 255
    assert width.max() - width.min() < 0.2, (width.min(), width.max())
    assert np.abs(resid).max() < 0.1, np.abs(resid).max()
