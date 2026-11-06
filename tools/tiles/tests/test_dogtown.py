import numpy as np
import shapely

from nmtiles.dogtown import split_major
from nmtiles.minimap import MAJOR_WIDTH_M


def _strip(x0, x1, y0, y1):
    return np.array([[(x0, y0), (x1, y0), (x1, y1)], [(x0, y0), (x1, y1), (x0, y1)]], np.float32)


def test_split_major_by_road_width():
    wide = _strip(0, 300, 0, 30)          # 30 m boulevard
    narrow = _strip(0, 300, 100, 106)     # 6 m lane
    minor, major = split_major(np.concatenate([wide, narrow]))
    assert len(major) == 2 and major[:, :, 1].max() <= 30.5
    assert len(minor) == 2 and minor[:, :, 1].min() >= 99.5
    assert 6.0 < MAJOR_WIDTH_M < 30.0


def test_a_wide_junction_between_lanes_stays_minor():
    lanes = np.concatenate([_strip(0, 100, 0, 8), _strip(130, 230, 0, 8)])
    junction = _strip(100, 130, -11, 19)      # 30 x 30 m crossing: wide, but no road of its own
    minor, major = split_major(np.concatenate([lanes, junction]))
    assert len(major) == 0 and len(minor) == 6
