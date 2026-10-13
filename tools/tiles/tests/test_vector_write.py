import json
import os
import re
import shutil
from pathlib import Path

import numpy as np
import pytest

from nmtiles.manifest import emit_vector_manifest, emit_vector_stub
from nmtiles.vector_cells import Cell, VGrid
from nmtiles.vector_config import VLevel
from nmtiles.vector_extract import Shape
from nmtiles.vector_write import collection_json, depot_path, local_points, write_level

TPL = json.loads((Path(__file__).resolve().parents[1] / "templates" / "shapes.inkshapecollection.json").read_text())
LV = VLevel("V0", 0.5, 0.8, 0.25, 250.0, 0.5, 0.0, 2.0, 0.0, 300.0)


def _cell():
    road = Shape("road", np.array([[100.0, -40.0], [180.0, -10.0]]), 85.0)
    block = Shape("block1", np.array([[110.0, -30.0], [130.0, -30.0], [130.0, -20.0], [110.0, -20.0], [110.0, -30.0]]), 200.0)
    return Cell(1, 2, [block, road])


def test_depot_path():
    assert depot_path(3, 7, 11) == "nightmap\\vec\\V3\\c_7_11.inkshapecollection"


def test_local_points_inside_widget_box():
    c = _cell()
    b = c.bounds()
    w, h = (b[2] - b[0]) / LV.min_mpp, (b[3] - b[1]) / LV.min_mpp
    for s in c.shapes:
        p = local_points(s.pts, b, LV.min_mpp)
        assert p[:, 0].min() >= -1e-9 and p[:, 0].max() <= w + 1e-9
        assert p[:, 1].min() >= -1e-9 and p[:, 1].max() <= h + 1e-9
    assert np.allclose(local_points(np.array([[100.0, -10.0]]), b, 0.5), [[0.0, 0.0]])   # (min x, max y) -> origin


def test_collection_json_presets_in_order():
    doc = collection_json(TPL, _cell(), 0.5)
    presets = doc["Data"]["RootChunk"]["presets"]
    assert [p["name"]["$value"] for p in presets] == ["s0", "s1"]
    # The fill ring is written open (ink closes fills itself; a repeated first point makes the fill draw nothing).
    assert len(presets[0]["points"]) == 4 and len(presets[1]["points"]) == 2
    first, last = presets[0]["points"][0], presets[0]["points"][-1]
    assert (first["X"], first["Y"]) != (last["X"], last["Y"])
    assert TPL["Data"]["RootChunk"]["presets"] == []          # template untouched


def test_write_level_rows(tmp_path):
    g = VGrid(0.0, 0.0, 4, 4, 250.0)
    row = write_level(tmp_path, 0, LV, g, {(1, 2): _cell()}, TPL)
    assert (tmp_path / "nightmap" / "vec" / "V0" / "c_1_2.inkshapecollection.json").is_file()
    assert row["nx"] == 4 and row["unit"] == 0.5 and row["max_mpp"] == 0.8
    c = row["cells"][0]
    assert c["key"] == 2 * 4 + 1
    assert c["counts"] == [0, 0, 0, 1, 0, 1, 0] and c["points"] == [0, 0, 0, 5, 0, 2, 0]
    assert c["bounds"] == pytest.approx((200.0, 20.0, 160.0, 60.0))   # ((100-0)/.5, (0-(-10))/.5, 80/.5, 30/.5)


def _level_row(ncells):
    cells = [{"key": k, "bounds": (k * 1.0, 0.0, 10.0, 10.0), "counts": [1, 0, 0, 0, 0, 2, 0],
              "points": [5, 0, 0, 0, 0, 40, 0]} for k in range(ncells)]
    return {"min_mpp": 0.5, "max_mpp": 0.8, "unit": 0.5, "cell": 250.0, "ox": -8000.0, "otop": 8000.0,
            "nx": 64, "ny": 64, "cells": cells}


