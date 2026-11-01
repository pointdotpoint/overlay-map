# NightMap Visual Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A hologram map where markers and roads read first. It gets a brightness ladder, dot-matrix buildings,
vanilla icons on dark plates, a restyled frame, and tiered scale-and-hide in place of clustering.

**Architecture:**
- **Tile build.** The build gains two road sets (`road_minor`, `road_major`) in place of `road`. Dots are baked into
  `bfill`. Glow is taken from the roads.
- **Atlas.** The UI and holo atlases gain the plate, the new chip, dots, rings and vignette parts. Cluster parts go
  away.
- **Runtime.** Each layer gets a tier (Always / Major / Minor). A pure `NMTiers` maps tier and zoom to fade and
  scale, and the renderer draws individual pins only.
- **Frame.** Panel, sidebar card and hint bar are restyled in place. Layout geometry is unchanged.

**Tech Stack:**
- redscript + Codeware (ink)
- Python 3 build in `tools/tiles` (numpy, Pillow, scipy, shapely; pytest)
- soak harness `tools/soak`

**Spec:** `docs/superpowers/specs/2026-11-01-nightmap-visual-overhaul-design.md` (mockups in
`docs/superpowers/specs/2026-11-01-visual-overhaul/`)

## Global Constraints

- No new runtime dependency: redscript, Codeware, Mod Settings only (RedIMGRetriever stays optional).
- Vanilla icon artwork and colours are unchanged: `NMTheme.VanillaStateColor`, mappin atlas parts, idle 50 %,
  emphasised 1.3×.
- Panel layout geometry is unchanged (`NMPanelLayout.Compute`: 90 % × 71.1 %, sidebar 25 %, hint height 110 × scale).
- Every existing feature keeps working. Clustering is the only deliberate removal.
- No frame-time regression in `NMPerfSuite` against main, within noise.
- `hologramEffects` off: no scanlines, glow, bar, noise, edge glow, dot grid, range rings or vignette. The ladder,
  dot-matrix buildings, plates and frame stay.
- Green theme (`holoColor` Green) mirrors every new Cyan token in green.
- Public API stays source-compatible: `NightMapLayer.SetClustering(enabled: Bool)` compiles and is ignored.
- No text labels on the map.
- Starting colour values (spec §4.1; tune in-game):
  - background `#0a1a2c` → `#02050a`
  - bfill `#123a5e` (fill) / `#4aa8ff` (dots)
  - outline `#3a8fd0` @ .40
  - minor roads `#2a86d8` @ .60
  - major roads `#8fdcff` @ .90
  - glow `#2f9cff` @ .50
  - scanlines black @ .14
  - map background opacity .92
- Rebuilding tiles needs the game install at `~/cyberpunk_symlink`. Install only while the game is closed.
- Full check before each commit that touches redscript: `tools/check.sh` compiles.
- Full Python check: `(cd tools && python3 -m pytest -q) && (cd tools/tiles && python3 -m pytest -q)`.

## Review Focus

- **Filter switched while zoomed out:** under JOBS or SERVICES, gigs and vendors appear at once at far zoom with no
  stale chips. Test `tier.filter_promotes_now` (Task 5).
- **Tracked quest at maximum zoom-out:** the pinned marker and the route stay fully visible at `MaxMpp()`. Test
  `tier.always_at_max` (Task 5).
- **Hovered marker fades out while zooming:** the sidebar card hides once the marker is gone, and a fully hidden pin is
  never picked. Test `render.faded_not_candidate` (Task 6).
- **Collected collectibles** keep the strike and dim on the new hex chip. Test `chip.struck_on_hex` (Task 7).
- **Effects off** still draws the dark plate (not a bare icon, not the old halo). Test `plate.effects_off` (Task 7).

---

### Task 1: Road classes in the tile build

**Files:**
- Modify: `tools/tiles/nmtiles/minimap.py`
  - `classify` gains a width return
  - `decode_sector` / `load_city` keep major and minor road triangles apart
  - bump `DECODE_VERSION`
- Modify: `tools/tiles/nmtiles/render_minimap.py`
  - `SETS = ("glow", "bfill", "outline", "road_minor", "road_major")`
  - `TileSources` gains `road_major: TriIndex`
  - `render_tile` renders both road masks
  - `_glow` is built from roads only (see Step 3)
- Modify: `tools/tiles/nmtiles/build.py`, `style.py` (`PREVIEW_SETS`), `holo_preview.py` (`SETS`), `footprints.py`
  (the footprint key hashes both road arrays)
