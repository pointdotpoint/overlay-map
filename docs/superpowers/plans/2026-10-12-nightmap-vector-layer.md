# NightMap Vector Map Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the pixelated raster map with smooth vector geometry at every zoom level. The geometry is road edges, land, water, building blocks and the metro. It is prebuilt into per-cell `inkShapeCollection` resources and drawn by a budgeted runtime layer. Raster tiles stay as a fallback.

**Architecture:** The offline Python pipeline (`tools/tiles/nmtiles/vector_*.py`) handles everything ahead of time:
- It rasterizes the vanilla 3D-map meshes and building boxes per cell.
- It traces contours with `contourpy`, then simplifies them with Douglas–Peucker.
- It enforces a worst-view budget.
- It writes one shape resource per non-empty cell for each of 5 LOD levels, plus a generated `NMVectorManifest`.

At runtime (`NMVectorLayer`), the layer:
- picks a level with hysteresis;
- moves and scales one canvas per level for pan and zoom;
- attaches pooled `inkShape` widgets only for visible cells, in two budget passes;
- compensates line thickness on zoom.

**Tech Stack:**
- Python 3.14 with numpy, scipy (`ndimage`), Pillow and contourpy 1.4, tested with pytest.
- WolvenKit.CLI (`convert d`, `pack`).
- redscript, compile-checked offline by `tools/check.sh`.
- Codeware `inkShape` API (`SetResource`, `SetShape`, `SetVariant`, `SetLineThickness`, …).

**Spec:** `docs/superpowers/specs/2026-10-12-nightmap-vector-layer-design.md`. Read it in full before starting. Evidence for every hard constraint is in `notes/VECTOR-SPIKE.md`.

## Global Constraints

- **Geometry source.** Geometry only comes from shape resources (`SetResource` + `SetShape`). A runtime `vertexList` is never drawn.
- **One path per widget.** Every closed outline is its own widget. Closed rings repeat their first point at the end, because the Border variant does not close a path.
- **Frame budget.** The vector map gets +2 ms average and +4 ms p95 over `closed_baseline`. That allows ≤ 30,000 drawn points and ≤ 400 shapes on screen. The pipeline targets 27,000 points and 360 shapes (10% headroom).
- **Worst-case view.** The worst-case map area is 1882 × 1480 HUD units.
- **Style ids** (shared by Python and redscript): `0 land, 1 water, 2 block0 (<30 m), 3 block1 (<80 m), 4 block2, 5 road, 6 metro`. Presets in a cell are written in this style order and named `s0, s1, …`.
- **Levels** (`min_mpp`, `max_mpp`, tolerance m, cell m, raster m/px, road min width m, merge gap m, min block area m², block margin m):
  - `V0 0.5 0.8 0.25 250 0.5 0 2 0 300`
  - `V1 0.8 1.6 0.4 500 0.5 0 6 100 300`
  - `V2 1.6 4 0.8 1000 1 8 12 600 600`
  - `V3 4 10 2 2000 2 14 30 4000 1200`
  - `V4 10 32 5 4000 4 20 60 20000 4000`
- **Units.**
  - The design unit is the level's `min_mpp`.
  - Preset points are `((wx - bminx)/unit, (bmaxy - wy)/unit)`, relative to the cell's draw bounds.
  - The widget sits at the draw bounds and is sized to them.
- **Depot path.** `nightmap\vec\V{l}\c_{ix}_{iy}.inkshapecollection`. Cell key is `iy * nx + ix`.
- **Runtime constants.**
  - Hysteresis 8%.
  - Thickness re-applied when the scale changes by more than 5%.
  - Widget pool of 800.
  - Fail-over to raster after 3 s with no existing visible cell resource.
- **Camera range.** The camera's max zoom-out is the last vector level's `max_mpp` (32) with Vector on, and 16 with Raster.
- **redscript gotchas:**
  - No `continue`.
  - No Bool `!=` (use `NotEquals`).
  - No negative literal field defaults (set them in `Create`).
  - `ArraySize`/iteration on a function-call temporary reads 0 in-game, so always bind manifest arrays to a local first.
  - Generated array literals stay at ≤ 128 elements.
- **Frame loop and timing.** Use `DelayCallback(cb, 0.0, false)` and `NMClock.NowMs()`. Never `DelayCallbackNextFrame` or `EngineTime`.
- **Commits** end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Preset points outside the widget box.** If any local point falls outside `[0,w]×[0,h]`, ink may clip or rescale the shape. Task 4 asserts that every point lies inside its cell's draw bounds.
2. **Seams between cells.** A road edge crossing a cell border must end at exactly the same point in both cells. Task 2 tests a diagonal road over a shared edge.
3. **Flicker at a level boundary.** Hovering the zoom near a boundary must not switch levels back and forth. Task 6's self-test drives a hysteresis sequence.
4. **Camera outside the data.** When the view covers no cells, the layer attaches nothing and doesn't error. Task 6's self-test covers an empty visible set; Task 7's `Sync` handles zero cells.
5. **Raster after a vector failure.** Raster mode, including after an automatic fail-over, must clamp zoom to 16. Task 7's self-test checks `MaxMppFor(false) ≤ 16`, and `FallBackToRaster` re-clamps the camera.

---

### Task 1: Vector config and geometry primitives

**Files:**
- Create: `tools/tiles/nmtiles/vector_config.py`, `tools/tiles/nmtiles/vector_geom.py`
- Test: `tools/tiles/tests/test_vector_geom.py`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `vector_config`: `VLevel` (frozen dataclass with fields `name, min_mpp, max_mpp, tol, cell, res, road_min_width, merge_gap, min_area, block_margin`), `LEVELS: tuple[VLevel, ...]`, `STYLES`, `BLOCK_STYLES`, `HEIGHT_BUCKETS`, `VIEW_UNITS`, `POINT_BUDGET`, `SHAPE_BUDGET`.
  - `vector_geom`:
    - `douglas_peucker(pts: np.ndarray, tol: float) -> np.ndarray`
    - `clip_polyline(pts: np.ndarray, rect: tuple) -> list[np.ndarray]`
    - `mask_rings(mask: np.ndarray, x0: float, y_top: float, res: float, fill_holes: bool = False) -> list[np.ndarray]`
    - `polygon_area(ring: np.ndarray) -> float`
    - `disk(r: int) -> np.ndarray`

- [ ] **Step 1: Write the failing tests**

`tools/tiles/tests/test_vector_geom.py`:
```python
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
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `cd tools/tiles && python3 -m pytest -q tests/test_vector_geom.py`
Expected: FAIL with `ModuleNotFoundError: No module named 'nmtiles.vector_config'`.

- [ ] **Step 3: Implement**

`tools/tiles/nmtiles/vector_config.py`:
```python
"""Vector map levels and budgets (spec 2026-10-12 §3, §4.5). The budget checker tightens copies of these."""
from __future__ import annotations

from dataclasses import dataclass

STYLES = ("land", "water", "block0", "block1", "block2", "road", "metro")   # draw order == style id
BLOCK_STYLES = frozenset({"block0", "block1", "block2"})
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


LEVELS = (
    VLevel("V0", 0.5, 0.8, 0.25, 250.0, 0.5, 0.0, 2.0, 0.0, 300.0),
    VLevel("V1", 0.8, 1.6, 0.4, 500.0, 0.5, 0.0, 6.0, 100.0, 300.0),
    VLevel("V2", 1.6, 4.0, 0.8, 1000.0, 1.0, 8.0, 12.0, 600.0, 600.0),
    VLevel("V3", 4.0, 10.0, 2.0, 2000.0, 2.0, 14.0, 30.0, 4000.0, 1200.0),
    VLevel("V4", 10.0, 32.0, 5.0, 4000.0, 4.0, 20.0, 60.0, 20000.0, 4000.0),
)
```

`tools/tiles/nmtiles/vector_geom.py`:
```python
"""Geometry primitives for the vector layer: simplification, clipping, mask contours."""
from __future__ import annotations

import contourpy
import numpy as np
from scipy import ndimage


def douglas_peucker(pts: np.ndarray, tol: float) -> np.ndarray:
    """Simplify a polyline (or a closed ring whose first point equals its last) within tol."""
    pts = np.asarray(pts, float)
    n = len(pts)
    if n < 3:
        return pts.copy()
    if np.allclose(pts[0], pts[-1]):
        d = np.hypot(*(pts - pts[0]).T)
        k = int(np.argmax(d))
        if k == 0:
            return pts[:1].copy()
        a = douglas_peucker(pts[: k + 1], tol)
        b = douglas_peucker(pts[k:], tol)
        return np.vstack([a, b[1:]])
    keep = np.zeros(n, bool)
    keep[0] = keep[-1] = True
    stack = [(0, n - 1)]
    while stack:
        i, j = stack.pop()
        if j <= i + 1:
            continue
        seg = pts[j] - pts[i]
        length = float(np.hypot(*seg))
        rel = pts[i + 1:j] - pts[i]
        if length == 0.0:
            d = np.hypot(rel[:, 0], rel[:, 1])
        else:
            d = np.abs(seg[0] * rel[:, 1] - seg[1] * rel[:, 0]) / length
        m = int(np.argmax(d))
        if d[m] > tol:
            k = i + 1 + m
            keep[k] = True
            stack.append((i, k))
            stack.append((k, j))
    return pts[keep]


def _clip_segment(a: np.ndarray, b: np.ndarray, rect: tuple) -> tuple | None:
    """Liang-Barsky: (p, q, t0, t1) for the visible part of segment a-b, or None."""
    x0, y0, x1, y1 = rect
    dx, dy = b[0] - a[0], b[1] - a[1]
    t0, t1 = 0.0, 1.0
    for p, q in ((-dx, a[0] - x0), (dx, x1 - a[0]), (-dy, a[1] - y0), (dy, y1 - a[1])):
        if p == 0:
            if q < 0:
                return None
            continue
        t = q / p
        if p < 0:
            if t > t1:
                return None
            t0 = max(t0, t)
        else:
            if t < t0:
                return None
            t1 = min(t1, t)
    if t0 > t1:
        return None
    return np.array([a[0] + t0 * dx, a[1] + t0 * dy]), np.array([a[0] + t1 * dx, a[1] + t1 * dy]), t0, t1


def clip_polyline(pts: np.ndarray, rect: tuple) -> list[np.ndarray]:
    """Clip a polyline to rect (min_x, min_y, max_x, max_y); returns the inside runs (each >= 2 points)."""
    runs: list[np.ndarray] = []
    cur: list[np.ndarray] = []

    def flush() -> None:
        if len(cur) >= 2:
            runs.append(np.array(cur))

    for a, b in zip(pts[:-1], pts[1:]):
        seg = _clip_segment(a, b, rect)
        if seg is None:
            flush()
            cur = []
            continue
        p, q, t0, t1 = seg
        if t0 > 0.0 or not cur:
            flush()
            cur = [p]
        cur.append(q)
        if t1 < 1.0:
            flush()
            cur = []
    flush()
    return runs


def mask_rings(mask: np.ndarray, x0: float, y_top: float, res: float, fill_holes: bool = False) -> list[np.ndarray]:
    """Closed iso-0.5 contours of a boolean mask in world metres.

    Pixel (row, col) covers x [x0 + col*res, x0 + (col+1)*res] and y [y_top - (row+1)*res, y_top - row*res].
    The mask is zero-padded, so every contour closes and a mask touching the window edge yields a ring on
    that edge exactly.
    """
    if not mask.any():
        return []
    m = ndimage.binary_fill_holes(mask) if fill_holes else mask
    z = np.pad(m.astype(np.float32), 1)
    gen = contourpy.contour_generator(z=z, line_type=contourpy.LineType.Separate)
    rings = []
    for line in gen.lines(0.5):
        col = line[:, 0] - 1.0
        row = line[:, 1] - 1.0
        r = np.column_stack((x0 + (col + 0.5) * res, y_top - (row + 0.5) * res))
        if not np.allclose(r[0], r[-1]):
            r = np.vstack([r, r[:1]])
        rings.append(r)
    return rings


def polygon_area(ring: np.ndarray) -> float:
    x, y = ring[:, 0], ring[:, 1]
    return float(abs(np.dot(x[:-1], y[1:]) - np.dot(x[1:], y[:-1])) / 2.0)


def disk(r: int) -> np.ndarray:
    yy, xx = np.ogrid[-r:r + 1, -r:r + 1]
    return xx * xx + yy * yy <= r * r
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `cd tools/tiles && python3 -m pytest -q tests/test_vector_geom.py`
Expected: 13 passed.

Run the whole fast suite: `python3 -m pytest -q`
Expected: all pass. Before this task it reported 50 passed and 1 skipped; it should now show 63 passed and 1 skipped.

- [ ] **Step 5: Commit**

```bash
git add tools/tiles/nmtiles/vector_config.py tools/tiles/nmtiles/vector_geom.py tools/tiles/tests/test_vector_geom.py
git commit -m "Vector: level config and geometry primitives (DP, clipping, mask contours)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Per-cell feature extraction

**Files:**
- Create: `tools/tiles/nmtiles/vector_extract.py`
- Test: `tools/tiles/tests/test_vector_extract.py`

**Interfaces:**
- Consumes:
  - From Task 1: `VLevel`, `HEIGHT_BUCKETS`, `clip_polyline`, `disk`, `douglas_peucker`, `mask_rings`, `polygon_area`.
  - Existing code:
    - `nmtiles.render.rasterize_mask(meshes, tf, origin_x, origin_top, mpp, width, height) -> np.ndarray[bool]`
    - `nmtiles.glb.Mesh(name, positions (N,3) glTF, triangles (M,3))`
    - `nmtiles.world.Transform(sx, sy, dx, dy)`, where world = `(sx*gx+dx, sy*gz+dy)`
    - `nmtiles.buildings.Boxes`
- Produces:
  - Types: `Shape(style: str, pts: np.ndarray, prio: float)` and `Sources(roads, metro, land, water: list[Mesh], boxes: Boxes, tf: Transform)`.
  - Feature functions:
    - `line_features(meshes, tf, cell, level, style, min_width=0.0) -> list[Shape]`
    - `area_features(src, cell, level) -> list[Shape]`
    - `block_features(corners, centres, heights, cell, level) -> list[Shape]`
  - Helpers: `height_style(h) -> str` and `grow(rect, m)`.
  - `Rect` is `(min_x, min_y, max_x, max_y)` in world metres.

- [ ] **Step 1: Write the failing tests**

`tools/tiles/tests/test_vector_extract.py`:
```python
import numpy as np
import pytest

