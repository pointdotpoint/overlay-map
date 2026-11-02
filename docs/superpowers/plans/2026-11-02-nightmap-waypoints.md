# NightMap Waypoints Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enter (pad RB) on NightMap's expanded map sets the vanilla custom waypoint, tracks a job's quest, or tracks
any other marker, through a small optional RED4ext plugin.

**Architecture:** A RED4ext DLL `NightMapNative` registers redscript-callable global natives and ships their
declarations (`module NightMapNative`) through `sdk->scripts->Add`, so they exist only when the DLL loads. It finds the
engine's mappin-tracking internals at runtime by following the RTTI-registered `WorldMapMenuGameController` natives
(`TrackMappin`, `UntrackMappin`, `TrackCustomPositionMappin`, `UntrackCustomPositionMappin`), checked by byte patterns;
any mismatch makes it report unavailable. NightMap decides the action in a pure `NMWaypoint.Decide` and calls the
plugin behind `@if(ModuleExists("NightMapNative"))`.

**Tech Stack:** C++ (RED4ext.SDK at `~/cyberpunk_photomode_custompose/vendor/RED4ext.SDK`), mingw-w64 (fallback
clang-cl + lld-link + xwin-downloaded MSVC CRT/SDK, user-approved), redscript, Codeware, the soak harness.

**Spec:** `docs/superpowers/specs/2026-11-02-nightmap-waypoints-design.md`

## Global Constraints

- Key: setting `keyWaypoint`, default `EInputKey.IK_Enter` (both Enter keys; hint "ENTER"); pad: `IK_Pad_RightShoulder`
  while the map holds the pad.
- Enter on: empty spot → custom waypoint there; job/gig (`NMVanillaTracking.CanTrackQuest`) → track its quest (works
  without the plugin); other vanilla marker → track it; photo / collectible / other-layer pin → custom waypoint at the
  pin; the current custom waypoint or tracked marker → clear it; the already-tracked quest → nothing.
- One custom waypoint (vanilla replaces). `Numpad 0` (act) unchanged.
- Plugin optional: without it NightMap compiles and runs as today, the waypoint hint is hidden except on quests.
- Fails closed: unknown engine bytes → `NightMapNative_Available()` false, logged once, no call made.
- Ships inside the main mod: `red4ext/plugins/NightMapNative/NightMapNative.dll` + `Scripts/NightMapNative.reds`,
  installed by `tools/install.sh`.
- Never read a field off a call's temporary in redscript (bind to a local first).
- In-game runs: soak campaigns `python3 -m tools.soak.soak campaign --save QuickSave-7 --allow-cloud <plan>`; the user
  set the goal "implement the spec and test ingame until it's ready".

## Review Focus

- **Game update / unknown exe:** the plugin must not call anything; `Available()` false. Test: plugin self-check refuses
  a mismatched pattern (Task 2, `wp_selfcheck` answer `ok` on 2.31, unit test of the matcher with a wrong byte).
