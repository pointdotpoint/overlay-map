# NightMap sub-project 1b: vector map layer

Status: approved in brainstorming on 2026-10-12. Revised while planning on 2026-10-12: vector blocks instead of individual buildings, contour-based road edges, and per-style manifest counts.
Builds on: `docs/superpowers/specs/2026-10-11-nightmap-core-design.md` (sub-project 1, merged to `main` at 56a63d4).
Evidence: `notes/VECTOR-SPIKE.md` (three in-game spikes), `notes/CHECKPOINTS.md` (checkpoint 2).

## 1. Context

Sub-project 1 draws the map from baked raster tiles at 2/4/8/16 m per pixel. At checkpoint 2 the user found the map pixelated, both zoomed in and zoomed out. The user wants it to look like a smooth SVG at every zoom level.

### Decisions made during brainstorming

| Topic | Decision |
|---|---|
| Where vector is used | **Everywhere**: every zoom level is drawn as vector. Raster tiles remain only as a fallback. |
| Detail when zoomed out | **Generalised level of detail** (LOD). The far view shows coastline, major roads, the metro and merged blocks; detail fades in as you zoom. |
| Frame budget for the map | **+2 ms average / +4 ms p95** over the closed baseline, with the map open and no markers. The markers keep their own existing budget on top. |
| Approach | **A: vector tiles.** Pipeline-built shape resources, one per zoom level and grid cell. The runtime attaches only the visible cells. |
| Metro line | **Solid** thin pink line. This departs from the mockup's dashes, because dashing a shape costs widgets. |
| Buildings | **Vector blocks at every level** (decided while planning, 2026-10-12). A downtown view at the closest zoom holds about 21,000 building boxes, about 50× the outline budget. Merged with a 2 m gap, the same view holds about 100 blocks (about 225 at a 1.4 km view). Individual buildings are not drawn. |
| Fallback | A **Vector map** on/off setting (on by default; off = raster tiles). The renderer falls back to raster automatically if the vector data is missing. |

### Hard constraints proven in-game (`notes/VECTOR-SPIKE.md`)

1. An `inkShape` only draws geometry that comes from a shape resource: `SetResource(.inkshapecollection)` plus `SetShape(<preset>)`. A `vertexList` set at runtime is never drawn, so **all geometry is prebuilt by the pipeline**.
2. One preset is one path. Bridges between separate outlines are drawn as visible lines, and a fill that crosses bridges draws nothing. **Every closed outline is its own widget.** Shapes cannot have holes.
3. Cost is about **15–20k drawn points per ms**, paid every frame even when the view is static. With the +2 ms budget that gives **≤ 30,000 points and ≤ 400 shape widgets on screen**.
4. Transforming a parent canvas costs nothing, so pan and zoom use the canvas transform. Line thickness scales with the canvas and must be compensated.
5. Lines and fills are anti-aliased. Concave fills render correctly.

## 2. Goals and non-goals

**Goals**
- The map is smooth, with no visible pixels, from 0.5 to 32 m per map unit.
- The map stays inside +2 ms average / +4 ms p95 at every zoom level, idle and while panning or zooming.
- It is aligned with the world as well as the raster tiles are; both use the same transform and calibration.
- Existing behaviour is unchanged: markers, crosshair, card, player arrow, input and the public layer API.

**Non-goals**
- Runtime geometry editing. Constraint 1 rules it out.
- Dashed lines and glow effects. The road glow may be emulated later; see §6.
- Map labels such as street and district names. These belong to a later sub-project.
- Removing the raster tile pipeline. It stays as the fallback.

## 3. Zoom levels and cells

Each of the five vector levels covers a range of camera zoom, given in m per map unit. "Unit" means a HUD virtual-window unit. The worst-case map area is **1882 × 1480 units**: the 4K panel, with the 1.75 aspect cap bounding ultrawide screens.