from nmtiles.buildings import Boxes, box_corners
from nmtiles.glb import Mesh
from nmtiles.vector_config import VLevel
from nmtiles.vector_extract import Sources, area_features, block_features, height_style, line_features
from nmtiles.world import Transform

TF = Transform(1.0, -1.0, 0.0, 0.0)                 # world = (gx, -gz)
LV = VLevel("T", 0.5, 1.0, 0.25, 50.0, 0.5, 0.0, 2.0, 0.0, 20.0)


def quad(x0, y0, x1, y1, name="q"):
    pos = np.array([[x0, 0, -y0], [x1, 0, -y0], [x1, 0, -y1], [x0, 0, -y1]], float)
    return Mesh(name, pos, np.array([[0, 1, 2], [0, 2, 3]]))


def strip(p0, p1, width, name="road"):
    d = np.array(p1, float) - np.array(p0, float)
    n = np.array([-d[1], d[0]]) / np.hypot(*d) * width / 2
    c = [np.array(p0) + n, np.array(p1) + n, np.array(p1) - n, np.array(p0) - n]
    pos = np.array([[x, 0, -y] for x, y in c], float)
    return Mesh(name, pos, np.array([[0, 1, 2], [0, 2, 3]]))


def boxes(*rows):
    a = np.array(rows, float)   # cx, cy, dx, dy, dz, yaw
    return Boxes(a[:, 0], a[:, 1], a[:, 2], a[:, 3], a[:, 4], a[:, 5])


def test_road_strip_gives_two_edges_across_the_cell():
    cell = (0.0, 0.0, 50.0, 50.0)
    shapes = line_features([strip((-20, 25), (70, 25), 10)], TF, cell, LV, "road")
    assert len(shapes) == 2 and all(s.style == "road" for s in shapes)
    ys = sorted(float(np.mean(s.pts[:, 1])) for s in shapes)
    assert ys[0] == pytest.approx(20.0, abs=0.3) and ys[1] == pytest.approx(30.0, abs=0.3)
    for s in shapes:
        assert s.pts[:, 0].min() == pytest.approx(0.0) and s.pts[:, 0].max() == pytest.approx(50.0)
        assert s.prio == pytest.approx(50.0, abs=0.5)


def test_road_width_filter_drops_narrow_roads():
    cell = (0.0, 0.0, 50.0, 50.0)
    assert line_features([strip((-20, 25), (70, 25), 6)], TF, cell, LV, "road", min_width=8.0) == []
    assert len(line_features([strip((-20, 25), (70, 25), 10)], TF, cell, LV, "road", min_width=8.0)) == 2


def test_road_edges_meet_exactly_at_shared_cell_edge():
    road = [strip((-20, 0), (120, 50), 8)]
    a = line_features(road, TF, (0.0, 0.0, 50.0, 50.0), LV, "road")
    b = line_features(road, TF, (50.0, 0.0, 100.0, 50.0), LV, "road")
    ends_a = sorted(round(float(p[1]), 6) for s in a for p in (s.pts[0], s.pts[-1]) if abs(p[0] - 50.0) < 1e-9)
    ends_b = sorted(round(float(p[1]), 6) for s in b for p in (s.pts[0], s.pts[-1]) if abs(p[0] - 50.0) < 1e-9)
    assert len(ends_a) == 2 and ends_a == ends_b


def test_land_minus_water_clipped_to_cell():
    src = Sources([], [], [quad(-100, -100, 200, 200)], [quad(-100, -100, 25, 200)], boxes([0, 0, 1, 1, 1, 0]), TF)
    cell = (0.0, 0.0, 50.0, 50.0)
    shapes = area_features(src, cell, LV)
    land = [s for s in shapes if s.style == "land"]
    water = [s for s in shapes if s.style == "water"]
    assert len(land) == 1 and len(water) == 1
    assert land[0].prio == pytest.approx(25 * 50, rel=0.02) and water[0].prio == pytest.approx(25 * 50, rel=0.02)
    for s in shapes:
        assert np.allclose(s.pts[0], s.pts[-1])
        assert s.pts[:, 0].min() >= -1e-9 and s.pts[:, 0].max() <= 50 + 1e-9


def _blocks(rows, cell, level=LV):
    b = boxes(*rows)
    corners = box_corners(b)
    return block_features(corners, corners.mean(axis=1), np.asarray(b.dz), cell, level)


def test_blocks_merge_within_gap_and_bucket_by_height():
    cell = (0.0, 0.0, 50.0, 50.0)
    out = _blocks([[20, 25, 8, 8, 10, 0], [29, 25, 8, 8, 100, 0]], cell)      # 1 m apart, gap 2 m
    assert len(out) == 1 and out[0].style == "block2"
    assert np.allclose(out[0].pts[0], out[0].pts[-1])
    apart = _blocks([[10, 25, 8, 8, 10, 0], [30, 25, 8, 8, 10, 0]], cell)     # 12 m apart
    assert len(apart) == 2 and {s.style for s in apart} == {"block0"}


def test_block_owned_only_by_centroid_cell():
    rows = [[60, 25, 8, 8, 10, 0]]          # centre in the neighbour cell
    assert _blocks(rows, (0.0, 0.0, 50.0, 50.0)) == []
    assert len(_blocks(rows, (50.0, 0.0, 100.0, 50.0))) == 1


def test_block_min_area_filter():
    lv = VLevel("T", 0.5, 1.0, 0.25, 50.0, 0.5, 0.0, 2.0, 100.0, 20.0)
    assert _blocks([[25, 25, 6, 6, 10, 0]], (0.0, 0.0, 50.0, 50.0), lv) == []
    assert len(_blocks([[25, 25, 12, 12, 10, 0]], (0.0, 0.0, 50.0, 50.0), lv)) == 1


def test_height_style_buckets():
    assert (height_style(5), height_style(30), height_style(79.9), height_style(80)) == ("block0", "block1", "block1", "block2")
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `cd tools/tiles && python3 -m pytest -q tests/test_vector_extract.py`
Expected: FAIL with `ModuleNotFoundError: No module named 'nmtiles.vector_extract'`.

- [ ] **Step 3: Implement**

`tools/tiles/nmtiles/vector_extract.py`:
```python
"""Per-cell vector features (spec 2026-10-12 §4.1-4.2): road/metro edges, land/water fills, building blocks.

Cell origins, window margins and raster resolution are whole multiples of each other, so neighbouring cells
see identical pixel grids and trace identical contours along their shared edges.
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

from nmtiles.buildings import Boxes
from nmtiles.glb import Mesh
from nmtiles.render import rasterize_mask
from nmtiles.vector_config import HEIGHT_BUCKETS, VLevel
from nmtiles.vector_geom import clip_polyline, disk, douglas_peucker, mask_rings, polygon_area
from nmtiles.world import Transform

Rect = tuple[float, float, float, float]   # (min_x, min_y, max_x, max_y), world metres
BOX_PICK_MARGIN = 150.0                     # boxes whose centre is this far outside a window can still reach into it


@dataclass
class Shape:
    style: str
    pts: np.ndarray     # (N, 2) world metres; closed rings repeat their first point last
    prio: float         # larger = more important within its style (length or area)


@dataclass
class Sources:
    roads: list[Mesh]
    metro: list[Mesh]
    land: list[Mesh]
    water: list[Mesh]
    boxes: Boxes
    tf: Transform


def grow(rect: Rect, m: float) -> Rect:
    return (rect[0] - m, rect[1] - m, rect[2] + m, rect[3] + m)


def window_mask(meshes: list[Mesh], tf: Transform, rect: Rect, res: float) -> np.ndarray:
    x0, y0, x1, y1 = rect
    w = max(1, int(round((x1 - x0) / res)))
    h = max(1, int(round((y1 - y0) / res)))
    if not meshes:
        return np.zeros((h, w), bool)
    return rasterize_mask(meshes, tf, x0, y1, res, w, h)


def line_features(meshes: list[Mesh], tf: Transform, cell: Rect, level: VLevel, style: str,
                  min_width: float = 0.0) -> list[Shape]:
    """Edge lines of a surface (iso-0.5 contours), clipped to the cell. min_width removes narrower parts."""
    win = grow(cell, 2 * level.res + min_width)
    mask = window_mask(meshes, tf, win, level.res)
    if min_width > 0 and mask.any():
        mask = ndimage.binary_opening(mask, structure=disk(max(1, int(round(min_width / 2 / level.res)))))
    out = []
    for ring in mask_rings(mask, win[0], win[3], level.res):
        for run in clip_polyline(ring, cell):
            s = douglas_peucker(run, level.tol)
            length = float(np.hypot(*np.diff(s, axis=0).T).sum()) if len(s) >= 2 else 0.0
            if length >= 3 * level.tol:
                out.append(Shape(style, s, length))
    return out


def area_features(src: Sources, cell: Rect, level: VLevel) -> list[Shape]:
    """Fill polygons for land (terrain minus water) and water, traced on exactly the cell (clipped there)."""
    land = window_mask(src.land, src.tf, cell, level.res)
    water = window_mask(src.water, src.tf, cell, level.res)
    out = []
    min_area = (2 * level.res) ** 2
    for style, mask in (("land", land & ~water), ("water", water)):
        for ring in mask_rings(mask, cell[0], cell[3], level.res, fill_holes=True):
            s = douglas_peucker(ring, level.tol)
            a = polygon_area(s) if len(s) >= 4 else 0.0
            if a >= min_area:
                out.append(Shape(style, s, a))
    return out


def height_style(h: float) -> str:
    if h < HEIGHT_BUCKETS[0]:
        return "block0"
    return "block1" if h < HEIGHT_BUCKETS[1] else "block2"


def block_features(corners: np.ndarray, centres: np.ndarray, heights: np.ndarray, cell: Rect,
                   level: VLevel) -> list[Shape]:
    """Merged building blocks whose outline centroid lies in the cell.

    corners: (N,4,2) world box corners; centres: (N,2); heights: (N,) metres.
    """
    win = grow(cell, level.block_margin)
    x0, y0, x1, y1 = win
    m = BOX_PICK_MARGIN
    pick = np.nonzero((centres[:, 0] > x0 - m) & (centres[:, 0] < x1 + m)
                      & (centres[:, 1] > y0 - m) & (centres[:, 1] < y1 + m))[0]
    if len(pick) == 0:
        return []
    res = level.res
    w = max(1, int(round((x1 - x0) / res)))
    h = max(1, int(round((y1 - y0) / res)))
    occ = Image.new("1", (w, h), 0)
    top = Image.new("L", (w, h), 0)
    d_occ, d_top = ImageDraw.Draw(occ), ImageDraw.Draw(top)
    for k in pick[np.argsort(heights[pick], kind="stable")]:
        poly = [((x - x0) / res, (y1 - y) / res) for x, y in corners[k]]
        d_occ.polygon(poly, fill=1)
        d_top.polygon(poly, fill=int(min(255, max(1, heights[k]))))
    mask = np.asarray(occ, bool)
    tops = np.asarray(top)
    if level.merge_gap > 0:
        mask = ndimage.binary_closing(mask, structure=disk(max(1, int(round(level.merge_gap / 2 / res))))) | mask
    mask = ndimage.binary_fill_holes(mask)
    lab, n = ndimage.label(mask)
    if n == 0:
        return []
    peak = ndimage.maximum(tops, lab, index=np.arange(1, n + 1))
    out = []
    for i, sl in enumerate(ndimage.find_objects(lab)):
        if sl is None:
            continue
        sub = lab[sl] == i + 1
        ox = x0 + sl[1].start * res
        oy = y1 - sl[0].start * res
        for ring in mask_rings(sub, ox, oy, res):
            s = douglas_peucker(ring, level.tol)
            if len(s) < 4:
                continue
            a = polygon_area(s)
            c = s[:-1].mean(axis=0)
            if a < max(level.min_area, (2 * res) ** 2):
                continue
            if not (cell[0] <= c[0] < cell[2] and cell[1] <= c[1] < cell[3]):
                continue
            out.append(Shape(height_style(float(peak[i])), s, a))
    return out
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `cd tools/tiles && python3 -m pytest -q tests/test_vector_extract.py`
Expected: 8 passed.

If `test_road_edges_meet_exactly_at_shared_cell_edge` fails, the two windows' pixel grids are not aligned. Check that `grow(cell, 2*res + min_width)` is a multiple of `res`, and don't loosen the test.

Then run the full fast suite with `python3 -m pytest -q`. All tests must pass.

- [ ] **Step 5: Commit**

```bash
git add tools/tiles/nmtiles/vector_extract.py tools/tiles/tests/test_vector_extract.py
git commit -m "Vector: per-cell road/metro edges, land/water fills, merged building blocks

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Level assembly and worst-view budget

**Files:**
- Create: `tools/tiles/nmtiles/vector_cells.py`, `tools/tiles/nmtiles/vector_budget.py`
- Test: `tools/tiles/tests/test_vector_cells.py`

**Interfaces:**
- Consumes:
  - From Task 2: `Shape`, `Sources`, `line_features`, `area_features`, `block_features`.
  - From Task 1: `STYLES`, `BLOCK_STYLES`, `VIEW_UNITS`, `POINT_BUDGET`, `SHAPE_BUDGET`, `douglas_peucker`.
  - Existing code: `nmtiles.buildings.box_corners`.
- Produces:
  - `vector_cells`:
    - `VGrid(ox, otop, nx, ny, cell)`, with `.rect(ix, iy) -> Rect`
    - `grid_for(level, extent) -> VGrid`
    - `Cell(ix, iy, shapes)`, with `.bounds() -> Rect` and `.style_counts() -> (list[int], list[int])`
    - `order(shapes) -> list[Shape]`
    - `build_level(level, src, extent, log=print) -> (VGrid, dict[(ix, iy), Cell])`
    - `road_shapes(level, src, grid) -> dict[(ix, iy), list[Shape]]`
  - `vector_budget`:
    - `BudgetError`
    - `worst_view(level, grid, cells) -> (points, shapes, (x0, y_top))`
    - `fit_level(level, grid, cells, rebuild_roads, log=print, point_budget=POINT_BUDGET, shape_budget=SHAPE_BUDGET) -> (VLevel, dict, dict)`. Its report dict has the keys `level, steps, points, shapes, at`.

- [ ] **Step 1: Write the failing tests**

