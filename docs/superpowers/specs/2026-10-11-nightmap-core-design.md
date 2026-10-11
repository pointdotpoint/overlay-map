# NightMap — Sub-project 1: Map core + tile pipeline

- **Date:** 2026-10-11
- **Status:** Draft — awaiting user review
- **Evidence base:** `~/cyberpunk_map_bench` (branch `spike/map-bench`, `notes/FINDINGS.md`)
- **Approved mockups:** `docs/superpowers/specs/mockups/` (`nightmap-overview.png`, `nightmap-street.png`; HTML sources alongside)

## 1. Context

NightMap is a custom 2D world map for Cyberpunk 2077 (redscript + Codeware + RedIMGRetriever, plus an
optional RED4ext plugin later). It opens **alongside** the vanilla map on its own key. The long-term goal
is feature parity with the vanilla map, plus user customization.

The benchmark spike showed that ink widgets are fast enough when the number of *live* widgets is bounded:
- One widget per pin costs about 7–10 µs per widget per frame. 2,000 pins add about 14 ms; 5,000 add 53–67 ms.
- A pooled, culled and clustered renderer stays within noise of baseline (+0–3.5 ms) at 50,000 pins.
- Screenshot thumbnails load through RedIMG `shot://` (48 in 0.93 s) at no measurable frame cost.

### Decisions made during brainstorming

| Topic | Decision |
|---|---|
| Relation to vanilla map | Alongside it, with its own key; vanilla stays untouched |
| Interaction model | **Live overlay**: the game keeps running and there is no cursor; selection is by a fixed crosshair |
| Controls | **Dedicated keys only**, so V keeps full control (walk/drive with the map open) |
| Native-only features | Optional RED4ext plugin (sub-project 3); the map works without it |
| Map imagery | Rendered offline from the game's own 3D-map meshes into tiles |
| Customization (later sub-projects) | User markers, layer toggles/opacity, mod API, theming — all four |
| Architecture | **Layer-based core**: every content source (built-in or third-party) is a layer using one public API |
| Visual style | **Hologram / blueprint** (cyan linework, glow, translucent) |
| Layout | **Centered panel** (~70% of screen) with holo corner brackets; the game stays visible around it |
| Selection info | **Docked info card** in the panel's right column |
| Pins / clusters | **Hex chips**; a cluster is a larger hex with a count and a fan of its top-3 icons |
| New behavior from mockups | **"Act" on a cluster zooms into it** (core feature, in this sub-project) |

### Sub-project roadmap (each gets its own spec → plan → build)

1. **Map core + tile pipeline** ← *this spec*
2. Vanilla pins: all mappin types/icons/visibility rules, filters, quest tracking, objective header, details content
3. Native plugin: track non-quest/custom waypoints, GPS route layer, district hit-test, Delamain taxi
4. Fast travel + districts: travel action, district labels/outlines/gangs
5. Customization: persistent user markers, photo pins, layer toggles/opacity UI, theming, published mod API docs

## 2. Goals and non-goals

**Goals (sub-project 1)**
- Open/close the map overlay on a hotkey; the map costs nothing while closed.
- Render the city from offline-built tiles with smooth pan and zoom, correctly aligned to world coordinates.
- Crosshair selection, the docked info card, cluster zoom-in, a player marker, and the key-hint bar.
- A public **layer API** that sub-projects 2–5 and other mods build on, with pooling, culling and clustering.
- Performance: within **+3 ms** of baseline with 50,000 items across layers; zero cost while closed.

**Non-goals (deferred)**
- Any vanilla pin data, tracking, fast travel, districts, GPS route (sub-projects 2–4).
- Saving user markers, theming, a layer-toggle UI (sub-project 5).
- Controller support (no free buttons without input takeover — revisit later).
- Map rotation / 3D tilt.

## 3. Visual design

The approved mockups are the reference; this section pins down the measurements. Coordinates are in the
HUD virtual window's 3840×2160 space. Final pixel values may be adjusted in-game during implementation;
the structure may not change without re-approval.

**Palette (hologram)**