| Level | Camera range | Simplify tolerance | Cell size | Raster | Content |
|---|---|---|---|---|---|
| V0 | 0.5 – 0.8 | 0.25 m | 250 m | 0.5 m | All roads (edges), blocks (gap 2 m), water, land, metro |
| V1 | 0.8 – 1.6 | 0.4 m | 500 m | 0.5 m | All roads, blocks (gap 6 m, ≥ 100 m²), water, land, metro |
| V2 | 1.6 – 4 | 0.8 m | 1000 m | 1 m | Roads ≥ 8 m wide, blocks (gap 12 m, ≥ 600 m²), water, land, metro |
| V3 | 4 – 10 | 2 m | 2000 m | 2 m | Roads ≥ 14 m wide, blocks (gap 30 m, ≥ 4000 m²), water, land, metro |
| V4 | 10 – 32 | 5 m | 4000 m | 4 m | Roads ≥ 20 m wide, blocks (gap 60 m, ≥ 20000 m²), coastline, water, metro |

Downtown density, measured on the real data, sets these ranges. With a 2 m gap there are about 146 blocks per km². The view's area in km² is 2.79 × mpp² (1882 × 1480 units). Each level therefore keeps its blocks at or below about 250 per view, which leaves room for road-edge rings within the 360-shape headroom.

- **Simplify tolerance** is half a pixel at the level's most zoomed-in end. Paths are therefore never visibly faceted, and no points are spent beyond that.
- **Hysteresis:** a level switches when the camera passes its boundary by 8% in either direction.
- **Cell size** is chosen so the worst-case view covers about 3×3 to 4×4 cells.
- **Tuning:** the content thresholds (road width, merge gap, smallest building kept) are tuning parameters in one Python config table. The budget check (§4.5) tunes them, and the table above gives the starting values.
- **Camera range:** the camera's max zoom-out rises from 16 to 32 m/unit, so the whole city fits at V4. The raster fallback still stops at 16, so in Raster mode it clamps to 16.

## 4. Pipeline (offline, `tools/tiles/nmtiles/`, Python)

It reuses the existing mesh export, `glb` reader, building boxes and calibration transform. New modules each have one job.

### 4.1 Feature extraction (`vector_extract.py`)
All mask work is done **per cell**, on a window around the cell, at the level's raster resolution (the Raster column of §3). Contours come from `contourpy` (marching squares, already installed). Cell origins and window margins are whole multiples of the resolution, so neighbouring cells trace identical contours along their shared edge.

- **Roads.** Rasterize the road surface (`3dmap_roads`) and trace the iso-0.5 contours of the mask. Those contours *are* the **road edge lines**, the approved look of cyan road outlines.
  - On levels with a minimum road width, apply a morphological opening with a disk of that diameter first. That removes narrower roads without needing centrelines.
  - Contours are clipped to the cell rectangle into open polylines (Liang–Barsky).
- **Metro.** Use the same contour tracing on `3dmap_metro`. Its two edge lines are about 6 m apart and read as one solid pink line at most zooms.
- **Land and water.** Fill-only polygons, traced on exactly the cell rectangle with holes filled, so the polygons are clipped at the cell edges. Fill has no border, so the seams are invisible.
  - Land is the terrain mask minus the water mask.
  - Water is drawn on top of land.
- **Blocks.** Take the 246,802 boxes from `buildings.py` and rasterize them per cell, on a window grown by the level's block margin (300/300/600/1200/4000 m for V0–V4) so that whole blocks are seen; a block is kept only by the cell that contains its centroid. Then:
  1. Close with a disk of the merge gap and fill holes.
  2. Label the connected components.
  3. Trace each component's outer ring.
  4. Bucket each block by the maximum box height inside it: < 30 m, < 80 m, or above.

  Closed rings repeat their first point at the end, because the Border variant does not close a path.

### 4.2 Generalisation (`vector_lod.py`)
- **Per level:** Douglas–Peucker with the level's tolerance; drop roads below the level's width threshold; drop polylines shorter than 3 × tolerance.
- **Blocks.** Drop blocks smaller than the level's minimum area.

### 4.3 Cell clipping (`vector_cells.py`)
- **Clipping.** Clip every feature to its level's grid cells; polylines are split at cell edges.
- **Ownership.** A block belongs to the cell that contains its centroid. It is not clipped, so each outline stays one widget. The cell's draw bounds grow by that block's extent, which the runtime uses for culling. Land and water are clipped per cell (§4.1).
- **Ordering.** Within a cell, shapes are ordered by draw order (land, water, blocks/buildings, roads, metro) and then by priority (bigger first).

