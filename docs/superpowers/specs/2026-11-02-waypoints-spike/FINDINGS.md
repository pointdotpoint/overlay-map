# Waypoints spike: findings

What the in-game spike (`tools/soak/plans/waypoints-spike.json`, then `waypoints.json`) established, game build
3.0.88.46235 ("2.5", Steam build id 26161058), RED4ext SDK upstream @8ebb8da. The design assumed 2.31; the installed
game is 2.5.

## Toolchain

- mingw-w64 (GCC) works. No MSVC CRT / Windows SDK download was needed.
- The SDK copy the photo-mode plugins used (2026-03) predates 2.5 and crashed the game at startup the moment the
  plugin registered its RTTI callbacks: 2.5 doubled the `Callback` inline buffer (32 → 64 bytes). The plugin builds
  against the upstream SDK, vendored as the submodule `native/vendor/RED4ext.SDK` (override with `RED4EXT_SDK`).
- GCC/MSVC vtable difference: GCC reserves two slots for a virtual destructor, MSVC one. Engine classes whose
  destructor comes before the slot being called (`IFunction`) are called by reading the vtable by MSVC index; classes
  that declare it last (`IRTTISystem`) are safe to call directly.

## Script side

- Global `native func` declarations inside a named module (`module NightMapNative`) crash the game while it binds
  scripts. They live in `NightMapNative.Global.reds` (root module). `NightMapNative.reds` holds only `module
  NightMapNative`, the marker NightMap tests with `@if(ModuleExists("NightMapNative"))`.
- `@addMethod` on a class declared in the same file doesn't resolve under `@if`: two whole class definitions are used.

## Native handler tables (2.5)

- The SDK's `CBaseFunction_Handlers` is wrong on 2.5. There are two inline arrays in `.data`, indexed by `regIndex`
  from one shared counter: statics and globals go into table A, members into table B.
- Table A is read from the `rtti::NativeGlobalFunction` constructor (pattern in `Resolve.hpp`), then calibrated by
  looking up the plugin's own registered native. Table B is the address the SDK's hash points at, without the extra
  dereference.
- Script opcode handlers are table A's first 256 entries; the plugin reads parameters through them.

## Tracking

- `WorldMapMenuGameController.TrackMappin` body → its internal → `call [rax+0x220]` (track) / `call [rax+0x228]`
  (untrack) on the mappin system.
- Before each call the plugin checks that the instance's untrack slot holds the implementation
  `MappinSystem.UntrackMappin`'s thunk jumps to. A mismatch refuses the call.
- On a build where any pattern fails the plugin logs the failing step once and `Available()` is false, so NightMap
  hides the waypoint actions (except tracking a quest, which needs no plugin).
- Fixed addresses were used only during the spike; the shipped plugin resolves everything at runtime.

## Custom waypoint

- No engine internal is needed to place it. Script registers the pin:
  `RegisterMappin(Mappins.CustomPositionMappinDefinition, CustomPositionVariant, active, visibleThroughWalls)`.
  The plugin tracks it once `GetMappin(id)` resolves, which is a frame or more later.
- Tracking in the same frame as registering stores the id but leaves `playerTracked` false: no GPS route. Hence the
  pending track with retry in `NMWaypoint.TryPending`.
- Proven: `playerTracked=true`, GPS route on the vanilla minimap (49 points near, 256 points at ~320 m). The vanilla
  map's own custom waypoint, for comparison: `playerTracked=true`, 273 points.
- Height: the cell's baked street level (`NMWaypoint.GroundZ`); a mappin's own Z when the target is a pin. V's height
  gave routes that never formed.

## Keys

- The game has no separate Numpad Enter: `IK_Enter` is both Enter keys.
- Harness: on the desktop (no gamescope wrapper in the launch options), `xdotool` presses never reach the game under
  KWin/Wayland. The `press <action>` soak command feeds a press + release through `NightMapSystem.HandleKey`, the same
  path as the game's `Input/Key` callback.

## End-to-end result (`waypoints.json`, 2026-11-03)

Pass: empty spot → custom waypoint set and routed; another spot → moved (same id); on it → cleared; fast travel point
→ tracked, again → cleared; cyberpsycho gig → quest tracked; map closed → Enter does nothing. Self-tests 526/0.
