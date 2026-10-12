# NightMap sub-project 1b: vector map layer

Status: approved in brainstorming on 2026-10-12. Awaiting written-spec review.
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
| Fallback | A **Map renderer: Vector / Raster** setting, default Vector. The renderer falls back to raster automatically if the vector data is missing. |

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

Each vector level covers a range of camera zoom, given in m per map unit. "Unit" means a HUD virtual-window unit. The worst-case map area is **1882 × 1480 units**: the 4K panel, with the 1.75 aspect cap bounding ultrawide screens.

| Level | Camera range | Simplify tolerance | Cell size | Content |
|---|---|---|---|---|
| V0 | 0.5 – 1.5 | 0.25 m | 250 m | All roads (edges), individual buildings, water, land, metro |
| V1 | 1.5 – 4 | 0.75 m | 600 m | All roads, buildings merged into blocks (gap ≤ 2 m), water, land, metro |
| V2 | 4 – 10 | 2 m | 1500 m | Roads above a width threshold, blocks merged with gap ≤ 8 m, water, land, metro |
| V3 | 10 – 32 | 5 m | 4000 m | Major roads only, district-scale blocks or none, coastline, water, metro |

- **Simplify tolerance** is half a pixel at the level's most zoomed-in end. Paths are therefore never visibly faceted, and no points are spent beyond that.
- **Hysteresis:** a level switches when the camera passes its boundary by 8% in either direction.
- **Cell size** is chosen so the worst-case view covers about 3×3 to 4×4 cells.
- **Tuning:** the content thresholds (road width, merge gap, smallest building kept) are tuning parameters in one Python config table. The budget check (§4.5) tunes them, and the table above gives the starting values.
- **Camera range:** the camera's max zoom-out rises from 16 to 32 m/unit, so the whole city fits at V3. The raster fallback still stops at 16, so in Raster mode it clamps to 16.

## 4. Pipeline (offline, `tools/tiles/nmtiles/`, Python)

It reuses the existing mesh export, `glb` reader, building boxes and calibration transform. New modules each have one job.

### 4.1 Feature extraction (`vector_extract.py`)
- **Roads.** Rasterize the road surface (`3dmap_roads`) into a 1 m/px mask in world space, then:
  1. Skeletonize the mask to centrelines. Implement Zhang–Suen thinning in numpy (scikit-image is not available).
  2. Trace the skeleton into polylines between junctions and endpoints.
  3. Attach a road width from the distance transform: twice the median distance along the path.
  4. Emit **road edge lines** by offsetting each centreline by ±width/2. Edge lines are the approved look: cyan road outlines.
  5. Keep the centreline and width. V2 and V3 filter on width.
- **Metro.** Use the same skeleton-and-trace method on `3dmap_metro`, emitting centrelines only.
- **Buildings.** Take the 246,802 boxes from `buildings.py`, each an oriented rectangle with a height.
- **Land and water.** Take the outer rings of the terrain and water masks, traced at 2 m/px. Islands are separate rings. Holes are dropped (constraint 2), so lakes are water drawn on top of land.

### 4.2 Generalisation (`vector_lod.py`)
- **Per level:** Douglas–Peucker with the level's tolerance; drop roads below the level's width threshold; drop polylines shorter than 3 × tolerance.
- **Blocks.** Rasterize the buildings at the level's resolution and dilate by the merge gap. Then trace the outer rings, erode them back by the same amount, and simplify. Each block keeps its maximum height for shading.

### 4.3 Cell clipping (`vector_cells.py`)
- **Clipping.** Clip every feature to its level's grid cells; polylines are split at cell edges.
- **Ownership.** A polygon belongs to the cell that contains its centroid. It is not clipped, so each outline stays one widget. The cell's draw bounds grow by that polygon's extent, which the runtime uses for culling.
- **Ordering.** Within a cell, shapes are ordered by draw order (land, water, blocks/buildings, roads, metro) and then by priority (bigger first).

### 4.4 Output (`vector_write.py`, extended `manifest.py`)
- **One `inkShapeCollectionResource` per non-empty cell**, at `nightmap\vec\V{l}\c_{ix}_{iy}.inkshapecollection`.
  - Presets are named `s0`, `s1`, … in draw order.
  - Points are in **level-local units**: world metres minus the cell origin, divided by the level's design unit (the min mpp of its range). Y points down.
  - The resources are written as WolvenKit JSON from the vanilla template, run through one batched `convert d`, and packed into `NightMap.archive` next to the raster tiles.