### 4.4 Output (`vector_write.py`, extended `manifest.py`)
- **One `inkShapeCollectionResource` per non-empty cell**, at `nightmap\vec\V{l}\c_{ix}_{iy}.inkshapecollection`.
  - Presets are named `s0`, `s1`, … in draw order. The styles are land, water, block0, block1, block2, road and metro; within a style, the most important shape comes first (largest area or longest).
  - Points are in **level-local units**: world metres minus the cell's draw-bounds corner (min X, max Y), divided by the level's design unit (the min mpp of its range). Y points down, so every point lies within [0, w] × [0, h] of the cell's draw bounds. The widget is placed at the draw bounds and sized to them.
  - The resources are written as WolvenKit JSON from the vanilla template, run through one batched `convert d`, and packed into `NightMap.archive` next to the raster tiles.
- **Generated `Generated/VectorManifest.reds`** (`NMVectorManifest`):
  - `Available()`
  - level count, plus each level's min/max mpp, design unit, cell size, origin and grid dimensions
  - for each non-empty cell: its key (`iy * nx + ix`), its draw bounds in level units, and **per style** the shape count and the point total. Per-shape data would make the generated script far too large.
  - **Large arrays are chunked to ≤ 128 elements per literal**, and callers bind them to locals. This follows the redscript gotcha from sub-project 1: `ArraySize` on a call temporary returns 0.

### 4.5 Budget check (`vector_budget.py`)
For each level, the check computes the **worst view**. That is the worst-case map area at the level's max mpp, slid over the grid in half-cell steps, counting every cell the view touches including its draw bounds. It sums points and shapes.

- **Budget:** ≤ 30,000 points and ≤ 400 shapes, with 10% headroom (27k and 360).
- **If over:** the checker tightens that level's parameters in a fixed order and rebuilds the level:
  1. drop the smallest buildings or blocks;
  2. raise the road width threshold;
  3. raise the tolerance by 25%, up to 2×.
- **If still over:** the build **fails** and prints the worst view's location and its counts.
- **Report:** the final per-level worst-case counts are printed and written to `build/vector_budget.json`.

### 4.6 Previews (`vector_preview.py`)
The pipeline writes a 2 km × 1.5 km downtown **SVG** crop for every level, plus whole-map SVGs for V2–V4. At V0/V1 a whole-map SVG would run to hundreds of MB. The SVGs are built from exactly the same per-cell geometry that is packed, using theme colours. They are used to review the look against the mockups before any in-game run.

## 5. Runtime (redscript, `r6/scripts/NightMap/Render/VectorLayer.reds`)

- **Placement.** `NMVectorLayer` takes the tile layer's slot in `NightMapSystem`: `OnOpened` builds it, `UpdateModules` calls `Update(camera)`, and `OnClosing` destroys it. When Raster mode is selected, or when `NMVectorManifest.Available()` is false, the existing `NMTileLayer` is used instead.
- **Level selection.** The camera mpp, with 8% hysteresis, picks the level.
- **Containers.** Each level has one `inkCanvas` inside the clipped map area. Each frame, the active container's translation and scale are set from the camera. That is two property writes; no per-shape work happens per frame.
  - scale = design unit / camera mpp
  - translation places the cell origins relative to the camera centre
- **Thickness.** Each style has a target width in screen units, defined in `NMTheme`. When the container scale changes by more than 5% since the last update, every attached shape is set to target ÷ scale.
- **Pivot.** Each container's render-transform pivot is (0, 0).
- **Cells and pool.**
  - Visible cells are those whose draw bounds intersect the view.
  - Shapes come from a pool of 800 `inkShape` widgets, enough for two levels during a transition. Reusing a widget means calling `SetResource(cell)` and `SetShape(sN)`, then applying the style (variant, colours, opacity, thickness).
  - A cell whose resource does not exist in the depot (`ResourceExists`) attaches nothing.
  - When a cell leaves the view, its widgets return to the pool.
