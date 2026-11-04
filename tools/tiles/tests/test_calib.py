import numpy as np

from nmtiles.calib import GATE_METERS, fit, parse_gamelog
from nmtiles.glb import Mesh
from tests.glbutil import square


def _road(x0, y0, x1, y1):
    pos, idx = square(x0, -y1, x1, -y0)
    return Mesh("r", np.array(pos, float), np.array(idx, np.int64))


# Small 4x4 m markers at road intersections: unlike long strips, they pin the offset on both axes.
CROSSINGS = [(x, y) for x in (0, 250, 500, 750, 1000) for y in (0, 200, 400, 600)]
ROADS = [_road(x - 2, y - 2, x + 2, y + 2) for x, y in CROSSINGS]


def test_parse_gamelog_keeps_last_per_name():
    text = "\n".join([
        "[2026-10-11 10:00:00 UTC-03:00] [1] [OverlayMap] CALIB|Corpo Plaza|-1520.5|120.25|7.0",
        "[2026-10-11 10:00:00 UTC-03:00] [1] [Other] CALIB|ignored|1|2|3",
        "[2026-10-11 10:00:01 UTC-03:00] [1] [OverlayMap] CALIB|Corpo Plaza|-1521.0|121.0|7.0",
        "[2026-10-11 10:00:01 UTC-03:00] [1] [OverlayMap] CALIB|Kabuki|10|-20|0",
    ])
    assert parse_gamelog(text) == [("Corpo Plaza", -1521.0, 121.0), ("Kabuki", 10.0, -20.0)]


def test_fit_recovers_offset_of_points_near_roads():
    rng = np.random.default_rng(1)
    true_offset = np.array([12.0, -6.0])          # world = mesh + offset
    pts = np.array(CROSSINGS, float) + true_offset + rng.normal(0, 0.5, (len(CROSSINGS), 2))
    tf, median = fit(pts, ROADS, search=30.0, step=2.0, mpp=2.0)
    assert (tf.sx, tf.sy) == (1.0, -1.0)
    assert abs(tf.dx - 12.0) <= 3.0 and abs(tf.dy + 6.0) <= 3.0
    assert median <= GATE_METERS


def test_fit_reports_large_median_for_points_unrelated_to_roads():
    pts = np.array([[5000.0 + i * 37.0, 9000.0 - i * 53.0] for i in range(30)])
    _, median = fit(pts, ROADS, search=10.0, step=5.0, mpp=4.0)
    assert median > GATE_METERS