| Token | Value | Use |
|---|---|---|
| `cyan` | `#7AF0FF` | primary lines, frame, crosshair, key hints, vendor/fast-travel chips |
| `text` | `#C8F6FF` | titles, values |
| `pink` | `#FF4FD8` | gigs, metro line, category accent |
| `yellow` | `#FFE066` | quests |
| `muted` | `rgba(170,220,235,.7)` | undiscovered, secondary labels |
| `panelBg` | `rgba(6,20,30,.74)` | panel background (opacity user-adjustable later) |
| `cardBg` | `rgba(10,40,55,.5)` | info card + hint bar |

Category colors live in one table (`Theme.reds`) so sub-project 5 can theme them.

**Typography:** in-game font families only. Headings use Orbitron
(`base\gameplay\gui\fonts\orbitron\orbitron.inkfontfamily`). Body and labels use Rajdhani
(`base\gameplay\gui\fonts\raj\raj.inkfontfamily`). The mockups' monospace font is a stand-in for these.

**Layout** (centered panel):
- Panel: 70% × 71% of the screen, centered (≈ 2688×1536). 1.5 px cyan outline at 35% opacity, plus four glowing corner brackets.
- Map area: the left 70% of the panel. The **crosshair sits at the map area's center**, not the screen center.
- Info card: the right 30% of the panel, separated by a thin cyan line.
- Hint bar: full panel width at the bottom, about 46 px high in the mockup scale.
- Header (top-left of the map area): "NIGHT CITY", with the subtitle showing the district under the crosshair. Sub-project 1 shows the player's current district (available via `PreventionSystem`).
- Scale bar: top-right of the map area, showing a "nice" length (100 m / 200 m / 500 m / 1 km / 2 km).

**Hex chip** (item):
- A flat-top hexagon, radius 20 (selected: 25 with a 3 px stroke), dark fill at 92%.
- The stroke and a 14% fill tint use the category color; the icon is centered.
- Icons come from an atlas and part name supplied by the item. Vanilla icons (sub-project 2) are drawn as-is but tinted.
- Constant on-screen size at every zoom level.

**Cluster**:
- A hex of radius 33 (selected: 38), cyan stroke, count text in the center (smaller font for 3+ digits).
- Up to **3 mini chips** (radius 14) fanned above it, showing the cluster's most frequent categories.

**Crosshair**: a 40 px ring plus four tick marks with a glow, drawn above everything except the panel chrome.

**Player marker**: a cyan arrow in a soft halo, rotated to V's facing (vehicle facing when driving), always on top of items.

