# NightMap waypoints (native plugin) — design

Date: 2026-11-02. Status: approved in conversation; builder-checked; user answers folded in.

## Intent

From NightMap's expanded map the player can set where they're going, the way the vanilla world map lets them:
point the crosshair anywhere or at a marker and press one key. Scripts can't do this (see Constraints), so a small
RED4ext plugin supplies the two missing engine calls. This was the "native plugin" deferred in the vanilla-markers
design (`docs/superpowers/specs/2026-10-13-nightmap-vanilla-markers-design.md`, sub-project 3).

## Behaviour (decided by the user)

New key **Enter** ("Set waypoint", rebindable in Mod Settings → Keys; default `IK_Enter`), acting on what the crosshair
selects in the expanded map. The game has no separate Numpad Enter key code (`IK_Enter` only), so both Enter keys act
while the map is open and the hint reads "ENTER" — accepted by the user.

- **Empty spot** → the game's own custom waypoint is placed there: the vanilla pin, its GPS route (minimap, NightMap,
  corner), the distance in the corner strip — exactly as right-clicking on the vanilla world map.
- **A job or gig** (any marker whose quest NightMap can track today) → that quest becomes the active quest (objective in
  the tracker, its route).
- **Any other marker** (vendor, ripperdoc, fast travel point, drop point, …) → that marker becomes the tracked
  waypoint, as the vanilla map allows.

## Claude's calls, confirmed by the user ("this is it, proceed")

- One custom waypoint at a time, as in vanilla: a new one replaces the old.
- Numpad Enter on the current waypoint (custom or tracked marker) clears it (toggle).
- `Numpad 0` (act) keeps doing what it does today (track quest / clear waypoint); nothing existing changes.
- Controller: the same action on **RB** while the map holds the pad (RB is unused there today; see
  `docs/superpowers/specs/2026-10-31-nightmap-controller-design.md` pad layout).
- **The plugin is optional.** Without it NightMap behaves as today and the hint bar does not offer the new key.

## Answers after the builder check (user)

- Key: **Enter** (both Enter keys) is fine.
- Toolchain: if mingw can't register script-callable functions, **downloading the MSVC CRT / Windows SDK** (e.g. with
  `xwin`) for `clang-cl` + `lld-link` is allowed — "whatever works".
- Shipping: the plugin ships **inside the main NightMap download** (same archive as the scripts and the `.archive`),
  installed by `tools/install.sh`. "Plugin absent" still has to work (players who skip RED4ext, or a failed load).

## Claude's calls after the builder check

- **Pins that aren't game mappins** (photo pins, collectible pins, items on other mods' layers): Enter places the
  custom waypoint at the pin's position (collectibles become GPS-reachable).
- **Game updates:** release builds must find the engine functions at runtime (RTTI-anchored world-map natives + a
  byte-pattern check at the call site); hard-coded addresses are for the spike only. Unknown build → feature off.
- Enter on the already-tracked quest does nothing (as vanilla); the empty-spot waypoint's Z comes from the teleport
  height logic.

## Goals

1. A RED4ext plugin (working name **NightMapNative**) exposing to redscript, at minimum:
   - set the custom position waypoint at a world position;
   - clear the custom waypoint;
   - track an existing mappin (by `NewMappinID`) as the manually tracked waypoint;
   - a version / availability query.
2. NightMap uses them when present: Numpad Enter / RB per the behaviour above; the hint bar and the sidebar card show
   the action ("SET WAYPOINT", "TRACK", "TRACK QUEST", "CLEAR WAYPOINT") for the current selection.
3. Quest tracking on Numpad Enter works **with or without** the plugin (it already uses script APIs:
   `Vanilla/Tracking.reds` `NMVanillaTracking.TrackQuest`). Without the plugin, Enter on a quest still tracks it; on
   anything else it does nothing and the hint isn't shown.
4. Fails closed: if the plugin can't find the engine functions (game update), its functions report "unavailable",
   NightMap hides the action and logs once. Never a crash, never a wrong call.
5. Built on this Linux machine and installed with NightMap's existing `tools/install.sh` (plus the plugin), with an
   offline compile check in the style of `tools/check.sh`.

## Non-goals

- Delamain taxi destinations, multiple custom waypoints, waypoint labels/notes.
- Changing what `Numpad 0` does.
- Any feature beyond placing/tracking/clearing (no generic "call any native" bridge).

## Anti-goals