- **Runtime budget guard.** The layer attaches in two passes over the visible cells, centre outward. The first pass attaches land, water, roads and metro; the second attaches blocks. A style group is skipped once adding it would pass 30,000 points or 400 shapes; the group's points come from the manifest's per-style totals. The layer logs a warning once per session.
- **Level transitions.** The old level stays attached until every visible cell of the new level has been assigned and one frame has passed. The old level is then released. Only one transition runs at a time, and further zoom input simply retargets it.
- **Styles** come from the approved palette. The values below are starting values, tuned at checkpoint 3.

  | Style | Variant | Colour / opacity | Width (screen units) |
  |---|---|---|---|
  | land | Fill | cyan 5% | — |
  | water | Fill | cyan 13% | — |
  | block / building | FillAndBorder | cyan fill 6% plus height × 6%; border 45% | 1.0 |
  | road edge | Border | cyan 85% | 1.5 (V0–V2), 1.2 (V3/V4) |
  | metro | Border | pink 80% | 2.0 |

## 6. Error handling

| Situation | Behaviour |
|---|---|
| A cell's resource is missing or never draws | The cell stays empty and the layer logs once. |
| No visible cell's resource exists for 3 s while the manifest lists cells there (the archive is stale or missing) | Automatic switch to Raster, with the panel warning "Vector map failed to load — showing raster tiles". |
| The pool is exhausted | The farthest cells are dropped first; the layer logs once. |
| The runtime budget guard trips | Low-priority shapes are skipped (§5); the layer logs once. |
| Vector manifest is the stub | Raster is used with no warning. The existing "tiles not found" warning still covers a missing archive. |
| The game version differs from the build | The existing version warning covers it, since the vector manifest records the same source version. |
| Road glow | Shapes cannot glow. If the look is too flat at checkpoint 3, the fix is a second, wider, faint road-edge stroke on V0/V1 only, which costs about 2× the road points there. This is a tuning decision, not a design change. |

## 7. Testing and acceptance

- **Python unit tests (pytest).** Each test uses synthetic inputs with exact assertions:
  - thinning and tracing on a T junction, a ring and a parallel pair;
  - Douglas–Peucker's error bound;
  - block merge and erode;
  - cell clipping at edges and corners, and polygon ownership;
  - preset JSON shape;
  - manifest chunking;
  - the budget checker's tightening order and failure path.
- **Slow test:** a WolvenKit round-trip of one generated collection.
- **Self-test cases** (`VectorCases`):
  - level selection with hysteresis;
  - visible-cell computation at view edges;
  - thickness compensation;
  - pool exhaustion order;
  - the budget guard's skip order;
  - manifest arrays bound to locals with non-zero counts.
- **Perf suite** additions:
  - scenarios: `vector_V0_idle` … `vector_V3_idle` and `vector_panzoom`, the latter sweeping 0.5 → 32 → 0.5 mpp over 300 frames;
  - **gate:** +2 ms average and +4 ms p95 over `closed_baseline` for each scenario;
  - the existing `items_50000` gate must still pass with Vector on;
  - `tools/results.py` gains the new rows and gates.
- **Checkpoint 3 (user, in-game):**
  - alignment with the minimap and the player arrow;
  - smoothness at every zoom;
  - no blank frames while panning or switching levels;
  - the perf suite;
  - a side-by-side comparison of Vector and Raster;
  - a review of the SVG previews before the in-game run.

## 8. Risks

