# Area Names Under the Cursor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When no marker is selected, the sidebar names the area under the map focus: game areas such as Japantown,
Afterlife or Red Peaks, plus hand-made ones such as Landfill.

**Architecture:** An offline Python pipeline (`tools/areas`) does three things. It pulls area outlines out of the
game's world sectors, merges them with `custom_areas.json`, and emits `Generated/AreaData.reds`. At runtime,
`NMAreaIndex` parses that data once and answers "which area contains (x, y)", smallest first. It resolves game names
through TweakDB, so they are localized. `OverlayMapSystem` shows the result as a docked card whenever nothing is
selected.

**Tech Stack:** Python 3 + pytest + Pillow, WolvenKit 10 CLI (`~/.local/share/nightmap-tools/wk10`), redscript
(compile check `tools/check.sh`), in-game self-tests (`NMSelfTest`), soak harness (`tools/soak`).

**Spec:** `docs/superpowers/specs/2026-11-05-overlay-map-area-names-design.md`

## Global Constraints

- Only game-file data and our own hand-made outlines may ship. No online or fan-map data (the mod is on Nexus).
- Sectors are converted with WolvenKit 10 only: `~/.local/share/nightmap-tools/wk10 convert s <dir> -o <dir>`.
- Outline shape = `AreaShapeOutline.buffer` (uint32 count + count x 4 float32), never the `points` field.
- Dropped IDs: empty or `0`; `(?i)cyberspace|VR_Tutorial|SpaceStation`; `^Districts\.ArasakaTower(?!Lobby$)`.
  When an ID has outlines whose debug name (braces stripped) ends in `_new`, only those outlines are kept.
- Smallest polygon area wins. Ties keep the generated order.
- Card label = parent chain, top first, upper case, joined by `" · "`. The title is the area name; the description is
  optional (custom areas only).
- Custom names, descriptions and keys must not contain `|`, `;` or `"`. gen.py rejects them.
- Coordinates are emitted with 1 decimal. Each generated chunk string is at most 8000 characters.
- Don't start a soak campaign without asking the user first, and check `ps` for Cyberpunk2077.exe right before
  launching (memory: soak-ask-before-running).
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. Focus over stacked same-place outlines (Totentanz has 4, Afterlife 2): the name must not flicker while panning
   inside. Pinned by `areas.same_name_stack` in Task 4.
2. An area whose TweakDB name is empty or missing (e.g. Dogtown without Phantom Liberty) must fall through to the next
   larger area, never show a blank card. Pinned by `areas.empty_name_falls_through` in Task 4.
3. A selected marker must hide the area card, and moving the focus off the marker must bring the card back. Pinned by
   the soak steps `focus_ft far` → `area` expect `^marker$`, then `focus_empty` → `area` expect an area (Task 6).
   Selection only changes in the relaid branch, and a removed item bumps `api.revision`, so both paths refresh.
4. Focus outside every outline, e.g. (-6000, 4000), must give an empty sidebar, not the last area. Pinned by
   `areas.outside_is_none` (Task 4) and the soak step (Task 6).
5. Polygons that are concave, or wind clockwise or counter-clockwise, must hit-test the same. Pinned by
   `test_polygon_area_winding` (Task 3) and `areas.concave_notch` (Task 4).

---

### Task 1: Sector scan to outlines

**Files:**
- Create: `tools/areas/__init__.py` (empty), `tools/areas/scan.py`, `tools/areas/test_scan.py`,
  `tools/areas/fixtures/sector_min.json`

**Interfaces:**
- Produces:
  - `decode_outline(outline: dict) -> list[tuple[float, float, float]]`
  - `world_polygon(pts: list[tuple[float, float, float]], transform: dict, scale: dict) -> list[tuple[float, float]]`
  - `outlines_from_sector(doc: dict, sector: str) -> list[dict]`. Rows are
    `{"id": str, "node": str, "debug": str, "sector": str, "poly": [[x, y], ...]}`.
  - CLI `python3 tools/areas/scan.py [--game ~/cyberpunk_symlink] [--work ~/.cache/nightmap-sectors]` writes
    `<work>/areas/outlines.json`, a JSON list of those rows.