- Test: `tools/tiles/tests/test_minimap.py`, `test_render_minimap.py`, `test_holo_preview.py`

**Interfaces:**
- Produces:
  - `classify_width(tris: np.ndarray) -> float` (metres: area / max bbox extent, today's `thick`)
  - `MAJOR_WIDTH_M: float = 12.0` (starting value)
  - `TileSources(road: TriIndex, road_major: TriIndex, foot: TriIndex, polys)`
  - Tile set names `road_minor` and `road_major` in the manifest
  - `NMTileManifest.SetName` order: 0 glow, 1 bfill, 2 outline, 3 road_minor, 4 road_major. This is the draw order:
    roads go over buildings.

- [ ] **Step 1: Write failing tests**
  - `test_classify_width_wide_vs_narrow`: a 40×20 m rectangle → ~20.0; a 40×6 m rectangle → ~6.0 (±0.5).
  - `test_sets_order`: `SETS == ("glow", "bfill", "outline", "road_minor", "road_major")`. Replaces the 4-set
    assertion at `test_render_minimap.py:28`.
  - `test_render_tile_splits_roads`: given a `TileSources` with one wide road (20 m) and one narrow road (6 m), the
    tile has alpha only in the wide road's pixels for `road_major` and only in the narrow one's for `road_minor`.
  - `test_glow_from_roads_only`: a tile with buildings and no roads has an empty glow.
- [ ] **Step 2:** Run `cd tools/tiles && python3 -m pytest tests/test_minimap.py tests/test_render_minimap.py -q`.
  Expect FAIL.
- [ ] **Step 3: Implement**
  - A shape is major when `classify_width >= MAJOR_WIDTH_M`.
  - `_glow(major, minor, gain)` = blur of `major` at full gain plus `minor` at 0.35. The building outline no longer
    feeds glow.
  - Update `holo_preview.py` and `style.PREVIEW_SETS` so previews draw both road sets: minor `#2a86d8`, major
    `#8fdcff`, drawn in this order.
- [ ] **Step 4:** Run the full Python check. Expect PASS.
- [ ] **Step 5: Calibrate (slow, needs the game)**
  - Run `cd tools/tiles && python3 -m nmtiles.build --game ~/cyberpunk_symlink` and open
    `build/preview_minimap_mid.png`.
  - Arterials and highways must be major, and side streets minor. In the City Center crop, roughly 60 % of road area
    should be major, like `map-look.jpg`. Adjust `MAJOR_WIDTH_M` until it is.
  - If merged road shapes make the per-shape width meaningless (whole blocks come out major), switch to a raster split
    on the L0 road mask (erode 6 px / dilate 8 px at 0.5 m/px), downsampled per level. Record which method was used in
    the commit message.
- [ ] **Step 6: Commit** `feat(tiles): split roads into major and minor sets`

### Task 2: Dot-matrix building fill

**Files:**
- Modify: `tools/tiles/nmtiles/render_minimap.py` (bfill composition)
- Test: `tools/tiles/tests/test_render_minimap.py`

**Interfaces:**
- Produces:
  - `DOT_PITCH_PX = 8`, `DOT_SIZE_PX = 3`, `FILL_BASE = 0.45`
  - `dot_pattern(ix: int, iy: int, size: int) -> np.ndarray` (float 0..1, anchored to the global pixel grid
    `ix*size + x`, rows staggered by half a pitch)
  - bfill alpha = `fill_mask * (FILL_BASE + (1 - FILL_BASE) * dots)`

- [ ] **Step 1: Write failing tests**
  - `test_dot_pattern_is_seamless`: the column after the right edge of tile (0, 0) equals column 0 of tile (1, 0).
    Compare `dot_pattern(0, 0, 520)[:, 512]` with `dot_pattern(1, 0, 512)[:, 0]`.
  - `test_dot_pattern_pitch`: row 0 has dots at x ≡ 0..2 (mod 8). Row 8 (the next dot row) is offset by 4.
  - `test_bfill_has_floor_and_dots`: the alpha of a fully covered tile has min ≈ 0.45 × 255 and max = 255.
- [ ] **Step 2:** Run the tests. Expect FAIL.
- [ ] **Step 3:** Implement `dot_pattern` and apply it in `render_tile` to bfill only.
- [ ] **Step 4:** Run the full Python check. Expect PASS. Rebuild and check `preview_minimap_close/mid/far.png`: dots
  are visible at every level, and the far level isn't turned into mush. If L5 moirés, raise the floor for L4–L5 only
  (`FILL_BASE` 0.7) and note it in the commit.
- [ ] **Step 5: Commit** `feat(tiles): bake dot matrix into building fill`

### Task 3: Atlas art

**Files:**
- Modify: `tools/tiles/nmtiles/ui_atlas.py`, `tools/tiles/nmtiles/holo_atlas.py`
- Test: `tools/tiles/tests/test_ui_atlas.py`, `tools/tiles/tests/test_holo_atlas.py`

**Interfaces:**
- Produces UI parts (4K-unit sizes in `SIZES`):
  - `plate` (224): a near-black disc to 0.5 of the radius (RGB ≤ 10, alpha ≈ 235), a soft dark falloff to the edge, and
    a white 4 px ring at 0.5 of the radius. One image, tinted with the icon colour at runtime: the ring takes the
    colour and the disc stays near black.
  - `chip` (redrawn, 72): a pointy-top hex with a near-black fill (RGB ≤ 10, alpha ≈ 225) and a white 4 px outline.
  - `icon_dot` (redrawn, 24): a solid disc.
  - `bracket_tl/tr/bl/br` (redrawn): 3 px L-strokes with a 6 px soft glow.
- Removes: `cluster`, `cluster_sel`, `mini`.
- Produces holo parts:
  - `holo_dots` (48×48 tile): a 2×2 px dot at a 24 px pitch, white. Replaces `holo_grid`, keeping the name
    `holo_grid` so `NMHolo.AddGrid` needs no rename.
  - `holo_rings` (512×512): four concentric white rings at radii 64, 128, 192, 248, 2 px.
  - `holo_vignette` (256×256): radial alpha 0 at the centre to 1 at the corners.

- [ ] **Step 1: Write failing tests**
  - `test_plate_ring_white_disc_dark`: centre pixel RGB ≤ 10 with alpha > 200; pixel at 0.5R RGB ≥ 240.
  - `test_chip_dark_fill_white_edge`: centre RGB ≤ 10; a pixel on the edge RGB ≥ 240.
  - `test_cluster_parts_removed`: `"cluster" not in SIZES`.
  - `test_holo_grid_is_dot_grid`: alpha > 0 at (0, 0) and 0 at (12, 12).
  - `test_rings_have_four_circles`: a horizontal scan through the centre crosses 8 alpha peaks.
  - Update the existing size, overlap and determinism tests to the new parts.
- [ ] **Step 2:** Run the tests. Expect FAIL.
- [ ] **Step 3:** Implement the parts in the existing helper style (`_hex`, `_glow`, `_ring`). Keep both atlases at
  their current page size.
- [ ] **Step 4:** Run the full Python check. Expect PASS.
- [ ] **Step 5: Commit** `feat(atlas): plates, new chip, dot grid, rings, vignette`

### Task 4: Runtime theme, tile sets and hologram overlays

**Files:**
- Modify: `r6/scripts/NightMap/Core/Theme.reds`, `r6/scripts/NightMap/Render/Holo.reds`,
  `r6/scripts/NightMap/Render/Panel.reds` (overlay z-order), `r6/scripts/NightMap/Render/PlayerMarker.reds` (rings)
- Test: `r6/scripts/NightMap/Debug/SelfTest.reds` (`TileCases`), `Debug/SelfTestHolo.reds`

**Interfaces:**
- Consumes: set names from Task 1, holo parts from Task 3.
- Produces:
  - `NMTheme.TileTint(set, theme)` / `TileOpacity(set)` for `glow`, `bfill`, `outline`, `road_minor` and `road_major`.
    Cyan values come from the Global Constraints; Green uses the same lightness in hue ~140°.
  - `NMTheme.HoloBackground(theme)`, with Cyan `#050d18`.
  - `NMTheme.HoloScanOpacity() = 0.14`
  - `NMTheme.HoloGridOpacity() = 0.08`
  - `NMTheme.RingsOpacity() = 0.10`
  - `NMTheme.VignetteOpacity() = 0.55`
  - `NMHolo.AddVignette(parent)`: a stretched `holo_vignette` over the tiles, under the routes; effects only.
  - Scanlines move above the items, under the overlay canvas. The spec puts them over the whole map, markers
    included. The noise stays where it is, under the markers.
  - `NMPlayerMarker` owns an optional `rings: ref<inkImage>` (`holo_rings`, 1440 4K units across, accent colour),
    moved with the arrow and created only with effects on.

- [ ] **Step 1: Write failing tests**
  - `tiles.five_sets_order`: `SetCount() == 5`, `SetName(3) == "road_minor"`, `SetName(4) == "road_major"`. Replaces
    `tiles.six_levels_four_sets`. Retarget the `SetIndex("road")` checks at `SelfTest.reds:592,611,637` to
    `"road_major"`.
  - `holo.effects_off_drops_glow_layer`: with effects off, `LayerCount() == 4`; with effects on, 5.
  - `theme.roads_brighter_than_buildings`: the luminance of `TileTint("road_major", 0)` × its opacity is greater than
    `bfill`'s, which is greater than `outline`'s. The same holds for theme 1.
  - `holo.rings_follow_player` (effects on): after `PlayerMarker.Update` the ring translation equals the arrow's.
- [ ] **Step 2:** Run `tools/check.sh`, then build the tiles and install them (`tools/install.sh`, game closed). Run
  `python3 tools/soak/soak.py campaign tools/soak/plans/render.json --save QuickSave-7 --allow-cloud`. Expect the new
  tests to FAIL, or fail to compile before Step 3.
- [ ] **Step 3: Implement**
  - Draw order comes from the manifest, so no stack code changes beyond the names.
  - The vignette and rings are inserted in `NMPanel.Build` next to the existing `AddScan` / `AddBar`.
- [ ] **Step 4:** Re-run check, install and the `render.json` campaign. Expect all `tiles.*`, `holo.*` and `theme.*`
  to PASS. Screenshots from the run should match the ladder in `map-look.jpg`: roads over buildings, dots visible.
- [ ] **Step 5: Commit** `feat(render): brightness ladder, dot grid, rings and vignette`

### Task 5: Tier model

**Files:**
- Create: `r6/scripts/NightMap/Render/Tiers.reds`
- Modify:
  - `r6/scripts/NightMap/Api/NightMapLayer.reds`
  - `r6/scripts/NightMap/Vanilla/Vanilla.reds` (assign tiers; promote in `ApplyFilters`)
  - `r6/scripts/NightMap/Collect/Collect.reds` and `r6/scripts/NightMap/Photos/Photos.reds` (Minor)
  - `docs/api.md`
- Test: create `r6/scripts/NightMap/Debug/SelfTestTiers.reds` (`NMTierTests.Run(t)`, registered in `NMSelfTest.Run`)

**Interfaces:**
- Produces:
  - `public enum NightMapTier { Always = 0, Major = 1, Minor = 2 }` in `Api/NightMapLayer.reds`
  - `NightMapLayer.tier: Int32 = 2`, `NightMapLayer.promoted: Bool`
  - `NightMapLayer.SetTier(t: NightMapTier)` and `NightMapLayer.SetPromoted(on: Bool)`, both `Touch()`
  - `NightMapLayer.EffectiveTier() -> Int32` = `promoted ? Min(tier, 1) : tier`
  - `NMTiers.Fade(tier: Int32, mpp: Float) -> Float` (0..1)
  - `NMTiers.Scale(tier: Int32, mpp: Float) -> Float`
  - Starting thresholds, as static funcs on `NMTiers`:
    - Scale is 1.0 at mpp ≤ 2 and falls (linear in log2 mpp) to 0.7 at mpp ≥ 8. Always-tier scale is 1.0.
    - Minor: fade 1 at ≤ 4, 0 at ≥ 6.
    - Major: fade 1 at ≤ 24, 0 at ≥ 32, so it stays visible across the whole zoom range (max 16) until tuned.
    - Always: fade 1.
- Tier assignment:
  - Vanilla pinned layer (`Vanilla.Pinned`): Always.
  - Vanilla layers whose `catalog.TypeOf(i)` is `Quest` or `FastTravel`: Major.
  - Every other vanilla layer, collectibles, photos and third-party layers: Minor.
  - `ApplyFilters(view, s)` sets `SetPromoted(view != 0 && NMVanillaFilters.InView(view, type, isOther))` on each
    vanilla layer.
  - Collectibles have no view of their own and stay unpromoted.

- [ ] **Step 1: Write failing tests**
  - `tier.minor_fades`: `Fade(2, 4.0) == 1`, `Fade(2, 5.0) ≈ 0.5`, `Fade(2, 6.0) == 0`.
  - `tier.major_stays`: `Fade(1, 16.0) == 1`.
  - `tier.always_at_max`: `Fade(0, NightMapSystem.MaxMpp()) == 1` and `Scale(0, 16.0) == 1`.
  - `tier.scale_shrinks`: `Scale(2, 2.0) == 1`, `Scale(2, 8.0) ≈ 0.7`, `Scale(1, 4.0) ≈ 0.85` (±0.01).
  - `tier.promoted_effective`: a Minor layer with `SetPromoted(true)` has `EffectiveTier() == 1`; an Always layer stays
    0.
  - `tier.filter_promotes_now`: create a vanilla-like Minor layer, record `api.revision`, call `SetPromoted(true)`, and
    check the revision increased (relayout is forced).
  - `tier.vanilla_assignment`: after `EnsureLayers`, the Quest and FastTravel layers are tier 1, `Vanilla.Pinned` is
    0, and the Gigs layer is 2. After `ApplyFilters(1, s)` the Gigs layer is promoted. After `ApplyFilters(0, s)` it
    isn't.
- [ ] **Step 2:** Run `tools/check.sh`. Expect FAIL (undefined symbols).
- [ ] **Step 3:** Implement. Document `SetTier` in `docs/api.md` and mark `SetClustering` deprecated (ignored).
- [ ] **Step 4:** Run `tools/check.sh`, then the `render.json` campaign. Expect all `tier.*` to PASS.
- [ ] **Step 5: Commit** `feat(api): marker tiers with filter promotion`

### Task 6: Renderer without clustering

**Files:**
- Modify:
  - `r6/scripts/NightMap/Render/ItemRenderer.reds`
  - `r6/scripts/NightMap/Render/Crosshair.reds` (remove the cluster kind)
  - `r6/scripts/NightMap/Render/Tooltip.reds` (remove `ShowCluster`)
  - `r6/scripts/NightMap/Core/NightMapSystem.reds` (remove the cluster act / zoom-into-cluster and `ShowCluster`
    call sites near lines 1121–1137)
  - `r6/scripts/NightMap/Core/Theme.reds` (remove `ClusterSize`, `ClusterSelSize`, `ClusterBudget`, `ClusterSpacing`,
    `MiniSize`, `MiniOffsetY`, `MiniSpacing`)
- Test: `Debug/SelfTest.reds` (`RendererCases`, `PickCases`), `Debug/SelfTestPerf.reds`, `Debug/SelfTestCollect.reds`
  (rewrite cluster assertions as tier assertions; do not just delete them)

**Interfaces:**
- Consumes: `NightMapLayer.EffectiveTier()`, `NMTiers.Fade/Scale` (Task 5).
- Produces:
  - `NMItemRenderer.Update` places individual pins only.
  - Per layer: `f = NMTiers.Fade(L.EffectiveTier(), cam.mpp)`. If `f <= 0`, skip the layer. Otherwise place it.
    Layers with `count <= 64` use `PlaceAllOf`; larger ones use cell ring order (`PlaceCellsOf`, nearest first). The
    `clustering` flag no longer matters. The level-0 ring order is always built.
  - Placed opacity is multiplied by `f`. Size is multiplied by `NMTiers.Scale(...)` through the existing
    `SetScale` / `SetGrow` path, so emphasis grow composes with the tier scale.
  - `ChipBudget()` stays at 300 as the cap.

- [ ] **Step 1: Write failing tests**
  - `render.no_clusters_far`: a Minor layer of 2,000 items at mpp 16 places 0 chips. The same layer at mpp 2 places
    ≤ 300 chips, nearest-first.
  - `render.major_far`: a Major layer of 40 items at mpp 16 places 40 chips at `Scale(1, 16)`.
  - `render.faded_not_candidate`: at mpp 6.5 a Minor item at the view centre produces no candidate. At mpp 5 it does,
    with opacity ≈ 0.5 × base.
  - `render.hover_clears_on_fade`: select a Minor pin at mpp 3, zoom to mpp 7, run one frame. The selection is none
    and the tooltip is hidden.
  - Rewrite every existing check that asserts `clustersUsed`, a cluster tooltip, or a "Zoom" action in tier terms.
    List each renamed check in the commit body.
- [ ] **Step 2:** Run `tools/check.sh`. Expect the new tests to FAIL in the campaign.
- [ ] **Step 3:** Implement. Delete `PlaceClusters`, `PlaceCluster`, the cluster widget pools, `selCluster`,
  `clTotal`, and `CollectCells` if no longer used. `SetClustering` stays as a no-op that still sets the field.
- [ ] **Step 4:** Run check, install, and the `render.json` and `regression.json` campaigns. Expect all PASS. Zoom
  screenshots show no hex badges, and at the farthest zoom only quests, fast travel and the tracked marker.
- [ ] **Step 5: Commit** `feat(render): tiered scale-and-hide replaces clustering`

### Task 7: Plates, collectible chips, reticle and player

**Files:**
- Modify:
  - `r6/scripts/NightMap/Render/ItemRenderer.reds` (`ApplyChipStyle`, `BlobOpacity`, tints in `PlaceChip`)
  - `r6/scripts/NightMap/Collect/Collect.reds` (pin style Hex, icon `icon_dot`)
  - `r6/scripts/NightMap/Render/Reticle.reds`, `r6/scripts/NightMap/Render/PlayerMarker.reds`
  - `r6/scripts/NightMap/Core/Theme.reds`
- Test: `Debug/SelfTestVanilla.reds`, `Debug/SelfTestCollect.reds`, `Debug/SelfTestHolo.reds`

**Interfaces:**
- Consumes: atlas parts `plate`, `chip`, `icon_dot`, and the brackets (Task 3).
- Produces:
  - Icon style (1/2): the background is `UiAtlas` part `plate`, tinted with the **icon colour**, size
    `NMTheme.PlateSize() = 224` × emphasis × tier scale, opacity = icon alpha × `NMTheme.PlateOpacity() = 1.0`. This
    holds with effects on and off; the `halo` / shadow-blob branch is removed and `SetHalo` becomes a no-op.
  - Hex style (0): `chip` part tinted with the category colour, `NMTheme.ChipSize() = 72`,
    `NMTheme.IconSize() = 24`.
  - Collectible layers use `NightMapPinStyle.Hex` with category icon `icon_dot`.
  - Player arrow tint `VanillaStateColor(n"Player")`, glow unchanged.
  - Reticle brackets tinted `#d8f4ff`.

- [ ] **Step 1: Write failing tests**
  - `plate.effects_on` and `plate.effects_off`: in both modes an Icon-style slot's background part is `n"plate"` and
    its tint equals the icon tint.
  - `plate.scales_with_emphasis`: an emphasised pin's background is `PlateSize() * VanillaEmphScale() * scale` across.
  - `chip.collect_is_hex`: a collectible item places a style-0 slot with part `chip` and icon `icon_dot`.
  - `chip.struck_on_hex`: a struck collected item on a hex chip shows the strike widget with the chip's opacity.
- [ ] **Step 2:** Run `tools/check.sh` and the campaign. Expect FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run check, install, and the `render.json` and `collect.json` campaigns. Expect PASS. In the
  screenshots, blue fast-travel and teal gig icons read clearly against blue roads, as in `map-look.jpg`.
- [ ] **Step 5: Commit** `feat(markers): dark plates for vanilla icons, hex chips for collectibles`

### Task 8: Frame: panel, header, scale bar, outline

**Files:**
- Modify:
  - `r6/scripts/NightMap/Render/Panel.reds`
  - `r6/scripts/NightMap/Core/NightMapSystem.reds` (`UpdateHeader`, `UpdateScale`, settings load)
  - `r6/scripts/NightMap/Core/Theme.reds`
  - `r6/scripts/NightMap/Core/Settings.reds`
- Test: `Debug/SelfTest.reds` (`LayoutCases`)

**Interfaces:**
- Produces:
  - `NMPanel.districtTitle: ref<inkText>`: top-left at (44, 40) × 2 × scale, Bold, 68 × scale (4K), letter-spaced,
    `#e6f7ff`.
  - `NMPanel.districtSub: ref<inkText>`: under the title, Medium, 32 × scale, accent colour. It shows
    `"FILTER · " + ViewName` when the view isn't ALL, and is hidden otherwise. *(My call: no sub-district data exists;
    the filter view moves here from the old subtitle.)*
  - The old bottom-right `subtitle` is removed. The quest title and objective move to the sidebar (Task 9).
  - Scale bar: top-right of the view, at `viewW - 500 × scale`. It gets 2 px end ticks and the label centred under it.
  - Outline at 35 % `HoloHighlight`. Brackets from the new atlas art.
  - `NMTheme.DefaultPanelOpacity() = 0.92`; `NightMapSettings.panelOpacity` default `0.92`.
  - `NMTheme.MigratePanelOpacity(saved: Float) -> Float`: returns 0.92 when `AbsF(saved - 0.45) < 0.001`, else
    `saved`. The 0.02 slider step from 0.3 can't produce 0.45, so 0.45 only ever means the old default. On settings
    load the system writes the result back to `s.panelOpacity`.

