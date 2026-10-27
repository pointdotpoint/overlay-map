# NightMap Teleport Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One key teleports V (and V's vehicle) to the point NightMap is pointing at: exactly onto fixed vanilla
markers, otherwise onto the first surface (or water) below the map point.

**Architecture:** Pure target choice and landing maths (`NMTeleport`), a frame-stepped state machine
(`NMTeleportDriver`) that talks to the game only through two small seams (`NMMover` moves and reads the teleported
object, `NMGround` finds ground and water), and thin game adapters plus wiring in `NightMapSystem`. The seams let the
self-tests run the whole lift / settle / land / timeout sequence with fakes.

**Tech Stack:** redscript + Codeware, Cyberpunk 2077 2.5. Offline compile with `tools/check.sh`; self-tests in-game
(Debug tools on, Ctrl + toggle key).

**Spec:** `docs/superpowers/specs/2026-10-27-nightmap-teleport-design.md`

## Global Constraints

- Setting `keyTeleport: EInputKey = EInputKey.IK_NumPeriod`, category Keys, display name "Teleport".
- Setting `teleportEnabled: Bool = true`, category Display, display name "Teleport key".
- Hint bar: `<key> TELEPORT` after ACT and before FILTER, only when `teleportEnabled`.
- Every outcome logs exactly one `NMLog.Info("teleport|...")` line: `ok|marker|x,y,z`, `ok|ground|x,y,z`,
  `ok|water|x,y,z`, `failed|no ground`, `refused|outside map`, `refused|vehicle`, `refused|busy`.