- [ ] **Step 1: Write the fixture and the failing tests**

  `fixtures/sector_min.json` is a hand-made WK10-style sector. It has `Data.RootChunk.nodes` with one
  `worldLocationAreaNode`: debugName `{test_loc_area}`, one `worldLocationAreaNotifier` with districtID
  `Districts.Kabuki`, and an outline whose stale `points` is the unit square. Its `buffer` is base64 of
  `struct.pack("<I12f", 3, 0,0,0,1, 1,0,0,1, 0,1,0,1)`. `nodeData` has one entry: `nodeIdx: "0"`,
  `scale {X: 10, Y: 20, Z: 1}`, `transform.position {X: 100, Y: 200, Z: 0}` and
  `transform.orientation {i: 0, j: 0, k: 0.70710678, r: 0.70710678}` (90° yaw).

  ```python
  def test_decode_prefers_buffer():
      o = load_fixture()["Data"]["RootChunk"]["nodes"][0]["Data"]["outline"]["Data"]
      assert decode_outline(o) == [(0, 0, 0), (1, 0, 0), (0, 1, 0)]

  def test_world_polygon_scale_rotate_offset():
      poly = world_polygon([(1, 0, 0), (0, 1, 0)], {"position": {"X": 100, "Y": 200, "Z": 0},
                           "orientation": {"i": 0, "j": 0, "k": 0.70710678, "r": 0.70710678}}, {"X": 10, "Y": 20, "Z": 1})
      assert poly == pytest.approx([(100, 210), (80, 200)], abs=1e-3)   # (10,0)->(0,10); (0,20)->(-20,0)

  def test_outlines_from_sector():
      rows = outlines_from_sector(load_fixture(), "fixture")
      assert [(r["id"], r["debug"], len(r["poly"])) for r in rows] == [("Districts.Kabuki", "{test_loc_area}", 3)]
  ```

- [ ] **Step 2: Run them and see them fail**

  Run: `python3 -m pytest tools/areas/test_scan.py -q`. Expected: ImportError / FAIL.

- [ ] **Step 3: Implement `scan.py`**

  Model it on `tools/collectibles/scan.py`, reusing its `--work` layout. Extract to `<work>/raw` only if it holds no
  `.streamingsector` yet, using regex `^(?!.*navigation_).*\.streamingsector$` on
  `basegame_3_nightcity.archive` and `ep1/ep1_1_nightcity.archive`. Keep only files whose bytes contain
  `b"worldLocationAreaNotifier"`. Symlink them under unique names (path with `/` replaced by `__`) into one temp dir
  and convert in one call. nodeData keys: `nodeIdx` (string) or `NodeIndex`; `transform` or
  `Position`/`Orientation`; `scale` or `Scale`. A node can have several nodeData entries: emit one row per entry.

- [ ] **Step 4: Run the tests and see them pass**

  Run: `python3 -m pytest tools/areas/test_scan.py -q`. Expected: 3 passed.

- [ ] **Step 5: Run the real scan**

  Run: `python3 tools/areas/scan.py`. Expected: it prints about 117 sectors and 205 outlines, and
  `~/.cache/nightmap-sectors/areas/outlines.json` exists. (The 2026-11-05 survey output in
  `.scratch/districts/districts.json` must match in count.)

- [ ] **Step 6: Commit** `tools/areas/` with message `feat(areas): scan the game's area outlines from world sectors`.

### Task 2: Landfill outline

**Files:**
- Create: `tools/areas/hull.py`, `tools/areas/test_hull.py`, `tools/areas/custom_areas.json`

**Interfaces:**
- Consumes: Task 1's `world_polygon`, and the raw sector dir `<work>/raw`.
- Produces:
  - `convex_hull(pts: list[tuple[float, float]]) -> list[tuple[float, float]]`, counter-clockwise, no repeated
    first point.
  - `custom_areas.json`:
    `[{"key": "Landfill", "name": "Landfill", "parent": "Districts.RedPeaks", "desc": "", "poly": [[x, y], ...]}]`.

- [ ] **Step 1: Write the failing tests**

  ```python
  def test_hull_square_drops_inner_and_collinear():
      pts = [(0, 0), (2, 0), (1, 0), (2, 2), (0, 2), (1, 1)]
      assert convex_hull(pts) == [(0, 0), (2, 0), (2, 2), (0, 2)]

  def test_hull_degenerate():
      assert convex_hull([(1, 1)]) == [(1, 1)]
  ```

