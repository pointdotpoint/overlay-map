# NCART Lines Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A "NCART lines" map filter that shows the five NCART lines, in their own colours and side by side on shared
track, along the real tracks and through the NCART station markers.

**Architecture:** Offline, the tile build turns the 3D map's metro mesh into a track graph, routes each line between
its stations (line definitions from the game's metro UI widget, station positions from an in-game dump), offsets
lines that share track into parallel slots, and bakes a full-colour `metro` tile set (antialiased, soft glow). At
runtime the set is one more tile layer, created only when the filter is on, tinted white.

**Tech Stack:** Python 3 (numpy, scipy, PIL, shapely; no new dependencies), WolvenKit CLI, redscript, the soak harness.

**Spec:** `docs/superpowers/specs/2026-11-03-nightmap-ncart-lines-design.md`

## Global Constraints

- Ship bar (user): the overlay must look **flawless and beautiful**, judged on in-game screenshots at several zooms.
- One switch: Mod Settings → NightMap → Map filters → "NCART lines" (`filterNcart`, default `false`).
- Fixed line colours from the game (`ue_metro_route_diagram.inkwidget`, `LinesList[].lineColor`): line 1 A
  (229, 25, 25), 2 B (255, 248, 0), 3 C (18, 228, 255), 4 D (27, 233, 32, looped), 5 E (250, 131, 0). Never themed,
  never HUD-Painter-tinted.
- Shared track: side by side, fixed slot order by line number, a line keeps its side through a shared stretch, offsets
  ease smoothly where lines split (no zig-zags).
- Layer order: above `road`, below markers/routes/reticle. Off = no layer created, the map looks exactly as today.
- No station dots, names or badges; NightMap's NCART markers are the stations.
- No new Python dependencies (no skimage/networkx): thinning and shortest paths in numpy/scipy/heapq.
- Ask before any in-game run when the user may be playing; check with `pgrep -f "[C]yberpunk2077\.exe"`.

## Review Focus

- A line's station that is not on the track mesh (south ends of B/C at Pacifica – Stadium, the mesh bounds stop near
  y ≈ -1925): expect a smooth spur to the marker, never a missing end. Pinned in Task 2 (`test_route_reaches_off_mesh_station`).
- Looped line (D, `lineIsLooped = 1`): the last station connects back to the first. Pinned in Task 2 (`test_loop_closes`).
- Three lines on one track and one leaving in the middle: the others keep their sides and ease, no crossing.
  Pinned in Task 3 (`test_three_share_then_one_leaves`).
- Tile edges: a line crossing a tile border is seamless (same pixels as one big render). Pinned in Task 4
  (`test_metro_tiles_stitch`).
- Filter off or archive without a `metro` set (older build): no layer, no errors. Pinned in Task 5
  (`ncart.no_layer_when_off`, `ncart.missing_set_is_harmless`).

---

### Task 1: Station positions and line definitions

**Files:**
- Modify: `tools/soak/autopilot/SoakHooks.reds`, `tools/soak/autopilot/SystemBody.inc` (command `ncart_dump`)
- Create: `tools/soak/plans/ncart-dump.json`
- Create: `tools/tiles/nmtiles/ncart.py` (data part), `tools/tiles/data/ncart_stations.json` (committed, from the dump)
- Modify: `tools/tiles/nmtiles/export.py` (extract + serialize `ue_metro_route_diagram.inkwidget` into `build/bdata`)
- Test: `tools/tiles/tests/test_ncart.py`

**Interfaces:**
- Produces: `Line(number: int, letter: str, rgb: tuple[int,int,int], stations: list[str], looped: bool)`;
  `load_lines(widget_json: Path) -> list[Line]` (letter = "ABCDE"[number-1]); `load_stations(path: Path) ->
  dict[str, tuple[float, float, float]]` keyed by `ENcartStations` names (e.g. `"ARASAKA_WATERFRONT"`).

- [ ] **Step 1:** Add soak command `ncart_dump`: for every mappin of variant `Zzz17_NCARTVariant` that is a
  `FastTravelMappin`, log `NCART|<TDBID.ToStringDEBUG(pointRecord)>|<display name>|x|y|z`, then `NCART|DONE|n`.
  Compile with `tools/check.sh --soak`. Run `ncart-dump.json` in game (ask first) and keep the log.
