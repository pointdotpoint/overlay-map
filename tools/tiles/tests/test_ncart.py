from pathlib import Path

import numpy as np
import pytest

from nmtiles import ncart

HERE = Path(__file__).resolve().parent
FIXTURE = HERE.parent / "data" / "ncart_lines.json"
STATIONS = HERE.parent / "data" / "ncart_stations.json"


def test_load_lines_reads_number_colour_order_loop():
    lines = ncart.load_lines(FIXTURE)
    assert [l.number for l in lines] == [1, 2, 3, 4, 5]
    a = lines[0]
    assert a.letter == "A" and a.rgb == (229, 25, 25) and not a.looped
    assert a.stations[0] == "ARASAKA_WATERFRONT" and len(a.stations) == 9
    d = lines[3]
    assert d.letter == "D" and d.looped and d.rgb == (27, 233, 32)
    assert lines[4].rgb == (250, 131, 0)


def test_every_line_station_has_a_place():
    st = ncart.load_stations(STATIONS)
    for line in ncart.load_lines(FIXTURE):
        for s in line.stations:
            assert s in st, (line.letter, s)
    assert sum(1 for s in st.values() if s.marked) == 15