**Info card content** (driven by the selected item's layer):
- A category line in the category color.
- A title.
- A subtitle line.
- Up to 6 key/value rows.
- A wrapped description of up to 4 lines.
- Up to 3 action rows, each a key cap plus a label.

For a cluster, the card shows "N LOCATIONS", the counts per category with a mini chip each, and `NUM 0 — zoom into cluster`.

**Key-hint bar**: `NUM 8456 PAN · NUM +− ZOOM · NUM 5 FOLLOW · NUM 0 ACT`, generated from the current bindings, plus extra hints contributed by layers in later sub-projects. (The mockups show arrows and Enter; those defaults were replaced after the binding check, §6.)

## 4. Architecture

```
nightmap/
  r6/scripts/NightMap/
    Core/    NightMapSystem.reds   lifecycle, hotkey, frame loop (zero-delay DelayCallback), owns everything
             Camera.reds           center/zoom, world<->map-area transforms, bounds clamp, follow mode, smoothing
             Input.reds            Codeware Input/Key -> actions; held-key state; bindings from settings
             Settings.reds         Mod Settings integration (keys, opacity, debug toggle)
             Theme.reds            palette, fonts, sizes (single source for visuals)
    Render/  Panel.reds            panel chrome, header, scale bar, hint bar
             TileLayer.reds        background tiles: LOD pick, pooled tile widgets
             ItemRenderer.reds     global widget budget, chip/cluster pools, culling, clustering, z-order
             Crosshair.reds        reticle + nearest-item selection
             InfoCard.reds         docked card rendering from NightMapDetails
             PlayerMarker.reds     V position + facing
    Api/     NightMap.reds         public entry point: NightMap.Get()
             NightMapLayer.reds    layer object (items, visibility, opacity, zoom range, listener)
             NightMapItem.reds     item value + icon/category data
             NightMapDetails.reds  card payload (title, rows, description, actions)
             SpatialGrid.reds      per-layer grid: buckets, per-cell counts/centroids/category tallies
    Generated/TileManifest.reds    emitted by the tile pipeline (levels, grid, bounds, calibration)
    Debug/   DebugLayer.reds       synthetic items (benchmark distributions)
             SelfTest.reds         in-game assertions -> gamelog PASS/FAIL
             PerfSuite.reds        benchmark suite as a regression test
  tools/     check.sh  install.sh  tiles/ (pipeline)  results.py
  archive/   NightMap.archive      tiles + UI atlas (hex chips, crosshair, brackets)
  docs/      specs, plans, API docs
```

**Units and their contracts**
- **NightMapSystem** (`ScriptableSystem`): registers the open/close hotkey. On open it builds the panel and starts the frame loop. On close it stops the loop and destroys the widgets. Each frame: Input → Camera → TileLayer → ItemRenderer → Crosshair → InfoCard → PlayerMarker.
- **Camera**: pure math plus state. `WorldToMap(Vector2)->Vector2` and `MapToWorld`, zoom limits from the manifest, a follow flag, smoothing.
- **ItemRenderer**: the only owner of item and cluster widgets. Input is the visible layers and the camera rectangle. Output is positioned widgets and the "selectable candidates" list for Crosshair.
- **Crosshair**: picks the nearest candidate within a 48 px radius of the map-area center, or none. It emits a selection-changed signal to InfoCard and the owning layer's listener.
- **Layers** know nothing about widgets; the renderer knows nothing about where items come from.

## 5. Tile pipeline (offline, `tools/tiles/`, Python)

1. **Export** the 3D-map meshes with WolvenKit CLI (`~/.local/bin/WolvenKit.CLI`) to `.glb`. Sources:
   - `base\entities\cameras\3dmap\`: `3dmap_terrain`, `3dmap_water`, `3dmap_cliffs`, `3dmap_roads`, `3dmap_roads_borders`, `3dmap_metro`, and the building geometry (`3dmap_triangle_soup`, `3dmap_coll_buildings*`, landmark meshes).
   - The EP1 (Dogtown/spaceport) counterparts.
   - *First plan task verifies this works on Linux.* Texture export to PNG already fails on Linux. Fallback: run the Windows CLI under Wine for this step only.
2. **Rasterize** top-down (orthographic) with numpy and trimesh, in hologram style. Back to front:
   1. terrain/land tint
   2. water
   3. cliffs
   4. minor roads (thin, 20% cyan)
   5. major roads (bright cyan; the glow is baked into the texture)
   6. building footprints (6% fill plus a 45% outline, with lightness by height)
   7. metro (pink, dashed)

   Output is premultiplied RGBA, so the panel background shows through.
3. **Calibrate** mesh → world. The debug command `NightMap.DumpCalibration` logs fast-travel point world positions (`FastTravelSystem.GetFastTravelPoints`).
   - The pipeline matches them to the mesh frame and solves for scale and offset by least squares.
   - **The build fails if the RMS error is over 2 m.**
4. **Tile and pack** into four detail levels (16, 8, 4 and 2 m/px):
   - Tiles are 512×512, packed into one atlas texture per level (or more where a level exceeds 4096²).
   - Encoding is BC7, reusing the encoder and archive-writer approach from `~/cyberpunk_hologram_mod/holo_core`, which works on this machine without WolvenKit's texture conversion.
   - The pipeline also builds the UI atlas: hex chip frames, the crosshair, brackets and the cluster hex.
   - Target size ≤ 25 MB.
5. **Emit** `NightMap.archive` and `Generated/TileManifest.reds`: levels, tile size, atlas paths and part names, world bounds, calibration, and the source game version.

Re-run once per game version. Per-layer tile sets (roads only, buildings, metro) are a pipeline flag reserved for sub-project 5.

## 6. Runtime behavior

**Open/close**
- **Key:** `\` by default (see the key table below), rebindable in Mod Settings.
- **On open:** the camera centers on V in follow mode, at the last-used zoom (default: the 4 m/px level).
- **Auto-hide:** the overlay hides whenever the HUD layer is hidden (menus, loading, photo mode, scenes) and reappears afterwards if the map is still open.

**Camera**
- North-up.
- **Zoom:** continuous, exponential at about 1.5×/s while held, clamped to the manifest range. The detail level switches at the 1:1 crossover.
- **Pan:** about 1500 map px/s, scaled by zoom and accelerating after 0.5 s held.
- **Follow mode:** panning disables it, and Numpad 5 re-enables it with a 250 ms ease.
- **Bounds:** the camera is clamped so the map area never shows more than half a screen of empty space past the world bounds.

**Keys (defaults, all rebindable).** The defaults come from a binding check against
`r6/cache/inputUserMappings.xml` and installed mods:
- **Arrow keys drive the car** (Up accelerate, Down brake, Left/Right steer via `LeftX_Axis_Vehicle`, plus radio volume), so they can't pan a live map.
- `T` is phone/notifications and `J` is the journal.
- The numpad has no vanilla gameplay bindings.

| Action | Key | Enum |
|---|---|---|
| Open/close | `\` | `IK_Backslash` (unbound everywhere) |
| Pan | Numpad 8/4/6/2, diagonals 7/9/1/3 (held) | `IK_NumPad8` … |
| Zoom in / out | Numpad `+` / `−` (held) | `IK_NumPlus` / `IK_NumMinus` |
| Recenter + follow | Numpad 5 | `IK_NumPad5` |
| Act on selection | Numpad 0 | `IK_NumPad0` |

- Act on a cluster zooms so the cluster's cell fills about 60% of the map area. On an item it calls `listener.OnActivated(id)`.
- Numpad `.`, `*` and `/` are reserved for sub-projects 2–4 (track, journal, filter cycle) and do nothing in sub-project 1.
- The hint bar shows the bound keys, so rebinding updates it.
- **Known overlap:** `PhotoModeUIImprovements/TimelineProbe.reds` listens globally to the numpad digits, `NumPlus` and `NumStar`. It's a debug probe whose effects only matter in photo mode, where NightMap is hidden.
- **To verify in-game:** that the numpad keys arrive as `IK_NumPad*` with NumLock both on and off. If NumLock-off maps them to arrows, the map ignores arrow events, and the hint bar shows "NumLock on".

**Selection**
- Evaluated each frame the camera or items change.
- Ties go to higher layer priority, then to the smaller distance.
- Selection is sticky: within 4 px of the previous pick, the previous pick wins, which prevents flicker.

## 7. Public layer API

```swift
// redscript
let map = NightMap.Get();                         // null if NightMap not installed/ready
let layer = map.CreateLayer(n"MyMod.Collectibles", "Collectibles", 50);  // id, display name, priority
layer.SetCategory(n"collectible", "COLLECTIBLE", new HDRColor(1.0, 0.88, 0.4, 1.0));
let id: Int32 = layer.Add(NightMapItem.Create(worldPos, n"collectible", r"mymod\icons.inkatlas", n"star"));
layer.Move(id, newPos); layer.Remove(id); layer.Clear();
layer.SetVisible(false); layer.SetOpacity(0.6); layer.SetZoomRange(0.5, 16.0);   // m/px range
layer.SetClustering(true);                        // opt out for a few must-see items
layer.SetListener(myListener);
```

```swift
public abstract class NightMapLayerListener {
  public func GetDetails(id: Int32) -> ref<NightMapDetails>;   // card content; null = default card
  public func OnSelected(id: Int32) -> Void;
  public func OnActivated(id: Int32) -> Void;                  // "act" key (Numpad 0)
}
```

- **Item fields:**
  - position (world X/Y; Z is stored for future floor logic)
  - category
  - icon (atlas + part, **or** a RedIMG image key)
  - optional tint override
  - label
  - priority within the layer
- **Ids:** stable per layer, recycled through a free list after `Remove`.
- **Default card** (no details): category line, label, distance from V.
- **Thread/session safety:** layers created before the map opens are allowed. All layers are cleared on session end, and mods recreate them on `Session/Ready`.
- **Validation:**
  - unknown layer, or position outside world bounds + 1 km → logged once per layer, item rejected
  - duplicate layer id → returns the existing layer

## 8. Rendering rules

- **Spatial grid:** each layer has a grid with 250 m cells, holding per-cell item lists, counts, centroids and per-category tallies. It is updated incrementally on Add/Move/Remove.
- **Visible query:** cells intersecting the map-area world rectangle plus a 1-cell margin.
- **Cluster switch:** a cell is drawn as **one cluster** when its on-screen size is under 96 px *and* it holds more than one item. Layers with `SetClustering(false)` always draw individual items.
- **Widget budget:**
  - chips: 600 (shared across layers, filled in layer-priority order)
  - clusters: 200
  - tiles: 64
  - fixed chrome: about 40
  - When the chip budget runs out, the remaining cells of lower-priority layers fall back to clusters.
- **Dirty tracking:** positions are recomputed only when the camera moved or a layer changed this frame. An idle open map does nearly no work.
- **Z-order (back to front):** tiles → clusters → chips → selected chip → player marker → crosshair → panel chrome/card.
- **Labels:** only the selected item has text on the map. The card holds the details.

## 9. Error handling

- **Missing Codeware or RedIMG:** one clear `[NightMap]` error, and the hotkey is not registered.
- **Missing or mismatched tile archive** (manifest game version ≠ running game, or atlas not found): the map opens with a plain hologram grid background and a warning line in the header.
- **API misuse:** logged once per layer and key, never fatal.
- **Logs:** all go to CET `gamelog.log` with the `[NightMap]` prefix (ModLog), with a debug-level toggle in settings.

## 10. Testing

- **Offline compile check:** `tools/check.sh` runs `scc` under Wine in a sandbox against the vanilla bundle + Codeware + RedIMG, on every change.
- **In-game self-test (debug key):** logs PASS/FAIL per case and a summary line. Cases:
  - camera round trip (`MapToWorld(WorldToMap(p)) ≈ p`)
  - grid add/move/remove/query counts against brute force
  - cluster tallies
  - id recycling
  - budget overflow fallback
  - manifest present and version matches
- **Performance regression (debug key):** the benchmark suite moved into `PerfSuite`.
  - **Pass:** `items_50000` ≤ baseline + 3 ms average and ≤ baseline + 6 ms p95.
  - `tools/results.py` parses the results.
- **Alignment check** (manual, once per tile build): the debug layer plots fast-travel points. They must sit on their street corners at 2 m/px, and V's marker must stay on the road while driving.

## 11. Risks and open items

| Risk | Mitigation |
|---|---|
| WolvenKit mesh export may fail on Linux (texture export already does) | First plan task proves it; Wine fallback |
| Mesh frame ≠ world frame | Calibration step with an error gate |
| HUD virtual window not 3840×2160 on all setups | Read the window size at open time; layout uses fractions of it |
| Key conflicts with live gameplay (arrow keys steer vehicles) | Numpad defaults chosen from a binding check; all keys rebindable; NumLock behavior verified in-game |
| Glow/translucency cost in ink (effects on many widgets) | Glow baked into textures; no runtime blur effects |
| `DelayCallbackNextFrame` re-arm is dropped | Frame loop uses `DelayCallback(cb, 0.0)` (proven in spike) |
| `EngineTime` 31.25 ms resolution | Use `RedIMG.NowMs()` for timing |

## 12. Dependencies

Codeware (1.20.5+), RedIMGRetriever (local `shot://` support), redscript, RED4ext, and Mod Settings.
The tile archive is a plain `.archive` in `archive/pc/mod`, so ArchiveXL is not required.
All are already installed on the dev machine. CET is used only for log output during development.