`tools/tiles/tests/test_vector_cells.py`:
```python
import numpy as np
import pytest

from nmtiles.buildings import Boxes
from nmtiles.glb import Mesh
from nmtiles.vector_budget import BudgetError, fit_level, worst_view
from nmtiles.vector_cells import Cell, VGrid, build_level, grid_for, order
from nmtiles.vector_config import VLevel
from nmtiles.vector_extract import Shape, Sources
from nmtiles.world import Transform

TF = Transform(1.0, -1.0, 0.0, 0.0)
LV = VLevel("T", 0.5, 1.0, 0.25, 50.0, 0.5, 0.0, 2.0, 0.0, 20.0)


def quad(x0, y0, x1, y1):
    pos = np.array([[x0, 0, -y0], [x1, 0, -y0], [x1, 0, -y1], [x0, 0, -y1]], float)
    return Mesh("q", pos, np.array([[0, 1, 2], [0, 2, 3]]))


def boxes(*rows):
    a = np.array(rows, float)
    return Boxes(a[:, 0], a[:, 1], a[:, 2], a[:, 3], a[:, 4], a[:, 5])


def sq(x, y, s=2.0, style="block0", prio=4.0):
    pts = np.array([[x, y], [x + s, y], [x + s, y + s], [x, y + s], [x, y]], float)
    return Shape(style, pts, prio)


def test_grid_for_aligns_to_cell():
    g = grid_for(LV, (-130.0, -70.0, 230.0, 40.0))
    assert (g.ox, g.otop, g.nx, g.ny) == (-150.0, 50.0, 8, 3)
    assert g.rect(0, 0) == (-150.0, 0.0, -100.0, 50.0)


def test_order_by_style_then_priority():
    s = [sq(0, 0, style="road", prio=1), sq(0, 0, style="land", prio=1), sq(0, 0, style="road", prio=9)]
    assert [(x.style, x.prio) for x in order(s)] == [("land", 1), ("road", 9), ("road", 1)]


def test_cell_bounds_and_style_counts():
    c = Cell(0, 0, [sq(1, 2), sq(10, 20, style="road")])
    assert c.bounds() == (1.0, 2.0, 12.0, 22.0)
    counts, points = c.style_counts()
    assert counts == [0, 0, 1, 0, 0, 1, 0] and points == [0, 0, 5, 0, 0, 5, 0]


def test_build_level_small_world():
    road = Mesh("r", np.array([[-10, 0, -20], [110, 0, -20], [110, 0, -30], [-10, 0, -30]], float),
                np.array([[0, 1, 2], [0, 2, 3]]))
    src = Sources([road], [], [quad(0, 0, 100, 50)], [], boxes([25, 40, 6, 6, 50, 0]), TF)
    g, cells = build_level(LV, src, (0.0, 0.0, 100.0, 50.0), log=lambda *_: None)
    assert (g.nx, g.ny) == (2, 1) and set(cells) == {(0, 0), (1, 0)}
    styles0 = [s.style for s in cells[(0, 0)].shapes]
    assert styles0[0] == "land" and "road" in styles0 and "block1" in styles0
    assert styles0 == sorted(styles0, key=["land", "water", "block0", "block1", "block2", "road", "metro"].index)


def _grid_cells(n_blocks_per_cell):
    g = VGrid(0.0, 100.0, 2, 2, 50.0)
    cells = {}
    for ix in range(2):
        for iy in range(2):
            x0, y1 = ix * 50.0, 100.0 - iy * 50.0
            cells[(ix, iy)] = Cell(ix, iy, [sq(x0 + 1 + k % 20 * 2, y1 - 3 - k // 20 * 2, 1.0, prio=float(k + 1))
                                            for k in range(n_blocks_per_cell)])
    return g, cells


def test_worst_view_counts_every_cell_a_view_can_touch():
    g, cells = _grid_cells(10)
    pts, shp, _ = worst_view(LV, g, cells)
    assert shp == 40 and pts == 200      # the 941 x 740 m worst view covers the whole 100 m world


def test_fit_level_passes_untouched_when_under_budget():
    g, cells = _grid_cells(10)
    lv, out, rep = fit_level(LV, g, cells, rebuild_roads=lambda l: {}, log=lambda *_: None,
                             point_budget=1000, shape_budget=100)
    assert lv == LV and rep["steps"] == [] and rep["shapes"] == 40


def test_fit_level_drops_smallest_blocks_first():
    g, cells = _grid_cells(10)       # block areas are 1 m^2 with prio 1..10
    lv, out, rep = fit_level(LV, g, cells, rebuild_roads=lambda l: {}, log=lambda *_: None,
                             point_budget=1000, shape_budget=10)
    assert rep["steps"][0].startswith("area") and rep["shapes"] <= 10
    assert all(s.prio >= lv.min_area for c in out.values() for s in c.shapes)


def test_fit_level_raises_when_nothing_helps():
    g = VGrid(0.0, 100.0, 1, 1, 50.0)
    road = Shape("road", np.column_stack((np.linspace(0, 40, 50), np.linspace(0, 40, 50) ** 1.5 / 10)), 40.0)
    cells = {(0, 0): Cell(0, 0, [road])}
    with pytest.raises(BudgetError):
        fit_level(LV, g, cells, rebuild_roads=lambda l: {(0, 0): [road]}, log=lambda *_: None,
                  point_budget=3, shape_budget=100)
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `cd tools/tiles && python3 -m pytest -q tests/test_vector_cells.py`
Expected: FAIL with `ModuleNotFoundError: No module named 'nmtiles.vector_budget'`.

- [ ] **Step 3: Implement**

`tools/tiles/nmtiles/vector_cells.py`:
```python
"""Assemble one vector level: grid, per-cell shapes in draw order, draw bounds (spec 2026-10-12 §4.3)."""
from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Callable

import numpy as np

from nmtiles.buildings import box_corners
from nmtiles.vector_config import STYLES, VLevel
from nmtiles.vector_extract import Rect, Shape, Sources, area_features, block_features, line_features


@dataclass(frozen=True)
class VGrid:
    ox: float        # world x of column 0's left edge
    otop: float      # world y of row 0's top edge (rows grow south)
    nx: int
    ny: int
    cell: float

    def rect(self, ix: int, iy: int) -> Rect:
        return (self.ox + ix * self.cell, self.otop - (iy + 1) * self.cell,
                self.ox + (ix + 1) * self.cell, self.otop - iy * self.cell)


def grid_for(level: VLevel, extent: Rect) -> VGrid:
    minx, miny, maxx, maxy = extent
    c = level.cell
    ox = math.floor(minx / c) * c
    otop = math.ceil(maxy / c) * c
    return VGrid(ox, otop, max(1, math.ceil((maxx - ox) / c)), max(1, math.ceil((otop - miny) / c)), c)


@dataclass
class Cell:
    ix: int
    iy: int
    shapes: list[Shape]

    def bounds(self) -> Rect:
        allp = np.vstack([s.pts for s in self.shapes])
        return (float(allp[:, 0].min()), float(allp[:, 1].min()), float(allp[:, 0].max()), float(allp[:, 1].max()))

    def style_counts(self) -> tuple[list[int], list[int]]:
        counts = [0] * len(STYLES)
        points = [0] * len(STYLES)
        for s in self.shapes:
            i = STYLES.index(s.style)
            counts[i] += 1
            points[i] += len(s.pts)
        return counts, points


def order(shapes: list[Shape]) -> list[Shape]:
    return sorted(shapes, key=lambda s: (STYLES.index(s.style), -s.prio))


def road_shapes(level: VLevel, src: Sources, grid: VGrid) -> dict[tuple[int, int], list[Shape]]:
    out = {}
    for iy in range(grid.ny):
        for ix in range(grid.nx):
            s = line_features(src.roads, src.tf, grid.rect(ix, iy), level, "road", level.road_min_width)
            if s:
                out[(ix, iy)] = s
    return out


def build_level(level: VLevel, src: Sources, extent: Rect,
                log: Callable[[str], None] = print) -> tuple[VGrid, dict[tuple[int, int], Cell]]:
    g = grid_for(level, extent)
    corners = box_corners(src.boxes) + np.array([src.tf.dx, src.tf.dy])
    centres = corners.mean(axis=1)
    heights = np.asarray(src.boxes.dz, float)
    cells: dict[tuple[int, int], Cell] = {}
    for iy in range(g.ny):
        for ix in range(g.nx):
            r = g.rect(ix, iy)
            shapes = (area_features(src, r, level)
                      + line_features(src.roads, src.tf, r, level, "road", level.road_min_width)
                      + line_features(src.metro, src.tf, r, level, "metro")
                      + block_features(corners, centres, heights, r, level))
            if shapes:
                cells[(ix, iy)] = Cell(ix, iy, order(shapes))
        if iy % 8 == 7 or iy == g.ny - 1:
            log(f"{level.name}: rows {iy + 1}/{g.ny}, cells {len(cells)}")
    return g, cells
```

`tools/tiles/nmtiles/vector_budget.py`:
```python
"""Worst-view budget check with automatic tightening (spec 2026-10-12 §4.5)."""
from __future__ import annotations

from dataclasses import replace
from typing import Callable

import numpy as np

from nmtiles.vector_cells import Cell, VGrid, order
from nmtiles.vector_config import BLOCK_STYLES, POINT_BUDGET, SHAPE_BUDGET, VIEW_UNITS, VLevel
from nmtiles.vector_geom import douglas_peucker

# Order fixed by the spec: smallest blocks, then road width, then tolerance (at most 2x).
STEPS = (("area", 2.0), ("area", 4.0), ("area", 8.0),
         ("road", 4.0), ("road", 8.0), ("road", 12.0),
         ("tol", 1.25), ("tol", 1.5625), ("tol", 2.0))


class BudgetError(RuntimeError):
    pass


def worst_view(level: VLevel, grid: VGrid, cells: dict) -> tuple[int, int, tuple[float, float]]:
    """Largest (points, shapes) any worst-case view at the level's max zoom-out can touch (half-cell steps)."""
    if not cells:
        return 0, 0, (0.0, 0.0)
    keys = list(cells)
    b = np.array([cells[k].bounds() for k in keys])
    pts = np.array([sum(len(s.pts) for s in cells[k].shapes) for k in keys])
    shp = np.array([len(cells[k].shapes) for k in keys])
    vw, vh = VIEW_UNITS[0] * level.max_mpp, VIEW_UNITS[1] * level.max_mpp
    step = grid.cell / 2.0
    best = (0, 0, (0.0, 0.0))
    best_load = -1.0
    for x0 in np.arange(b[:, 0].min() - vw, b[:, 2].max() + step, step):
        inx = (b[:, 2] >= x0) & (b[:, 0] <= x0 + vw)
        if not inx.any():
            continue
        for y1 in np.arange(b[:, 1].min(), b[:, 3].max() + vh + step, step):
            hit = inx & (b[:, 3] >= y1 - vh) & (b[:, 1] <= y1)
            p, s = int(pts[hit].sum()), int(shp[hit].sum())
            load = max(p / POINT_BUDGET, s / SHAPE_BUDGET)
            if load > best_load:
                best_load, best = load, (p, s, (float(x0), float(y1)))
    return best


def _drop_small_blocks(cells: dict, min_area: float) -> dict:
    out = {}
    for k, c in cells.items():
        keep = [s for s in c.shapes if s.style not in BLOCK_STYLES or s.prio >= min_area]
        if keep:
            out[k] = Cell(c.ix, c.iy, keep)
    return out


def _replace_roads(cells: dict, roads: dict) -> dict:
    out = {}
    for k in set(cells) | set(roads):
        base = [s for s in cells[k].shapes if s.style != "road"] if k in cells else []
        shapes = order(base + roads.get(k, []))
        if shapes:
            out[k] = Cell(k[0], k[1], shapes)
    return out


def _resimplify(cells: dict, tol: float) -> dict:
    out = {}
    for k, c in cells.items():
        shapes = []
        for s in c.shapes:
            pts = douglas_peucker(s.pts, tol)
            if len(pts) >= 2:
                shapes.append(type(s)(s.style, pts, s.prio))
        if shapes:
            out[k] = Cell(c.ix, c.iy, shapes)
    return out


def fit_level(level: VLevel, grid: VGrid, cells: dict, rebuild_roads: Callable[[VLevel], dict],
              log: Callable[[str], None] = print, point_budget: int = POINT_BUDGET,
              shape_budget: int = SHAPE_BUDGET) -> tuple[VLevel, dict, dict]:
    cur, steps = level, []

    def fits() -> tuple[bool, tuple]:
        global_view = worst_view(cur, grid, cells)
        return global_view[0] <= point_budget and global_view[1] <= shape_budget, global_view

    ok, view = fits()
    log(f"{level.name}: worst view {view[0]} points / {view[1]} shapes at {view[2]}")
    for kind, v in STEPS:
        if ok:
            break
        if kind == "area":
            cur = replace(cur, min_area=max(level.min_area, 10.0) * v)
            cells = _drop_small_blocks(cells, cur.min_area)
        elif kind == "road":
            cur = replace(cur, road_min_width=level.road_min_width + v)
            cells = _replace_roads(cells, rebuild_roads(cur))
        else:
            cur = replace(cur, tol=level.tol * v)
            cells = _resimplify(cells, cur.tol)
        steps.append(f"{kind} {v:g}")
        ok, view = fits()
        log(f"{level.name}: after {steps[-1]}: {view[0]} points / {view[1]} shapes")
    if not ok:
        raise BudgetError(f"{level.name}: worst view {view[0]} points / {view[1]} shapes at {view[2]} "
                          f"exceeds {point_budget}/{shape_budget} after {steps}")
    return cur, cells, {"level": level.name, "steps": steps, "points": view[0], "shapes": view[1], "at": view[2]}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `cd tools/tiles && python3 -m pytest -q tests/test_vector_cells.py`
Expected: 8 passed. Then run `python3 -m pytest -q`; all tests must pass.

- [ ] **Step 5: Commit**

