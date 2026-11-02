# NightMap corner minimap — design

Date: 2026-11-02. Status: approved; in implementation (Phase A, Task 1).

## Implementation progress (updated 2026-11-02)

Branch `feat/corner-minimap`. Plan: `docs/superpowers/plans/2026-11-02-nightmap-corner-minimap.md`.
Ledger: `.superpowers/sdd/2026-11-02-nightmap-corner-minimap/progress.md`. Execution: inline
(superpowers:executing-plans) — every task implemented in one session, one fresh whole-branch review at the end.

**Done**
- **Task 1, offline portion (commit `0b8676a`).** The parity-spike instrumentation is built and compiles:
  - `tools/soak/autopilot/MinimapSpike.reds` — `@wrapMethod`s on `BaseMinimapMappinController` /
    `MinimapStealthMappinController` / `MinimapSecurityAreaMappinController`, a container stash on
    `MinimapContainerController.OnPlayerAttach` (chains with `Vanilla/Gps.reds`, since the container is a
    `inkProjectedHUDGameController` and is **not** reachable via `inkWidget.GetController()`), plus static
    tree/visibility/palette/mask helpers.
  - Spike commands wired in `tools/soak/autopilot/SystemBody.inc` + `SoakHooks.reds`: `mm_tree`, `mm_vis`,
    `mm_reset`, `mm_ctrls`, `mm_stealth`, `mm_zone`, `palette_probe`, `palette_read`, `mask_probe`.
  - Staged into the campaign build (`tools/soak/paths.py`, `builds.py`, `tools/check.sh --soak`); harness fixture in
    `tools/test_soak.py` updated. Spike plan: `tools/soak/plans/minimap-spike.json` (one `probe` run).
  - Verification: `tools/check.sh --soak` and base `tools/check.sh` → COMPILE OK; `python3 -m pytest tools` → green.
  - The shipping build was installed via `tools/install.sh` at the user's request; the spike is **campaign-only** and
    is not in the shipping build.

**Blocked / in progress**
- **Task 1, Step 3 — the in-game parity-spike run.** The user runs this themselves (standing rule: ask before every
  in-game run). Per save:
  `python3 -m tools.soak.soak campaign --save <SAVE> tools/soak/plans/minimap-spike.json`.
  Coverage wanted: open street, hostile gang area (get spotted), restricted/security area, in a vehicle. Results land
  in `.soak/results/<timestamp>-minimap-spike/`. No results exist yet.

**Next**
1. When the user hands over the results directory: read `result.json` (command answers), `channel/mm_*.txt` (dumps)
   and the screenshots.
2. Write `docs/superpowers/specs/2026-11-02-corner-minimap-spike/FINDINGS.md` — the parity checklist table (one row per
   vanilla-minimap element: what it shows / vanilla source class+method+atlas / readable from script yes·no·partial /
   how NightMap gets it) plus the game hiding mechanism, the vanilla box widget path, the mask resource path+result,
   the palette read-back result, and the vertical-relation thresholds. Any `no`/`partial` row or a failed palette/mask
   probe goes back to the user with a proposed substitute **before** Tasks 8–11 are finalised.
3. Commit FINDINGS (`feat(spike): …`), then Task 2 (amend plan Tasks 8–11 to the findings), then proceed task-by-task
   through Tasks 3–13.

**Open question to settle before Task 6:** the plan stores corner zoom in a `persistent` field on `NightMapSystem`
(**per-save**); this spec's "Calls made by Claude" says it "persists across game restarts and save loads… stored like
other settings" (reads **global**). Confirm with the user which scope is wanted before implementing Task 6.

## Intent