- **Plugin absent:** NightMap compiles (`tools/check.sh` without the plugin's reds) and Enter on a quest still tracks.
  Test `wp.decide_no_plugin` (Task 3).
- **Enter while the map is closed:** must do nothing (Enter is a common key). Test `input.waypoint_only_open` (Task 3).
- **Waypoint on an empty spot in water / off the map bounds:** placed at the focus point's ground height or the player's
  Z; never NaN. Test `wp.ground_z_fallback` (Task 3).
- **Replace and toggle:** a second Enter elsewhere moves the waypoint (one only); Enter on it clears. Campaign
  `waypoints.json` (Task 4).

---

### Task 1: Plugin skeleton + a registered native callable from redscript (spike, in game)

**Files:**
- Create: `native/NightMapNative/Main.cpp`, `native/NightMapNative/NightMapNative.reds`, `tools/native/build.py`
  (cross-compile → `red4ext/plugins/NightMapNative/NightMapNative.dll` + `Scripts/NightMapNative.reds` under
  `dist-native/`), `docs/superpowers/specs/2026-11-02-waypoints-spike/FINDINGS.md`
- Modify: `tools/install.sh` (copy the plugin folder when built), `tools/check.sh` (`--native`: also compile with the
  plugin's reds), `tools/soak/paths.py`/`builds.py` (campaign part `native`), soak hooks (`wp_version`, `wp_rvas`)

**Interfaces (Produces):**
- redscript (module `NightMapNative`): `public static native func NightMapNative_Version() -> Int32` (returns 1),
  `public static native func NightMapNative_Rvas() -> String` (the four world-map natives' RVAs, `name=0x…|…`).

- [ ] Build with mingw (`-std=c++23`, the photomode case-fix shims approach); `tools/check.sh --native` → COMPILE OK.
- [ ] Campaign `tools/soak/plans/waypoints-spike.json`: `wp_version` expect `^1$`, `wp_rvas`.
- [ ] If the native isn't callable (load error, crash, missing function): switch to clang-cl + lld-link with
  `xwin`-downloaded MSVC CRT/Windows SDK; same test. Record which toolchain works in FINDINGS.
- [ ] Disassemble the four RVAs (`llvm-objdump -d --start-address --stop-address` on `Cyberpunk2077.exe`, image base
  0x140000000): note each call target, the argument setup, and stable byte patterns. FINDINGS: the internal functions,
  their arguments, and how to reach them from the natives.
- [ ] Commit `feat(native): NightMapNative skeleton callable from redscript`.

### Task 2: Engine calls: set / clear custom waypoint, track / untrack mappin

**Files:** Modify `native/NightMapNative/Main.cpp`; create `native/NightMapNative/Resolve.hpp` (+ `ResolveTest.cpp`,
host-compiled with g++ for the matcher); soak hooks `wp_set x y z`, `wp_clear`, `wp_track_nearest <layer part>`,
`wp_state`.

**Interfaces (Produces, redscript):**
- `NightMapNative_Available() -> Bool`
- `NightMapNative_SetWaypoint(pos: Vector4) -> Bool` (replaces any custom waypoint)
- `NightMapNative_ClearWaypoint() -> Bool`
- `NightMapNative_TrackMappin(id: NewMappinID) -> Bool`
- `NightMapNative_Untrack() -> Bool` (custom waypoint or tracked marker)

- [ ] Matcher test (host g++): pattern with wildcards matches the recorded bytes, refuses one changed byte.
- [ ] Implement per FINDINGS; every call gated by `Available()`.
- [ ] Campaign: `wp_set` near V → `wp_state` shows a custom-position mappin tracked (`GetManuallyTrackedMappinID`
  non-zero, variant `CustomPositionVariant`), GPS route read non-empty; `wp_set` elsewhere → one mappin, moved;
  `wp_clear` → none; `wp_track_nearest Services` → tracked id equals that mappin; screenshots of vanilla map pin.
- [ ] Commit `feat(native): set, clear and track waypoints`.

### Task 3: NightMap side

**Files:** create `r6/scripts/NightMap/Vanilla/Waypoint.reds` (`NMWaypoint`), `Debug/SelfTestWaypoint.reds`
(registered); modify `Core/Settings.reds` (`keyWaypoint`), `Core/Input.reds` (`waypoint` flag, hint), `Core/Pad.reds`
(RB → `waypoint`), `Core/NightMapSystem.reds` (act on it), `Render/HintBar.reds` only if needed.

**Interfaces (Produces):**
- `enum NMWaypointAction { None = 0, TrackQuest = 1, SetCustom = 2, TrackMappin = 3, Clear = 4 }`
- `NMWaypoint.Decide(hasSel: Bool, isMappin: Bool, questTrackable: Bool, questTracked: Bool, isTrackedNow: Bool, plugin: Bool) -> NMWaypointAction`
- `NMWaypoint.Label(a: NMWaypointAction) -> String` ("TRACK QUEST", "SET WAYPOINT", "TRACK", "CLEAR WAYPOINT", "")
- `NMWaypoint.Available() -> Bool` (`@if(ModuleExists("NightMapNative"))` → `NightMapNative_Available()`, else false)
- `NMWaypoint.GroundZ(gi: GameInstance, x: Float, y: Float, fallbackZ: Float) -> Float`

- [ ] Tests: `wp.decide_*` table (empty spot → SetCustom; quest → TrackQuest; tracked quest → None; vendor → TrackMappin;
  tracked vendor or the custom waypoint → Clear; photo/collect pin (isMappin false) → SetCustom; plugin false: quest →
  TrackQuest, all else None), `wp.decide_no_plugin`, `input.waypoint_only_open`, `wp.ground_z_fallback`, labels.
- [ ] `tools/check.sh` red → implement → `tools/check.sh` and `tools/check.sh --native` green.
- [ ] Commit `feat(waypoints): Enter sets, tracks and clears waypoints`.

### Task 4: Campaign, install, docs

- [ ] `tools/soak/plans/waypoints.json`: open map; focus an empty spot (`zoom`, pan), `key Return` → custom waypoint
  tracked + route; again elsewhere → replaced; on it → cleared; `focus_layer Services` → tracked marker; `focus_layer
  Jobs`/quest → quest tracked; pad RB once; Enter with the map closed → nothing changes. Screenshots.
- [ ] Regression: `regression.json`, `corner.json`, `controller.json` pass with the plugin installed; `regression.json`
  with the plugin absent.
- [ ] README (keys, plugin optional, what each target does), install; commit `docs: waypoints`.