def test_vector_manifest_chunks_and_functions():
    src = emit_vector_manifest([_level_row(300)], "2.31")
    for fn in ("Available", "SourceGameVersion", "LevelCount", "StyleCount", "LevelMinMpp", "LevelMaxMpp", "LevelUnit",
               "LevelCell", "LevelOriginX", "LevelOriginTop", "LevelNx", "LevelNy", "LevelCells", "LevelBounds",
               "LevelCounts", "LevelPoints"):
        assert f"public static func {fn}(" in src, fn
    for lit in re.findall(r"= \[([^\]]*)\]|return \[([^\]]*)\]", src):
        body = lit[0] or lit[1]
        assert body.count(",") + 1 <= 128
    assert "module NightMap" in src and "return true;" in src


def test_vector_stub_unavailable():
    src = emit_vector_stub()
    assert "public static func Available() -> Bool {\n        return false;" in src
    assert "LevelCount() -> Int32 {\n        return 0;" in src


@pytest.mark.skipif(not os.environ.get("NIGHTMAP_SLOW") or not shutil.which("WolvenKit.CLI"), reason="slow: needs WolvenKit")
def test_wolvenkit_roundtrip(tmp_path):
    import subprocess
    from nmtiles.pack import deserialize_all
    g = VGrid(0.0, 0.0, 4, 4, 250.0)
    write_level(tmp_path / "ws", 0, LV, g, {(1, 2): _cell()}, TPL)
    (target,) = deserialize_all(tmp_path / "ws")
    out = tmp_path / "rt"
    out.mkdir()
    subprocess.run(["WolvenKit.CLI", "convert", "s", str(target), "-o", str(out)], check=True, stdout=subprocess.DEVNULL)
    back = json.loads(next(out.glob("*.json")).read_text())["Data"]["RootChunk"]["presets"]
    assert [p["name"]["$value"] for p in back] == ["s0", "s1"] and len(back[0]["points"]) == 5


def test_write_level_orders_shapes_to_match_counts(tmp_path):
    g = VGrid(0.0, 0.0, 4, 4, 250.0)
    c = _cell()
    unordered = Cell(1, 2, [c.shapes[1], c.shapes[0]])      # road before block
    row = write_level(tmp_path, 0, LV, g, {(1, 2): unordered}, TPL)
    doc = json.loads((tmp_path / "nightmap" / "vec" / "V0" / "c_1_2.inkshapecollection.json").read_text())
    presets = doc["Data"]["RootChunk"]["presets"]
    assert len(presets[0]["points"]) == 4 and len(presets[1]["points"]) == 2      # s0 = block (open ring), s1 = road
    assert row["cells"][0]["counts"] == [0, 0, 0, 1, 0, 1, 0]


def _funcs(src):
    parts = re.split(r"(?m)^    (?:public|private) static func ", src)[1:]
    return {p.split("(")[0]: p for p in parts}


def test_vector_manifest_small_functions_and_order():
    row = _level_row(300)
    src = emit_vector_manifest([row, _level_row(2)], "2.31")
    fs = _funcs(src)
    for n, body in fs.items():
        assert len(re.findall(r"-?\d+\.\d+|\b\d+\b", body.split("{", 1)[1])) <= 128 + 4 or n.startswith("Level") and "_" not in n, n
    for n in ("LevelCells", "LevelBounds", "LevelCounts", "LevelPoints"):
        assert "[" not in fs[n].split("{", 1)[1].replace("array<", "")
    for n, body in fs.items():
        lits = re.findall(r"return \[([^\]]*)\]", body)
        for l in lits:
            assert l.count(",") + 1 <= 128
    # chunk order reconstructs values
    vals = []
    k = 0
    while f"LevelCells_0_{k}" in fs:
        vals += [int(x) for x in re.search(r"return \[([^\]]*)\]", fs[f"LevelCells_0_{k}"]).group(1).split(",")]
        k += 1
    assert vals == list(range(300))
    assert "LevelBounds_L0()" in fs["LevelBounds"]
