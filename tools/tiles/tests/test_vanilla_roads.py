import numpy as np

from nmtiles.minimap import MAJOR_WIDTH_M
from nmtiles.vanilla_roads import apply


def _strip(x0, x1, y0, y1):
    return np.array([[(x0, y0), (x1, y0), (x1, y1)], [(x0, y0), (x1, y1), (x0, y1)]], np.float32)


def _city(road, major, stroke):
    return {"road": road, "road_major": major, "stroke": stroke}


def test_minimap_roads_are_replaced_by_the_vanilla_mesh_everywhere():
    # the minimap has a road the vanilla map does not draw, and lacks one it does (Border Crossing's highway)
    minimap_only = _strip(0, 200, 0, 8)
    vanilla = np.concatenate([_strip(0, 200, 500, 508), _strip(0, 200, 1000, 1000 + 2 * MAJOR_WIDTH_M)])
    out = apply(_city(minimap_only, minimap_only[:0], np.zeros((0, 3, 2), np.float32)), vanilla)
    roads = np.concatenate([out["road"], out["road_major"]])
    ys = roads[:, :, 1].mean(axis=1)
    assert not (ys < 100).any()                     # the minimap-only road is gone
    assert (abs(ys - 504) < 10).sum() == 2           # the narrow vanilla road is minor
    assert len(out["road_major"]) == 2 and (out["road_major"][:, :, 1] >= 1000).all()


def test_building_triangles_are_kept():
    stroke = _strip(50, 60, 50, 60)
    out = apply(_city(_strip(0, 1, 0, 1), _strip(0, 1, 0, 1), stroke), _strip(0, 200, 500, 508))
    assert np.array_equal(out["stroke"], stroke)


def test_output_is_float32():
    out = apply(_city(_strip(0, 1, 0, 1), _strip(0, 1, 0, 1), _strip(0, 1, 0, 1)),
                _strip(0, 200, 500, 508).astype(np.float64))
    assert out["road"].dtype == np.float32 and out["road_major"].dtype == np.float32