| Risk | Mitigation |
|---|---|
| Road-edge rings in dense downtown cells push the shape count toward the 400 limit | The build's budget check measures it per level and tightens automatically (§4.5). The SVG previews show the result. |
| The budget fails at V1/V2 downtown | Automatic tightening (§4.5). If it still fails, the build stops early, at build time rather than in-game. |
| Async resource loading causes pop-in when panning fast | Cells are attached when they are partially visible, and level transitions keep the old level. If pop-in is still visible, prefetch one ring at zero opacity, after measuring that hidden shapes are free (a spike-1 result suggests they are). |
| Archive size from about 4 levels × hundreds of cells | Shape JSON is small (the spike's 7 presets packed to 24 KB). Estimate below 15 MB; the build reports the actual size. |
| Off-screen shapes might cost as much as visible ones | The runtime attaches only visible cells. The perf suite measures this. |

## 9. Dependencies

These are unchanged from sub-project 1: Codeware (required), Mod Settings and RedIMG (optional), WolvenKit.CLI, Python 3 with numpy, Pillow and scipy. No new dependencies.

## 10. Revision after checkpoint 3: exact geometry (2026-10-12)

**Why.** In-game, the first vector build was rated "inaccurate / confusing". There were three causes:
- roads drawn as two edge outlines;
- jagged building blobs traced from a raster;
- fills too faint to read.

The user chose **exact geometry**, and of the prototype renders (`.scratch/proto_V0*.png`), the look **filled roads + soft
filled buildings, no outlines**. This section supersedes §4.1 for roads, land/water and blocks, the road rules of §4.2, the
styling in §5, and the no-new-dependency line in §9. Metro is unchanged.

### 10.1 Extraction with polygon operations (shapely ≥ 2.1, system package `python-shapely`)
- **Roads.** Union the road-mesh triangles that touch the cell window (`shapely.union_all`, `grid_size=0.01`), then clip to
  the cell rectangle.
  - On levels with a minimum road width, first apply an opening (`buffer(-w/2)` then `buffer(+w/2)`, mitre joins).
  - The result is **filled road surfaces**, style `road`.
- **Land and water.** Exact unions:
  - water = water-mesh union minus land-mesh union (the water mesh is one sea plane under the city);
  - land = land union minus water.
  - Both are clipped to the cell.
- **Blocks.** Union the footprint rectangles of the boxes (height ≥ `MIN_BOX_HEIGHT`) on the block window, then:
  1. Close by the level's `merge_gap` (buffer out, then in).
  2. Open by the level's new `open_width` (buffer in, then out). This removes the thin wall slabs that make the raw union noisy.
  3. Keep exterior rings only.
  4. Simplify, then drop blocks below `min_area` or touching the window border, as before.
  5. Ownership stays with the cell containing the centroid.
  6. Height bucket = the maximum `dz` of the boxes intersecting the block.
- **Simplification.** shapely `simplify(tol)` on every polygon, then pieces below `(2·tol)²` m² are dropped.
- **Hole-free pieces.** A shape preset is one path, so a filled polygon cannot carry holes. Any polygon with interiors is
  split recursively: bisect its bounding box along the longer side, through a point of its first hole, until no piece has
  holes. The pieces cover the polygon exactly. Blocks only keep exteriors, so this applies to roads, land and water.
- Every shape is a closed ring (first point repeated) in world metres, as before. Priority stays area for fills.

### 10.2 Levels
`VLevel` gains `open_width` (m), defaulting to 0.

| | merge_gap | open_width |
|---|---|---|
| V0 | 4 | 3 |
| V1 | 6 | 3 |
| V2 | 12 | 6 |
| V3 | 30 | 12 |
| V4 | 60 | 24 |

All other values are unchanged. The raster resolution is now used by metro only.

### 10.3 Styling (runtime theme and SVG preview, kept identical)

| style | variant | fill opacity | border opacity |
|---|---|---|---|
| land | Fill | 0.05 | 0 |
| water | Fill | 0.16 | 0 |
| block0 | Fill | 0.14 | 0 |
| block1 | Fill | 0.19 | 0 |
| block2 | Fill | 0.24 | 0 |
| road | Fill | 0.22 | 0 |
| metro | Border | 0 | 0.80 (unchanged) |

Colours are unchanged: cyan, metro pink.

### 10.4 Acceptance
The checkpoint-3 gates are unchanged (§7): the perf suite at +2 ms avg / +4 ms p95, plus visual review. One new visual
check: no visible seams between adjacent road, land or water pieces (cell edges and hole-split cuts).

### 10.5 Rulings after implementation
- **Land is not drawn.** `area_features` emits water only (water mesh minus land mesh). The `land` style id stays in `STYLES` with zero shapes, so the manifest layout is unchanged.
- **Budgets.** Shape budget 810 in the build (`SHAPE_BUDGET`), 900 at runtime (`VecShapeBudget`). Widget pool 1800 (`VecPoolSize`), enough to hold two levels during a transition.
- **Holes are cut with slits.** A polygon with holes becomes one ring by a 0.05 m wide keyhole cut from each hole's top vertex to the exterior (largest hole first). The bisect split of §10.1 is kept only as the fallback past recursion depth 64. Budget-ladder re-simplification of fill rings uses shapely, so a slit cannot collapse.
- **Ladder order.** area (2, 4, 8, 16, 32) then tol (1.25, 1.5625, 2) then road width (4, 8, 12): streets are sacrificed last.
