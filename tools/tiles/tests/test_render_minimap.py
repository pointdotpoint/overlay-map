import numpy as np

from nmtiles.glb import Mesh
from nmtiles.render import LevelGrid, tile_grid
from nmtiles.render_minimap import TileSources, TriIndex, make_sources, render_tile
from nmtiles.world import Transform
from tests.glbutil import square

# 2x2 tiles of 512 px at 1 m/px: tile (ix, iy) covers x in [512 ix, 512 ix + 512), y in (1024 - 512 (iy+1), 1024 - 512 iy]
GRID = LevelGrid(1.0, 0.0, 1024.0, 2, 2, 512)


def tri(*pts):
    return np.array([pts], np.float32)


def src(road=None, stroke=None):
    empty = np.zeros((0, 3, 2), np.float32)
    return make_sources({"road": empty if road is None else road, "stroke": empty if stroke is None else stroke},
                        {}, Transform(), GRID.tile_world)


def alpha(img):
    return np.asarray(img)[:, :, 3]


def test_tile_grid_is_the_subrectangle_with_margin():
    g = tile_grid(GRID, 1, 0, ss=2, margin=4)
    assert (g.origin_x, g.origin_top, g.mpp, g.tile, g.nx, g.ny) == (512.0 - 4, 1024.0 + 4, 0.5, (512 + 8) * 2, 1, 1)


def test_tri_index_returns_overlapping_bboxes_and_nothing_far():
    rng = np.random.default_rng(1)
    c = rng.uniform(-5000, 5000, (3000, 1, 2))
    tris = (c + rng.uniform(-30, 30, (3000, 3, 2))).astype(np.float32)
    tris[0] = [[-4000, -4000], [4000, -4000], [0, 4000]]                 # one huge triangle spanning many cells
    idx = TriIndex(tris, 256.0)
    for box in [(0, 0, 300, 300), (-1000, 2000, -400, 2600), (4900, 4900, 5200, 5200), (-9000, -9000, -8000, -8000)]:
        x0, y0, x1, y1 = box
        lo, hi = tris.min(1), tris.max(1)
        want = np.nonzero((hi[:, 0] >= x0) & (lo[:, 0] <= x1) & (hi[:, 1] >= y0) & (lo[:, 1] <= y1))[0]
        assert sorted(idx.query(*box).tolist()) == want.tolist()
    assert len(idx.query(-9000, -9000, -8000, -8000)) == 0
    assert TriIndex(np.zeros((0, 3, 2), np.float32), 256.0).query(0, 0, 10, 10).size == 0


def test_road_triangle_paints_centroid_and_leaves_far_pixels_clear():
    out = render_tile(src(road=tri((100, 900), (200, 900), (150, 1000))), GRID, 0, 0)
    assert set(out) == {"road"}
    a = alpha(out["road"])
    assert a.shape == (512, 512)
    cx, cy = 150, int(1024 - 933)
    assert a[cy, cx] == 255
    assert (np.asarray(out["road"])[cy, cx, :3] == 255).all()              # white mask: colour comes from the theme
    assert a[300:, 300:].max() == 0 and a[:, 400:].max() == 0


def test_stroke_gives_stroke_and_glow_sets_and_empty_tiles_are_none():
    s = src(stroke=tri((100, 900), (140, 900), (100, 902)))
    out = render_tile(s, GRID, 0, 0)
    assert set(out) == {"stroke", "glow"}
    assert alpha(out["glow"]).max() > 0 and (alpha(out["glow"]) > 0).sum() > (alpha(out["stroke"]) > 0).sum()
    assert render_tile(s, GRID, 1, 1) == {}                                # nothing near tile (1, 1)
    assert render_tile(src(), GRID, 0, 0) == {}


def test_thin_stroke_is_still_visible_at_coarse_level():
    coarse = LevelGrid(16.0, 0.0, 8192.0, 1, 1, 512)
    s = make_sources({"road": np.zeros((0, 3, 2), np.float32), "stroke": tri((100, 8000), (400, 8000), (100, 8000.2))},
                     {}, Transform(), coarse.tile_world)
    assert alpha(render_tile(s, coarse, 0, 0)["stroke"]).max() > 0


def test_adjacent_tiles_agree_along_the_shared_edge():
    big = tri((400, 900), (700, 900), (550, 1000))                           # crosses x = 512
    thin = tri((480, 700), (560, 700), (480, 701))                            # a thin stroke across the border
    s = src(road=big, stroke=thin)
    l, r = render_tile(s, GRID, 0, 0), render_tile(s, GRID, 1, 0)
    whole = render_tile(s, LevelGrid(1.0, 0.0, 1024.0, 1, 1, 1024), 0, 0)      # the same rows as one tile, no border
    for name in ("road", "stroke", "glow"):
        left, right = alpha(l[name]).astype(int), alpha(r[name]).astype(int)
        assert left[:, 511].max() > 0 and right[:, 0].max() > 0, name           # the shape paints both edge columns
        top = alpha(whole[name]).astype(int)[:512]                              # tile row 0 = the top half
        assert np.abs(np.hstack([left, right]) - top).max() <= 2, name          # stitched tiles == one render: no seam


def test_base_and_metro_sets():
    def quad(x0, y0, x1, y1):       # world rectangle; world y = -gltf z under the default Transform
        pos, idx = square(x0, -y1, x1, -y0)
        return Mesh("m", np.array(pos, float), np.array(idx, np.int64))
    styled = {"land": [quad(0, 0, 1024, 1024)], "road": [quad(0, 0, 1024, 1024)], "building": [], "metro": [quad(100, 600, 400, 612)]}
    coarse = LevelGrid(2.0, 0.0, 1024.0, 1, 1, 512)
    s = make_sources({"road": np.zeros((0, 3, 2), np.float32), "stroke": np.zeros((0, 3, 2), np.float32)}, styled,
                     Transform(), coarse.tile_world)
    out = render_tile(s, coarse, 0, 0)
    assert set(out) == {"base", "metro"}                                     # base: land only, the 3D-map road is off
    assert 0 < alpha(out["base"])[10, 10] < 60
    fine = LevelGrid(1.0, 0.0, 512.0, 1, 1, 512)
    s2 = make_sources({"road": np.zeros((0, 3, 2), np.float32), "stroke": np.zeros((0, 3, 2), np.float32)}, styled,
                      Transform(), fine.tile_world)
    assert "base" not in render_tile(s2, fine, 0, 0)                          # base exists only for m/px >= 2