- **Generated `Generated/VectorManifest.reds`** (`NMVectorManifest`):
  - `Available()`
  - level count, plus each level's min/max mpp, design unit, cell size, origin and grid dimensions
  - for each cell: whether it exists, shape count, total points, and draw bounds
  - for each shape: style id (land, water, block, building, road, metro) and point count
  - for each building or block shape: a height bucket for shading
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
The pipeline writes one **SVG** per level of the whole map, plus downtown crops at the V0 and V1 extremes. The SVGs are built from exactly the same per-cell geometry that is packed, using theme colours. They are used to review the look against the mockups before any in-game run.

## 5. Runtime (redscript, `r6/scripts/NightMap/Render/VectorLayer.reds`)

- **Placement.** `NMVectorLayer` takes the tile layer's slot in `NightMapSystem`: `OnOpened` builds it, `UpdateModules` calls `Update(camera)`, and `OnClosing` destroys it. When Raster mode is selected, or when `NMVectorManifest.Available()` is false, the existing `NMTileLayer` is used instead.
- **Level selection.** The camera mpp, with 8% hysteresis, picks the level.
- **Containers.** Each level has one `inkCanvas` inside the clipped map area. Each frame, the active container's translation and scale are set from the camera. That is two property writes; no per-shape work happens per frame.
  - scale = design unit / camera mpp
  - translation places the cell origins relative to the camera centre
- **Thickness.** Each style has a target width in screen units, defined in `NMTheme`. When the container scale changes by more than 5% since the last update, every attached shape is set to target ÷ scale.
- **Cells and pool.**
  - Visible cells are those whose draw bounds intersect the view.
  - Shapes come from a pool of 450 `inkShape` widgets. Reusing a widget means calling `SetResource(cell)` and `SetShape(sN)`, then applying the style (variant, colours, opacity, thickness).
  - When a cell leaves the view, its widgets return to the pool.
- **Runtime budget guard.** The layer sums the manifest point counts of the attached shapes. When a view would exceed 30,000 points or 400 shapes, it skips the lowest-priority shapes: buildings and blocks first, then the narrowest roads. It logs a warning once per session.
- **Level transitions.** The old level stays attached until every visible cell of the new level has been assigned and one frame has passed. The old level is then released. Only one transition runs at a time, and further zoom input simply retargets it.
- **Styles** come from the approved palette. The values below are starting values, tuned at checkpoint 3.

  | Style | Variant | Colour / opacity | Width (screen units) |
  |---|---|---|---|
  | land | Fill | cyan 5% | — |
  | water | Fill | cyan 13% | — |
  | block / building | FillAndBorder | cyan fill 6% plus height × 6%; border 45% | 1.0 |
  | road edge | Border | cyan 85% | 1.5 (V0/V1), 1.2 (V2/V3) |
  | metro | Border | pink 80% | 2.0 |

## 6. Error handling

| Situation | Behaviour |
|---|---|
| A cell's resource is missing or never draws | The cell stays empty and the layer logs once. |
| A whole level draws nothing for 3 s (manifest says cells exist, but no attached shape reports loaded) | Automatic switch to Raster, with the panel warning "Vector map failed to load — showing raster tiles". |
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
| Skeleton tracing on dense downtown interchanges gives spurs or broken chains | Prune spurs shorter than 2 × road width. The SVG previews show problems before any game run. |
| The budget fails at V1/V2 downtown | Automatic tightening (§4.5). If it still fails, the build stops early, at build time rather than in-game. |
| Async resource loading causes pop-in when panning fast | Cells are attached when they are partially visible, and level transitions keep the old level. If pop-in is still visible, prefetch one ring at zero opacity, after measuring that hidden shapes are free (a spike-1 result suggests they are). |
| Archive size from about 4 levels × hundreds of cells | Shape JSON is small (the spike's 7 presets packed to 24 KB). Estimate below 15 MB; the build reports the actual size. |
| Off-screen shapes might cost as much as visible ones | The runtime attaches only visible cells. The perf suite measures this. |

## 9. Dependencies

These are unchanged from sub-project 1: Codeware (required), Mod Settings and RedIMG (optional), WolvenKit.CLI, Python 3 with numpy, Pillow and scipy. No new dependencies.
