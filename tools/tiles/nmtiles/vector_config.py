"""Vector map levels and budgets (spec 2026-10-12 §3, §4.5). The budget checker tightens copies of these."""
from __future__ import annotations

from dataclasses import dataclass

STYLES = ("land", "water", "block0", "block1", "block2", "road", "metro")   # draw order == style id
BLOCK_STYLES = frozenset({"block0", "block1", "block2"})
MIN_BOX_HEIGHT = 5.0               # boxes lower than this (ground, plazas, road surfaces) are not buildings
HEIGHT_BUCKETS = (30.0, 80.0)        # block0 < 30 m <= block1 < 80 m <= block2
VIEW_UNITS = (1882.0, 1480.0)        # worst-case map area (4K panel; the 1.75 aspect cap bounds ultra-wide)
POINT_BUDGET = 27_000                # 30k minus 10 % headroom
SHAPE_BUDGET = 360                   # 400 minus 10 % headroom


@dataclass(frozen=True)
class VLevel:
    name: str
    min_mpp: float          # camera range start (m per map unit); also the level's design unit
    max_mpp: float
    tol: float              # Douglas-Peucker tolerance (m)
    cell: float             # cell size (m)
    res: float              # raster resolution for mask features (m/px)
    road_min_width: float   # roads narrower than this are removed by an opening (0 = keep all)
    merge_gap: float        # buildings closer than this merge into one block
    min_area: float         # blocks smaller than this are dropped (m^2)
    block_margin: float     # block window margin so whole blocks are seen (m)
    open_width: float = 0.0  # blocks thinner than this are removed by an opening (m); 0 = off


LEVELS = (
    VLevel("V0", 0.5, 0.8, 0.25, 250.0, 0.5, 0.0, 4.0, 0.0, 600.0, 3.0),
    VLevel("V1", 0.8, 1.6, 0.4, 500.0, 0.5, 0.0, 6.0, 100.0, 600.0, 3.0),
    VLevel("V2", 1.6, 4.0, 0.8, 1000.0, 1.0, 8.0, 12.0, 600.0, 1200.0, 6.0),
    VLevel("V3", 4.0, 10.0, 2.0, 2000.0, 2.0, 14.0, 30.0, 4000.0, 1200.0, 12.0),
    VLevel("V4", 10.0, 32.0, 5.0, 4000.0, 4.0, 20.0, 60.0, 20000.0, 4000.0, 24.0),
)
