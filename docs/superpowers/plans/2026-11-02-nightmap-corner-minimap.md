# NightMap Corner Minimap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An option that runs NightMap permanently in the vanilla minimap's box (three styles, full vanilla-minimap
parity, optional HUD Painter colours), expanding to today's panel on the Open / close map key.

**Architecture:** A new `NMCorner` owns a persistent widget tree in the HUD window with its own `NMCamera`,
`NMLayerStack`, `NMItemRenderer`, `NMRouteLayer` and `NMPlayerMarker`, all reading the one shared `NightMap` API, so
the expanded panel's build/destroy path stays as it is. `NightMapSystem` gains a mode (Off / Corner / Expanded): the
frame loop runs while either view is live, and closing the expanded panel shows the corner again with the zoom handed
over. Vanilla-minimap parity comes from observing the vanilla minimap's own mappin controllers (`@wrapMethod`, names
fixed by the Task 1 spike) into an `NMMinimapMirror`, which feeds API layers and a new shape layer for cones and areas.
HUD Painter colours are read back from hidden probe widgets bound to `MainColors.*` style slots.

**Tech Stack:** redscript, Codeware, Mod Settings (RedFileSystem / RedIMGRetriever optional, as today); Python 3 stdlib
soak harness.

**Spec:** `docs/superpowers/specs/2026-11-02-nightmap-corner-minimap-design.md`

## Global Constraints

- New Mod Settings switch "Replace vanilla minimap", default **off**; off = NightMap behaves exactly as today (no
  corner widgets, no frame loop while the map is closed, vanilla minimap untouched).
- The vanilla minimap is faded by **opacity only**, never removed, hidden or disabled; GPS route reading
  (`Vanilla/Gps.reds`) depends on it running. Its opacity is restored whenever corner mode ends.
- Corner: north-up, never rotates; V centred; no input of any kind in corner mode.
- Corner zoom = the `mpp` the expanded map was last closed at; no corner zoom control. Persisted in a `persistent`
  field on `NightMapSystem`. First-ever value `NMCorner.DefaultMpp()` = 0.4.
- Corner markers = the expanded map's filter view + Map filter / Collectibles switches; enemies and police ignore the
  filter view and have their own switches.
- Styles (dropdown "Corner map style"): `Circle`, `Square`, `SquareStrip` (default). Strip: district left, distance to
  the tracked objective right (district only when nothing is tracked); strip sits **inside** the vanilla box.