```bash
git add tools/tiles/nmtiles/vector_cells.py tools/tiles/nmtiles/vector_budget.py tools/tiles/tests/test_vector_cells.py
git commit -m "Vector: level assembly, worst-view budget check with automatic tightening

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Shape resource writer and vector manifest

**Files:**
- Create:
  - `tools/tiles/templates/shapes.inkshapecollection.json`
  - `tools/tiles/nmtiles/vector_write.py`
  - `r6/scripts/NightMap/Generated/VectorManifest.reds` (the stub)
- Modify: `tools/tiles/nmtiles/manifest.py` (generic chunked array emitter, `emit_vector_manifest`, `emit_vector_stub`)
- Test: `tools/tiles/tests/test_vector_write.py`

**Interfaces:**
- Consumes:
  - From Task 3: `Cell`, `VGrid`.
  - From Task 1: `STYLES`.
  - Existing code: `nmtiles.pack.write_resource(ws, depot_path, js) -> Path` and `deserialize_all`.
- Produces:
  - `vector_write`:
    - `depot_path(level_idx, ix, iy) -> str`
    - `local_points(pts, bounds, unit) -> np.ndarray`
    - `collection_json(template, cell, unit) -> dict`
    - `write_level(ws, level_idx, level, grid, cells, template) -> dict` (a manifest level row)
  - `manifest`: `emit_vector_manifest(levels: list[dict], game_version: str) -> str` and `emit_vector_stub() -> str`.
  - redscript `NMVectorManifest`:
    - Scalars: `Available()`, `SourceGameVersion()`, `LevelCount()`, `StyleCount()`.
    - Per level, as `Float`: `LevelMinMpp(i)`, `LevelMaxMpp(i)`, `LevelUnit(i)`, `LevelCell(i)`, `LevelOriginX(i)`, `LevelOriginTop(i)`.
    - Per level, as `Int32`: `LevelNx(i)`, `LevelNy(i)`.
    - Per level, as arrays: `LevelCells(i) -> array<Int32>`, `LevelBounds(i) -> array<Float>` (4 per cell), `LevelCounts(i) -> array<Int32>` (7 per cell), `LevelPoints(i) -> array<Int32>` (7 per cell).

- [ ] **Step 1: Create the shape-collection template from the vanilla resource**

```bash
mkdir -p /tmp/nm_tpl/x /tmp/nm_tpl/j
WolvenKit.CLI extract ~/cyberpunk_symlink/archive/pc/content -r 'main_shapes\.inkshapecollection$' -o /tmp/nm_tpl/x
WolvenKit.CLI convert s /tmp/nm_tpl/x/base/gameplay/gui/common/main_shapes.inkshapecollection -o /tmp/nm_tpl/j
cd tools/tiles && python3 - <<'EOF'
import json
d = json.load(open('/tmp/nm_tpl/j/main_shapes.inkshapecollection.json'))
assert d["Data"]["RootChunk"]["$type"] == "inkShapeCollectionResource"
d["Data"]["RootChunk"]["presets"] = []
d["Header"].pop("ArchiveFileName", None)
open('templates/shapes.inkshapecollection.json', 'w').write(json.dumps(d, indent=1) + "\n")
EOF
```
Expected: `tools/tiles/templates/shapes.inkshapecollection.json` exists with `"presets": []`.

- [ ] **Step 2: Write the failing tests**

`tools/tiles/tests/test_vector_write.py`:
```python
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
    assert len(presets[0]["points"]) == 5 and len(presets[1]["points"]) == 2
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
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run: `cd tools/tiles && python3 -m pytest -q tests/test_vector_write.py`
Expected: FAIL with `ImportError: cannot import name 'emit_vector_manifest'`.

- [ ] **Step 4: Implement**

`tools/tiles/nmtiles/vector_write.py`:
```python
"""Per-cell inkShapeCollection JSON and manifest rows (spec 2026-10-12 §4.4)."""
from __future__ import annotations

import copy
from pathlib import Path

import numpy as np

from nmtiles.pack import write_resource
from nmtiles.vector_cells import Cell, VGrid
from nmtiles.vector_config import VLevel

MIN_EXTENT = 0.01      # widget size floor (units) for degenerate bounds


def depot_path(level_idx: int, ix: int, iy: int) -> str:
    return f"nightmap\\vec\\V{level_idx}\\c_{ix}_{iy}.inkshapecollection"


def local_points(pts: np.ndarray, bounds: tuple, unit: float) -> np.ndarray:
    """World metres -> level units relative to the draw-bounds corner (min x, max y); Y points down."""
    minx, _, _, maxy = bounds
    return np.column_stack(((pts[:, 0] - minx) / unit, (maxy - pts[:, 1]) / unit))


def collection_json(template: dict, cell: Cell, unit: float) -> dict:
    doc = copy.deepcopy(template)
    b = cell.bounds()
    doc["Data"]["RootChunk"]["presets"] = [
        {"$type": "inkShapePreset",
         "name": {"$type": "CName", "$storage": "string", "$value": f"s{i}"},
         "points": [{"$type": "Vector2", "X": round(float(x), 3), "Y": round(float(y), 3)}
                    for x, y in local_points(s.pts, b, unit)]}
        for i, s in enumerate(cell.shapes)]
    return doc


def write_level(ws: Path, level_idx: int, level: VLevel, grid: VGrid, cells: dict, template: dict) -> dict:
    u = level.min_mpp
    rows = []
    for (ix, iy), cell in sorted(cells.items(), key=lambda kv: (kv[0][1], kv[0][0])):
        write_resource(ws, depot_path(level_idx, ix, iy), collection_json(template, cell, u))
        minx, miny, maxx, maxy = cell.bounds()
        counts, points = cell.style_counts()
        rows.append({"key": iy * grid.nx + ix,
                     "bounds": ((minx - grid.ox) / u, (grid.otop - maxy) / u,
                                max((maxx - minx) / u, MIN_EXTENT), max((maxy - miny) / u, MIN_EXTENT)),
                     "counts": counts, "points": points})
    return {"min_mpp": level.min_mpp, "max_mpp": level.max_mpp, "unit": u, "cell": grid.cell,
            "ox": grid.ox, "otop": grid.otop, "nx": grid.nx, "ny": grid.ny, "cells": rows}
```

In `tools/tiles/nmtiles/manifest.py`, replace `_array_case` with a typed version and add the vector emitters. `emit_manifest` keeps calling `_array_case(i, idx)`, and the defaults keep its output unchanged.

```python
def _array_case(i: int, idx: list, typ: str = "Int32", fmt=str) -> str:
    """Case body building array<typ>; no literal exceeds MAX_LITERAL elements."""
    ch = _chunks(idx)
    if len(ch) == 1:
        return f"            case {i}: return [{', '.join(map(fmt, ch[0]))}];\n"
    pad = "                "
    body = f"            case {i}:\n{pad}let a: array<{typ}> = [{', '.join(map(fmt, ch[0]))}];\n"
    for n, c in enumerate(ch[1:], 1):
        body += (f"{pad}let c{n}: array<{typ}> = [{', '.join(map(fmt, c))}];\n"
                 f"{pad}for x in c{n} {{ ArrayPush(a, x); }}\n")
    return body + f"{pad}return a;\n"


def _array_func(name: str, typ: str, per_level: list[list], fmt=str) -> str:
    cases = "".join(_array_case(i, vals, typ, fmt) for i, vals in enumerate(per_level) if vals)
    return (f"    public static func {name}(i: Int32) -> array<{typ}> {{\n        switch i {{\n{cases}"
            f"            default: break;\n        }}\n        let empty: array<{typ}>;\n        return empty;\n    }}\n\n")


def _f3(v: float) -> str:
    return f"{float(v):.3f}"


VECTOR_STYLE_COUNT = 7


def emit_vector_manifest(levels: list[dict], game_version: str) -> str:
    out = ["// GENERATED by tools/tiles (nmtiles.manifest) - do not edit.\nmodule NightMap\n\n",
           "public abstract class NMVectorManifest {\n"]
    out.append(_scalar("Available", "Bool", "true" if levels else "false"))
    out.append(_scalar("SourceGameVersion", "String", f'"{game_version}"'))
    out.append(_scalar("LevelCount", "Int32", str(len(levels))))
    out.append(_scalar("StyleCount", "Int32", str(VECTOR_STYLE_COUNT)))
    for name, key in (("LevelMinMpp", "min_mpp"), ("LevelMaxMpp", "max_mpp"), ("LevelUnit", "unit"),
                      ("LevelCell", "cell"), ("LevelOriginX", "ox"), ("LevelOriginTop", "otop")):
        out.append(_switch(name, "Float", [_f3(l[key]) for l in levels], "0.0"))
    out.append(_switch("LevelNx", "Int32", [str(l["nx"]) for l in levels], "0"))
    out.append(_switch("LevelNy", "Int32", [str(l["ny"]) for l in levels], "0"))
    out.append(_array_func("LevelCells", "Int32", [[c["key"] for c in l["cells"]] for l in levels]))
    out.append(_array_func("LevelBounds", "Float", [[v for c in l["cells"] for v in c["bounds"]] for l in levels], _f3))
    out.append(_array_func("LevelCounts", "Int32", [[v for c in l["cells"] for v in c["counts"]] for l in levels]))
    out.append(_array_func("LevelPoints", "Int32", [[v for c in l["cells"] for v in c["points"]] for l in levels]))
    out.append("}\n")
    return "".join(out)


def emit_vector_stub() -> str:
    return emit_vector_manifest([], "none")
```

Write the stub into the repo so redscript can compile before the first real build:
```bash
cd tools/tiles && python3 -c "from nmtiles.manifest import emit_vector_stub; open('../../r6/scripts/NightMap/Generated/VectorManifest.reds','w').write(emit_vector_stub())"
```

- [ ] **Step 5: Run the tests and confirm they pass, and that the stub compiles**

Run: `cd tools/tiles && python3 -m pytest -q tests/test_vector_write.py tests/test_manifest.py`
Expected: all pass (the new tests plus the existing manifest tests; the slow test is skipped).

Run: `NIGHTMAP_SLOW=1 python3 -m pytest -q tests/test_vector_write.py::test_wolvenkit_roundtrip`
Expected: 1 passed.

Run: `cd ../.. && tools/check.sh`
Expected: `COMPILE OK`.

- [ ] **Step 6: Commit**

```bash
git add tools/tiles/templates/shapes.inkshapecollection.json tools/tiles/nmtiles/vector_write.py tools/tiles/nmtiles/manifest.py tools/tiles/tests/test_vector_write.py r6/scripts/NightMap/Generated/VectorManifest.reds
git commit -m "Vector: shape-collection writer, chunked NMVectorManifest emitter, stub manifest

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: SVG previews, build integration, real build

**Files:**
- Create: `tools/tiles/nmtiles/vector_preview.py`, `tools/tiles/nmtiles/vector_build.py`
- Modify:
  - `tools/tiles/nmtiles/build.py`: add a `--no-vector` flag, call `build_vector` before `deserialize_all`, and write `VectorManifest.reds`.
  - `.gitignore`, only if `tools/tiles/build/` is not already ignored.
- Regenerated: `r6/scripts/NightMap/Generated/VectorManifest.reds`
- Test: `tools/tiles/tests/test_vector_build.py`

**Interfaces:**
- Consumes: all earlier tasks.
- Produces:
  - `vector_preview.write_svg(path, cells: dict, rect: Rect, unit: float) -> Path`
  - `vector_build.build_vector(styled: dict[str, list[Mesh]], boxes, tf, extent, ws, out_dir, template, levels=LEVELS, log=print) -> list[dict]`. It returns the manifest level rows and writes:
    - `out_dir/vector_budget.json`;
    - `out_dir/vector_V{n}_downtown.svg` for every level;
    - `out_dir/vector_V{n}_full.svg` for V2–V4. The full map at V0/V1 would be hundreds of MB.

- [ ] **Step 1: Write the failing tests**

`tools/tiles/tests/test_vector_build.py`:
```python
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
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `cd tools/tiles && python3 -m pytest -q tests/test_vector_build.py`
Expected: FAIL with `ModuleNotFoundError: No module named 'nmtiles.vector_build'`.

- [ ] **Step 3: Implement**

`tools/tiles/nmtiles/vector_preview.py`:
```python
"""SVG previews of the packed vector geometry (spec 2026-10-12 §4.6), drawn as in-game at the level's design unit."""
from __future__ import annotations

from pathlib import Path

from nmtiles.vector_extract import Rect

BG = "#08121a"
# style -> (fill, fill opacity, stroke, stroke opacity, stroke width in screen units)
STYLE_SVG = {
    "land": ("#28c8ff", 0.05, "none", 0.0, 0.0),
    "water": ("#28c8ff", 0.13, "none", 0.0, 0.0),
    "block0": ("#7af0ff", 0.06, "#7af0ff", 0.45, 1.0),
    "block1": ("#7af0ff", 0.09, "#7af0ff", 0.45, 1.0),
    "block2": ("#7af0ff", 0.12, "#7af0ff", 0.45, 1.0),
    "road": ("none", 0.0, "#7af0ff", 0.85, 1.5),
    "metro": ("none", 0.0, "#ff4fd8", 0.80, 2.0),
}


def _hits(b: Rect, r: Rect) -> bool:
    return b[2] >= r[0] and b[0] <= r[2] and b[3] >= r[1] and b[1] <= r[3]


def write_svg(path: Path, cells: dict, rect: Rect, unit: float) -> Path:
    x0, y0, x1, y1 = rect
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{x0:g} {-y1:g} {x1 - x0:g} {y1 - y0:g}" '
           f'width="{min(4000, int((x1 - x0) / unit))}">',
           f'<rect x="{x0:g}" y="{-y1:g}" width="{x1 - x0:g}" height="{y1 - y0:g}" fill="{BG}"/>']
    for c in cells.values():
        if not _hits(c.bounds(), rect):
            continue
        for s in c.shapes:
            fill, fo, stroke, so, w = STYLE_SVG[s.style]
            d = "M" + " L".join(f"{x:.2f} {-y:.2f}" for x, y in s.pts)
            out.append(f'<path d="{d}" fill="{fill}" fill-opacity="{fo}" stroke="{stroke}" stroke-opacity="{so}" '
                       f'stroke-width="{w * unit:g}" stroke-linejoin="round" stroke-linecap="round"/>')
    out.append("</svg>\n")
    path.write_text("\n".join(out))
    return path
```

`tools/tiles/nmtiles/vector_build.py`:
```python
"""Run the whole vector pipeline: per-level extraction, budget fitting, resource JSON, previews (spec §4)."""
from __future__ import annotations

import json
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
                 log: Callable[[str], None] = print) -> list[dict]:
    src = Sources(roads=styled.get("road", []), metro=styled.get("metro", []), land=styled.get("land", []),
                  water=styled.get("water", []), boxes=boxes, tf=tf)
    rows, report = [], []
    for li, level in enumerate(levels):
        grid, cells = build_level(level, src, extent, log)
        used, cells, rep = fit_level(level, grid, cells, lambda lv: road_shapes(lv, src, grid), log)
        rows.append(write_level(ws, li, used, grid, cells, template))
        report.append({**rep, "cells": len(cells), "params": used.__dict__})
        cx, cy = DOWNTOWN
        write_svg(out_dir / f"vector_V{li}_downtown.svg", cells,
                  (cx - CROP[0] / 2, cy - CROP[1] / 2, cx + CROP[0] / 2, cy + CROP[1] / 2), used.min_mpp)
        if li >= 2:
            write_svg(out_dir / f"vector_V{li}_full.svg", cells, extent, used.min_mpp * 4)
        log(f"{level.name}: {len(cells)} cells, worst view {rep['points']} points / {rep['shapes']} shapes, steps {rep['steps']}")
    (out_dir / "vector_budget.json").write_text(json.dumps(report, indent=2))
    return rows
```

