import numpy as np

from nmtiles import lit
from nmtiles.buildings import Boxes

SS = 4


def _box(cx, cy, dx, dy, z_bottom, dz):
    """One box by its footprint, its bottom height and its height."""
    return Boxes(np.array([cx], float), np.array([cy], float), np.array([dx], float), np.array([dy], float),
                 np.array([dz], float), np.zeros(1), np.array([z_bottom + dz / 2]))


def _lb(*bs):
    return lit.lit_boxes(Boxes.concat(list(bs)))


def _shade(lb, mpp=1.0, size_px=200, x0=0.0, y1=200.0):
    """(fill, edge) of a size_px square window at mpp whose top-left world corner is (x0, y1)."""
    return lit.shade(lb.quads, lb.top, x0, y1, size_px * SS, SS, mpp)


def _px(x, y, mpp=1.0, x0=0.0, y1=200.0):
    """(row, col) of world (x, y) in a _shade output."""
    return int((y1 - y) / mpp), int((x - x0) / mpp)


# ---- boxes ----

def test_heights_are_measured_from_the_local_ground():
    lb = _lb(_box(0, 0, 10, 10, 20, 5),            # 5 m shed on ground at 20 m
             _box(30, 0, 10, 10, 20, 40),          # 40 m block next to it
             _box(3000, 0, 10, 10, 80, 5))         # 5 m shed on a hill at 80 m: still 5 m tall
    assert np.allclose(lb.top, [5, 40, 5])


def test_a_floor_slab_high_up_counts_by_its_top():
    lb = _lb(_box(0, 0, 10, 10, 0, 3), _box(40, 0, 28, 28, 150, 1.5))   # ground marker; a tower's floor at 150 m
    assert np.isclose(lb.top[1], 151.5)


def test_floating_cables_and_beams_are_dropped_but_ground_walls_stay():
    lb = _lb(_box(0, 0, 10, 10, 0, 3),                # ground marker
             _box(50, 0, 0.7, 24, 40, 0.7),           # a cable 40 m up
             _box(80, 0, 3.5, 36, 180, 25),           # a thick beam high on a tower (Dogtown's spokes)
             _box(120, 0, 0.5, 30, 0, 5),             # Border Crossing's wall, standing on the ground
             _box(160, 0, 20, 20, 60, 2))             # a wide floor slab up high: a building, kept
    xs = lb.quads[:, :, 0].mean(1)
    assert not ((xs > 40) & (xs < 100)).any()
    assert ((xs > 110) & (xs < 130)).any() and ((xs > 150) & (xs < 170)).any()


def test_sweep_box_covers_the_shadow():
    lb = _lb(_box(0, 0, 10, 10, 0, 100))
    (lo, hi), d = lb.sweep[0], 100 * lit.SHADOW_K / np.sqrt(2)
    assert np.allclose(lo, [-5, -5 - d]) and np.allclose(hi, [5 + d, 5])     # shadows fall south-east


# ---- shading ----

def test_building_is_opaque_grey_and_taller_roofs_are_brighter():
    lb = _lb(_box(50, 100, 20, 20, 0, 5), _box(150, 100, 20, 20, 0, 120))
    fill, _ = _shade(lb)
    low, tall = fill[_px(48, 105)], fill[_px(145, 105)]                     # north-west halves: no shadow there
    assert low[3] == tall[3] == 255
    assert low[0] == low[1] == low[2] and tall[0] > low[0] + 60


def test_tall_box_casts_a_black_shadow_on_the_ground_to_the_south_east_only():
    lb = _lb(_box(100, 120, 10, 10, 0, 60))
    fill, _ = _shade(lb)
    se, nw = fill[_px(120, 100)], fill[_px(80, 140)]
    assert se[3] > 60 and se[0] == 0                                          # dark, see-through
    assert nw[3] < 30


def test_lower_roof_in_a_towers_shadow_is_darker_than_one_in_the_open():
    tower = _box(60, 140, 10, 10, 0, 150)
    shaded, open_ = _box(85, 115, 20, 20, 0, 10), _box(160, 40, 20, 20, 0, 10)
    fill, _ = _shade(_lb(tower, shaded, open_))
    assert fill[_px(85, 115)][3] == fill[_px(160, 40)][3] == 255
    assert fill[_px(85, 115)][0] < fill[_px(160, 40)][0] - 20


def test_edges_on_the_silhouette_and_tall_steps_only():
    podium, tower = _box(100, 100, 80, 80, 0, 10), _box(100, 100, 20, 20, 0, 80)
    small_step = _box(75, 75, 10, 10, 0, 12)                 # 2 m above the podium: no line
    _, edge = _shade(_lb(podium, tower, small_step))
    assert edge[_px(68, 120)] == 0                                          # podium interior
    assert edge[_px(100, 140)[0], :].max() > 150                            # podium's north edge row
    r, c = _px(110, 100)
    assert edge[r, c - 1:c + 2].max() > 150                                 # tower's east edge
    r, c = _px(75, 75)
    assert edge[r - 3:r + 4, c - 3:c + 4].max() == 0                        # small step inside its 10 m box
    assert edge[r, c - 7:c - 3].max() < 100


def test_empty_window_is_none():
    assert _shade(_lb()) is None


def test_margin_covers_the_widest_blur():
    for mpp in (0.5, 2.0, 16.0):
        assert lit.margin_px(mpp) * mpp >= 3 * max(lit.AO_SIGMA_M, lit.SOFT_M)