- Corner is visible only while the vanilla minimap would be (follows the vanilla widget's game-driven visibility).
- "Follow HUD Painter colours", default **off**: off = today's colours bit-for-bit. No NightMap per-colour settings.
  No compile or load dependency on HUD Painter.
- One theme for both views (`holoColor`, `hologramEffects`); separate opacity for corner (`cornerOpacity`) and panel
  (`panelOpacity`).
- Performance pass bar: corner mode adds **≤ 0.5 ms per frame** (perf suite, fast drive through City Center) over the
  same run with the option off.
- **Ask the user before every in-game run** (spike, self-test campaign, perf, soak). They run it or say go.
- Do not regress: GPS routes, hold-to-show, controller Hold View open/close (closing with View has locked V's movement
  before), Hide HUD while open, teleport, fast travel, photo pins, collectibles.
- Unreadable parity items go back to the user with a proposed substitute; nothing is dropped or approximated silently.

## Review Focus

- **Option switched off mid-game** in Mod Settings: corner widgets gone, vanilla minimap opacity back to its original
  value within one settings poll. Test `corner.option_off_restores_vanilla` (Task 6).
- **Save load / quit to menu while the corner is shown**: no orphaned widgets, vanilla opacity restored, corner rebuilt
  after the new session's player attach. Test `corner.detach_restores` (Task 6).
- **Vanilla minimap widget not found yet** (early load, HUD rebuilding, a HUD mod that renamed it): corner draws
  nothing (never at 0,0) and retries. Test `corner.no_box_no_draw` (Task 4).
- **Expanded map closed by teleport or fast travel** (not the key): corner returns, zoom handed over. Test
  `corner.teleport_close_returns` (Task 6).
- **Hide HUD while open + corner**: after expand→close, vanilla minimap still at 0, corner at `cornerOpacity`. Test
  `corner.hudhider_roundtrip` (Task 6).

---

## Phase A — prove it

### Task 1: Parity spike (in-game)

**Files:**
- Modify: `tools/soak/autopilot/SystemBody.inc`, `tools/soak/autopilot/SoakHooks.reds` (spike-only commands; these
  files only exist in campaign builds)
- Create: `tools/soak/autopilot/MinimapSpike.reds` (spike-only `@wrapMethod`s on vanilla minimap mappin controllers that
  count instances by class and log one sample of their fields), added to the campaign build by `tools/soak/builds.py`
- Create: `tools/soak/plans/minimap-spike.json`
- Create: `docs/superpowers/specs/2026-11-02-corner-minimap-spike/FINDINGS.md`

Spike commands (each returns one line, `|`-separated, like `police`):
- `mm_tree [depth]` — the vanilla minimap's widget subtree from the HUD window: name, widget class, controller class,
  absolute box, visible, opacity.
- `mm_vis` — the visibility/opacity chain from the minimap widget up to the window, so we learn which widget the game
  toggles for menus, scanner, cutscenes, braindance and photo mode.
- `mm_ctrls` — live minimap mappin controller classes with counts and one sample each (mappin variant, world pos,
  clamped?, vertical relation, any area radius).
- `mm_stealth` — per hostile NPC mappin: world pos, facing, cone angle, cone range, detection/awareness state, and the
  atlas parts the vanilla controller uses for dot and cone.
- `mm_zone` — security-zone label text/state and where the wanted indicator lives (inside the minimap widget or not).
- `palette_probe` — create hidden `inkRectangle`s styled with `base\gameplay\gui\common\main_colors.inkstyle` and
  bound (`BindProperty(n"tintColor", …)`) to `MainColors.Blue`, `MainColors.Yellow`, `MainColors.EnemyMinimapBase`;
  two frames later report `GetTintColor()` for each (is the bound value readable?).
- `mask_probe` — draw a test canvas under an `inkMaskWidget` using the mask resource the vanilla minimap uses (from
  `mm_tree`); screenshot proves a circular clip of child canvases.

Expected vanilla names to start from (verify; FINDINGS wins): `MinimapContainerController`,
`BaseMinimapMappinController`, `MinimapStealthMappinController`, `MinimapDeviceMappinController`,
`MinimapQuestAreaMappinController`, `MinimapSecurityAreaMappinController`, `MinimapPreventionVehicleMappinController`,
`MinimapStubMappinController`, `MinimapPOIMappinController`, `MinimapRoleMappinController`.

- [ ] **Step 1:** Add the commands and wraps; `tools/check.sh --soak` → no `COMPILE FAILED`.
- [ ] **Step 2:** Write `minimap-spike.json`: per scenario run `mm_tree 6`, `mm_vis`, `mm_ctrls`, `mm_stealth`,
  `mm_zone`, plus `palette_probe` and `mask_probe` once. Scenarios: open street; hostile gang area (sneak, then get
  spotted); restricted area; `wanted 2`; driving fast; open menu / scanner / photo mode (for `mm_vis`).
- [ ] **Step 3:** **Ask the user** which saves cover those scenarios and whether to run now. Run
  `python3 -m tools.soak.soak campaign --save <save> tools/soak/plans/minimap-spike.json` per save.
- [ ] **Step 4:** Write `FINDINGS.md`: a **parity checklist** table — one row per thing the vanilla minimap shows
  (from `mm_tree`/`mm_ctrls`, not from this plan's list), columns: what it shows, vanilla source (class/method/atlas
  part), readable from script (yes/no/partial), how NightMap will get it. Plus: game hiding mechanism, the vanilla box
  widget path, mask resource path and result, palette read-back result, the vertical-relation thresholds vanilla uses.
- [ ] **Step 5:** Commit `feat(spike): inventory the vanilla minimap for corner-mode parity`.

### Task 2: Amend this plan from the findings

**Files:** Modify: this plan (Tasks 9–11 names, the shape-layer parts, the palette approach in Task 8).

- [ ] **Step 1:** Replace every "expected" vanilla name in Tasks 8–11 with the FINDINGS names; add a task for any
  checklist row Tasks 9–11 don't cover.
- [ ] **Step 2:** Any row marked "no" or "partial", and a failed `palette_probe` or `mask_probe`: stop, bring them to
  the user in one message with a proposed substitute each (e.g. dots without cones; square-only if no circular mask;
  reading the style resource instead of probes). Record answers in the plan.
- [ ] **Step 3:** Commit `docs(plan): fix corner-minimap tasks to the spike findings`.

## Phase B — corner mode

### Task 3: Settings

**Files:**
- Modify: `r6/scripts/NightMap/Core/Settings.reds`
- Create: `r6/scripts/NightMap/Debug/SelfTestCorner.reds` (`NMCornerTests.Run(t: ref<NMSelfTest>)`, registered in
  `SelfTest.Run`)

**Interfaces (Produces):**
- `enum NightMapCornerStyle { Circle = 0, Square = 1, SquareStrip = 2 }`
- New `NightMapSettings` fields, category **"Minimap"** (sliders use Mod Settings `step/min/max`):

| field | type | default | range |
|---|---|---|---|
| `replaceMinimap` | Bool | false | |
| `cornerStyle` | NightMapCornerStyle | SquareStrip | |
| `cornerScale` | Float | 1.0 | 0.75–1.5, step 0.05 |
| `cornerMarkerSize` | Float | 1.0 | 0.5–2.0, step 0.1 |
| `cornerTextSize` | Float | 1.0 | 0.5–2.0, step 0.1 |
| `cornerFrameThickness` | Float | 1.0 | 0.5–3.0, step 0.25 |
| `cornerOpacity` | Float | 0.92 | 0.2–1.0, step 0.02 |
| `cornerEnemies` | Bool | true | |
| `cornerPolice` | Bool | true | |
| `expandedScale` | Float | 1.0 | 0.7–1.0, step 0.05 |
| `followHudPainter` | Bool | false | (category "Display") |

  Every field except `replaceMinimap` and `followHudPainter` carries `ModSettings.dependency` on `replaceMinimap`
  (except `expandedScale`, which always applies).

- [ ] **Step 1:** Test `corner.settings_defaults`: `new NightMapSettings()` has exactly the defaults above.
- [ ] **Step 2:** `tools/check.sh` → `COMPILE FAILED` (fields missing).
- [ ] **Step 3:** Add the enum and fields with display names and descriptions (description of `replaceMinimap`:
  "Show NightMap in place of the game's minimap. The Open / close map key expands it.").
- [ ] **Step 4:** `tools/check.sh` → passes.
- [ ] **Step 5:** Commit `feat(settings): corner minimap options`.

### Task 4: Corner layout and the vanilla minimap probe

**Files:**
- Create: `r6/scripts/NightMap/Corner/CornerLayout.reds`
- Create: `r6/scripts/NightMap/Corner/MinimapProbe.reds`
- Modify: `r6/scripts/NightMap/Debug/SelfTestCorner.reds`

**Interfaces (Produces):**
- `NMCornerLayout.Compute(box: ref<NMRect>, style: NightMapCornerStyle, cornerScale: Float, textSize: Float, winW: Float, winH: Float) -> ref<NMCornerLayout>`
  with fields `x, y, w, h` (whole corner), `mapX, mapY, mapW, mapH` (map area), `stripH` (0 unless SquareStrip),
  `round: Bool`, `scale` (as `NMPanelLayout.scale`). The box is scaled by `cornerScale` about its **top-right**
  corner. Circle/Square: map area = whole box (circle: square bounding box of the circle, diameter = min(w,h)).
  SquareStrip: `stripH = NMCornerLayout.StripHeight() * scale * textSize` (`StripHeight()` = 44.0, 4K units) and the
  map area is the box minus the strip at the bottom.
- `NMCornerLayout.AsPanelLayout() -> ref<NMPanelLayout>` (mapW/mapH = map area, `viewW = mapW`, `sideW = 0`, for
  `NMItemRenderer.UpdateFor`).
- `NMMinimapProbe.Find(window: wref<inkCompoundWidget>) -> ref<NMMinimapProbe>` (null when not found; widget path from
  FINDINGS), `Box() -> ref<NMRect>` (absolute, window units; null when size < 8 px), `ShownByGame() -> Bool` (the
  mechanism from FINDINGS), `Fade()`, `Restore()` (the opacity seen before `Fade`, like `NMHudHider`).

- [ ] **Step 1:** Tests:
  - `corner.layout_strip_inside_box`: box (3300,100)-(3700,500), SquareStrip, scale 1, text 1, 3840×2160 →
    `y + h == 500`, `mapH == 400 - 44`, `stripH == 44`.
  - `corner.layout_scale_top_right`: same box, Square, `cornerScale` 1.5 → right edge 3700, top 100, `w == 600`.
  - `corner.layout_circle_square_bounds`: box 400×360, Circle → `mapW == mapH == 360`, `round`.
  - `corner.no_box_no_draw`: `NMCornerLayout.Compute(null, …)` returns null.
- [ ] **Step 2:** `tools/check.sh` → `COMPILE FAILED`.
- [ ] **Step 3:** Implement both classes.
- [ ] **Step 4:** `tools/check.sh` → passes.
- [ ] **Step 5:** Commit `feat(corner): layout from the vanilla minimap's box`.

### Task 5: The corner view

**Files:**
- Create: `r6/scripts/NightMap/Corner/Corner.reds`
- Create: `r6/scripts/NightMap/Corner/CornerConfig.reds`
- Modify: `r6/scripts/NightMap/Debug/SelfTestCorner.reds`

**Interfaces:**
- Consumes: `NMCornerLayout`, `NMMinimapProbe` (Task 4); `NMLayerStack.Create`, `NMItemRenderer.Create/UpdateFor`,
  `NMRouteLayer.Create/Update`, `NMPlayerMarker.Create/Update`, `NMCamera.Create/SetCenter/SetMpp` (existing).
- Produces:
  - `NMCornerConfig.From(s: ref<NightMapSettings>) -> ref<NMCornerConfig>`; `Same(o: ref<NMCornerConfig>) -> Bool`
    (every corner field from Task 3 plus `holoColor`, `hologramEffects`, `followHudPainter`).
  - `NMCorner.Build(window: wref<inkCompoundWidget>, layout: ref<NMCornerLayout>, cfg: ref<NMCornerConfig>, api: ref<NightMap>, mpp: Float) -> ref<NMCorner>`
  - `Update(player: ref<GameObject>, dt: Float, routes: ref<NMGpsReading>, routeColor: HDRColor, district: String, objectiveM: Float)`
    (`objectiveM < 0` = nothing tracked)
  - `SetShown(on: Bool)`, `SetMpp(m: Float)`, `Mpp() -> Float`, `Root() -> ref<inkCanvas>` (named `n"NightMapCorner"`),
    `Destroy()`; `static DefaultMpp() -> Float` = 0.4; `static StripText(district: String, objectiveM: Float) -> String`.

Widget tree: root canvas at the layout box, `SetOpacity(cfg.cornerOpacity)`; map area clipped by an `inkScrollArea`
internal mask (Square/SquareStrip, same pattern as `NMPanel.Build`) or by the `inkMaskWidget` from FINDINGS (Circle).
Inside: tiles, routes, items, overlay canvases in that order, as in `NMPanel`. Frame: Circle = ring + "N" tick; Square
= `NMPanel`'s corner brackets; thickness × `cornerFrameThickness`. Camera follows V every update (no easing). Item
icon sizes × `cornerMarkerSize`; strip text × `cornerTextSize`. Strip text format: `"RANCHO CORONADO"` left,
`"320 M"` right (metres rounded to 10 below 1 km, `"1.4 KM"` above).

- [ ] **Step 1:** Tests:
  - `corner.style_widgets`: Build each style into a test canvas → Circle has the mask widget and no strip; Square has
    brackets and no strip; SquareStrip has a strip text widget.
  - `corner.strip_text`: `StripText("RANCHO CORONADO", 320.0)` → right part `"320 M"`; `1440.0` → `"1.4 KM"`;
    `-1.0` → no right part.
  - `corner.config_same`: `From` of two default settings → `Same` true; change `cornerStyle` → false.
  - `corner.never_rotates`: after `Update` with the player at yaw 90°, the map content's rotation is 0 (only the V
    marker rotates).