In `tools/tiles/nmtiles/build.py`:
- Add imports: `from nmtiles.manifest import emit_vector_manifest, emit_vector_stub` and `from nmtiles.vector_build import build_vector`.
- Add the argument `ap.add_argument("--no-vector", action="store_true", help="skip the vector layer (writes the stub manifest)")`.
- Insert directly before `deserialize_all(ws)`:
```python
    if args.no_vector:
        vector_src = emit_vector_stub()
    else:
        shape_tpl = json.loads((TPL / "shapes.inkshapecollection.json").read_text())
        vector_rows = build_vector(styled, boxes, tf, bounds, ws, out, shape_tpl)
        vector_src = emit_vector_manifest(vector_rows, args.game_version)
```
- After the line that writes `TileManifest.reds`, add:
```python
    vmanifest = manifest.parent / "VectorManifest.reds"
    vmanifest.write_text(vector_src)
    print(f"vector manifest {vmanifest}")
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `cd tools/tiles && python3 -m pytest -q tests/test_vector_build.py && python3 -m pytest -q`
Expected: all pass.

- [ ] **Step 5: Run the real build**

Run it in the background; it takes about 30–60 minutes. Tile encoding is cached, and the vector extraction dominates.
```bash
cd tools/tiles && python3 -m nmtiles.build --game ~/cyberpunk_symlink --skip-export > build/vector_build.log 2>&1
```
Expected at the end of the log:
- one line per level, `V{n}: … cells, worst view P points / S shapes, steps [...]`, with P ≤ 27000 and S ≤ 360;
- `archive … MB`, under 60 MB;
- `vector manifest …`.

On a `BudgetError`:
1. Read the reported worst-view location.
2. Raise that level's starting parameters in `vector_config.LEVELS`: `min_area` first, then `road_min_width`.
3. Rebuild, and list the change in your report.

Never raise the budgets.

Then:
- **Previews.** Open `build/vector_V0_downtown.svg` and `build/vector_V2_full.svg`, render them to PNG with a headless browser or `rsvg-convert` if present, and look at them. Describe in your report whether road edges, blocks, water and metro look right and whether there are visible seams.
- **Compile.** Run `cd ../.. && tools/check.sh`. Expected: `COMPILE OK`, with the large generated manifest compiling.

- [ ] **Step 6: Commit**

```bash
git add tools/tiles/nmtiles/vector_preview.py tools/tiles/nmtiles/vector_build.py tools/tiles/nmtiles/build.py tools/tiles/tests/test_vector_build.py r6/scripts/NightMap/Generated/VectorManifest.reds
git commit -m "Vector: SVG previews, build integration, generated vector manifest

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
If `tools/tiles/nmtiles/vector_config.py` changed during budget tuning, include it in the commit.

---

### Task 6: Runtime core (theme, setting, level data, pure functions, self-test)

**Files:**
- Create: `r6/scripts/NightMap/Render/VectorLevel.reds`, `r6/scripts/NightMap/Render/VectorLayer.reds`. This task adds the static functions and data only; Task 7 adds the runtime methods.
- Modify:
  - `r6/scripts/NightMap/Core/Theme.reds` (vector constants)
  - `r6/scripts/NightMap/Core/Settings.reds` (`vectorMap`)
  - `r6/scripts/NightMap/Debug/SelfTest.reds` (`VectorCases`)

**Interfaces:**
- Consumes: `NMVectorManifest` (Task 4), `NMRect` (`Core/Math.reds`), `NMTheme`.
- Produces:
  - `NMTheme`: `VecStyleCount()`, `VecPoolSize()`, `VecPointBudget()`, `VecShapeBudget()`, `VecHysteresis()`, `VecThicknessStep()`, `VecFailMs()`, `VecIsBlock(style)`, `VecVariant(style)`, `VecColor(style)`, `VecFillOpacity(style)`, `VecBorderOpacity(style)`, `VecLineWidth(style, level)`.
  - `NightMapSettings.vectorMap: Bool` (default true).
  - `NMVecLevel`:
    - Fields: `index, minMpp, maxMpp, unit, ox, otop, nx, ny, cell, keys, bounds, counts, points, lookup, reach, exists`.
    - Methods: `FromManifest(i)`, `BuildLookup()`, `CellCount()`, `Path(c) -> String`, `Hits(c, r) -> Bool`, `FirstPreset(c, style) -> Int32`.
  - `NMVectorLayer` statics:
    - `PickLevel(mins, maxs, current, mpp, h) -> Int32`
    - `VisibleCells(lv, r) -> array<Int32>` (centre-out)
    - `PlanGroups(lv, cells, maxPoints, maxShapes) -> array<Int32>` (group = `cell * 8 + style`)
    - `LineWidthFor(style, level, scale) -> Float`
    - `NeedsThickness(last, now, step) -> Bool`

- [ ] **Step 1: Add the failing self-test cases**

In `Debug/SelfTest.reds`, add `this.VectorCases();` to `Run()` after `this.VersionCases();`. Add these methods to `NMSelfTest`:
```swift
    private func VectorCaseLevel() -> ref<NMVecLevel> {
        let lv = new NMVecLevel();
        lv.index = 0;
        lv.minMpp = 0.5;
        lv.maxMpp = 0.8;
        lv.unit = 1.0;
        lv.ox = 0.0;
        lv.otop = 300.0;
        lv.nx = 3;
        lv.ny = 3;
        lv.cell = 100.0;
        let counts: array<Int32> = [1, 0, 3, 0, 0, 2, 0];
        let pts: array<Int32> = [5, 0, 30, 0, 0, 40, 0];
        let c = 0;
        while c < 9 {
            ArrayPush(lv.keys, c);
            ArrayPush(lv.bounds, Cast<Float>(c % 3) * 100.0);
            ArrayPush(lv.bounds, Cast<Float>(c / 3) * 100.0);
            ArrayPush(lv.bounds, 100.0);
            ArrayPush(lv.bounds, 100.0);
            for v in counts { ArrayPush(lv.counts, v); }
            for v in pts { ArrayPush(lv.points, v); }
            c += 1;
        }
        lv.BuildLookup();
        return lv;
    }

    private func VectorCases() {
        let mins: array<Float> = [0.5, 0.8, 1.6];
        let maxs: array<Float> = [0.8, 1.6, 4.0];
        this.Check("vector.pick_initial", NMVectorLayer.PickLevel(mins, maxs, -1, 0.6, 0.08) == 0
            && NMVectorLayer.PickLevel(mins, maxs, -1, 1.0, 0.08) == 1, "");
        this.Check("vector.pick_hysteresis_holds", NMVectorLayer.PickLevel(mins, maxs, 0, 0.85, 0.08) == 0, "");
        this.Check("vector.pick_hysteresis_switches", NMVectorLayer.PickLevel(mins, maxs, 0, 0.9, 0.08) == 1, "");
        this.Check("vector.pick_back_down_holds", NMVectorLayer.PickLevel(mins, maxs, 1, 0.76, 0.08) == 1, "");
        // Hovering around the 0.8 boundary from level 0: 0.79, 0.83, 0.79, 0.85 must never leave level 0.
        let cur = 0;
        let hover: array<Float> = [0.79, 0.83, 0.79, 0.85];
        let flips = 0;
        for m in hover {
            let next = NMVectorLayer.PickLevel(mins, maxs, cur, m, 0.08);
            if next != cur { flips += 1; }
            cur = next;
        }
        this.Check("vector.pick_no_flicker", flips == 0, ToString(flips));
        this.Check("vector.pick_beyond_last", NMVectorLayer.PickLevel(mins, maxs, -1, 50.0, 0.08) == 2, "");
        let none: array<Float>;
        this.Check("vector.pick_no_levels", NMVectorLayer.PickLevel(none, none, -1, 1.0, 0.08) == -1, "");

        let lv = this.VectorCaseLevel();
        let c1 = NMVectorLayer.VisibleCells(lv, NMRect.Create(120.0, 120.0, 180.0, 180.0));
        this.Check("vector.visible_centre_only", ArraySize(c1) == 1 && c1[0] == 4, ToString(ArraySize(c1)));
        let c2 = NMVectorLayer.VisibleCells(lv, NMRect.Create(90.0, 90.0, 210.0, 210.0));
        this.Check("vector.visible_centre_first", ArraySize(c2) == 9 && c2[0] == 4, ToString(ArraySize(c2)));
        let c3 = NMVectorLayer.VisibleCells(lv, NMRect.Create(1000.0, 1000.0, 1200.0, 1200.0));
        this.Check("vector.visible_outside_empty", ArraySize(c3) == 0, ToString(ArraySize(c3)));
        this.Check("vector.path", Equals(lv.Path(5), "nightmap\\vec\\V0\\c_2_1.inkshapecollection"), lv.Path(5));
        this.Check("vector.first_preset", lv.FirstPreset(4, 0) == 0 && lv.FirstPreset(4, 2) == 1 && lv.FirstPreset(4, 5) == 4, "");

        let three: array<Int32> = [4, 0, 1];
        let all = NMVectorLayer.PlanGroups(lv, three, 100000, 100000);
        this.Check("vector.plan_all", ArraySize(all) == 9 && all[0] == 4 * 8 + 0 && all[6] == 4 * 8 + 2, ToString(ArraySize(all)));
        let pts = NMVectorLayer.PlanGroups(lv, three, 170, 100000);       // 3 x (5 + 40) = 135, +30 for one block group
        this.Check("vector.plan_points_blocks_last", ArraySize(pts) == 7 && ArrayContains(pts, 4 * 8 + 2) && !ArrayContains(pts, 0 * 8 + 2), ToString(ArraySize(pts)));
        let shp = NMVectorLayer.PlanGroups(lv, three, 100000, 7);         // land 1 + road 2 per cell
        this.Check("vector.plan_shapes", ArraySize(shp) == 5, ToString(ArraySize(shp)));

        this.Check("vector.thickness_compensates", this.Near(NMVectorLayer.LineWidthFor(5, 0, 2.0), 0.75, 0.001), this.F(NMVectorLayer.LineWidthFor(5, 0, 2.0)));
        this.Check("vector.thickness_step", !NMVectorLayer.NeedsThickness(1.0, 1.04, 0.05) && NMVectorLayer.NeedsThickness(1.0, 1.06, 0.05)
            && NMVectorLayer.NeedsThickness(0.0, 1.0, 0.05), "");

        if NMVectorManifest.Available() {
            let k: array<Int32> = NMVectorManifest.LevelCells(0);
            let b: array<Float> = NMVectorManifest.LevelBounds(0);
            let n: array<Int32> = NMVectorManifest.LevelCounts(0);
            this.Check("vector.manifest_arrays", ArraySize(k) > 0 && ArraySize(b) == 4 * ArraySize(k)
                && ArraySize(n) == NMTheme.VecStyleCount() * ArraySize(k), ToString(ArraySize(k)));
            this.Check("vector.manifest_styles", NMVectorManifest.StyleCount() == NMTheme.VecStyleCount(), "");
        }
    }
```

- [ ] **Step 2: Run the compile check and confirm it fails**

Run: `tools/check.sh`
Expected: `COMPILE FAILED`, with unresolved `NMVecLevel` and `NMVectorLayer`. A failure takes about 90 s.

- [ ] **Step 3: Implement**

`Core/Theme.reds`: add these static functions inside `NMTheme`, after `PlayerRotationSign`:
```swift
    // Vector layer (sub-project 1b). Style ids match tools/tiles nmtiles.vector_config.STYLES:
    // 0 land, 1 water, 2 block0, 3 block1, 4 block2, 5 road, 6 metro.
    public static func VecStyleCount() -> Int32 { return 7; }
    public static func VecPoolSize() -> Int32 { return 800; }
    public static func VecPointBudget() -> Int32 { return 30000; }
    public static func VecShapeBudget() -> Int32 { return 400; }
    public static func VecHysteresis() -> Float { return 0.08; }
    public static func VecThicknessStep() -> Float { return 0.05; }
    public static func VecFailMs() -> Float { return 3000.0; }
    public static func VecIsBlock(style: Int32) -> Bool { return style >= 2 && style <= 4; }
    public static func VecVariant(style: Int32) -> inkEShapeVariant {
        if style <= 1 { return inkEShapeVariant.Fill; }
        if style <= 4 { return inkEShapeVariant.FillAndBorder; }
        return inkEShapeVariant.Border;
    }
    public static func VecColor(style: Int32) -> HDRColor { return style == 6 ? NMTheme.Pink() : NMTheme.Cyan(); }
    public static func VecFillOpacity(style: Int32) -> Float {
        if style == 0 { return 0.05; }
        if style == 1 { return 0.13; }
        if style == 2 { return 0.06; }
        if style == 3 { return 0.09; }
        if style == 4 { return 0.12; }
        return 0.0;
    }
    public static func VecBorderOpacity(style: Int32) -> Float {
        if NMTheme.VecIsBlock(style) { return 0.45; }
        if style == 5 { return 0.85; }
        if style == 6 { return 0.80; }
        return 0.0;
    }
    // Target stroke width in map (screen) units.
    public static func VecLineWidth(style: Int32, level: Int32) -> Float {
        if style == 6 { return 2.0; }
        if style == 5 { return level <= 2 ? 1.5 : 1.2; }
        if NMTheme.VecIsBlock(style) { return 1.0; }
        return 0.0;
    }
```

`Core/Settings.reds`: add this field after `panelOpacity`. Use the same `ModSettings.category` and `category.order` values as `panelOpacity`; read them from the file.
```swift
    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "<same as panelOpacity>")
    @runtimeProperty("ModSettings.category.order", "<same as panelOpacity>")
    @runtimeProperty("ModSettings.displayName", "Vector map")
    @runtimeProperty("ModSettings.description", "Draws the map as smooth vector shapes. Off = the older raster tiles.")
    public let vectorMap: Bool = true;
```