- [ ] **Step 2: Run them and see them fail**: `python3 -m pytest tools/areas/test_hull.py -q`.
- [ ] **Step 3: Implement `convex_hull`** (Andrew's monotone chain) **and the CLI**

  CLI: `hull.py --match landfill_pile [--work ...]`. It takes sectors whose bytes contain the match, converts them
  (WK10), and collects the world position (`transform.position` X/Y) of every node whose debugName contains the match.
  It prints the hull as JSON, the point count, the centroid and the area in km². It writes nothing.
- [ ] **Step 4: Run the tests and see them pass**: 2 passed.
- [ ] **Step 5: Derive and write the Landfill polygon**

  Run `python3 tools/areas/hull.py --match landfill_pile`. Put the printed hull into `custom_areas.json` with the
  values in Interfaces. Record the printed centroid in the JSON as `"probe": [x, y]`. Task 6 focuses there, and
  gen.py ignores the field.
- [ ] **Step 6: Commit** with message `feat(areas): hand-made Landfill outline from the landfill prefabs`.

### Task 3: Generator and preview

**Files:**
- Create: `tools/areas/gen.py`, `tools/areas/test_gen.py`
- Create (generated): `r6/scripts/OverlayMap/Generated/AreaData.reds`

**Interfaces:**
- Consumes: Task 1's `outlines.json` rows; Task 2's `custom_areas.json`.
- Produces:
  - `@dataclass Area(key: str, name: str, parent: str, desc: str, poly: list[tuple[float, float]])`, with property
    `size` (absolute shoelace area).
  - `polygon_area(poly) -> float`
  - `keep_id(id: str) -> bool`
  - `game_areas(rows: list[dict]) -> list[Area]`. Applies the drop rules and the `_new` rule. Game areas have
    `name=""`, `parent=""` and `desc=""`.
  - `merge(game: list[Area], custom: list[Area]) -> list[Area]`, sorted by `size` ascending.
  - `emit(areas: list[Area]) -> str`
  - CLI `gen.py [--outlines ~/.cache/nightmap-sectors/areas/outlines.json] [--custom tools/areas/custom_areas.json]
    [--out r6/scripts/OverlayMap/Generated/AreaData.reds] [--preview PNG]`
  - The generated class:
    `public abstract class NMAreaData { static Count() -> Int32; static Chunks() -> Int32; static Chunk(index: Int32) -> String }`.
    An entry is `key|name|parent|desc|x1,y1,x2,y2,...`, entries are joined by `;`, and the file header comment
    states this.

- [ ] **Step 1: Write the failing tests**

  ```python
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
      # `row` builds a 3-point outline row; exactly one Coastview survives (the _new one)

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
  ```

- [ ] **Step 2: Run them and see them fail**: `python3 -m pytest tools/areas/test_gen.py -q`.
- [ ] **Step 3: Implement `gen.py`**

  Follow `tools/collectibles/gen.py`. Chunking packs entries until adding the next one would pass 8000 characters.
  `--preview` draws every outline (labelled with the key, minus `Districts.`) over the L4 tiles. The L4 tiles are
  `tools/tiles/build/png/{bfill,road}_L4_t_{a}_{b}.png`: 8 m/px, origin x -8192, top 8192, 512 px tiles, column a,
  row b, layered by alpha. The prototype is
  `/tmp/claude-1000/-home-pdp-nightmap/5a96d696-91bb-429b-93f4-4aa3e48944e7/scratchpad/districts_render.py`. The
  CLI prints the total count, the custom count and every pair of areas whose overlap is above 0.05 km², measured on a
  40 m grid sample.
- [ ] **Step 4: Run the tests and see them pass**: 6 passed.
- [ ] **Step 5: Generate and review**

  Run `python3 tools/areas/gen.py --preview /tmp/claude-1000/-home-pdp-nightmap/5a96d696-91bb-429b-93f4-4aa3e48944e7/scratchpad/areas_preview.png`.
  Expected:
  - About 100 areas, 1 of them custom.
  - No overlap pair involving Coastview and Dogtown above 0.05 km².
  - The Landfill outline sits east of the city inside Red Peaks, on the preview.

  Run `tools/check.sh`. Expected: `COMPILE OK`.
- [ ] **Step 6: Commit** `tools/areas/gen.py tools/areas/test_gen.py r6/scripts/OverlayMap/Generated/AreaData.reds`
  with message `feat(areas): generate the area data`.

### Task 4: Runtime area index

**Files:**
- Create: `r6/scripts/OverlayMap/Areas/Areas.reds`, `r6/scripts/OverlayMap/Debug/SelfTestAreas.reds`
- Modify: `r6/scripts/OverlayMap/Debug/SelfTest.reds` (add `NMAreaTests.Run(this);` after `NMWaypointTests.Run(this);`)

**Interfaces:**
- Consumes: `NMAreaData.Count/Chunks/Chunk` (Task 3).
- Produces (module `OverlayMap`):
  - `public class NMArea { public let key: String; public let name: String; public let parent: String; public let desc: String; public let minX: Float; public let minY: Float; public let maxX: Float; public let maxY: Float; public let xs: array<Float>; public let ys: array<Float>; }`
  - `public class NMAreaIndex`:
    - `static func Parse(chunks: array<String>) -> ref<NMAreaIndex>`
    - `static func Load() -> ref<NMAreaIndex>` (from `NMAreaData`)
    - `func Count() -> Int32`
    - `func At(x: Float, y: Float) -> Int32`: the first area in data order whose bbox and even-odd test contain the
      point and whose `Title` is non-empty; -1 if none.
    - `func Title(i: Int32) -> String`: the custom name, else the localized TweakDB name; cached per index.
    - `func Label(i: Int32) -> String`
    - `func Desc(i: Int32) -> String`
    - `static func Contains(a: ref<NMArea>, x: Float, y: Float) -> Bool`
    - `static func DistrictName(id: String) -> String`: `GetLocalizedText(TweakDBInterface.GetDistrictRecord(TDBID.Create(id)).LocalizedName())`,
      or "" when the record is undefined.
  - For a game area, `Label` walks `ParentDistrict()` from the area's own record. For a custom area it walks from the
    `parent` record, included. Names are upper case, top first, joined by `" · "`, and empty names are skipped.
    Example: Landfill gives `BADLANDS · RED PEAKS`.

- [ ] **Step 1: Write the failing self-tests** in `SelfTestAreas.reds` (`public abstract class NMAreaTests { public static func Run(t: ref<NMSelfTest>) }`)

  The fixture chunks are custom-style entries, so no TweakDB is needed. They are in smallest-first order, as gen.py
  emits them:
  - `"Tot|Tot|||301,301,309,301,309,309,301,309"` (inner)
  - `"Tot|Tot|||300,300,310,300,310,310,300,310"` (outer)
  - `"Small|Small|||0,0,10,0,10,10,0,10"`
  - `"Blank||||200,200,210,200,210,210,200,210"` (empty title)
  - `"Notch|Notch|||0,0,100,0,100,100,60,100,60,40,40,40,40,100,0,100"` (a U shape)
  - `"Big|Big|||-500,-500,500,-500,500,500,-500,500"`

  Checks:
  - `areas.parse_count`: Count() == 6.
  - `areas.smallest_wins`: At(5, 5) == 2 (Small, not Notch or Big).
  - `areas.concave_notch`: At(50, 80) == 5 (Big: inside the notch, outside Notch), and At(20, 80) == 4 (Notch).
  - `areas.empty_name_falls_through`: At(205, 205) == 5 (Big, skipping Blank).
  - `areas.same_name_stack`: At(305, 305) == 0, At(300.5, 300.5) == 1, and both titles are "Tot".
  - `areas.outside_is_none`: At(900, 900) == -1.
  - `areas.real_data`:
    - Load().Count() == NMAreaData.Count() and > 50.
    - At(-6000, 4000) == -1.
    - Title(At(-1431.6, 997.0)) (Afterlife) and Title(At(-373.8, 1038.6)) (Japantown) are both non-empty and
      differ.
  - `areas.landfill`: Title(At(<probe from custom_areas.json>)) == "Landfill" and
    `StrContains(Label(...), " · ")`.
- [ ] **Step 2: Compile and see them fail**: `tools/check.sh`. Expected: an error that `NMAreaIndex` is undefined.
- [ ] **Step 3: Implement `Areas.reds`**

  Parse: split chunks on `;`, then fields on `|`, then the coordinate list on `,` with `StringToFloat`. Compute the
  bbox at parse time.
- [ ] **Step 4: Compile**: `tools/check.sh`. Expected: `COMPILE OK`. (The tests themselves run in game, in Task 6.)
- [ ] **Step 5: Commit** with message `feat(areas): runtime area index with smallest-first lookup`.

### Task 5: Sidebar area card

**Files:**
- Modify: `r6/scripts/OverlayMap/Core/OverlayMapSystem.reds`. Fields go near `tipApiRev` (line ~95), the relaid branch
  is at ~1116-1128 and `RefreshSidebar` is at ~1186.
- Modify: `tools/soak/autopilot/SoakHooks.reds`, `tools/soak/autopilot/SystemBody.inc`

**Interfaces:**
- Consumes: `NMAreaIndex.Load/At/Title/Label/Desc` (Task 4); `OverlayMapDetails.Create(category, title).WithDescription(s)`;
  `NMTooltip.ShowDetails(d, color)`; `NMTheme.Cyan()`.
- Produces:
  - System fields `private let areas: ref<NMAreaIndex>;` and `private let areaAt: Int32;`. `areaAt` is reset to -1
    wherever `tipApiRev = -1` is reset on open (line ~961).
  - `private func AreaAtFocus() -> Int32`: loads `areas` lazily, then returns `areas.At(this.camera.cx, this.camera.cy)`.
  - Soak commands:
    - `area` reports what the card shows: `"marker"` when a marker or photo is selected, else
      `"area|<label>|<title>"` for `areaAt`, else `"none"`.
    - `area_names` logs `AREA|<key>|<label>|<title>` per area and returns `"areas <count>"`.

- [ ] **Step 1: Wire the lookup.** In the relaid branch, compute `let a = this.AreaAtFocus();` before the refresh test.
  Refresh when `changed || a != this.areaAt || this.api.revision != this.tipApiRev`, and set `this.areaAt = a` inside.
- [ ] **Step 2: Show the card.** In `RefreshSidebar`'s final `else` branch (no selected marker), call `drawer.Hide()`.
  Then, if `areaAt >= 0`, call `tooltip.ShowDetails(OverlayMapDetails.Create(Label, Title).WithDescription(Desc), NMTheme.Cyan())`;
  otherwise `tooltip.Hide()`. The photo and marker branches stay as they are.
- [ ] **Step 3: Add the soak commands** (`Soak_Area`, `Soak_AreaNames` in `SystemBody.inc`; dispatch in `SoakHooks.reds`
  next to `"selected"`).
- [ ] **Step 4: Compile both builds**: `tools/check.sh` and `tools/check.sh --soak`. Expected: `COMPILE OK` twice.
- [ ] **Step 5: Commit** with message `feat(areas): name the area under the focus in the sidebar`.

### Task 6: In-game verification and docs

**Files:**
- Create: `tools/soak/plans/areas.json`
- Modify: `README.md` (the features section and the data-regeneration commands next to the collectibles ones)

- [ ] **Step 1: Write the soak plan.** It has one run with parts `scripts`, `archive`, `bootstrap`, `autopilot` and
  expect `{"log": "TEST\\|SUMMARY\\|passed=\\d+\\|failed=0"}`. Steps, each followed by `{"wait": 3}`:
  1. `selftest`
  2. `open`
  3. `area_names`, expect `^areas \d+`
  4. `focus_empty <Landfill probe> 4`
  5. `area`, expect `^area\|.* · .*\|Landfill$`
  6. `focus_empty -373.8 1038.6 4`, then `area`, expect `^area\|.+\|.+` (Japantown, localized)
  7. `focus_ft far`, then `area`, expect `^marker$`
  8. `focus_empty -373.8 1038.6 4`, then `area`, expect `^area\|` (the card returns once the focus leaves the marker)
  9. `focus_at -6000 4000 4`, then `area`, expect `^none$`
  10. `shot` `landfill`, after re-focusing the probe
- [ ] **Step 2: Ask the user before running it** (Global Constraints), then run
  `python3 tools/soak/soak.py campaign tools/soak/plans/areas.json --save <their save> --allow-cloud`.
  Expected: `.soak/results/areas/report.md` all passed, `failed=0`.
- [ ] **Step 3: Review the names.** Read the `AREA|` lines in the campaign log, and list any area whose title is empty
  or odd (e.g. apartment records). If one should be hidden, add its ID to `keep_id`'s drop pattern, rerun Task 3
  Step 5, and add the ID to `test_keep_id`.
- [ ] **Step 4: Document.** In the README, add one feature line ("With no marker selected, the sidebar names the area
  under the cursor; game areas are localized") and the regeneration commands
  `python3 tools/areas/scan.py` and `python3 tools/areas/gen.py`.
- [ ] **Step 5: Commit** with message `test(areas): soak plan and docs for area names`.
