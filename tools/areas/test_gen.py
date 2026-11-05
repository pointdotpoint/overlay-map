"""gen.py: area sizes, drop rules, superseded shapes, ordering and the generated script."""
import re
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen import Area, emit, game_areas, keep_id, merge, polygon_area  # noqa: E402


def row(id_, debug, poly=((0, 0), (1, 0), (0, 1))):
    return {"id": id_, "node": "worldLocationAreaNode", "debug": debug, "sector": "s", "poly": [list(p) for p in poly]}


def test_polygon_area_winding():
    sq = [(0, 0), (10, 0), (10, 10), (0, 10)]
    assert polygon_area(sq) == polygon_area(sq[::-1]) == 100


def test_keep_id():
    assert keep_id("Districts.JapanTown") and keep_id("Districts.ArasakaTowerLobby")
    assert not any(keep_id(i) for i in ("", "0", "Districts.q110Cyberspace", "Districts.VR_Tutorial",
                                        "Districts.q201SpaceStation", "Districts.ArasakaTowerCEOFloor"))


def test_new_shapes_supersede_old():
    rows = [row("Districts.Coastview", "{coastview_loc_area}"), row("Districts.Coastview", "{coastview_loc_area_new}"),
            row("Districts.Kabuki", "{kabuki_loc_area}")]
    assert sorted((a.key, len(a.poly)) for a in game_areas(rows)) == [("Districts.Coastview", 3), ("Districts.Kabuki", 3)]
    # exactly one Coastview survives (the _new one)


def test_merge_sorts_smallest_first():
    big, small = Area("A", "", "", "", [(0, 0), (100, 0), (0, 100)]), Area("B", "b", "Districts.A", "", [(0, 0), (1, 0), (0, 1)])
    assert [a.key for a in merge([big], [small])] == ["B", "A"]


def test_emit_round_trip_and_chunk_limit():
    areas = [Area(f"Districts.X{i}", "", "", "", [(i, 0.04), (i + 1.26, 0), (i, 1)]) for i in range(400)]
    src = emit(areas)
    bodies = re.findall(r'case \d+: return "(.*)";', src)
    assert all(len(b) <= 8000 for b in bodies)
    entries = ";".join(bodies).split(";")
    assert len(entries) == 400 and entries[0] == "Districts.X0||||0.0,0.0,1.3,0.0,0.0,1.0"
    assert "return 400;" in src


def test_emit_rejects_separators():
    with pytest.raises(ValueError):
        emit([Area("K", "a|b", "", "", [(0, 0), (1, 0), (0, 1)])])