`Render/VectorLevel.reds`:
```swift
module NightMap

// One vector LOD level, copied from NMVectorManifest once per open. Manifest arrays are bound to locals
// first: ArraySize on a function-call temporary reads 0 in-game.
public class NMVecLevel {
    public let index: Int32;
    public let minMpp: Float;
    public let maxMpp: Float;
    public let unit: Float;
    public let ox: Float;
    public let otop: Float;
    public let nx: Int32;
    public let ny: Int32;
    public let cell: Float;
    public let keys: array<Int32>;      // cell key = iy * nx + ix
    public let bounds: array<Float>;    // 4 per cell: x, y, w, h in level units from (ox, otop), Y down
    public let counts: array<Int32>;    // NMTheme.VecStyleCount() per cell
    public let points: array<Int32>;
    public let lookup: array<Int32>;    // key -> cell index, -1 if empty
    public let reach: Int32;            // cells a draw bound can overhang its own cell
    public let exists: array<Int32>;    // per cell: -1 unknown, 0 resource missing, 1 present

    public static func FromManifest(i: Int32) -> ref<NMVecLevel> {
        let l = new NMVecLevel();
        l.index = i;
        l.minMpp = NMVectorManifest.LevelMinMpp(i);
        l.maxMpp = NMVectorManifest.LevelMaxMpp(i);
        l.unit = NMVectorManifest.LevelUnit(i);
        l.ox = NMVectorManifest.LevelOriginX(i);
        l.otop = NMVectorManifest.LevelOriginTop(i);
        l.nx = NMVectorManifest.LevelNx(i);
        l.ny = NMVectorManifest.LevelNy(i);
        l.cell = NMVectorManifest.LevelCell(i);
        let k: array<Int32> = NMVectorManifest.LevelCells(i);
        let b: array<Float> = NMVectorManifest.LevelBounds(i);
        let c: array<Int32> = NMVectorManifest.LevelCounts(i);
        let p: array<Int32> = NMVectorManifest.LevelPoints(i);
        l.keys = k;
        l.bounds = b;
        l.counts = c;
        l.points = p;
        l.BuildLookup();
        return l;
    }

    public func BuildLookup() {
        ArrayClear(this.lookup);
        ArrayClear(this.exists);
        let n = this.nx * this.ny;
        let i = 0;
        while i < n {
            ArrayPush(this.lookup, -1);
            i += 1;
        }
        this.reach = 0;
        let cu = this.cell / this.unit;
        let c = 0;
        while c < ArraySize(this.keys) {
            let key = this.keys[c];
            this.lookup[key] = c;
            ArrayPush(this.exists, -1);
            let ix = Cast<Float>(key % this.nx);
            let iy = Cast<Float>(key / this.nx);
            let over = MaxF(MaxF(ix * cu - this.bounds[4 * c], this.bounds[4 * c] + this.bounds[4 * c + 2] - (ix + 1.0) * cu),
                MaxF(iy * cu - this.bounds[4 * c + 1], this.bounds[4 * c + 1] + this.bounds[4 * c + 3] - (iy + 1.0) * cu));
            this.reach = Max(this.reach, CeilF(MaxF(over, 0.0) / cu));
            c += 1;
        }
    }

    public func CellCount() -> Int32 {
        return ArraySize(this.keys);
    }

    public func Path(c: Int32) -> String {
        let key = this.keys[c];
        return "nightmap\\vec\\V" + ToString(this.index) + "\\c_" + ToString(key % this.nx) + "_" + ToString(key / this.nx) + ".inkshapecollection";
    }

    // Does cell c's draw bounds intersect world rect r?
    public func Hits(c: Int32, r: ref<NMRect>) -> Bool {
        let x0 = this.ox + this.bounds[4 * c] * this.unit;
        let top = this.otop - this.bounds[4 * c + 1] * this.unit;
        let x1 = x0 + this.bounds[4 * c + 2] * this.unit;
        let bottom = top - this.bounds[4 * c + 3] * this.unit;
        return x1 >= r.minX && x0 <= r.maxX && top >= r.minY && bottom <= r.maxY;
    }

    // Index of the first preset of a style in cell c (presets are written in style order).
    public func FirstPreset(c: Int32, style: Int32) -> Int32 {
        let n = NMTheme.VecStyleCount();
        let first = 0;
        let s = 0;
        while s < style {
            first += this.counts[n * c + s];
            s += 1;
        }
        return first;
    }
}
```

`Render/VectorLayer.reds` (static part; Task 7 adds the instance part):
```swift
module NightMap

// Vector map layer (spec docs/superpowers/specs/2026-10-12-nightmap-vector-layer-design.md §5).
public class NMVectorLayer {
    // The current level is kept while mpp stays inside its range widened by h; otherwise the first level whose
    // max covers mpp (the last one beyond the range). -1 without levels.
    public static func PickLevel(mins: array<Float>, maxs: array<Float>, current: Int32, mpp: Float, h: Float) -> Int32 {
        let n = ArraySize(mins);
        if n == 0 {
            return -1;
        }
        if current >= 0 && current < n && mpp >= mins[current] * (1.0 - h) && mpp <= maxs[current] * (1.0 + h) {
            return current;
        }
        let i = 0;
        while i < n {
            if mpp <= maxs[i] {
                return i;
            }
            i += 1;
        }
        return n - 1;
    }

    // Cells whose draw bounds intersect r, nearest centre first.
    public static func VisibleCells(lv: ref<NMVecLevel>, r: ref<NMRect>) -> array<Int32> {
        let out: array<Int32>;
        let dist: array<Float>;
        let ix0 = Max(FloorF((r.minX - lv.ox) / lv.cell) - lv.reach, 0);
        let ix1 = Min(FloorF((r.maxX - lv.ox) / lv.cell) + lv.reach, lv.nx - 1);
        let iy0 = Max(FloorF((lv.otop - r.maxY) / lv.cell) - lv.reach, 0);
        let iy1 = Min(FloorF((lv.otop - r.minY) / lv.cell) + lv.reach, lv.ny - 1);
        let cx = (r.minX + r.maxX) * 0.5;
        let cy = (r.minY + r.maxY) * 0.5;
        let iy = iy0;
        while iy <= iy1 {
            let ix = ix0;
            while ix <= ix1 {
                let c = lv.lookup[iy * lv.nx + ix];
                if c >= 0 && lv.Hits(c, r) {
                    let dx = lv.ox + (Cast<Float>(ix) + 0.5) * lv.cell - cx;
                    let dy = lv.otop - (Cast<Float>(iy) + 0.5) * lv.cell - cy;
                    let d = dx * dx + dy * dy;
                    let j = ArraySize(out);
                    ArrayPush(out, c);
                    ArrayPush(dist, d);
                    while j > 0 && dist[j - 1] > d {
                        out[j] = out[j - 1];
                        dist[j] = dist[j - 1];
                        j -= 1;
                    }
                    out[j] = c;
                    dist[j] = d;
                }
                ix += 1;
            }
            iy += 1;
        }
        return out;
    }

    // Groups (cell * 8 + style) to attach. Pass 1: land, water, roads, metro; pass 2: blocks. A group is skipped
    // when it would push the totals past the point or shape budget.
    public static func PlanGroups(lv: ref<NMVecLevel>, cells: array<Int32>, maxPoints: Int32, maxShapes: Int32) -> array<Int32> {
        let out: array<Int32>;
        let n = NMTheme.VecStyleCount();
        let pts = 0;
        let shp = 0;
        let pass = 0;
        while pass < 2 {
            for c in cells {
                let s = 0;
                while s < n {
                    let block = NMTheme.VecIsBlock(s);
                    if (pass == 0 && !block) || (pass == 1 && block) {
                        let gc = lv.counts[n * c + s];
                        let gp = lv.points[n * c + s];
                        if gc > 0 && pts + gp <= maxPoints && shp + gc <= maxShapes {
                            pts += gp;
                            shp += gc;
                            ArrayPush(out, c * 8 + s);
                        }
                    }
                    s += 1;
                }
            }
            pass += 1;
        }
        return out;
    }

    public static func LineWidthFor(style: Int32, level: Int32, scale: Float) -> Float {
        let w = NMTheme.VecLineWidth(style, level);
        return scale > 0.0 ? w / scale : w;
    }

    public static func NeedsThickness(last: Float, now: Float, step: Float) -> Bool {
        if last <= 0.0 {
            return true;
        }
        return AbsF(now / last - 1.0) > step;
    }
}
```

- [ ] **Step 4: Run the compile check and confirm it passes**

Run: `tools/check.sh`
Expected: `COMPILE OK`.

Adjust the code minimally if scc rejects a construct, for example `CeilF`'s return type or `AbsF`. Keep the names and behaviour, and list every adjustment in your report. The self-tests run in-game at Task 9.

- [ ] **Step 5: Commit**

```bash
git add r6/scripts/NightMap/Core/Theme.reds r6/scripts/NightMap/Core/Settings.reds r6/scripts/NightMap/Render/VectorLevel.reds r6/scripts/NightMap/Render/VectorLayer.reds r6/scripts/NightMap/Debug/SelfTest.reds
git commit -m "Vector runtime core: theme styles, Vector map setting, level data, pick/visible/plan functions, self-tests

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Runtime layer and system integration

**Files:**
- Modify:
  - `r6/scripts/NightMap/Render/VectorLayer.reds`: add the instance state and the `Create`, `Update`, `Destroy` and helper methods.
  - `r6/scripts/NightMap/Core/NightMapSystem.reds`: add the `vector` and `vectorFailed` fields, `UseVector`, `MaxMppFor`, `FallBackToRaster`, and the changes to `Open`, `OnOpened`, `OnClosing`, `UpdateModules` and `UpdateWarning`.
  - `r6/scripts/NightMap/Debug/SelfTest.reds`: add `vector.raster_max_mpp` and `vector.vector_max_mpp`.

**Interfaces:**
- Consumes: everything from Task 6, plus `NMCamera` (`mpp`, `revision`, `maxMpp`, `VisibleRect`, `WorldToMap`, `SetMpp`), `NMTileLayer` and `NMLog`.
- Produces:
  - `NMVectorLayer.Create(parent: ref<inkCanvas>) -> ref<NMVectorLayer>`
  - `.Update(cam: ref<NMCamera>, dtMs: Float)`
  - `.Destroy()`
  - fields `available: Bool`, `failed: Bool`, `current: Int32`
  - `NightMapSystem.MaxMppFor(useVector: Bool) -> Float`

- [ ] **Step 1: Add the failing self-test cases**

In `VectorCases()` in `Debug/SelfTest.reds`, append:
```swift
        this.Check("vector.raster_max_mpp", NightMapSystem.MaxMppFor(false) <= 16.001, this.F(NightMapSystem.MaxMppFor(false)));
        if NMVectorManifest.Available() {
            this.Check("vector.vector_max_mpp", NightMapSystem.MaxMppFor(true) > 16.0, this.F(NightMapSystem.MaxMppFor(true)));
        }