- [ ] **Step 1: Write failing tests**
  - `layout.district_top_left`: the title translation is within the left 10 % of `viewW` and the top 10 % of `mapH`.
  - `settings.panel_opacity_migrates`: `MigratePanelOpacity(0.45) == 0.92`, `MigratePanelOpacity(0.6) == 0.6`,
    `MigratePanelOpacity(0.92) == 0.92`.
  - `layout.scale_bar_in_view`: the scale bar's right end is ≤ `viewW`.
- [ ] **Step 2:** Run `tools/check.sh` and the campaign. Expect FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run check and the campaign. Expect PASS. Compare a screenshot with `frame.jpg` (header, scale bar,
  outline).
- [ ] **Step 5: Commit** `feat(frame): opaque panel, district title, scale bar, outline`

### Task 9: Sidebar card and tracking block

**Files:**
- Modify:
  - `r6/scripts/NightMap/Render/Tooltip.reds`
  - `r6/scripts/NightMap/Render/PhotoDrawer.reds` (sidebar glass, empty state)
  - `r6/scripts/NightMap/Render/Panel.reds` (quest block moves into the sidebar bottom)
  - `r6/scripts/NightMap/Core/NightMapSystem.reds`
- Test: `Debug/SelfTest.reds` (`TooltipCases`)