Let the player replace Cyberpunk 2077's vanilla minimap with NightMap. With the option on, NightMap lives permanently
in the vanilla minimap's spot at the vanilla minimap's size ("corner mode"). The open/close key (the user plays with it
bound to `\`; the shipped default is `'`) expands it into the large panel NightMap shows today ("expanded mode"); closing
shrinks it back to the corner instead of removing it.

Why: NightMap already looks and reads better than the vanilla map when open; the user wants that same map all the time,
not only when they stop to open it.

**The bar is "better than vanilla, at no cost".** The user will turn this off and go back to the vanilla minimap if any of
these hold:

- it does not look better than the vanilla minimap;
- something does not work (anything the vanilla minimap tells you that corner mode silently loses counts);
- it costs noticeable performance.

## Goals

1. **Option, off by default.** New Mod Settings switch "Replace vanilla minimap". Off = NightMap behaves exactly as today.
2. **Corner mode.**
   - Occupies the vanilla minimap's on-screen box. The box is measured at runtime from the vanilla minimap widget in the
     HUD (so it tracks resolution, aspect ratio and the game's HUD scale), not hard-coded.
   - North-up, never rotates. Follows V; V's arrow (heading-rotated, as today) at the centre.
   - Markers: the same set the expanded map shows under the current filter view (ALL / JOBS / SERVICES) and the per-
     category Map filter / Collectibles switches. Changing the filter in the expanded map changes the corner.
   - Zoom: the corner uses the zoom (metres per pixel) the player last left the expanded map at. There is no zoom
     control in corner mode.
   - GPS routes drawn (quest yellow / gig teal, as today), subject to the existing "GPS routes" switch.
   - Never takes input. Keyboard, mouse and controller stay with the game.
3. **Three styles**, chosen by a new "Corner map style" setting:
   - **Circle** — round clip, thin holo ring, an "N" tick at the top.
   - **Square** — a miniature of the expanded panel: square clip, the same corner brackets, the same V reticle.
   - **Square + info strip** (default) — Square plus a thin strip beneath: district name on the left, distance to the
     tracked objective on the right (district only when nothing is tracked).
   Mockups: `.superpowers/brainstorm/*/content/corner-look.html` (not committed; regenerate from this description).
4. **Expand / shrink.**
   - Key press (or hold, with "Hold key to show") expands to the current expanded panel with everything it has today:
     pan, zoom, filter cycling, act, teleport, fast travel, sidebar, hint bar, controller ownership.
   - Close returns to the corner and re-centres on V; the zoom the player ended on is kept and becomes the corner's zoom.
   - The controller "Hold View" open path expands the same way.
5. **Enemies** (corner and expanded): vanilla-equivalent hostile NPC dots with vision cones whose colour follows the
   NPC's detection state, shown under the same conditions the vanilla minimap shows them. Always shown in the corner
   regardless of filter view (see §Customisation for the switch). Police dots already exist (`Vanilla/Vanilla.reds`
   `IsPolice`) and stay.
5a. **Full parity with the vanilla minimap.** User decision: *everything the vanilla minimap does, NightMap's corner
   must do.* NightMap today mirrors world-map mappins only; the vanilla minimap also draws, at least:
   - the tracked objective clamped to the rim when off-map;
   - above/below elevation arrows on markers;
   - quest areas and search-area circles;
   - restricted / hostile zone shading and the security-zone label;
   - NCPD search areas and the wanted indicator (if it lives in or is hidden with the minimap widget);
   - minimap-only icons (cameras, turrets, loot, V's vehicle, …);
   - enemy dots and vision cones (item 5), police dots (exists).
   This list is a starting point, not the definition. **The parity spike (first build step) inventories every widget
   and mappin controller the vanilla minimap uses** (`MinimapContainerController` and its mappin controllers), records
   for each what it shows and whether script can read it, and the result becomes the parity checklist. Anything that
   proves unreadable comes back to the user with a proposed substitute; nothing is dropped silently.
6. **Hides when vanilla would.** Corner mode is invisible whenever the vanilla minimap is (menus, scanner, cutscenes,
   braindance, photo mode, loading, death, …). Following the vanilla widget's own effective visibility is the intended
   mechanism, rather than enumerating game states.
7. **Customisation** (Mod Settings):
   - Theme: the existing "Hologram colour" preset and "Hologram effects" apply to both modes (one theme; expanding never
     changes colour).
   - **"Follow HUD Painter colours"** switch, off by default. Off: today's NightMap colours, unchanged. On: every NightMap
     colour is taken from the game's HUD palette (`base\gameplay\gui\common\main_colors.inkstyle`, `MainColors.*`
     slots). HUD Painter patches that resource in place, so NightMap follows whatever preset the player made in HUD
     Painter's in-game colour picker. No compile- or load-time dependency on HUD Painter: without it the switch simply
     follows the vanilla palette.
   - **No per-colour settings in NightMap.** Players who want custom colours use HUD Painter. (Explicit user decision.)
   - Sizes: corner scale relative to the measured vanilla box, corner marker size, strip/label text size, ring/frame
     thickness, expanded-panel size, corner opacity (separate from the existing panel opacity).
   - Markers: the existing Map filters and Collectibles switches; new switches for enemies and police on the corner.
8. **Performance budget**, measured, not assumed. Extend the perf suite (`Debug/PerfSuite.reds`, `SelfTestPerf.reds`)
   with a corner-mode case (standing, walking, driving fast through dense City Center, combat with enemies) and
   set a budget from it before shipping. Corner mode must not redraw everything every frame; it redraws on camera
   change, marker changes and route reads, as the expanded map's revision checks already do (`cam.revision`,
   `api.revision`).

## Non-goals

- No auto-zoom-out at vehicle speed (the vanilla minimap does this; the user chose a kept, player-set zoom).
- No rotation / heading-up mode.
- No input in corner mode (no zoom keys, no clicking).
- No NightMap-side colour pickers or per-colour sliders.
- Not replacing the world map (the pause-menu map).

## Anti-goals (would make this a failure even if it technically works)

- Looks worse than the vanilla minimap in the corner (muddy at that size, unreadable markers, clutter).
- Loses information the vanilla minimap gives in play — above all enemy dots/cones in a fight, and routes.
- Breaks anything that works today: GPS route reading, `\` behaviour, hold-to-show, controller open/close (note the
  known risk that closing with View can lock V's movement), "Hide HUD while open", teleport, fast travel.
- A measurable FPS drop during normal play.
- Corner map visible when the vanilla minimap would not be (e.g. over a menu or cutscene).

## Constraints and known facts

- **The vanilla minimap must keep running.** GPS routes are read from it (`Vanilla/Gps.reds`), and `NMHudHider` already
  fades HUD widgets by opacity for exactly this reason. Corner mode fades the vanilla minimap by opacity, never removes
  or disables it, and restores it when the option is turned off.
- **Today the panel is built on open and destroyed on close** (`NightMapSystem.Open` / `Close`, `NMPanel.Build` /
  `Destroy`), and the frame loop (`Tick`) stops when closed. Corner mode needs a persistent widget tree and a loop that
  runs while the corner is shown. How the two modes share widgets is the builder's call.
- **HUD window:** `inkHUDLayer` virtual window (`NightMapSystem.HudWindow`). The vanilla minimap is a widget in that
  window; finding it and reading its absolute box is part of the work.
- **Mod Settings** offers toggles, sliders and dropdowns only (no colour picker) — hence HUD Painter for colours.
- **HUD Painter 1.4.1** (archive the user supplied): patches `main_colors.inkstyle` on `Resource/Loaded`; re-points the
  vanilla minimap's style (`MiniMapStyle.RoadColor` → `MainColors.DarkBlue`, `FloorColor` → `MainColors.White`,
  `ExteriorWallColor` / `InteriorWallColor` → `MainColors.Neutral`). Has `MainColors.EnemyMinimapBase`,
  `MainColors.EnemyBase`, `MainColors.CombatRed`, the Blue / Yellow / Red families, `FastTravel`, `RelicColor`, etc.
- **Parity is unproven.** NightMap mirrors world-map mappins already, but it is not yet known which minimap-only data
  is readable from script: hostile NPC (stealth) mappins with facing, cone angle/range and detection state; zone
  shading; area circles; elevation; rim clamping; minimap-only icons. **First build step is the parity spike** (§5a),
  proven in-game and written up like the earlier spikes (`docs/superpowers/specs/*-spike/FINDINGS.md`). Anything that
  cannot be read reliably goes back to the user with a proposed substitute — never an approximation shipped silently.
- **If the vanilla minimap widget also hosts things that are not the map** (zone label, wanted indicator), fading it
  must not lose them: either NightMap redraws them (parity) or only the map part of the widget is faded.
- **Soak/perf runs:** ask the user before running anything that launches or drives the game; a campaign once killed
  their game session.

## Decided by the user

- Option to replace the vanilla minimap; corner mode starts at the vanilla minimap's size and position.
- The key expands to a big view like the current one.
- North-up, no rotation.
- Corner markers = the current filter, changeable at any time.
- Zoom set in the expanded view and kept in the corner.
- Three styles (Circle, Square, Square + info strip), all available, Square + info strip default.
- Enemy dots and vision cones implemented.
- Very customisable: theme, colours, sizes, which markers.
- Colours: optional "follow HUD Painter", default keeps current colours; no NightMap per-colour settings.
- Full parity: everything the vanilla minimap does, the corner map does.

## Calls made by Claude (not confirmed by the user)

- Shrinking re-centres on V.
- Info strip sits inside the vanilla box (map area shrinks), so the quest tracker below is never pushed or covered.
- Corner follows the vanilla minimap's visibility rather than a list of game states.
- Enemies always shown in the corner regardless of filter view, with their own on/off switch.
- Colour mapping under "Follow HUD Painter": copy HUD Painter's own minimap mapping for the map body (roads DarkBlue,
  floors White, walls Neutral), enemies `EnemyMinimapBase`, route `Yellow`, frame/ring and V's arrow from the Blue family.
  Exact slot table is the builder's to finalise and document.
- One shared theme for both modes; separate opacity per mode.
- Redraw on change, not per frame.
- If the enemy spike fails, only the enemy work stops; corner mode, styles, HUD Painter and customisation proceed in
  parallel. The fallback offered to the user is dots without cones (or dots with a non-directional detection ring),
  never a silent approximation.
- Performance pass bar: corner mode adds ≤ 0.5 ms per frame (perf suite, fast drive through City Center, compared
  against the same run with the option off). Every in-game run (spikes, perf, soak) is asked for first; the user
  either runs it or says go.
- The corner zoom persists across game restarts and save loads (stored like other settings, hidden from the menu if
  Mod Settings allows). First-ever launch uses a corner-appropriate default, not `OpenMpp()`.

## Left to the builder

- Widget architecture for the two modes (one tree re-laid-out vs. two trees sharing layers), and the expand/shrink
  transition (instant or short animation).
- How to locate the vanilla minimap widget and read its box robustly.
- How to read resolved `MainColors.*` values (style binding vs. reading the style resource) and when to re-read.
- Marker density/decluttering at corner scale (the tiered declutter in `Render/Tiers.reds` is the starting point).
- Exact ranges and defaults of the size sliders.
- Self-tests for the new pieces, in the style of `Debug/SelfTest*.reds`.