```

- [ ] **Step 2: Run the compile check and confirm it fails**

Run: `tools/check.sh`
Expected: `COMPILE FAILED` (`MaxMppFor` is not defined).

- [ ] **Step 3: Implement the layer instance**

Add the following to `NMVectorLayer` in `Render/VectorLayer.reds`, keeping the static functions from Task 6:
```swift
    public let available: Bool;
    public let failed: Bool;
    public let current: Int32;
    private let levels: array<ref<NMVecLevel>>;
    private let canvases: array<ref<inkCanvas>>;
    private let mins: array<Float>;
    private let maxs: array<Float>;
    private let pool: array<ref<inkShape>>;
    private let used: array<ref<inkShape>>;
    private let usedLevel: array<Int32>;
    private let usedGroup: array<Int32>;
    private let groups: array<Int32>;
    private let lastCells: array<Int32>;
    private let previous: Int32;
    private let releaseIn: Int32;
    private let lastRev: Int32;
    private let lastScale: Float;
    private let wanted: Int32;
    private let missing: Int32;
    private let missingMs: Float;
    private let warnedBudget: Bool;
    private let warnedPool: Bool;
    private let warnedMissing: Bool;

    public static func Create(parent: ref<inkCanvas>) -> ref<NMVectorLayer> {
        let v = new NMVectorLayer();
        v.current = -1;
        v.previous = -1;
        v.lastRev = -1;
        v.available = NMVectorManifest.Available() && NMVectorManifest.LevelCount() > 0;
        if !v.available {
            return v;
        }
        let i = 0;
        while i < NMVectorManifest.LevelCount() {
            let l = NMVecLevel.FromManifest(i);
            ArrayPush(v.levels, l);
            ArrayPush(v.mins, l.minMpp);
            ArrayPush(v.maxs, l.maxMpp);
            let c = new inkCanvas();
            c.SetAnchor(inkEAnchor.TopLeft);
            c.SetRenderTransformPivot(new Vector2(0.0, 0.0));
            c.SetInteractive(false);
            c.Reparent(parent);
            ArrayPush(v.canvases, c);
            i += 1;
        }
        let p = 0;
        while p < NMTheme.VecPoolSize() {
            let s = new inkShape();
            s.SetAnchor(inkEAnchor.TopLeft);
            s.SetInteractive(false);
            s.SetEndCapStyle(inkEEndCapStyle.ROUND);
            s.SetJointStyle(inkEJointStyle.ROUND);
            ArrayPush(v.pool, s);
            p += 1;
        }
        return v;
    }

    public func Update(cam: ref<NMCamera>, dtMs: Float) {
        if !this.available || this.failed {
            return;
        }
        let lv = NMVectorLayer.PickLevel(this.mins, this.maxs, this.current, cam.mpp, NMTheme.VecHysteresis());
        if lv != this.current {
            if this.previous >= 0 {
                this.DetachLevel(this.previous);    // one transition at a time: finish the older one
            }
            this.previous = this.current;
            this.current = lv;
            this.releaseIn = 2;
            ArrayClear(this.groups);
            ArrayClear(this.lastCells);
            this.lastRev = -1;
            this.lastScale = 0.0;
        }
        this.Place(this.current, cam);
        if this.previous >= 0 {
            this.Place(this.previous, cam);
        }
        if cam.revision != this.lastRev {
            this.lastRev = cam.revision;
            this.Sync(cam);
        }
        if this.previous >= 0 {
            this.releaseIn -= 1;
            if this.releaseIn <= 0 {
                this.DetachLevel(this.previous);
                this.previous = -1;
            }
        }
        let scale = this.levels[this.current].unit / cam.mpp;
        if NMVectorLayer.NeedsThickness(this.lastScale, scale, NMTheme.VecThicknessStep()) {
            this.lastScale = scale;
            this.Restroke(scale);
        }
        this.WatchMissing(dtMs);
    }

    public func Destroy() {
        let i = ArraySize(this.used) - 1;
        while i >= 0 {
            this.DetachAt(i);
            i -= 1;
        }
        for c in this.canvases {
            let parent = c.GetParentWidget() as inkCompoundWidget;
            if IsDefined(parent) {
                parent.RemoveChild(c);
            }
        }
        ArrayClear(this.canvases);
        ArrayClear(this.pool);
    }

    private func Place(l: Int32, cam: ref<NMCamera>) {
        let lv = this.levels[l];
        let s = lv.unit / cam.mpp;
        let c = this.canvases[l];
        c.SetScale(new Vector2(s, s));
        c.SetTranslation(cam.WorldToMap(lv.ox, lv.otop));
    }

    private func SameCells(a: array<Int32>, b: array<Int32>) -> Bool {
        if ArraySize(a) != ArraySize(b) {
            return false;
        }
        let i = 0;
        while i < ArraySize(a) {
            if a[i] != b[i] {
                return false;
            }
            i += 1;
        }
        return true;
    }

    private func Sync(cam: ref<NMCamera>) {
        let lv = this.levels[this.current];
        let cells = NMVectorLayer.VisibleCells(lv, cam.VisibleRect(0.0));
        if this.SameCells(cells, this.lastCells) {
            return;
        }
        this.lastCells = cells;
        this.wanted = ArraySize(cells);
        this.missing = 0;
        for c in cells {
            if lv.exists[c] < 0 {
                lv.exists[c] = GameInstance.GetResourceDepot().ResourceExists(ResRef.FromString(lv.Path(c))) ? 1 : 0;
            }
            if lv.exists[c] == 0 {
                this.missing += 1;
            }
        }
        if this.missing > 0 && !this.warnedMissing {
            this.warnedMissing = true;
            NMLog.Error("vector: " + ToString(this.missing) + " visible cells have no shape resource (archive stale or missing?)");
        }
        let plan = NMVectorLayer.PlanGroups(lv, cells, NMTheme.VecPointBudget(), NMTheme.VecShapeBudget());
        let full = NMVectorLayer.PlanGroups(lv, cells, 2147483647, 2147483647);
        if ArraySize(plan) < ArraySize(full) && !this.warnedBudget {
            this.warnedBudget = true;
            NMLog.Info("vector: view over budget, skipped " + ToString(ArraySize(full) - ArraySize(plan)) + " shape groups");
        }
        let i = ArraySize(this.used) - 1;
        while i >= 0 {
            if this.usedLevel[i] == this.current && !ArrayContains(plan, this.usedGroup[i]) {
                this.DetachAt(i);
            }
            i -= 1;
        }
        let kept: array<Int32>;
        for g in this.groups {
            if ArrayContains(plan, g) {
                ArrayPush(kept, g);
            }
        }
        this.groups = kept;
        let scale = lv.unit / cam.mpp;
        for g in plan {
            if !ArrayContains(this.groups, g) && lv.exists[g / 8] == 1 {
                if this.AttachGroup(lv, g / 8, g % 8, scale) {
                    ArrayPush(this.groups, g);
                }
            }
        }
    }

    private func AttachGroup(lv: ref<NMVecLevel>, cell: Int32, style: Int32, scale: Float) -> Bool {
        let n = lv.counts[NMTheme.VecStyleCount() * cell + style];
        let path = ResRef.FromString(lv.Path(cell));
        let first = lv.FirstPreset(cell, style);
        let color = NMTheme.VecColor(style);
        let pos = new Vector2(lv.bounds[4 * cell], lv.bounds[4 * cell + 1]);
        let size = new Vector2(MaxF(lv.bounds[4 * cell + 2], 0.01), MaxF(lv.bounds[4 * cell + 3], 0.01));
        let k = 0;
        while k < n {
            if ArraySize(this.pool) == 0 {
                if !this.warnedPool {
                    this.warnedPool = true;
                    NMLog.Error("vector: widget pool exhausted (" + ToString(NMTheme.VecPoolSize()) + ")");
                }
                return false;
            }
            let s = ArrayPop(this.pool);
            s.SetResource(path);
            s.SetShape(StringToName("s" + ToString(first + k)));
            s.SetVariant(NMTheme.VecVariant(style));
            s.SetTintColor(color);
            s.SetFillOpacity(NMTheme.VecFillOpacity(style));
            s.SetBorderColor(color);
            s.SetBorderOpacity(NMTheme.VecBorderOpacity(style));
            s.SetLineThickness(NMVectorLayer.LineWidthFor(style, lv.index, scale));
            s.SetTranslation(pos);
            s.SetSize(size);
            s.Reparent(this.canvases[lv.index]);
            ArrayPush(this.used, s);
            ArrayPush(this.usedLevel, lv.index);
            ArrayPush(this.usedGroup, cell * 8 + style);
            k += 1;
        }
        return true;
    }

    private func DetachAt(i: Int32) {
        let s = this.used[i];
        this.canvases[this.usedLevel[i]].RemoveChild(s);
        ArrayPush(this.pool, s);
        ArrayErase(this.used, i);
        ArrayErase(this.usedLevel, i);
        ArrayErase(this.usedGroup, i);
    }

    private func DetachLevel(l: Int32) {
        let i = ArraySize(this.used) - 1;
        while i >= 0 {
            if this.usedLevel[i] == l {
                this.DetachAt(i);
            }
            i -= 1;
        }
    }

    private func Restroke(scale: Float) {
        let i = 0;
        while i < ArraySize(this.used) {
            if this.usedLevel[i] == this.current {
                this.used[i].SetLineThickness(NMVectorLayer.LineWidthFor(this.usedGroup[i] % 8, this.current, scale));
            }
            i += 1;
        }
    }

    // Every visible cell's resource missing for VecFailMs -> failed (the system falls back to raster).
    private func WatchMissing(dtMs: Float) {
        if this.wanted > 0 && this.missing == this.wanted {
            this.missingMs += dtMs;
            if this.missingMs >= NMTheme.VecFailMs() {
                this.failed = true;
            }
        } else {
            this.missingMs = 0.0;
        }
    }
```

- [ ] **Step 4: Integrate into the system**

Make these changes in `Core/NightMapSystem.reds`:

1. Fields, next to `private let tiles: ref<NMTileLayer>;`:
```swift
    private let vector: ref<NMVectorLayer>;
    private let vectorFailed: Bool;
```
2. Helpers, next to `Settings()`:
```swift
    public static func MaxMppFor(useVector: Bool) -> Float {
        if useVector && NMVectorManifest.LevelCount() > 0 {
            return NMVectorManifest.LevelMaxMpp(NMVectorManifest.LevelCount() - 1);
        }
        return NMTileManifest.LevelCount() > 0 ? NMTileManifest.LevelMpp(NMTileManifest.LevelCount() - 1) : 16.0;
    }

    private func UseVector() -> Bool {
        let s = this.Settings();
        return !this.vectorFailed && (IsDefined(s) ? s.vectorMap : true) && NMVectorManifest.Available();
    }

    private func FallBackToRaster() {
        NMLog.Error("vector map failed to load - falling back to raster tiles");
        this.vector.Destroy();
        this.vector = null;
        this.vectorFailed = true;
        this.tiles = NMTileLayer.Create(this.panel.tiles);
        this.camera.maxMpp = NightMapSystem.MaxMppFor(false);
        this.camera.SetMpp(this.camera.mpp);
        this.UpdateWarning();
    }
```
`SetMpp` re-clamps to the new `maxMpp`. If `ApplyMpp` only clamps on change, also call `this.camera.SetMpp(MinF(this.camera.mpp, this.camera.maxMpp));`.

3. In `Open()`, replace the `let maxMpp = NMTileManifest.LevelCount() > 0 ? … : 16.0;` line with:
```swift
        let maxMpp = NightMapSystem.MaxMppFor(this.UseVector());
```
4. In `OnOpened()`, replace `this.tiles = NMTileLayer.Create(this.panel.tiles);` with:
```swift
        this.vector = null;
        this.tiles = null;
        if this.UseVector() {
            this.vector = NMVectorLayer.Create(this.panel.tiles);
        }
        if !IsDefined(this.vector) || !this.vector.available {
            this.vector = null;
            this.tiles = NMTileLayer.Create(this.panel.tiles);
        }
```
5. In `OnClosing()`, before `this.tiles = null;`:
```swift
        if IsDefined(this.vector) {
            this.vector.Destroy();
        }
        this.vector = null;
```
6. In `UpdateModules(dt)`, replace `this.tiles.Update(this.camera);` with:
```swift
        if IsDefined(this.vector) {
            this.vector.Update(this.camera, dt);
            if this.vector.failed {
                this.FallBackToRaster();
            }
        } else {
            if IsDefined(this.tiles) {
                this.tiles.Update(this.camera);
            }
        }
```
7. In `UpdateWarning()`, directly after the existing `if !NMTileManifest.Available() { … } else if IsDefined(this.tiles) && !this.tiles.available { … }` block and before `let built = …`, insert:
```swift
        if this.vectorFailed {
            if NotEquals(text, "") {
                text += "  |  ";
            }
            text += "Vector map failed to load - showing raster tiles";
        }
```

- [ ] **Step 5: Run the compile check and confirm it passes**

Run: `tools/check.sh`
Expected: `COMPILE OK`.

If scc rejects `SetRenderTransformPivot`, `GetParentWidget() as inkCompoundWidget` or `ArrayPop`, adjust minimally and keep the behaviour. In particular, without a pivot setter, compute the translation so the canvas scales from its top-left corner. List every adjustment in your report.

- [ ] **Step 6: Commit**

```bash
git add r6/scripts/NightMap/Render/VectorLayer.reds r6/scripts/NightMap/Core/NightMapSystem.reds r6/scripts/NightMap/Debug/SelfTest.reds
git commit -m "Vector runtime: pooled per-cell shapes, canvas pan/zoom, thickness, budget passes, raster fallback

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Perf suite scenarios and results gates

**Files:**
- Modify: `r6/scripts/NightMap/Debug/PerfSuite.reds`, `tools/results.py`, `tools/test_results.py`

**Interfaces:**
- Consumes: the existing `NMPerfSuite` and `tools/results.py` (`parse`, `verdict`, `AVG_BUDGET_MS`, `P95_BUDGET_MS`).
- Produces:
  - Perf rows: `vector_V0_idle` … `vector_V4_idle` and `vector_panzoom`.
  - `results.VEC_AVG_BUDGET_MS = 2.0`, `results.VEC_P95_BUDGET_MS = 4.0`.
  - `verdict(rows)` judges every `vector_*` row against `closed_baseline` when any are present.

- [ ] **Step 1: Write the failing Python tests**

Append to `tools/test_results.py`:
```python
VEC = """
[t] [1] [NightMap] PERF|SUITE|start
[t] [1] [NightMap] RESULT|closed_baseline|items=0|frames=300|setup_ms=0.1|frame_avg=20.0|frame_p95=29.0|frame_p99=40.0|frame_max=60.0|script_avg=0.01|script_p95=0.02
[t] [1] [NightMap] RESULT|items_50000|items=50000|frames=300|setup_ms=900.0|frame_avg=22.5|frame_p95=33.0|frame_p99=45.0|frame_max=70.0|script_avg=1.9|script_p95=3.0
[t] [1] [NightMap] RESULT|vector_V0_idle|items=0|frames=300|setup_ms=0|frame_avg=21.5|frame_p95=32.0|frame_p99=40.0|frame_max=60.0|script_avg=0.1|script_p95=0.2
[t] [1] [NightMap] RESULT|vector_panzoom|items=0|frames=300|setup_ms=0|frame_avg=21.0|frame_p95=31.0|frame_p99=40.0|frame_max=60.0|script_avg=0.5|script_p95=1.0
[t] [1] [NightMap] PERF|SUITE|done
"""


def test_vector_rows_pass_within_budget():
    ok, msg = results.verdict(results.parse(VEC))
    assert ok, msg
    assert "vector_V0_idle" in msg and "vector_panzoom" in msg


def test_vector_row_over_budget_fails():
    ok, msg = results.verdict(results.parse(VEC.replace("frame_avg=21.5", "frame_avg=22.5")))
    assert not ok and "vector_V0_idle" in msg


def test_vector_p95_over_budget_fails():
    ok, msg = results.verdict(results.parse(VEC.replace("frame_p95=31.0", "frame_p95=33.5")))
    assert not ok and "vector_panzoom" in msg
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `python3 -m pytest -q tools/test_results.py`
Expected: the 3 new tests FAIL, because the vector rows are not judged yet.

- [ ] **Step 3: Implement `results.py`**

Add these constants after `P95_BUDGET_MS`:
```python
VEC_AVG_BUDGET_MS = 2.0
VEC_P95_BUDGET_MS = 4.0
```
Replace `verdict` with:
```python
def verdict(rows: list[dict]) -> tuple[bool, str]:
    by = {r["name"]: r for r in rows}
    if "closed_baseline" not in by or "items_50000" not in by:
        return False, "missing closed_baseline or items_50000 row"
    base, test = by["closed_baseline"], by["items_50000"]
    for r in (base, test):
        if "frame_avg" not in r or "frame_p95" not in r:
            return False, f"row {r['name']} lacks frame_avg/frame_p95"
    d_avg = test["frame_avg"] - base["frame_avg"]
    d_p95 = test["frame_p95"] - base["frame_p95"]
    ok = d_avg <= AVG_BUDGET_MS and d_p95 <= P95_BUDGET_MS
    parts = [f"items_50000: avg +{d_avg:.2f} ms (budget {AVG_BUDGET_MS}), p95 +{d_p95:.2f} ms (budget {P95_BUDGET_MS})"]
    vec = [r for r in rows if r["name"].startswith("vector_")]
    for r in vec:
        if "frame_avg" not in r or "frame_p95" not in r:
            ok = False
            parts.append(f"{r['name']}: lacks frame_avg/frame_p95")
            continue
        va, vp = r["frame_avg"] - base["frame_avg"], r["frame_p95"] - base["frame_p95"]
        good = va <= VEC_AVG_BUDGET_MS and vp <= VEC_P95_BUDGET_MS
        ok = ok and good
        parts.append(f"{r['name']}: avg +{va:.2f} ms (budget {VEC_AVG_BUDGET_MS}), p95 +{vp:.2f} ms "
                     f"(budget {VEC_P95_BUDGET_MS}){'' if good else ' OVER'}")
    if not vec:
        parts.append("no vector rows (raster run)")
    return ok, "; ".join(parts)