**Interfaces:**
- Consumes: `NightMapDetails` (category, title, subtitle, description, rows, actions); plate part (Task 3).
- Produces:
  - Sidebar background: `rgba(3,9,18,.80)` fill, a 1.5 px left edge in `HoloHighlight` @ .55, and a 40 px inner
    gradient.
  - The tooltip card is laid out top to bottom:
    1. "HOVERED" label (Medium 28, `#6f9cc0`)
    2. the icon on a plate (or the chip for Hex layers)
    3. title (Bold 52, white, truncated to fit width)
    4. category · subtitle in the marker colour
    5. divider
    6. description (Medium 32, `#b5cde0`, wrapped, max 3 lines)
    7. up to `MaxRows()` rows
    8. up to **2** actions as keycaps
  - `NMTooltip.Keycap(parent, key: String, label: String) -> Float` returns the width used. The key sits in an
    outlined box (fill `HoloHighlight` @ .14, 1 px edge @ .55) and the label beside it.
  - Empty state: no "POINT AT A MARKER" text; the card area stays empty.
  - Tracking block, pinned to the bottom of the sidebar:
    - "TRACKING" label
    - quest-yellow diamond
    - `questTitle` (Bold 40, `VanillaStateColor(Quest | Gigs)` as today)
    - `questObjective` wrapped to sidebar width (`NMQuestHeader.Clip` unchanged)

