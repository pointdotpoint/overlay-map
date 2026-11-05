"""scan.py: outline decoding, world transform and sector rows."""
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from scan import decode_outline, outlines_from_sector, world_polygon  # noqa: E402

FIXTURE = Path(__file__).resolve().parent / "fixtures" / "sector_min.json"


def load_fixture():
    return json.loads(FIXTURE.read_text())


def test_decode_prefers_buffer():
    o = load_fixture()["Data"]["RootChunk"]["nodes"][0]["Data"]["outline"]["Data"]
    assert decode_outline(o) == [(0, 0, 0), (1, 0, 0), (0, 1, 0)]


def test_world_polygon_scale_rotate_offset():
    poly = world_polygon([(1, 0, 0), (0, 1, 0)], {"position": {"X": 100, "Y": 200, "Z": 0},
                         "orientation": {"i": 0, "j": 0, "k": 0.70710678, "r": 0.70710678}}, {"X": 10, "Y": 20, "Z": 1})
    flat = [c for pt in poly for c in pt]   # pytest.approx does not take nested sequences
    assert flat == pytest.approx([100, 210, 80, 200], abs=1e-3)   # (10,0)->(0,10); (0,20)->(-20,0)


def test_outlines_from_sector():
    rows = outlines_from_sector(load_fixture(), "fixture")
    assert [(r["id"], r["debug"], len(r["poly"])) for r in rows] == [("Districts.Kabuki", "{test_loc_area}", 3)]
