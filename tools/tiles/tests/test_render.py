import math

import numpy as np

from nmtiles.glb import Mesh
from nmtiles.render import level_grid, rasterize_mask, render_level, slice_tiles
from nmtiles.world import Transform
from tests.glbutil import square


def _mesh(x0, y0, x1, y1, h=0.0, name="m"):
    # world y = -gltf z, so world [y0,y1] is gltf z [-y1,-y0]
    pos, idx = square(x0, -y1, x1, -y0, y=h)
    return Mesh(name, np.array(pos, float), np.array(idx, np.int64))


def test_level_grid_aligns_to_tile_multiples():
    g = level_grid((10.0, -700.0, 1000.0, 100.0), mpp=2.0, tile=512)
    assert g.tile_world == 1024.0
    assert g.origin_x == 0.0          # floor(10/1024)*1024
    assert g.origin_top == 1024.0     # ceil(100/1024)*1024
    assert g.nx == 1 and g.ny == 2    # x 0..1024 ; y 1024..-1024
    assert (g.width, g.height) == (512, 1024)


def test_rasterize_mask_places_world_square_north_up():
    m = _mesh(0, 0, 100, 100)
    mask = rasterize_mask([m], Transform(), origin_x=0.0, origin_top=512.0, mpp=1.0, width=512, height=512)
    # world y in [0,100] -> rows 412..512 (top = 512 - y)
    assert mask[450, 50] and mask[500, 10]
    assert not mask[300, 50]   # world y = 212, outside
    assert not mask[450, 200]  # world x = 200, outside


def test_render_level_draws_styles_and_slices_skip_empty_tiles():
    grid = level_grid((0.0, 0.0, 2000.0, 1000.0), mpp=2.0)
    styled = {"road_border": [_mesh(0, 0, 200, 20)], "water": [_mesh(1200, 0, 1600, 400)]}
    img = render_level(styled, Transform(), grid)
    assert img.mode == "RGBA" and img.size == (grid.width, grid.height)
    tiles = slice_tiles(img, grid)
    assert (0, 0) in tiles and (1, 0) in tiles
    assert all(t.size == (512, 512) for t in tiles.values())
    alpha = np.asarray(img)[:, :, 3]
    assert alpha.max() > 150          # bright road border
    assert len(tiles) == 2            # grid is 2x1 here, both have content


def test_slice_tiles_omits_fully_transparent_tiles():
    grid = level_grid((0.0, 0.0, 4000.0, 1000.0), mpp=2.0)
    img = render_level({"water": [_mesh(10, 10, 50, 50)]}, Transform(), grid)
    tiles = slice_tiles(img, grid)
    assert list(tiles) == [(0, 0)]


def _boxes(cx, cy, dx, dy, dz, yaw=0.0):
    from nmtiles.buildings import Boxes
    return Boxes(*(np.array([v], float) for v in (cx, cy, dx, dy, dz, yaw)))


def test_render_box_fills_inside_and_outlines_only_at_fine_mpp():
    # one 40x20 m box centred at world (100, 100); grid origin top-left of tile (0, 512*mpp)
    for mpp, outline in ((2.0, True), (8.0, False)):
        grid = level_grid((0.0, 0.0, 200.0, 200.0), mpp=mpp)
        alpha = np.asarray(render_level({}, Transform(), grid, boxes=_boxes(100, 100, 40, 20, 150)))[:, :, 3]
        px = lambda x, y: alpha[int((grid.origin_top - y) / mpp), int((x - grid.origin_x) / mpp)]
        inside = px(100, 100)
        assert inside >= 15 + 30 - 1                    # fill alpha + height_alpha at h >= 150 m
        assert px(100, 140) == 0 and px(160, 100) == 0   # outside the box
        edge = alpha[int((grid.origin_top - 110) / mpp) - 1: int((grid.origin_top - 110) / mpp) + 2, :].max()
        assert (edge >= 115) == outline                  # outline alpha 115 only when mpp <= 4
        if not outline:
            assert alpha.max() == inside


def test_render_box_respects_yaw_and_height_scaling():
    grid = level_grid((0.0, 0.0, 200.0, 200.0), mpp=1.0)
    tall = np.asarray(render_level({}, Transform(), grid, boxes=_boxes(100, 100, 40, 10, 150, math.pi / 2)))[:, :, 3]
    short = np.asarray(render_level({}, Transform(), grid, boxes=_boxes(100, 100, 40, 10, 15, math.pi / 2)))[:, :, 3]
    top = grid.origin_top
    assert tall[int(top - 120), 100] > 0 and tall[int(top - 100), 130] == 0   # yawed: long axis is N-S
    assert short[int(top - 100) + 3, 100] < tall[int(top - 100) + 3, 100]


def test_render_box_yaw_45_leans_north_east_on_north_up_image():
    grid = level_grid((0.0, 0.0, 200.0, 200.0), mpp=1.0)
    alpha = np.asarray(render_level({}, Transform(), grid, boxes=_boxes(100, 100, 60, 6, 150, math.pi / 4)))[:, :, 3]
    row = lambda y: int(grid.origin_top - y)
    assert alpha[row(120), 120] > 0 and alpha[row(80), 80] > 0     # along the NE-SW diagonal
    assert alpha[row(80), 120] == 0 and alpha[row(120), 80] == 0   # off it: not a SE-NW lean


def test_box_centres_follow_calibrated_translation_only():
    grid = level_grid((0.0, -100.0, 300.0, 200.0), mpp=1.0)
    def centre(tf):
        a = np.asarray(render_level({}, tf, grid, boxes=_boxes(100, 50, 20, 20, 150)))[:, :, 3]
        ys, xs = np.nonzero(a)
        return grid.origin_x + (xs.min() + xs.max() + 1) / 2, grid.origin_top - (ys.min() + ys.max() + 1) / 2
    x0, y0 = centre(Transform())
    x1, y1 = centre(Transform(dx=10.0, dy=-5.0))
    assert abs((x1 - x0) - 10.0) <= 1 and abs((y1 - y0) + 5.0) <= 1
    xs_, ys_ = centre(Transform(sx=-1.0, sy=-1.0))            # axis signs must not move or mirror the boxes
    assert abs(xs_ - x0) <= 1 and abs(ys_ - y0) <= 1


def test_metro_is_dashed_along_its_length():
    grid = level_grid((0.0, 0.0, 1000.0, 200.0), mpp=2.0)
    horiz = np.asarray(render_level({"metro": [_mesh(0, 90, 1000, 102)]}, Transform(), grid))[:, :, 3]
    row = horiz[int((grid.origin_top - 96) / 2.0)]
    covered = row[:500] > 0
    assert covered.any() and (~covered[: 480]).any()             # coloured and transparent pixels along the strip
    assert 0.5 < covered[:480].mean() < 0.7                      # about 24 of every 40 m
    vert = np.asarray(render_level({"metro": [_mesh(90, 0, 102, 200)]}, Transform(), grid))[:, :, 3]
    col = vert[:, int(96 / 2.0)]
    assert (col > 0).any() and ((col == 0)[int((grid.origin_top - 200) / 2.0):int((grid.origin_top - 0) / 2.0)]).any()