- [ ] **Step 2:** `tools/check.sh` → `COMPILE FAILED`.
- [ ] **Step 3:** Implement `NMCornerConfig` and `NMCorner`.
- [ ] **Step 4:** `tools/check.sh` → passes.
- [ ] **Step 5:** Commit `feat(corner): the corner view in three styles`.

### Task 6: Modes, expand / shrink, lifecycle

**Files:**
- Modify: `r6/scripts/NightMap/Core/NightMapSystem.reds`
- Modify: `r6/scripts/NightMap/Render/Panel.reds` (`NMPanelLayout.Compute` gains `expandedScale: Float`, multiplying
  the 0.90 / 0.711 fractions; existing callers pass `s.expandedScale`)
- Create: `tools/soak/plans/corner.json`
- Modify: `r6/scripts/NightMap/Debug/SelfTestCorner.reds`, `tools/soak/autopilot/SystemBody.inc` (command `corner` →
  `corner shown|hidden|off box x,y,w,h mpp <m> vanilla_opacity <o>`)

**Interfaces:**
- Consumes: Task 4–5 classes.
- Produces on `NightMapSystem`: `private persistent let cornerMpp: Float`; `public func Corner() -> ref<NMCorner>`;
  `public func CornerActive() -> Bool`.

Behaviour:
- Corner is created on player attach and whenever a settings poll (every 30 frames while the loop runs, and on
  player attach) finds `replaceMinimap` on and no corner; destroyed (and the probe's `Restore()` called) when it is
  off, on `OnDetach`, and before a rebuild when `NMCornerConfig.Same` is false.
- `EnsureLoop` runs while `isOpen || CornerActive()`; `Tick` stops only when neither. While closed, `Tick` runs only
  corner work: vanilla poll (`vanilla.Tick`), route read every 500 ms, `corner.Update`, the probe's visibility
  (`SetShown(probe.ShownByGame())`) and `probe.Fade()` re-applied every 30 frames (HUD controllers fade back in).
- `Open()`: corner `SetShown(false)`; the panel opens as today with `camera.SetMpp(cornerMpp)` when corner mode is on.
- `Close()` (every path: key, B/View, teleport, fast travel, `OnDetach`): `cornerMpp = camera.mpp`, corner
  `SetMpp(cornerMpp)`, re-centre on V, `SetShown(true)` unless detaching.
- `cornerMpp <= 0` → `NMCorner.DefaultMpp()`.
- `NMHudHider` keeps working unchanged: it fades the corner root with the rest while expanded and restores it after.

- [ ] **Step 1:** Tests (drive the system through public methods with a test window where needed):
  - `corner.zoom_handover`: corner on, `Open()`, `camera.SetMpp(1.7)`, `Close()` → `Corner().Mpp() == 1.7`, and a
    new `Open()` starts at 1.7.
  - `corner.option_off_restores_vanilla`: corner on with a fake minimap widget at opacity 0.8 → faded to 0; set
    `replaceMinimap = false`, run one settings poll → no `NightMapCorner` child, fake widget opacity 0.8.
  - `corner.detach_restores`: corner on, call the detach path → no corner child, fake widget opacity restored.
  - `corner.teleport_close_returns`: corner on, `Open()`, close through the path `StartTeleport` uses → corner shown,
    mpp handed over.
  - `corner.hudhider_roundtrip`: `hideHud` on, `Open()` then `Close()` → fake minimap opacity 0, corner root opacity
    `cornerOpacity`.
  - `corner.off_means_today`: `replaceMinimap` off → after `Close()` the loop is not alive and no corner child exists.
- [ ] **Step 2:** `tools/check.sh` → `COMPILE FAILED`.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `tools/check.sh` → passes; `python3 -m pytest tools` → passes.
- [ ] **Step 5:** Write `corner.json`: `selftest` (expect `failed=0`); `corner` (expect `shown`); `open`, `zoom 2`,
  close, `corner` (expect the new mpp); menu open/close and photo mode, `corner` each time (expect `hidden` then
  `shown`); toggle the option off via the settings command, `corner` (expect `off`, `vanilla_opacity` back); hold-to-show
  and `padhold VIEW` open/close, then `vpos` before/after a move (V not locked).
- [ ] **Step 6:** **Checkpoint — ask the user**, then run `install.sh` (game closed) and the `corner.json` campaign;
  ask the user for a hand look at all three styles. Record in `notes/CHECKPOINTS.md`.
- [ ] **Step 7:** Commit `feat(corner): replace the vanilla minimap and expand on the map key`.

## Phase C — colours

### Task 7: HUD palette read-back

**Files:**
- Create: `r6/scripts/NightMap/Core/HudPalette.reds`
- Create: `r6/scripts/NightMap/Debug/SelfTestPalette.reds` (registered in `SelfTest.Run`)

**Interfaces (Produces):**
- `enum NMColorRole { Accent, Highlight, Background, PanelBg, Text, Muted, Warn, Route, Enemy, Police, Player, Road, Floor, Wall, FastTravel, Relic }`
- `NMHudPalette.Create(window: wref<inkCompoundWidget>) -> ref<NMHudPalette>` (builds hidden probes, one per role);
  `Refresh() -> Bool` (re-reads probes; true when any colour changed); `Get(role: NMColorRole) -> HDRColor`;
  `static Slot(role: NMColorRole) -> CName`.
- Slot table (`Slot`): Accent `MainColors.Blue`, Highlight `MainColors.ActiveBlue`, Background
  `MainColors.PanelDarkBlue`, PanelBg `MainColors.PanelBlack`, Text `MainColors.White`, Muted `MainColors.MildBlue`,
  Warn `MainColors.Red`, Route `MainColors.Yellow`, Enemy `MainColors.EnemyMinimapBase`, Police `MainColors.SupBlue`,
  Player `MainColors.ActiveGreen`, Road `MainColors.DarkBlue`, Floor `MainColors.White`, Wall `MainColors.Neutral`,
  FastTravel `MainColors.FastTravel`, Relic `MainColors.RelicColor` (Road/Floor/Wall copy HUD Painter's minimap
  patch). If Task 2 replaced probes with reading the style resource, keep this interface and swap the internals.

- [ ] **Step 1:** Tests: `palette.slot_table` (each role → the slot above); `palette.readback` (after `Refresh` in a
  test window, `Get(Route)` equals the vanilla `MainColors.Yellow` value from `main_colors.inkstyle`, which FINDINGS
  records).
- [ ] **Step 2:** `tools/check.sh` → `COMPILE FAILED`. **Step 3:** implement. **Step 4:** `tools/check.sh` → passes.
- [ ] **Step 5:** Commit `feat(theme): read HUD palette colours back from style-bound probes`.

### Task 8: Route NightMap colours through the palette

**Files:**
- Modify: `r6/scripts/NightMap/Core/Theme.reds`, `r6/scripts/NightMap/Core/NightMapSystem.reds`
- Modify: `r6/scripts/NightMap/Debug/SelfTestPalette.reds`

**Interfaces:**
- `NMTheme.Use(p: ref<NMHudPalette>)` / `NMTheme.Palette() -> ref<NMHudPalette>` held on `NightMapSystem` (set when
  `followHudPainter` is on, null otherwise). Every colour function in `Theme.reds` (`Cyan`, `Text`, `Pink`, `Yellow`,
  `Muted`, `PanelBg`, `CardBg`, `MapBackground`, `VanillaStateColor`, `HoloAccent`, `HoloHighlight`, `HoloBackground`,
  `HeaderTitle`, `SidebarBg`, `CardLabel`, `CardBody`, `TileTint`) returns the palette role's colour when a palette is
  set, and today's constant otherwise. Call sites do not change.
- Role mapping: Cyan/HoloAccent → Accent; HoloHighlight/HeaderTitle → Highlight; HoloBackground/MapBackground →
  Background; PanelBg/SidebarBg/CardBg → PanelBg; Text/CardBody → Text; Muted/CardLabel → Muted; Pink → Warn; Yellow →
  Route; VanillaStateColor: Quest → Route, Player → Player, FastTravel/FastTravelMetro → FastTravel, Relic → Relic,
  Prevention_LightBlue → Police, others unchanged; TileTint: road_major/road_minor → Road, bfill → Floor, outline/glow
  → Wall.
- When `Refresh()` reports a change (polled every 60 frames while a view is live): `ApplyTheme()` and rebuild the
  corner.

- [ ] **Step 1:** Tests: `palette.off_is_today` (no palette → `NMTheme.Cyan()` equals the current constant, and
  `TileTint("road_major", 0)` equals `#8fdcff`); `palette.on_routes_roles` (a palette with known colours → `Cyan()`
  returns its Accent, `TileTint("bfill", 0)` returns its Floor).
- [ ] **Step 2:** compile red. **Step 3:** implement. **Step 4:** compile green.
- [ ] **Step 5:** **Ask the user** for a hand check with HUD Painter installed and a non-default preset, both views.
- [ ] **Step 6:** Commit `feat(theme): follow HUD Painter colours when asked`.

## Phase D — parity (names per FINDINGS; Task 2 fixes them)

### Task 9: Minimap mirror and enemy dots / cones

**Files:**
- Create: `r6/scripts/NightMap/Minimap/Mirror.reds`, `r6/scripts/NightMap/Minimap/Wraps.reds`,
  `r6/scripts/NightMap/Minimap/ShapeLayer.reds`
- Create: `r6/scripts/NightMap/Debug/SelfTestParity.reds` (registered)
- Modify: `r6/scripts/NightMap/Corner/Corner.reds`, `r6/scripts/NightMap/Core/NightMapSystem.reds` (expanded panel
  gets a shape layer between routes and items)

**Interfaces (Produces):**
- `enum NMMiniKind { Enemy, Police, Device, Loot, Vehicle, Area, SearchArea, Zone, Other }`
- `class NMMiniEntry { key: Uint64; kind: NMMiniKind; x, y, z: Float; heading: Float; coneAngle: Float; coneRange: Float; state: Int32; radius: Float; part: CName; vertical: Int32 }`
- `NMMinimapMirror` (owned by `NightMapSystem`): `Upsert(e: ref<NMMiniEntry>)`, `Remove(key: Uint64)`,
  `Entries(kind: NMMiniKind) -> array<ref<NMMiniEntry>>`, `revision: Int32`. Fed only by `Wraps.reds`.
- `Wraps.reds`: `@wrapMethod` on the stealth mappin controller's init/update/uninit (exact methods per FINDINGS),
  calling `NightMapSystem.Get(gi).Mirror().Upsert/Remove`.
- `NMShapeLayer.Create(parent: ref<inkCanvas>, scale: Float) -> ref<NMShapeLayer>`;
  `Update(cam: ref<NMCamera>, mirror: ref<NMMinimapMirror>, viewW: Float, viewH: Float, enemies: Bool, police: Bool)` —
  draws cones (vanilla atlas parts from FINDINGS, rotated to `heading`, scaled to `coneRange / mpp`, tinted per
  `state` with the vanilla colours) and enemy dots; pooled widgets; relayout only on camera or mirror revision change.
- Police: existing `NMVanilla` police dots stay; `cornerPolice` hides them in the corner only.

- [ ] **Step 1:** Tests: `parity.mirror_upsert_remove`; `parity.cone_geometry` (entry heading 90°, range 20 m, mpp 0.5
  → cone widget rotation 90°, length 40 px); `parity.enemies_ignore_filter` (filter view JOBS → enemy entries still
  drawn in the corner); `parity.enemies_switch` (`cornerEnemies` off → none drawn in the corner, still in expanded).
- [ ] **Step 2:** compile red. **Step 3:** implement. **Step 4:** compile green.
- [ ] **Step 5:** Campaign `tools/soak/plans/corner-enemies.json` (ask first): gang-area save, `mm_stealth` vs a new
  `corner_enemies` command (counts and positions equal within 1 m); screenshot while spotted.
- [ ] **Step 6:** Commit `feat(parity): enemy dots and vision cones from the vanilla minimap`.

### Task 10: Markers the vanilla minimap draws that NightMap doesn't

**Files:** Modify `Minimap/Wraps.reds`, `Minimap/Mirror.reds`, `Corner/Corner.reds`, `Render/ItemRenderer.reds`;
create `r6/scripts/NightMap/Minimap/Parity.reds`; tests in `SelfTestParity.reds`.

**Interfaces (Produces):**
- `NMParity.Vertical(dz: Float) -> Int32` (−1 below, 0 level, 1 above; thresholds from FINDINGS).
- `NMParity.ClampToRim(px: Float, py: Float, l: ref<NMCornerLayout>, inset: Float) -> Vector2` (circle: onto the
  circle; square styles: onto the map-area rectangle) and `NMParity.IsOff(px, py, l) -> Bool`.
- Minimap-only icons (cameras, turrets, loot, V's vehicle, and every other FINDINGS row of that kind) mirrored as
  `NMMiniKind.Device/Loot/Vehicle` entries and drawn through a `minimap.icons` API layer with vanilla atlas parts.
- Tracked objective (and anything vanilla clamps) drawn at `ClampToRim` with the vanilla clamp arrow part when off-map;
  above/below arrows on items whose `Vertical` ≠ 0, in both views.

- [ ] **Step 1:** Tests: `parity.vertical` (thresholds at ±their FINDINGS values); `parity.rim_circle` (point far east
  of a circle corner → lands on the circle at angle 0); `parity.rim_square`; `parity.icons_layer` (a Device entry
  appears as an item in `minimap.icons`).
- [ ] **Step 2:** red. **Step 3:** implement. **Step 4:** green.
- [ ] **Step 5:** Commit `feat(parity): minimap-only icons, rim clamping, above/below arrows`.

### Task 11: Areas, zones, wanted

**Files:** Modify `Minimap/Wraps.reds`, `Minimap/Mirror.reds`, `Minimap/ShapeLayer.reds`, `Corner/Corner.reds`; tests
in `SelfTestParity.reds`.

- Quest areas and search areas: `NMMiniKind.Area/SearchArea` entries with `radius`; `NMShapeLayer` draws filled
  circles (vanilla parts/colours from FINDINGS) under markers, both views.
- Restricted / hostile zone: tint the corner frame and show the zone label exactly as the vanilla minimap does (text
  and colours from FINDINGS). Strip style: label replaces nothing; it sits above the district in the strip. Other
  styles: label under the map area, inside the vanilla box.
- Wanted indicator: if FINDINGS shows it lives inside the faded minimap widget, `NMMinimapProbe.Fade()` fades only
  the map part (path from FINDINGS) so it stays vanilla; otherwise nothing to do.

- [ ] **Step 1:** Tests: `parity.area_radius` (radius 50 m at mpp 0.5 → 200 px diameter widget);
  `parity.zone_label_inside_box` (label rect inside the layout box for every style); `parity.wanted_untouched` (after
  `Fade()`, the wanted widget path's opacity is unchanged).
- [ ] **Step 2:** red. **Step 3:** implement. **Step 4:** green.
- [ ] **Step 5:** Campaign (ask first): restricted-area save and `wanted 2`; screenshots of each style.
- [ ] **Step 6:** Commit `feat(parity): quest and search areas, zones, wanted`.

## Phase E — ship

### Task 12: Performance

**Files:** Modify `r6/scripts/NightMap/Debug/PerfSuite.reds`, `r6/scripts/NightMap/Debug/SelfTestPerf.reds`; create
`tools/soak/plans/corner-perf.json`.

- `PerfSuite` gains a corner case that records corner script ms per frame (same method as `perfItemMs`).
- [ ] **Step 1:** Test `perf.corner_case_registered`. red → implement → green.
- [ ] **Step 2:** `corner-perf.json`: the fast City Center drive and a gang-area fight, each twice — option off, then on.
- [ ] **Step 3:** **Ask the user**, run it. Pass = mean frame time on − off ≤ 0.5 ms on both routes. Fail → profile
  (`perfTileMs`, `perfItemMs`, shape layer), add a corner update stride or cheaper relayout, re-run.
- [ ] **Step 4:** Record numbers in `notes/CHECKPOINTS.md`; commit `perf(corner): budget the corner minimap`.

### Task 13: Docs and final checkpoint

**Files:** Modify `README.md`, `docs/api.md` (if the API layers `minimap.icons` etc. are public).

- [ ] **Step 1:** README: the Minimap settings, the three styles, HUD Painter colours (optional; no NightMap colour
  pickers), what parity covers, and that the vanilla minimap keeps running underneath.
- [ ] **Step 2:** `tools/check.sh` and `python3 -m pytest tools` pass; full `regression.json` + `corner.json`
  campaigns (ask first) → `failed=0`.
- [ ] **Step 3:** User hand checkpoint against the FINDINGS parity checklist, every row ticked or explicitly waived by
  the user. Record in `notes/CHECKPOINTS.md`.
- [ ] **Step 4:** Commit `docs: corner minimap`.
