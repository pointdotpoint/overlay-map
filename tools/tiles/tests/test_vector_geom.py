import numpy as np
import pytest

from nmtiles.vector_config import LEVELS, STYLES
from nmtiles.vector_geom import clip_polyline, disk, douglas_peucker, mask_rings, polygon_area


def _dist_to_polyline(p, poly):
    best = np.inf
    for a, b in zip(poly[:-1], poly[1:]):
        ab = b - a
        t = 0.0 if not ab.any() else np.clip(np.dot(p - a, ab) / np.dot(ab, ab), 0, 1)
        best = min(best, np.hypot(*(p - (a + t * ab))))
    return best


def test_levels_are_ordered_and_grid_aligned():
    assert [l.name for l in LEVELS] == ["V0", "V1", "V2", "V3", "V4"]
    for a, b in zip(LEVELS[:-1], LEVELS[1:]):
        assert a.max_mpp == b.min_mpp
    for l in LEVELS:
        for v in (l.cell, l.block_margin, 2 * l.res + l.road_min_width):
            assert abs(v / l.res - round(v / l.res)) < 1e-9, (l.name, v)
    assert STYLES == ("land", "water", "block0", "block1", "block2", "road", "metro")


def test_dp_straight_line_collapses():
    pts = np.column_stack((np.linspace(0, 10, 11), np.zeros(11)))
    assert douglas_peucker(pts, 0.1).tolist() == [[0.0, 0.0], [10.0, 0.0]]


def test_dp_keeps_corner_beyond_tolerance():
    pts = np.array([[0.0, 0.0], [5.0, 1.0], [10.0, 0.0]])
    assert len(douglas_peucker(pts, 0.5)) == 3
    assert len(douglas_peucker(pts, 2.0)) == 2


def test_dp_closed_ring_stays_closed():
    ring = np.array([[0, 0], [4, 0], [4, 4], [0, 4], [0, 0]], float)
    out = douglas_peucker(ring, 0.1)
    assert np.allclose(out[0], out[-1]) and len(out) == 5


def test_dp_error_bound():
    rng = np.random.default_rng(1)
    x = np.linspace(0, 100, 400)
    pts = np.column_stack((x, np.cumsum(rng.normal(0, 0.3, 400))))
    out = douglas_peucker(pts, 0.5)
    assert len(out) < len(pts)
    assert max(_dist_to_polyline(p, out) for p in pts) <= 0.5 + 1e-9


def test_clip_polyline_inside_unchanged():
    pts = np.array([[1.0, 1.0], [2.0, 3.0], [4.0, 4.0]])
    runs = clip_polyline(pts, (0, 0, 10, 10))
    assert len(runs) == 1 and np.allclose(runs[0], pts)


def test_clip_polyline_splits_into_runs_with_edge_endpoints():
    pts = np.array([[-5.0, 5.0], [5.0, 5.0], [15.0, 5.0], [15.0, 8.0], [5.0, 8.0], [-5.0, 8.0]])
    runs = clip_polyline(pts, (0, 0, 10, 10))
    assert len(runs) == 2
    assert np.allclose(runs[0][0], [0, 5]) and np.allclose(runs[0][-1], [10, 5])
    assert np.allclose(runs[1][0], [10, 8]) and np.allclose(runs[1][-1], [0, 8])


def test_clip_polyline_fully_outside_is_empty():
    assert clip_polyline(np.array([[20.0, 20.0], [30.0, 30.0]]), (0, 0, 10, 10)) == []


def test_mask_rings_square_lies_on_pixel_edges():
    m = np.zeros((4, 4), bool)
    m[1:3, 1:3] = True
    rings = mask_rings(m, 10.0, 100.0, 2.0)
    assert len(rings) == 1
    r = rings[0]
    assert np.allclose(r[0], r[-1])
    assert np.allclose([r[:, 0].min(), r[:, 1].min(), r[:, 0].max(), r[:, 1].max()], [12, 94, 16, 98])


def test_mask_rings_touching_window_reaches_window_edge():
    rings = mask_rings(np.ones((3, 3), bool), 0.0, 6.0, 2.0)
    r = rings[0]
    assert np.allclose([r[:, 0].min(), r[:, 1].min(), r[:, 0].max(), r[:, 1].max()], [0, 0, 6, 6])


def test_mask_rings_fill_holes():
    m = np.ones((5, 5), bool)
    m[2, 2] = False
    assert len(mask_rings(m, 0, 10, 1)) == 2
    assert len(mask_rings(m, 0, 10, 1, fill_holes=True)) == 1


def test_mask_rings_empty():
    assert mask_rings(np.zeros((3, 3), bool), 0, 0, 1) == []


def test_polygon_area_and_disk():
    assert polygon_area(np.array([[0, 0], [1, 0], [1, 1], [0, 1], [0, 0]], float)) == pytest.approx(1.0)
    assert disk(1).astype(int).tolist() == [[0, 1, 0], [1, 1, 1], [0, 1, 0]]