- Constants (spec §6, builder's values): `LiftZ` 600 m, `SettleTimeoutMs` 5000, ray from `LiftZ - 2` down to
  `RayBottomZ` −200 m, `FootOffset` 0.5 m, `VehicleOffset` 1.0 m, `RefuseDrop` 50 m.
- Layers whose markers land exactly (on foot): any `Vanilla.*` layer except `Vanilla.Pinned` and `Vanilla.Other`.
- The map closes when a teleport starts. One teleport at a time.
- Install only with the game closed (`tools/install.sh`); compile check `tools/check.sh` must print `COMPILE OK`.

## Review Focus

1. **Second press while a teleport is settling** (map reopened and key pressed again): expect it ignored with
   `refused|busy`, not two drivers fighting. Test: `teleport.busy` in Task 3.
2. **The teleported object disappears mid-settle** (save loaded, vehicle despawned): expect the driver to stop quietly
   with `failed|lost`, never to call Move on a dead object. Test: `teleport.driver_lost` in Task 2.
3. **Fall between frames before the first hit:** each settle frame without a hit must re-lift to `LiftZ`, so V never
   falls more than one frame. Test: `teleport.driver_holds` in Task 2.
4. **Water above the hit but below the offset** (shallow puddle): expect the higher of hit + offset and water level.
   Test: `teleport.landing_shallow` in Task 1.
5. **Target exactly on the world bounds edge:** inside counts as inside (inclusive). Test: `teleport.bounds_edge` in
   Task 1.

---

### Task 1: Target choice and landing maths

**Files:**
- Create: `r6/scripts/NightMap/Core/Teleport.reds`
- Create: `r6/scripts/NightMap/Debug/SelfTestTeleport.reds`
- Modify: `r6/scripts/NightMap/Debug/SelfTest.reds` (add `NMTeleportTests.Run(this);` after `NMHudTests.Run(this);`)

**Interfaces:**
- Produces:
  - `public class NMTeleportTarget { public let x: Float; public let y: Float; public let z: Float; public let exact: Bool; }`
  - `NMTeleport.LiftZ() -> Float` (600), `SettleTimeoutMs() -> Float` (5000), `RayBottomZ() -> Float` (−200),
    `FootOffset() -> Float` (0.5), `VehicleOffset() -> Float` (1.0), `RefuseDrop() -> Float` (50)
  - `NMTeleport.ExactLayer(layerId: CName) -> Bool`
  - `NMTeleport.Choose(selKind: Int32, layerId: CName, marker: Vector4, cx: Float, cy: Float, inVehicle: Bool) -> ref<NMTeleportTarget>`
    (`selKind` as in `NMCrosshair`: 0 item, 1 cluster, anything else none; `marker` is the selected item's position)
  - `NMTeleport.InBounds(x: Float, y: Float) -> Bool` (tile manifest `WorldMin/MaxX/Y`, inclusive)
  - `NMTeleport.LandZ(hitZ: Float, hasWater: Bool, waterZ: Float, inVehicle: Bool) -> Float`
  - `NMTeleport.LandKind(hitZ: Float, hasWater: Bool, waterZ: Float, inVehicle: Bool) -> String` ("ground" or "water")

- [ ] **Step 1: Write the failing tests** in `NMTeleportTests.Run(t: ref<NMSelfTest>)`:

```
let m = new Vector4(100.0, 200.0, 35.0, 1.0);
let a = NMTeleport.Choose(0, n"Vanilla.FastTravel", m, 5.0, 6.0, false);
t.Check("teleport.choose_fixed_marker", a.exact && a.x == 100.0 && a.y == 200.0 && a.z == 35.0, "");
let b = NMTeleport.Choose(0, n"Vanilla.Pinned", m, 5.0, 6.0, false);
t.Check("teleport.choose_pinned", !b.exact && b.x == 100.0 && b.y == 200.0, "");
let c = NMTeleport.Choose(0, n"Vanilla.Other", m, 5.0, 6.0, false);
t.Check("teleport.choose_other", !c.exact && c.x == 100.0, "");
let d = NMTeleport.Choose(0, n"Vanilla.FastTravel", m, 5.0, 6.0, true);
t.Check("teleport.choose_vehicle_marker", !d.exact && d.x == 100.0 && d.y == 200.0, "");
let e = NMTeleport.Choose(1, n"Vanilla.FastTravel", m, 5.0, 6.0, false);
t.Check("teleport.choose_cluster", !e.exact && e.x == 5.0 && e.y == 6.0, "");
let f = NMTeleport.Choose(-1, n"", m, 5.0, 6.0, false);
t.Check("teleport.choose_none", !f.exact && f.x == 5.0 && f.y == 6.0, "");
let g = NMTeleport.Choose(0, n"mymod.pins", m, 5.0, 6.0, false);
t.Check("teleport.choose_other_mod", !g.exact && g.x == 100.0 && g.y == 200.0, "");
t.Check("teleport.bounds_in", NMTeleport.InBounds(0.0, 0.0), "");
t.Check("teleport.bounds_out", !NMTeleport.InBounds(NMTileManifest.WorldMaxX() + 1.0, 0.0), "");
t.Check("teleport.bounds_edge", NMTeleport.InBounds(NMTileManifest.WorldMaxX(), NMTileManifest.WorldMinY()), "");
t.Check("teleport.landing_ground", t.Near(NMTeleport.LandZ(30.0, false, 0.0, false), 30.5, 0.001)
    && Equals(NMTeleport.LandKind(30.0, false, 0.0, false), "ground"), "");
t.Check("teleport.landing_vehicle", t.Near(NMTeleport.LandZ(30.0, false, 0.0, true), 31.0, 0.001), "");
t.Check("teleport.landing_water", t.Near(NMTeleport.LandZ(-10.0, true, 0.0, false), 0.0, 0.001)
    && Equals(NMTeleport.LandKind(-10.0, true, 0.0, false), "water"), "");
t.Check("teleport.landing_shallow", t.Near(NMTeleport.LandZ(10.0, true, 10.2, false), 10.5, 0.001)
    && Equals(NMTeleport.LandKind(10.0, true, 10.2, false), "ground"), "");
t.Check("teleport.landing_water_below", t.Near(NMTeleport.LandZ(10.0, true, 5.0, false), 10.5, 0.001), "");
```

Note: an item's "other mod" layer and `Vanilla.Pinned` / `Vanilla.Other` keep the marker's X/Y; only "no item"
(cluster or none) uses the map centre.

- [ ] **Step 2: Run `tools/check.sh`.** Expected: `COMPILE FAILED` with `UNRESOLVED_REF` on `NMTeleport`.

- [ ] **Step 3: Implement `NMTeleportTarget` and `NMTeleport`** in `Core/Teleport.reds` (abstract class of statics).
  `ExactLayer`: name starts with `"Vanilla."` and is not `Vanilla.Pinned` or `Vanilla.Other`. `LandZ`: offset =
  `VehicleOffset` or `FootOffset`; ground = hitZ + offset; result = water level when `hasWater && waterZ > ground`,
  else ground. `LandKind` returns "water" exactly when `LandZ` chose the water level.

- [ ] **Step 4: Run `tools/check.sh`.** Expected: `COMPILE OK`.

- [ ] **Step 5: Commit** `feat(teleport): target choice and landing maths`.

### Task 2: Teleport driver (lift, settle, land, time out)

**Files:**
- Create: `r6/scripts/NightMap/Core/TeleportDriver.reds`
- Modify: `r6/scripts/NightMap/Debug/SelfTestTeleport.reds` (add `NMTeleportTests.DriverCases(t)` called from `Run`,
  plus the fakes below)

**Interfaces:**
- Consumes: Task 1 (`NMTeleportTarget`, `NMTeleport.*`).
- Produces:
  - `public class NMGroundHit { public let z: Float; public let hasWater: Bool; public let waterZ: Float; }`
  - `public class NMGround { public func Probe(x: Float, y: Float) -> ref<NMGroundHit> }` (base returns null = no hit;
    overridden by the game adapter in Task 3 and a fake in tests)
  - `public class NMMover { public func Valid() -> Bool; public func Position() -> Vector4; public func Move(p: Vector4) }`
    (base: `Valid` false; the game adapter keeps the object's yaw)
  - `NMTeleportDriver.Create(t: ref<NMTeleportTarget>, mover: ref<NMMover>, ground: ref<NMGround>, inVehicle: Bool) -> ref<NMTeleportDriver>`
  - `NMTeleportDriver.Step(dtMs: Float) -> Int32`: 0 running, 1 done (`result` holds the log tail)
  - `public let result: String` — one of `ok|marker|x,y,z`, `ok|ground|x,y,z`, `ok|water|x,y,z`, `failed|no ground`,
    `failed|lost`, `refused|vehicle`

Behaviour (spec §4.3–4.5), one decision per `Step`:
- First step: remember `start = mover.Position()`. Exact target → `Move(x, y, z + offset)`, done `ok|marker`.
  Otherwise `Move(x, y, LiftZ)`.
- Vehicle only, second step: if `mover.Position().Z < LiftZ - RefuseDrop` the move was refused → done
  `refused|vehicle` with no further Move.
- Each later step: `!mover.Valid()` → done `failed|lost` (no Move). Probe; a hit → `Move(x, y, LandZ(...))`, done
  `ok|<LandKind>`. No hit and elapsed ≥ `SettleTimeoutMs` → `Move(start)`, done `failed|no ground`. Otherwise
  `Move(x, y, LiftZ)` again (holds V up; resets the fall).

- [ ] **Step 1: Write the failing tests.** Fakes in the test file: `NMFakeMover extends NMMover` records every
  `Move` in `moves: array<Vector4>`, `Position()` returns the last move (or a start position), `moving: Bool` (false =
  ignores moves, for the refused case), `valid: Bool`; `NMFakeGround extends NMGround` returns a hit
  `(z, hasWater, waterZ)` once `calls >= hitOn`, else null. Cases, each driving `Step(16.0)` until it returns 1 (cap
  at 1000 steps):
  - `teleport.driver_marker`: exact target (1, 2, 3) → one move to (1, 2, 3.5), result starts `ok|marker`.
  - `teleport.driver_ground`: hit z 40 on the 3rd probe, on foot → last move Z 40.5, result starts `ok|ground`.
  - `teleport.driver_holds`: same run; every move before the last has Z == `LiftZ()` (no step lets V fall).
  - `teleport.driver_water`: hit z −10 with water 0 → last move Z 0, result starts `ok|water`.
  - `teleport.driver_timeout`: never hits, start (7, 8, 9) → last move (7, 8, 9), result `failed|no ground`, and the
    number of steps × 16 ≥ 5000.
  - `teleport.driver_refused`: vehicle, mover ignores moves (stays at Z 20) → result `refused|vehicle`, exactly one
    move recorded.
  - `teleport.driver_lost`: mover becomes invalid after the lift → result `failed|lost`, no move after the lift.

- [ ] **Step 2: Run `tools/check.sh`.** Expected: `COMPILE FAILED` on `NMTeleportDriver` / `NMMover`.

- [ ] **Step 3: Implement** `NMGroundHit`, `NMGround`, `NMMover` and `NMTeleportDriver` in `Core/TeleportDriver.reds`
  per the behaviour list. Result coordinates use `FloatToStringPrec(v, 1)` joined by commas.

- [ ] **Step 4: Run `tools/check.sh`.** Expected: `COMPILE OK`.

- [ ] **Step 5: Commit** `feat(teleport): frame-stepped teleport driver`.

### Task 3: Game adapters, key, settings and wiring; checkpoint

**Files:**
- Create: `r6/scripts/NightMap/Core/TeleportGame.reds` (adapters and the frame callback)
- Modify: `r6/scripts/NightMap/Core/Settings.reds` (two settings, after `keyFilter` and after `hideHud`)
- Modify: `r6/scripts/NightMap/Core/Input.reds` (`public let teleport: Bool`; key branch next to `keyAct`; reset in
  `ResetHeld`; hint)
- Modify: `r6/scripts/NightMap/Core/NightMapSystem.reds` (start, tick, log)
- Modify: `r6/scripts/NightMap/Debug/SelfTestTeleport.reds` (hint and busy tests)

**Interfaces:**
- Consumes: Tasks 1–2.
- Produces:
  - `NMGameMover extends NMMover`: `Create(obj: ref<GameObject>) -> ref<NMGameMover>`; holds `wref<GameObject>`;
    `Move` calls `GameInstance.GetTeleportationFacility(gi).Teleport(obj, p, new EulerAngles(0.0, 0.0, yaw))` with
    the yaw captured at `Create` (`obj.GetWorldYaw()`), so pitch and roll are level.
  - `NMWorldGround extends NMGround`: `Create(gi: GameInstance) -> ref<NMWorldGround>`; `Probe` raycasts with
    `GameInstance.GetSpatialQueriesSystem(gi).SyncRaycastByCollisionGroup(from, to, n"Static", hit, true, false)`
    from `(x, y, LiftZ - 2)` to `(x, y, RayBottomZ)`; on a valid hit, `AIScriptUtils.GetWaterLevel(gi,
    Vector3(x, y, hit.position.Z), level)` fills the water fields. *(If `Static` misses ground in testing, try
    `n"PlayerBlocker"`, which vanilla's seabed check uses.)*
  - `public class NightMapTeleportFrame extends DelayCallback` calling `NightMapSystem.TeleportTick()` (same
    zero-delay re-arm pattern as `NightMapFrame`).
  - `NightMapSystem.StartTeleport() -> Bool` (false and `refused|busy` when a driver is running) and
    `TeleportTick()`.
  - `NMInput.HintText(s, view)` includes `NMInput.KeyName(s.keyTeleport) + " TELEPORT"` after ACT only when
    `s.teleportEnabled`.

- [ ] **Step 1: Write the failing tests:**
  - `teleport.hint_on`: settings object with `teleportEnabled = true` → `StrContains(NMInput.HintText(s, "ALL"),
    "TELEPORT")`.
  - `teleport.hint_off`: `teleportEnabled = false` → not contained.
  - `teleport.busy`: with a running driver installed through a test hook
    `NightMapSystem.SetTeleportDriverForTest(d: ref<NMTeleportDriver>)`, `StartTeleport()` returns false. Clear the
    hook afterwards (`SetTeleportDriverForTest(null)`).

- [ ] **Step 2: Run `tools/check.sh`.** Expected: `COMPILE FAILED` on the missing members.

- [ ] **Step 3: Implement.** Settings: `keyTeleport` (Keys) and `teleportEnabled` (Display, description "Teleport V,
  and V's vehicle, to the map point.") with the defaults from Global Constraints. Input: when
  `s.teleportEnabled && Equals(key, s.keyTeleport)`, set `teleport` on press and consume. System, in
  `UpdateModules` next to `input.act`: on `input.teleport`, clear it and call `StartTeleport()`. `StartTeleport`:
  busy check; player and `GetMountedVehicle(player)` (object to move = vehicle if mounted, else player); target from
  `NMTeleport.Choose` using the crosshair selection (`selKind`, the selected layer's `id` and `Position(selItem)` when
  `selKind == 0`) and `camera.cx/cy`; refuse `outside map` when `!InBounds`; build the driver with `NMGameMover` and
  `NMWorldGround`; `Close()`; arm `NightMapTeleportFrame`. `TeleportTick`: step with the clamped frame time from
  `NMClock`; on 1, log `"teleport|" + result` and drop the driver; else re-arm.

- [ ] **Step 4: Run `tools/check.sh`.** Expected: `COMPILE OK`.

- [ ] **Step 5: Commit** `feat(teleport): key, settings and game wiring`, then install with the game closed
  (`tools/install.sh`).

- [ ] **Step 6: In-game checkpoint** (user). Self-tests (Ctrl + toggle) show every `teleport.*` passing, then the
  spec §5 list:
  1. On foot, empty street spot 1 km away: lands on the street, no damage.
  2. On foot, a spot on a tall building: lands on the roof.
  3. On foot, a fast travel marker: lands at it.
  4. Driving, empty road 1 km away: car and V arrive together, upright, not rolling. *(If the car keeps its speed
     after landing, add a velocity reset for vehicles in `NMGameMover.Move` if script exposes one (spec §4.5), and
     re-run this item.)*
  5. A spot out at sea: V swims at the surface (log `ok|water`); in a car, the car lands on the water.
  6. A spot outside the map bounds: nothing happens (log `refused|outside map`).
  7. Teleport setting off: key does nothing, hint hidden.
  Read the `teleport|` lines from the CET gamelog. Fix what fails before Task 4.

### Task 4: Docs

**Files:**
- Modify: `README.md` (Using it: one line for the teleport key and its setting)
- Modify: `notes/CHECKPOINTS.md` (a "Teleport, checkpoint (date)" section in the GPS checkpoint's format)
- Modify: `docs/superpowers/specs/2026-10-27-nightmap-teleport-design.md` (status: implemented on `feat/teleport`,
  plus the values actually used for §6 and any collision group change)

- [ ] **Step 1: Write the three edits.**
- [ ] **Step 2: Run** `tools/check.sh && (cd tools && python3 -m pytest -q) && (cd tools/tiles && python3 -m pytest -q)`.
  Expected: `COMPILE OK`, all Python tests pass.
- [ ] **Step 3: Commit** `docs(teleport): teleport shipped`.
