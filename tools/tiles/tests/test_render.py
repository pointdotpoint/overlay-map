import math

import numpy as np

from nmtiles.glb import Mesh
from nmtiles.render import level_grid, rasterize_mask
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
