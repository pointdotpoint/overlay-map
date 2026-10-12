"""Run the whole vector pipeline: per-level extraction, budget fitting, resource JSON, previews (spec §4)."""
from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Callable

from nmtiles.vector_budget import fit_level
from nmtiles.vector_cells import build_level, road_shapes
from nmtiles.vector_config import LEVELS
from nmtiles.vector_extract import Sources
from nmtiles.vector_preview import write_svg
from nmtiles.vector_write import write_level

DOWNTOWN = (-1800.0, 150.0)      # Corpo Plaza; crops are 2 km x 1.5 km around it
CROP = (2000.0, 1500.0)


def build_vector(styled: dict, boxes, tf, extent, ws: Path, out_dir: Path, template: dict, levels=LEVELS,
                 log: Callable[[str], None] = print, strict: bool = False) -> list[dict]:
    src = Sources(roads=styled.get("road", []), metro=styled.get("metro", []), land=styled.get("land", []),
                  water=styled.get("water", []), boxes=boxes, tf=tf)
    rows, report = [], []
    for li, level in enumerate(levels):
        t0 = time.time()
        grid, cells = build_level(level, src, extent, log)
        used, cells, rep = fit_level(level, grid, cells, lambda lv: road_shapes(lv, src, grid), log, strict=strict)
        rows.append(write_level(ws, li, used, grid, cells, template))
        report.append({**rep, "cells": len(cells), "params": used.__dict__, "seconds": round(time.time() - t0)})
        cx, cy = DOWNTOWN
        write_svg(out_dir / f"vector_V{li}_downtown.svg", cells,
                  (cx - CROP[0] / 2, cy - CROP[1] / 2, cx + CROP[0] / 2, cy + CROP[1] / 2), used.min_mpp)
        if li >= 2:
            write_svg(out_dir / f"vector_V{li}_full.svg", cells, extent, used.min_mpp * 4)
        log(f"{level.name}: {len(cells)} cells, worst view {rep['points']} points / {rep['shapes']} shapes, "
            f"steps {rep['steps']}, {time.time() - t0:.0f}s")
    log("vector summary:")
    for r in report:
        log(f"  {r['level']}: {r['points']} points / {r['shapes']} shapes, over_budget={r['over_budget']}, "
            f"{r['cells']} cells, {r['seconds']}s")
    (out_dir / "vector_budget.json").write_text(json.dumps(report, indent=2))
    return rows