- [ ] **Step 1: Write failing tests**
  - `tooltip.shows_description`: details with a description of about 200 characters set the description text visible,
    and the card height grows by ≤ 3 lines.
  - `tooltip.two_actions`: details with two actions show two keycaps; a third is ignored.
  - `tooltip.empty_state_blank`: with no selection the sidebar shows no text widget except the tracking block.
  - `layout.tracking_bottom`: the quest title's Y is greater than 70 % of `mapH`, and its X is ≥ `viewW`.
- [ ] **Step 2:** Run `tools/check.sh` and the campaign. Expect FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run check and the `render.json`, `regression.json` and `teleport.json` campaigns (the act and teleport
  labels come from the actions). Expect PASS. Compare with `frame.jpg`.
- [ ] **Step 5: Commit** `feat(frame): sidebar details card and tracking block`

### Task 10: Keycap hint bar

**Files:**
- Create: `r6/scripts/NightMap/Render/HintBar.reds`
- Modify:
  - `r6/scripts/NightMap/Core/Input.reds`, `r6/scripts/NightMap/Core/Pad.reds`
  - `r6/scripts/NightMap/Render/Panel.reds` (replace `hints: ref<inkText>` with `hintBar: ref<NMHintBar>`)
  - `r6/scripts/NightMap/Core/NightMapSystem.reds` (`UpdateHeader` hint section)