```
In `main()`, widen the scenario column from 18 to 22 characters in both the header and the row format strings, so `vector_panzoom` and `vector_V0_idle` align.

- [ ] **Step 4: Implement the perf scenarios**

In `Debug/PerfSuite.reds`:
1. Add the fields:
```swift
    private let modes: array<Int32>;      // 0 = circle + 1..16 sweep, 1 = fixed downtown view, 2 = circle + 0.5..32 sweep
    private let mpps: array<Float>;
```
2. Change `Add` to take a mode and an mpp, and add the two arrays:
```swift
    private func Add(name: String, count: Int32, show: Bool, mode: Int32, mpp: Float) {
        ArrayPush(this.names, name);
        ArrayPush(this.counts, count);
        ArrayPush(this.shows, show);
        ArrayPush(this.modes, mode);
        ArrayPush(this.mpps, mpp);
    }
```
3. In `Start()`, clear `modes` and `mpps` next to the other arrays. Pass `0, 0.0` on every existing `Add` call. Insert these before `closed_end`:
```swift
        this.Add("vector_V0_idle", 0, true, 1, 0.65);
        this.Add("vector_V1_idle", 0, true, 1, 1.2);
        this.Add("vector_V2_idle", 0, true, 1, 2.8);
        this.Add("vector_V3_idle", 0, true, 1, 7.0);
        this.Add("vector_V4_idle", 0, true, 1, 20.0);
        this.Add("vector_panzoom", 0, true, 2, 0.0);
```
4. In `Step()`, replace the three camera-path lines (`cam.SetCenter(-700.0 + …)` and `cam.SetMpp(PowF(16.0, …))`, keeping `cam.follow = false;`) with:
```swift
        let mode = this.modes[this.idx];
        if mode == 1 {
            cam.SetCenter(-1800.0, 150.0);
            cam.SetMpp(this.mpps[this.idx]);
        } else {
            cam.SetCenter(-700.0 + 2500.0 * CosF(a), 1500.0 + 2500.0 * SinF(a));
            if mode == 2 {
                cam.SetMpp(0.5 * PowF(64.0, 0.5 - 0.5 * CosF(2.0 * a)));
            } else {
                cam.SetMpp(PowF(16.0, 0.5 - 0.5 * CosF(2.0 * a)));
            }
        }
```
The camera clamps to `maxMpp`, so in Raster mode the vector scenarios simply run at ≤ 16.

- [ ] **Step 5: Run the tests and the compile check**

Run: `python3 -m pytest -q tools/test_results.py`
Expected: 11 passed.

Run: `tools/check.sh`
Expected: `COMPILE OK`.

- [ ] **Step 6: Commit**

```bash
git add r6/scripts/NightMap/Debug/PerfSuite.reds tools/results.py tools/test_results.py
git commit -m "Perf: vector idle/panzoom scenarios and +2/+4 ms vector gates

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: In-game checkpoint 3 (human-in-the-loop)

**Files:**
- Modify: `notes/CHECKPOINTS.md`. Tuning edits (for example the `NMTheme.Vec*` values or `vector_config.LEVELS`) go in their owning files, followed by a rebuild.

The controller runs this task with the user; subagents can't drive the game.

- [ ] **Step 1: Review the SVG previews before any game run**

Ask the user to open the previews in a browser:
- `tools/tiles/build/vector_V0_downtown.svg`
- `vector_V1_downtown.svg`
- `vector_V2_full.svg`
- `vector_V4_full.svg`

They compare them against `docs/superpowers/specs/mockups/nightmap-street.png` and `nightmap-overview.png`.

Expected: smooth cyan road outlines, blocks with height shading, water, and a pink metro, with no gaps at cell edges. Record the user's verdict and any requested tuning.

- [ ] **Step 2: Install, run the self-test and check the look in-game**

Run: `tools/install.sh`. Ask the user to restart the game, open the map, and press Ctrl+`'`.

Run: `grep -a "\[NightMap\] TEST|" ~/cyberpunk_symlink/bin/x64/plugins/cyber_engine_tweaks/gamelog.log | tail -80`
Expected: `failed=0`. Fix any failure in the task that owns it, then repeat.

Ask the user to zoom across the whole range (0.5 → 32) and pan. Expected:
- smooth lines at every zoom;
- no blank frames when switching levels;
- roads aligned with the minimap and V's arrow;
- roads keep a constant on-screen width.

Then ask the user to switch Mod Settings → NightMap → Vector map off, reopen the map, and compare it with raster.

- [ ] **Step 3: Run the perf suite**

Ask the user to stand still in a busy street with Vector map on, open the map and press Shift+`'`.

Run: `python3 tools/results.py`
Expected: a `PASS:` line that includes `items_50000` and all six `vector_*` rows within their budgets.

If a vector row fails, the levers in order are:
1. Lower `VecShapeBudget`/`VecPointBudget` in `NMTheme`, and the matching `SHAPE_BUDGET`/`POINT_BUDGET` in `vector_config`, then rebuild.
2. Raise `min_area` for the failing level.
3. Raise the tolerance.

- [ ] **Step 4: Record and commit**

Append a `## Checkpoint 3 (vector layer)` section to `notes/CHECKPOINTS.md` with:
- the preview review;
- the self-test summary;
- the visual and alignment notes;
- the Vector-versus-Raster comparison;
- the perf table and the PASS/FAIL line.

```bash
git add notes/CHECKPOINTS.md
git commit -m "Checkpoint 3: vector layer previews, in-game review, perf results

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Documentation

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the README**

In the README's "Using it" section, add:
```markdown
- The map is drawn as smooth vector shapes by default. Mod Settings → NightMap → **Vector map** off switches to the older raster tiles (also used automatically if the vector data fails to load).
```
In the build section, add:
```markdown
- The tile build also bakes the vector layer: five zoom levels of road edges, land, water, building blocks and the metro, written as per-cell `.inkshapecollection` resources plus `Generated/VectorManifest.reds`. It takes 30–60 minutes. `--no-vector` skips it and writes a stub manifest.
- Every vector level must pass a worst-view budget (≤ 27k points, ≤ 360 shapes). The build tightens detail automatically, fails if it still can't fit, and writes `tools/tiles/build/vector_budget.json` plus SVG previews (`build/vector_V*_downtown.svg`, `build/vector_V2..4_full.svg`).
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "Docs: vector map setting and build notes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Revision 2 (2026-10-13): baked minimap tiles (spec §11)

Tasks 11–13 replace the remaining live-vector work. Task 9 (checkpoint 3) resumes as Task 14 after them, and Task 10 (docs)
runs last. The spike code in `.scratch/minimap_spike/` (`fastdec.py`, `extract.py`, `build_all.py`, `w/lib.py`) is a
**reference only**: port its logic, don't import it. `FINDINGS.md` there is the format spec.

### Task 11: Minimap extraction and decode (`nmtiles/minimap.py`)

**Files:** create `tools/tiles/nmtiles/minimap.py` and `tools/tiles/tests/test_minimap.py`, plus a tiny fixture
`tools/tiles/tests/data/minimap_sample.json`: one real small `minimapEncodedShapes` RootChunk, e.g. the
`a0_0_0_c111_80_222` one from `.scratch/cmm/json/`.

**Interfaces (produced):**
- `decode_shapes(root: dict) -> list[DecodedShape]`. `DecodedShape(tris: np.ndarray (M,3,2) local xy, z: float,
  type: int, flag: int)`.
- `sector_nodes(sector_json: dict) -> list[(position_xy, encoded_root_dict)]`. Skips interiors, soft refs with no
  embedded data, and scale = -inf.
- `classify(tris) -> "road" | "stroke"`: thickness = area / max bbox extent; road if ≥ 3.0 m.
- `load_city(game_dir: Path, cache_dir: Path, log, workers=None) -> dict[str, np.ndarray]`. Returns `{"road": (N,3,2)
  float32, "stroke": (K,3,2) float32}` in world xy. It:
  1. lists the sectors (base `basegame_3_nightcity.archive` plus the EP1 archives; an EP1 copy of a path replaces the
     base one);
  2. extracts and converts them in parallel with WolvenKit (`extract -w/-r`, then `convert s`, whose output dir must
     exist);
  3. caches the JSON and a final `minimap_city.npz` in `cache_dir`, keyed by the source archives' size + mtime.

**Tests (write first):**
1. Decoding the fixture gives `NumShapes` shapes. Every fill index is in range, the fill ranges tile the fill buffer exactly
   once, and the triangle count equals `NumFillPoints / 3`.
2. Both D-record packings (normal and compact): synthetic buffers built in the test decode to the expected start/count.
3. The quantization maps qx = 0 → bias and qx = 65535 → bias + scale.
4. `classify`: a 10×40 m rectangle → road; a 0.8×12 m rectangle → stroke.
5. `sector_nodes` on a synthetic sector JSON:
   - adds the node position;
   - skips an `allInteriorShapes` node;
   - skips a soft ref with no embedded file.
6. EP1 precedence: given base and EP1 path lists, the resolver picks the EP1 copy for a duplicated path.

**Verify:**
- `pytest` green.
- Run `load_city` for real once and log the totals (sectors, nodes, road and stroke triangles). The cold run is
  long (about 772 sectors × 15 s ÷ workers). Report the wall time and the npz size.

**Spec §11.5 is binding on Tasks 12–14:**
- **Performance:** idle ≤ +1.0 ms avg and ≤ +2.0 ms p95; pan/zoom ≤ +1.5 ms avg and ≤ +3.0 ms p95.
- **Look:** downscale-only level choice, a crossfade between levels, and a glow layer.
- **Tiles:** colourless mask tile sets (base, road, stroke, glow, metro), tinted at runtime by `NMTheme`.
- **Layer stack:** an `NMMapLayer` stack for future photos and widgets.

Where Task 12 or 13 below says "coloured" or "single tile", §11.5 overrides it:
- **Task 12** renders one white-alpha mask tile set per class, plus the glow set (strokes blurred, radius about 3 px at
  each level), and emits a TileManifest with tile sets. Previews composite the sets with the default theme colours.
- **Task 13** builds the layer stack, with one `NMTileLayer` per set, tint from `NMTheme`, crossfade between levels, and
  the new perf gates in `tools/results.py`.

### Task 12: Styled minimap tiles in the build (`nmtiles/render_minimap.py`, `build.py`)

**Files:**
- create `tools/tiles/nmtiles/render_minimap.py` and `tools/tiles/tests/test_render_minimap.py`;
- modify `tools/tiles/nmtiles/build.py`;
- modify `tools/tiles/nmtiles/style.py` (the base style: buildings off).

**Behaviour (spec §11.2):**
- **Levels.** `--levels` defaults to `0.5,1,2,4,8,16`.
- **Per-tile rendering.** For each level and tile, render at 2× and downsample (LANCZOS). Layers:
  1. the base 3D-map layer: land, water, coast, roads off, buildings off. Reuse `render.py`'s drawing on a tile-sized
     grid; refactor `render_level` so it can render a sub-rectangle;
  2. minimap road triangles, fill `#1e8c96` at alpha 0.55;
  3. minimap stroke triangles, `#9ff3ff` at alpha 0.9;
  4. metro, as the current style draws it.
- **Triangle lookup.** Use a per-level spatial grid (numpy binning by triangle bbox) so a tile only touches nearby
  triangles.
- **Skipping.** Fully transparent tiles are skipped.
- **Parallelism.** A fork pool over tiles. Memory must stay bounded: no whole-level images.
- **Removals.** Remove the vector build from `build.py`: no `build_vector`, no `VectorManifest` emission, and drop the
  `--no-vector` and `--vector-budget` flags. Delete the `nmtiles/vector_*.py` modules and their tests, and
  `templates/shapes.inkshapecollection.json`.
- **Previews.** Write `build/preview_minimap_{close,mid,far}.png`: crops of downtown, centre game xy (-1800, 150), at
  0.5, 2 and 8 m/px, each 1882×1480. Write them from the actual tiles (stitched), so they show exactly what ships.
- **Reporting.** The build logs per-level tile counts, the archive size, and the total wall time.

**Tests (write first):**
- A tile containing one road triangle has teal pixels at its centroid and transparent pixels far away.
- Stroke pixels draw over road pixels.
- An empty tile returns None and is skipped.
- Adjacent tiles agree along the shared edge (no seams): a triangle across the border paints both edge columns.
- The spatial grid returns every triangle whose bbox overlaps the tile, and none far away.

**Verify:**
- `pytest` green.
- Run the real build (`python3 -m nmtiles.build --skip-export`) and report:
  - wall time;
  - tile counts per level;
  - archive MB.
- **Size rule.** If the archive exceeds 250 MB, rebuild with the finest level at 0.75 m/px and report both sizes. That is
  a pre-authorised ruling.

### Task 13: Runtime: six tile levels, retire the vector layer

**Files:**
- `r6/scripts/NightMap/Core/NightMapSystem.reds`;
- `Core/Settings.reds`;
- `Core/Theme.reds`;
- `Render/TileLayer.reds`, if its level count or pool assumes 4 levels;
- `Debug/PerfSuite.reds`;
- `Debug/SelfTest.reds`;
- `tools/results.py`;
- delete `Render/VectorLayer.reds`, `Render/VectorLevel.reds`, `Generated/VectorManifest.reds`, and `Debug/Trace.reds`
  (along with its NMTrace call sites).

**Behaviour (spec §11.3):**
- The tile layer is always used.
- The camera's min m/px is the finest `NMTileManifest` level (0.5), and its max is the coarsest level's limit as today.
- `PickLevel` works for six levels.
- Remove the `vectorMap` setting and every Vec* constant.
- Perf scenarios:
  - drop the vector scenarios;
  - extend the raster pan/zoom sweep to reach 0.5 m/px;
  - add an idle scenario at 0.5 m/px over downtown.
- `results.py`: drop the vector thresholds. The verdict uses the sub-project 1 thresholds.
- `tools/check.sh` must not need RedFileSystem any more, if Trace was its only user. Keep check.sh working either way.
- Self-test: update the level-count and zoom-limit assertions.

**Verify:**
- `tools/check.sh` prints COMPILE OK.
- `pytest` green.
- `grep -ri "vector\|NMVec\|NMTrace" r6/scripts/NightMap` finds nothing except comments that explain history (prefer
  none).

### Task 14: Checkpoint 3, final (human, in-game)

The procedure is Task 9's, with spec §11.4 as acceptance:
1. Install with `tools/install.sh` **while the game is closed**. Check that the archive's mtime is before the game's start.
2. Self-test.
3. Visual review at fully in, mid and far zoom, plus alignment with the world.
4. Perf suite: `python3 tools/results.py` must PASS.
5. Record the archive size.
6. Write the checkpoint section in `notes/CHECKPOINTS.md` and commit.