- [ ] **Step 2:** Map the 19 dumped stations to `ENcartStations` names by record id / name, write
  `tools/tiles/data/ncart_stations.json` (`{"ARASAKA_WATERFRONT": [x, y, z], ...}`); all 19 present.
- [ ] **Step 3: Failing tests** `test_load_lines_reads_number_colour_order_loop` (fixture: a trimmed copy of the real
  widget JSON with lines 1 and 4: line 1 rgb (229,25,25), first station `ARASAKA_WATERFRONT`, 9 stations, not looped;
  line 4 looped) and `test_every_line_station_has_a_position` (real data file: every station of every line in
  `load_lines(fixture)` is a key of `load_stations`).
- [ ] **Step 4:** Implement `load_lines`, `load_stations`; extend `export.py` so a full build writes
  `bdata/ue_metro_route_diagram.inkwidget.json`.
- [ ] **Step 5:** `pytest tools/tiles/tests/test_ncart.py` passes; commit.

### Task 2: Track graph and routes

**Files:** Modify `tools/tiles/nmtiles/ncart.py`; test `tools/tiles/tests/test_ncart.py`

**Interfaces:**
- Consumes: Task 1 `Line`, stations.
- Produces: `TrackGraph` (nodes: (n,2) float64 world xy; edges: list of (a, b, polyline (k,2))) from
  `track_graph(tris: np.ndarray, res: float = 1.0) -> TrackGraph` (rasterize xy triangles, close 2 m, thin to a
  1-px skeleton with a numpy Zhang–Suen pass, trace junction-to-junction polylines, Douglas–Peucker 0.5 m);
  `route(g: TrackGraph, line: Line, stations) -> list[tuple[int, int]]` = the ordered edge ids (with direction) the
  line runs over; `spur(g, station_xy) -> np.ndarray | None` = straight/smoothed polyline from the nearest track point
  to a station farther than `SPUR_MIN_M = 6.0` from the track.