- Test: `Debug/SelfTest.reds` (`InputCases`, `PadCases`). The existing `HintText` checks must keep passing.

**Interfaces:**
- Produces:
  - `public struct NMHint { key: String; label: String; }` (empty key = plain text, e.g. the NumLock warning)
  - `NMInput.Hints(s: ref<NightMapSettings>, view: String, teleportLabel: String) -> array<NMHint>`
  - `NMPad.Hints(view: String, teleportLabel: String, teleportOn: Bool, holdToShow: Bool) -> array<NMHint>`
  - `NMHints.Join(h: array<NMHint>) -> String`. It reproduces today's exact strings, and `NMInput.HintText` /
    `NMPad.HintText` become `Join(Hints(...))`.
  - `NMPad.PassThroughHints(base: array<NMHint>) -> array<NMHint>`
  - `NMHintBar.Create(parent, x, y, w, h, scale, theme) -> ref<NMHintBar>`
  - `NMHintBar.Set(h: array<NMHint>)`: rebuilds only when the content changed. The last entry (CLOSE / RELEASE …
    CLOSE / HOLD VIEW CLOSE) is right-aligned; the rest flow left to right with a 60 × scale gap. The keycap style is
    shared with Task 9 (`NMTooltip.Keycap`); move it to `NMUi.Keycap` if both use it.
  - Key names use short forms inside keycaps: `NUM 8/NUM 4/NUM 6/NUM 2` → `8 4 6 2`, `NUM +` → `+`. Short forms are
    applied only when every entry's key starts with `NUM `, so custom non-numpad binds show in full.

