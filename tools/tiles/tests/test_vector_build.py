import json
from pathlib import Path

import numpy as np

from nmtiles.buildings import Boxes
from nmtiles.glb import Mesh
from nmtiles.vector_build import build_vector
from nmtiles.vector_cells import Cell
from nmtiles.vector_config import VLevel
from nmtiles.vector_extract import Shape
from nmtiles.vector_preview import write_svg
from nmtiles.world import Transform

TPL = json.loads((Path(__file__).resolve().parents[1] / "templates" / "shapes.inkshapecollection.json").read_text())


def quad(x0, y0, x1, y1):
    pos = np.array([[x0, 0, -y0], [x1, 0, -y0], [x1, 0, -y1], [x0, 0, -y1]], float)
    return Mesh("q", pos, np.array([[0, 1, 2], [0, 2, 3]]))


def test_svg_has_one_path_per_shape(tmp_path):
    cells = {(0, 0): Cell(0, 0, [Shape("land", np.array([[0, 0], [10, 0], [10, 10], [0, 0]], float), 50.0),
                                 Shape("road", np.array([[0, 5], [10, 5]], float), 10.0)])}
    p = write_svg(tmp_path / "x.svg", cells, (0.0, 0.0, 10.0, 10.0), 0.5)
    text = p.read_text()
    assert text.startswith("<svg") and text.count("<path") == 2 and 'viewBox="0 -10 10 10"' in text


def test_build_vector_end_to_end_small(tmp_path):
    levels = (VLevel("V0", 0.5, 1.0, 0.25, 50.0, 0.5, 0.0, 2.0, 0.0, 20.0),
              VLevel("V1", 1.0, 4.0, 1.0, 100.0, 1.0, 0.0, 6.0, 0.0, 40.0))
    styled = {"land": [quad(0, 0, 100, 100)], "road": [quad(-10, 40, 110, 50)], "water": [], "metro": []}
    boxes = Boxes(*(np.array([v]) for v in (20.0, 80.0, 8.0, 8.0, 40.0, 0.0)))
    rows = build_vector(styled, boxes, Transform(1.0, -1.0, 0.0, 0.0), (0.0, 0.0, 100.0, 100.0),
                        tmp_path / "ws", tmp_path, TPL, levels=levels, log=lambda *_: None)
    assert len(rows) == 2 and rows[0]["cells"] and rows[1]["cells"]
    assert (tmp_path / "ws" / "nightmap" / "vec" / "V0").is_dir()
    report = json.loads((tmp_path / "vector_budget.json").read_text())
    assert [r["level"] for r in report] == ["V0", "V1"]
    assert (tmp_path / "vector_V0_downtown.svg").is_file()