- A wrong engine call after a game update (corrupting a save's tracking state, a crash). Version mismatch must disable
  the feature, not guess.
- Breaking NightMap for players without the plugin (compile errors, missing-native errors at load).
- A waypoint that only NightMap sees: the vanilla map, minimap and GPS must all agree, as if set from the vanilla map.

## Constraints and known facts

- **Script API gap** (decompiled `orphans.script`, `MappinSystem`): scripts can `RegisterMappin`,
  `GetManuallyTrackedMappinID`, `UntrackMappin`, `SetMappinTrackingAlternative`, but there is **no script function to
  track a mappin or to place the custom position waypoint**.
- **Where vanilla does it** (`UI/fullscreen/map/worldMap.script`, `WorldMapMenuGameController`): native methods
  `TrackMappin(mappinController)`, `UntrackMappin()`, `TrackCustomPositionMappin()` (no arguments: uses the world map's
  own cursor), `UntrackCustomPositionMappin()`. These are RTTI-registered natives on a menu controller that only exists
  while the world map menu is open, so NightMap can't call them. Their native bodies call the engine's mappin-system
  internals; those internals are what the plugin needs.
- **Finding the internals (first build step, a spike):** at runtime the plugin can look the four natives up through
  RTTI (`WorldMapMenuGameController` class → function → native pointer), log their RVAs, and `llvm-objdump` on
  `~/cyberpunk_symlink/bin/x64/Cyberpunk2077.exe` (game 2.31, build 26161058) shows which functions they call and with
  what (e.g. a mappin-system method taking a position, or a track call taking a `NewMappinID`). Record findings in
  `docs/superpowers/specs/2026-11-02-waypoints-spike/FINDINGS.md`. If the internals take arguments we can't produce
  safely, stop and bring it back to the user.
- **Resolving addresses across game updates:** prefer anchoring on the RTTI-registered world-map natives at runtime
  (their names survive updates) and following their calls, with a byte-pattern check at the call site; if a check
  fails, the feature is unavailable (goal 4). Hard-coded RVAs only as a last resort, keyed to the game build.
- **Toolchain on this machine:** mingw-w64 (`x86_64-w64-mingw32-g++`), `clang-cl` and `lld-link` are installed;
  `cmake` 3.x. Prior art: `~/cyberpunk_photomode_custompose/plugin` (CMake + `vendor/RED4ext.SDK` + mingw case-fix
  shims, see its `notes/FINDINGS.md` "Phase 3") and `~/photomode_ui_improvements/scripts/build_thermal_target.py`
  (single-file mingw build, hooks only). **Known risk:** that mingw build excluded the SDK's `Scripting/Natives.cpp`
  (MSVC-vs-Itanium ABI) and has not proven registering new script-callable functions (RTTI `CGlobalFunction`/class
  registration). Proving a registered function callable from redscript under this toolchain is part of the spike;
  `clang-cl` + `lld-link` with MSVC headers/libs is the fallback if mingw can't.
- **Optional dependency pattern:** the plugin ships its redscript declarations through RED4ext's script registration
  (the way Codeware ships `red4ext/plugins/Codeware/Scripts`), so they exist only when the DLL loads; NightMap guards its
  calls with `@if(ModuleExists("NightMapNative"))` (pattern already used for RedIMGRetriever / RedFileSystem). Without
  the plugin NightMap compiles and runs exactly as today. `tools/check.sh` compiles both ways.
- **Ask before every in-game run** (standing rule; the user has the harness launch options enabled and asked for
  automated testing on the corner work — soak campaigns via `python3 -m tools.soak.soak campaign --save QuickSave-7
  --allow-cloud`).
- In-game script quirk (FINDINGS 2026-11-02): never read a field straight off a call's temporary
  (`m.GetNewMappinID().value` reads 0) — bind to a local first.

## What exists to build on

- Selection: the expanded map's crosshair already picks markers and photo pins (`NightMapSystem.SelectedMappin`,
  `NMCrosshair`); an empty selection has a focus point in world space (teleport uses it: `StartTeleport`).
- Quest tracking: `NMVanillaTracking.CanTrackQuest/TrackQuest/IsQuestTracked`; clearing: `ClearCustomWaypoint`,
  `ClearManual`, `ManualKey`.
- Input: `NMInput` keys + hints (`Core/Input.reds`), `NMPad` buttons (`Core/Pad.reds`), hint bar (`Render/HintBar.reds`).
- The pinned layer `Vanilla.Pinned` already shows the custom waypoint and tracked marker.

## Left to the builder

- Plugin structure, build script (CMake vs single-file), and toolchain (after the spike).
- The exact native names and signatures exposed to redscript.
- Z of a waypoint placed on an empty spot (ground height: the teleport code's height logic is a candidate).
- Hint/card wording beyond the actions named in goal 2.
- Self-tests (script side, with the plugin absent and present) and a soak campaign for set / replace / clear / track.