- [ ] **Step 1: Write failing tests**
  - `hint.join_matches_legacy`: `Join(NMInput.Hints(s, "ALL", "TELEPORT")) == NMInput.HintText(s, "ALL", "TELEPORT")`
    on the old implementation's string, captured as a literal in the test. Same for the pad, with and without Hold to
    show.
  - `hint.close_last`: the last entry's label ends with `CLOSE`.
  - `hint.numlock_plain`: with `arrowSeen`, the extra entry has an empty key.
  - `hint.short_numpad`: with default binds the PAN key shows `8 4 6 2`; with `keyPanUp = IK_W` it shows in full.
- [ ] **Step 2:** Run `tools/check.sh` and the campaign. Expect FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run check and the `regression.json` and `controller.json` campaigns. Expect PASS. Compare a
  screenshot of the hint bar with `frame.jpg`.
- [ ] **Step 5: Commit** `feat(frame): keycap hint bar`

### Task 11: Tune, measure, and record

**Files:**
- Modify: `Core/Theme.reds` and `Render/Tiers.reds` (tuned values only)
- Modify: `notes/CHECKPOINTS.md` (add a section for this branch)

- [ ] **Step 1:** On **main**, install and run the perf suite: Debug setting on, Shift + toggle key, with
  RedIMGRetriever installed. Save the `PERF|` lines from CET `gamelog.log` to
  `.scratch/perf-main.txt`.