- [ ] **Step 1: Failing tests:** `test_graph_of_a_cross_has_one_junction_four_edges` (two 8 m wide crossing ribbons);
  `test_route_follows_track_between_stations` (an L-shaped ribbon, stations at both ends: route length within 2 % of
  the L's centreline); `test_route_reaches_off_mesh_station` (station 40 m past a ribbon's end: `spur` returns a
  polyline ending at the station); `test_loop_closes` (looped line over a ring: last edge returns to the first node);
  `test_real_mesh_routes_all_lines` (skipped when `build/meshes/.../3dmap_metro.glb` is absent: every real line routes,
  no station farther than 60 m from its route; print each station's distance).
- [ ] **Step 2:** Run, expect failures (missing functions).
- [ ] **Step 3:** Implement. Shortest path between consecutive stations: Dijkstra (heapq) on edge lengths, stations
  snapped to the nearest edge point (split the edge there).
- [ ] **Step 4:** Tests pass; commit.

### Task 3: Shared-track slots

**Files:** Modify `tools/tiles/nmtiles/ncart.py`; test `tools/tiles/tests/test_ncart.py`

**Interfaces:**
- Produces: `slots(routes: dict[int, list[tuple[int,int]]]) -> dict[int, dict[int, float]]` = per edge id, per line
  number, its signed slot (centred: lines on the edge sorted by number, slot = i - (n-1)/2), measured to the left of the
  edge's canonical direction (node a -> b) so every line uses the same frame; `offset_polyline(g, line_route, slots,
  spacing_m: float, ease_m: float) -> np.ndarray` = the line's world polyline shifted sideways by slot·spacing,
  with the shift interpolated over `ease_m` around nodes where the slot changes.

- [ ] **Step 1: Failing tests:** `test_two_lines_on_one_edge_are_parallel_at_spacing` (distance between the two
  offset polylines along the shared edge = spacing ± 1 %); `test_slot_frame_ignores_travel_direction` (line running
  b->a gets the same side as a->b with the same slot); `test_three_share_then_one_leaves` (three lines share an edge,
  the middle one leaves at a node: the outer two ease to ±spacing/2 within `ease_m`, never cross, no point jumps more
  than spacing/4 between samples).
- [ ] **Step 2:** Run, expect failures. **Step 3:** Implement. **Step 4:** Pass; commit.

### Task 4: The `metro` tile set

**Files:** Modify `tools/tiles/nmtiles/ncart.py` (rendering), `tools/tiles/nmtiles/render_minimap.py` (SETS gets
`"metro"` last), `tools/tiles/nmtiles/build.py` (compute routes once, pass to the tile workers), `nmtiles/style.py`,
`nmtiles/holo_preview.py` (preview the set); test `tools/tiles/tests/test_ncart.py`, `tests/test_render_minimap.py`

**Interfaces:**
- Consumes: Tasks 2–3.
- Produces: `render_metro_tile(paths: list[tuple[np.ndarray, tuple[int,int,int]]], grid: LevelGrid, ix: int, iy: int)
  -> Image.Image | None` (RGBA, colour in RGB, coverage in alpha; None when empty). Pixel values per level:
  `LINE_PX = 4.0`, `SPACING_PX = 5.0` (offsets recomputed per level as `spacing_m = SPACING_PX * mpp`), glow = the
  same polylines at `GLOW_PX = 12.0`, Gaussian blur sigma 3 px, alpha 0.35, under the core line; rendered at SS×,
  LANCZOS-downsampled with a margin like the other sets.

- [ ] **Step 1: Failing tests:** `test_metro_tile_is_coloured_and_transparent_elsewhere` (a red line: core pixel rgb ≈
  (229,25,25), alpha 255; a pixel 30 px away alpha 0); `test_metro_glow_is_soft` (alpha falls monotonically from the
  core to 0 within ~12 px); `test_metro_tiles_stitch` (a line across a tile edge: two tiles equal one big render
  within 2/255); `test_sets_order` updated to `("glow", "bfill", "outline", "road", "metro")`.
- [ ] **Step 2:** Run, expect failures. **Step 3:** Implement; wire into the build. **Step 4:** Pass.
- [ ] **Step 5:** Full tile build; render previews of downtown (the Memorial Park → Congress & MLK shared stretch),
  Watson and the Pacifica ends at L1–L3; look at them and fix anything that is not clean. Commit.

### Task 5: Runtime layer and filter

**Files:** Modify `r6/scripts/NightMap/Core/Settings.reds` (Map filters: `filterNcart`, display name "NCART lines",
description "Show the five NCART metro lines along their tracks.", default false), `Render/MapLayer.reds`
(`WantsSet(name, effects, ncart)`), `Core/Theme.reds` (`TileTint("metro")` = white, not routed through `Pick`;
`TileOpacity("metro")` = 1.0), the stack's creator in `Core/NightMapSystem.reds`; README; test
`r6/scripts/NightMap/Debug/SelfTestHolo.reds`, `tools/test_holo_settings.py`

**Interfaces:**
- Produces: `NMLayerStack.WantsSet(name: String, effects: Bool, ncart: Bool) -> Bool` (metro only when `ncart`);
  `NMLayerStack.Create(parent, theme, effects, opt ncart: Bool)`.

- [ ] **Step 1: Failing tests:** in-game `ncart.no_layer_when_off` (`Create(..., false)` has no `metro` layer and the
  same count as before), `ncart.layer_when_on`, `ncart.tint_is_white_and_unthemed` (TileTint("metro", 3) == white
  with a HUD palette set), `ncart.missing_set_is_harmless` (WantsSet true but manifest without `metro`: no crash,
  count unchanged); offline: the settings test covers `filterNcart` (category Map filters, default false).
- [ ] **Step 2:** Compile fails (`tools/check.sh`). **Step 3:** Implement. **Step 4:** `tools/check.sh` and
  `--soak` compile; pytest green; commit.

### Task 6: In-game verification and polish

**Files:** Create `tools/soak/plans/ncart.json`; modify styling constants in `ncart.py` if needed.

- [ ] **Step 1:** Install-free campaign (ask first): filter on, open the map at several zooms over downtown, Watson,
  Pacifica, plus self-tests; screenshots; filter off screenshot unchanged.
- [ ] **Step 2:** Judge against the ship bar: lines meet every NCART marker, parallels clean, colours right, glow soft,
  no seams; compare with the diagram. Fix and rebuild until it is flawless.
- [ ] **Step 3:** Regression campaign passes; commit; whole-branch review; merge and install when the user agrees.