- [ ] **Step 2:** On the branch, install and run the same suite. Save to `.scratch/perf-branch.txt`. Every scenario's
  mean and p95 frame time must be ≤ main + 5 %. If one isn't, find the cause before tuning looks. Likely suspects are
  the extra plate size (overdraw), the vignette, and rings.
- [ ] **Step 3: Tune in-game**
  - Take screenshots (F12) at close (≤1 mpp), mid (~4) and whole city (16), with one marker hovered.
  - Tune colours, opacities, the `NMTiers` thresholds and minimum scale until:
    - the whole-city view shows only Major-tier markers and the tracked marker;
    - mid zoom shows vendors and collectibles without overlap walls;
    - every vanilla colour reads on the plates.
  - Re-run the `tier.*` tests after any threshold change (update their expected values with the tuned numbers).
- [ ] **Step 4:** Check:
  - effects off;
  - Green theme;
  - `panelOpacity` 0.3;
  - pad hint bar;
  - a photo pin;
  - a GPS route;
  - collectibles on and off;
  - teleport;
  - fast travel.

  Run the `regression.json`, `collect.json`, `teleport.json`, `fast-travel.json` and `controller.json` campaigns. All
  must PASS.
- Not built: the optional leader line from a marker to the sidebar (spec §5.2) and the optional open animation
  (spec §8). Both are noted in the checkpoint as candidates.
- [ ] **Step 5:** Record in `notes/CHECKPOINTS.md`:
  - the perf table (main against branch);
  - the tuned values;
  - the screenshot names;
  - the road split method used in Task 1.

  Commit `chore: tune visual overhaul and record checkpoint`.
