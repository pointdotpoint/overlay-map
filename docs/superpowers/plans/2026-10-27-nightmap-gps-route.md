# NightMap GPS Route Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** While NightMap is open, draw the HUD minimap's GPS routes on the map: the waypoint/tracked-pin route in white,
and the tracked quest's route in yellow (quests) or teal (gigs). Both use flowing dashes.

**Architecture:**
- **Source.** `NMGps` reads the live route points from the HUD minimap controller's `inkLinePattern` widgets. It gets
  the controller from two method wraps. It converts the points to world space with the transform measured in the
  spike, every 500 ms.
- **Drawing.** `NMRouteLayer` caches the world polylines. It trims the part V has passed, projects through
  `NMCamera`, and lays out animated dashes on a new `routes` canvas between the scanlines and the markers.
- **Geometry.** Pure geometry (`NMRouteGeom`) and pure maths (`NMGps` statics) are covered by in-game self-tests.

**Tech Stack:**
- Redscript (Cyberpunk 2077 2.x) with Codeware (reflection fields `gpsQuestPathWidget`, `inkLinePattern.vertexList`).
- Mod Settings.
- Python 3 + pytest for `tools/results.py` and the holo atlas.

**Spec:** `docs/superpowers/specs/2026-10-27-nightmap-gps-route-design.md`. The evidence is
`docs/superpowers/specs/2026-10-27-gps-route-spike/FINDINGS.md`.

## Global Constraints
- **Zero cost while NightMap is closed.** The wraps only store or clear a weak ref; there is no polling and no
  callbacks.
- **Transform:**
  - `v[0] = s * (P.y, P.x)`;
  - `s = |v[0]| / |P.xy|`;
  - `W[i] = P + flipY(R(-c) * (v[i] - v[0])) / s`, with `flipY(x, y) = (x, -y)` and `R(a)` a counter-clockwise
    rotation;
  - `c` = camera yaw in degrees = `atan2(-fwd.x, fwd.y)` of `CameraSystem.GetActiveCameraForward()`. Never the player
    yaw.
- **Sanity, drop the reading if:**
  - `s` lies outside `[0.2, 10]`;
  - the axis estimates `v[0].x / P.y` and `v[0].y / P.x` differ by > 5 % (skip this test when either divisor is
    < 50 m);
  - the converted first point is > 15 m from `P`;
  - `|P.xy| < 50 m` reuses the last accepted `s` of this open, or the reading is skipped.
- **Read:** every 500 ms while open, plus one immediate read in `OnOpened`. Read a widget only when it is visible and
  has ≥ 2 points.
- **Style** (4K units × `layout.scale`):
  - dash 16 long, 8 gap, 4 thick;
  - glow under it, 8 thick at about 25 % opacity, only with the hologram effects on;
  - flow toward the destination at about 30 units/s.
- **Colours:**
  - waypoint `#FFFFFF`;
  - quest `NMTheme.VanillaStateColor(n"Quest")` (#FFFF4E) when `NMQuestHeader.Read(gi).isQuest`, otherwise
    `NMTheme.VanillaStateColor(n"Gigs")` (#00FFD5);
  - the same in the cyan and green themes.
- **Order:** quest route first, waypoint route on top.
- **Change test:** rebuild the geometry only when the point count differs, or the first or last point moved > 0.5 m.
- **Trim:** search only the segments within 30 m of the route start.
- **Setting:** `showRoutes: Bool = true`, category "Display". Display name "GPS routes", description "Show the
  waypoint and quest routes from the minimap." Marker filters never hide routes.
- **Logs:**
  - `gps|no minimap`, at most once per open;
  - `gps|reject|<reason>`, at most once per open, with reasons `scale_range`, `axis_mismatch`, `first_far`,
    `near_origin`.
- **Out of scope:** the Delamain and autodrive routes, waypoint creation, distance/ETA readouts.
- **Probe:** `Debug/GpsProbe.reds` is never carried to `feat/gps-route`. Installing the feature build deletes it from
  the game, because `install.sh` replaces the scripts folder.

## Review Focus
1. **Route offset or rotated when the camera yaw differs from the vehicle heading** (driving while looking sideways).
   Expected: the route stays on the roads. Task 1 pins it with `gps.toWorld_yaw_*` cases, including 90° and 180°;
   checkpoint step 5 covers it in the game.
2. **Readings while the minimap zoom changes between two reads** (accelerating). Expected: each reading uses its own
   `s`, with no jump. Task 1: `gps.toWorld_scale_0p8` and `_3p18` round trips with the same world points.
3. **Player near the world origin**, where `|P| < 50 m` and the scale is unstable. Expected: the last good `s` is
   reused, or nothing is drawn; never a wild route. Task 1: `gps.scale_near_origin`.
4. **V off the route by 20 m before a re-plan.** Expected: the line runs from V to the nearest route point, not
   backwards along old points. Task 2: `geom.trim_off_route`.
5. **Routes left behind after the waypoint is cleared or the quest re-tracked.** Expected: an absent route clears on
   the next reading. Task 4: `route.clear_on_empty`.

---

### Task 0: Branch setup

**Files:**
- Commit on `spike/gps-probe`: `r6/scripts/NightMap/Debug/GpsProbe.reds`,
  `docs/superpowers/specs/2026-10-27-gps-route-spike/FINDINGS.md`
- Commit on `feat/gps-route`: `tools/check.sh` (the RedIMGRetriever-optional fix, already in the working tree), the
  design doc, this plan, and `FINDINGS.md`

- [ ] **Step 1: Record the spike**

```bash
git checkout spike/gps-probe
git add r6/scripts/NightMap/Debug/GpsProbe.reds docs/superpowers/specs/2026-10-27-gps-route-spike/FINDINGS.md
git commit -m "spike(gps): minimap GPS route probe and findings"
```

- [ ] **Step 2: Branch from main**

The working-tree changes to `tools/check.sh`, the design doc and the plan carry over.

```bash
git checkout main && git checkout -b feat/gps-route
git checkout spike/gps-probe -- docs/superpowers/specs/2026-10-27-gps-route-spike/FINDINGS.md
test ! -e r6/scripts/NightMap/Debug/GpsProbe.reds && echo "probe absent: ok"
```

- [ ] **Step 3: Commit**

```bash
git add tools/check.sh && git commit -m "fix(tools): RedIMGRetriever is optional in check.sh"
git add docs/superpowers && git commit -m "docs(gps): route layer design, plan and spike findings"
```

---

### Task 1: `NMGps` maths

**Files:**
- Create: `r6/scripts/NightMap/Vanilla/Gps.reds` (the pure statics only, in this task)
- Create: `r6/scripts/NightMap/Debug/SelfTestGps.reds` (`NMGpsTests`)
- Modify: `r6/scripts/NightMap/Debug/SelfTest.reds:25`: add `NMGpsTests.Run(this);` after `NMVanillaTests.Run(this);`

**Interfaces (Produces):**
- `NMGps.CameraYaw(fwd: Vector4) -> Float`: degrees, `Rad2Deg(AtanF(-fwd.X, fwd.Y))`.
- `NMGps.Scale(v0: Vector2, px: Float, py: Float) -> Float`: `|v0| / |(px, py)|`, or `-1.0` when `|(px, py)| < 50.0`.
- `NMGps.ToWorld(v: Vector2, v0: Vector2, px: Float, py: Float, camYaw: Float, s: Float) -> Vector2`.
- `NMGps.Reject(v0: Vector2, px: Float, py: Float, s: Float, first: Vector2) -> String`:
  - `""` means accept;
  - otherwise one of `"scale_range"`, `"axis_mismatch"`, `"first_far"`, checked in that order;
  - `first` is the converted first point (world).
- Test-only helper, in `SelfTestGps.reds`: `NMGpsTests.Forward(w: Vector2, px: Float, py: Float, camYaw: Float, s: Float) -> Vector2`.
  It returns the absolute minimap point: `s*(py, px) + s*R(camYaw)*flipY(w - P)`.

- [ ] **Step 1: Write the self-tests** in `NMGpsTests.Run(t)`, using `t.Check(name, ok, detail)` and
  `t.Near(a, b, eps)`.
  - **Round trips.** For `P = (-957.2, -806.1)` and world points `(-1624.3, -386.8)` and `(-953.8, -783.6)`:
    `ToWorld(Forward(w, P, c, s), Forward(P, P, c, s), P, c, s)` equals `w` within 0.01 on both axes.
    - `gps.toWorld_yaw_0`, `_yaw_90`, `_yaw_m90`, `_yaw_180`: `s = 3.18`, `c` = 0, 90, −90, 180;
    - `gps.toWorld_scale_0p8`, `gps.toWorld_scale_3p18`: `c = 37.5`.
  - **Spike sample.** `gps.toWorld_spike_sample`: with `P = (-957.8, -805.6)`, `c = -53.6`, `s = 3.182`,
    `v0 = (-2563.3, -3047.8)` and `v = (-2877.3, -3129.7)`, the result is within 3.0 m of `(-995.7, -710.9)`. This is
    the quest mappin from session 1. The yaw source there was the player, equal to the camera at that tick.
  - **Scale.**
    - `gps.scale_matches`: `Scale(Forward(P, P, 0, 3.18), P)` is within 0.001 of 3.18;
    - `gps.scale_near_origin`: `Scale((10, 10), 20.0, -30.0) == -1.0`.
  - **Camera yaw.** `gps.cameraYaw_north`: `CameraYaw((0, 1, 0, 0)) ≈ 0`. `gps.cameraYaw_west`:
    `CameraYaw((-1, 0, 0, 0)) ≈ 90`.
  - **Reject.**
    - `gps.reject_ok` → `""`;
    - `gps.reject_scale` (`s = 12`) → `"scale_range"`;
    - `gps.reject_axis`: `v0 = (3.18*py*1.08, 3.18*px)` → `"axis_mismatch"`;
    - `gps.reject_first_far`: `first` 20 m from P → `"first_far"`.

- [ ] **Step 2: Run the compile check; it must fail.** Run `tools/check.sh`. Expected: `COMPILE FAILED`, naming
  `NMGps`.

- [ ] **Step 3: Implement the four statics in `Vanilla/Gps.reds`** (module `NightMap`, `public abstract class NMGps`
  for now). Task 3 turns it into a normal class. Use the Global Constraints transform as written.

- [ ] **Step 4: Run the compile check; it must pass.** Run `tools/check.sh`. Expected: `COMPILE OK`. The in-game
  self-test run happens in Task 5, step 5.

- [ ] **Step 5: Commit**

```bash
git add r6/scripts/NightMap/Vanilla/Gps.reds r6/scripts/NightMap/Debug/SelfTestGps.reds r6/scripts/NightMap/Debug/SelfTest.reds
git commit -m "feat(gps): minimap-to-world route transform with self-tests"
```

---

### Task 2: `NMRouteGeom` (change test, trim, simplify)

**Files:**
- Create: `r6/scripts/NightMap/Render/RouteGeom.reds`
- Modify: `r6/scripts/NightMap/Debug/SelfTestGps.reds` (add `GeomCases`)

**Interfaces (Produces)** (all `public static` on `public abstract class NMRouteGeom`):
- `Changed(a: array<Vector2>, b: array<Vector2>) -> Bool`: true when the counts differ, or the first or last point
  moved > 0.5.
- `Trim(pts: array<Vector2>, px: Float, py: Float) -> array<Vector2>`:
  - project P onto every segment whose start lies strictly less than 30 m of route length from `pts[0]`, and take
    the closest;
  - return `[P, projection, pts[k+1], ..., pts[n-1]]`, where `k` is that segment's start index;
  - with fewer than 2 points, return a copy.
  - The spec's "over 15 m off the route" rule builds the same polyline, so there is no separate branch.
- `Simplify(pts: array<Vector2>, tol: Float) -> array<Vector2>`: Douglas–Peucker with an explicit index stack (no
  recursion). It always keeps the first and last points.
- `Length(pts: array<Vector2>) -> Float`.

- [ ] **Step 1: Write the self-tests** (`GeomCases`). The route `R = [(0,0), (0,10), (0,20), (0,30), (40,30)]`, in
  metres.
  - **Changed.**
    - `geom.changed_same` → false;
    - `geom.changed_end_0p4` (last point +0.4) → false;
    - `geom.changed_end_0p6` → true;
    - `geom.changed_count` → true.
  - **Trim.**
    - `geom.trim_at_start`: P = (0,0). The result starts `[(0,0), (0,0), (0,10)]` and has n+1 points;
    - `geom.trim_12m`: P = (0,12). The result is `[(0,12), (0,12), (0,20), (0,30), (40,30)]`;
    - `geom.trim_off_route`: P = (20,12). The result starts `[(20,12), (0,12)]` and continues at `(0,20)`;
    - `geom.trim_window`: P = (40,30), at the far end. The search ignores the segment starting at `(0,30)`, which lies
      30 m along. The result's second point is `(0,30)`, the end of the last searchable segment, not `(40,30)`.
  - **Simplify.**
    - `geom.simplify_keeps_corner`: `Simplify([(0,0), (0,5), (0,10), (10,10)], 1.0)` equals `[(0,0), (0,10), (10,10)]`;
    - `geom.simplify_keeps_ends`: a 2-point input comes back unchanged.
  - **Length.** `geom.length`: `Length(R) == 70.0`.

- [ ] **Step 2: Run the compile check; it must fail.** Run `tools/check.sh`. Expected: `COMPILE FAILED`, naming
  `NMRouteGeom`.

- [ ] **Step 3: Implement `NMRouteGeom`** per the signatures.

- [ ] **Step 4: Run the compile check; it must pass.** Run `tools/check.sh`. Expected: `COMPILE OK`.

- [ ] **Step 5: Commit**

```bash
git add r6/scripts/NightMap/Render/RouteGeom.reds r6/scripts/NightMap/Debug/SelfTestGps.reds
git commit -m "feat(gps): route geometry (change test, trim, simplify) with self-tests"
```

---

### Task 3: Live reading (`NMGps` instance + minimap wraps)

**Files:**
- Modify: `r6/scripts/NightMap/Vanilla/Gps.reds`. Turn `NMGps` into `public class NMGps`, keep the statics, add the
  instance state and the wraps.
- Modify: `r6/scripts/NightMap/Core/NightMapSystem.reds`. Add a `gps: ref<NMGps>` created in `OnAttach`, and
  `public func Gps() -> ref<NMGps>`.

**Interfaces:**
- Consumes: the Task 1 statics.
- Produces:
  - `public class NMGpsReading { public let quest: array<Vector2>; public let tracked: array<Vector2>; }`, with
    world-space points; an empty array means no route.
  - `NMGps.SetMinimap(c: ref<MinimapContainerController>)` and `NMGps.ClearMinimap(c: ref<MinimapContainerController>)`.
    Clear only when `c` is the stored one.
  - `NMGps.BeginOpen()`: resets the per-open state (last accepted `s`, the log-once flags).
  - `NMGps.Read(player: ref<GameObject>) -> ref<NMGpsReading>`. It never returns null. It returns an empty reading
    when there is no controller or player.
  - `public var readMsLast: Float; public var readMsMax: Float;` and `ResetReadStats()`, for Task 6.
- The wraps, in `Gps.reds`:
  - `@wrapMethod(MinimapContainerController) protected cb func OnPlayerAttach(player: ref<GameObject>) -> Bool` calls
    `wrappedMethod`, then `NightMapSystem.Get(player.GetGame()).Gps().SetMinimap(this)`;
  - `OnPlayerDetach` calls `ClearMinimap(this)` before `wrappedMethod`.
  - Add `public static func Get(gi: GameInstance) -> ref<NightMapSystem>` to `NightMapSystem`, via
    `GetScriptableSystemsContainer(gi).Get(n"NightMap.NightMapSystem")`, if it does not exist yet.

- [ ] **Step 1: Write the self-test** `gps.read_safe`: `sys.Gps().Read(GetPlayer(gi))` is defined, and each of its
  arrays is empty or has ≥ 2 points.
  - Add it to `NMGpsTests`. It needs the system: pass `gi` into `NMGpsTests.Run(t, gi)`, and update the call site in
    `SelfTest.reds`. Check first how `NMVanillaTests.Run` gets the game instance, and do the same.

- [ ] **Step 2: Run the compile check; it must fail.** Run `tools/check.sh`. Expected: `COMPILE FAILED`, naming
  `Read`/`Gps`.

- [ ] **Step 3: Implement `Read`.** For each of `ctrl.gpsQuestPathWidget.widget` and
  `ctrl.gpsPlayerTrackedPathWidget.widget`:
  1. cast to `inkLinePattern`; skip unless it is visible and has `vertexList` size ≥ 2;
  2. read `P` and `c` once per `Read`;
  3. compute `s` with the near-origin fallback to the last accepted `s` (none → reject `near_origin`);
  4. convert every vertex with `ToWorld`;
  5. run `Reject` on `v[0]` and the converted first point; on a reject, log once and return the previous accepted
     polyline for that path;
  6. on accept, store the polyline and update the last `s`.

  Log `gps|no minimap` once per open when `ctrl` is undefined. Time the call with `NMClock.NowMs()` into `readMsLast`
  and `readMsMax`.

- [ ] **Step 4: Run the compile check; it must pass.** Run `tools/check.sh`. Expected: `COMPILE OK`.

- [ ] **Step 5: Commit**

```bash
git add r6/scripts/NightMap/Vanilla/Gps.reds r6/scripts/NightMap/Core/NightMapSystem.reds r6/scripts/NightMap/Debug/SelfTestGps.reds r6/scripts/NightMap/Debug/SelfTest.reds
git commit -m "feat(gps): read the minimap's quest and tracked routes in world space"
```

---

### Task 4: `NMRouteLayer` (drawing)

**Files:**
- Create: `r6/scripts/NightMap/Render/RouteLayer.reds`
- Modify: `r6/scripts/NightMap/Render/Panel.reds:78-79`. Add `public let routes: ref<inkCanvas>;`, created with
  `NMUi.Canvas(p.mapContent, 0.0, 0.0, layout.mapW, layout.mapH)` between `p.holo.AddScan(...)` and `p.items = ...`.
  Update the draw-order comment in `MapLayer.reds:12-20` with the new step.
- Modify, only on the preferred path: `tools/tiles/nmtiles/holo_atlas.py` and `tools/tiles/tests/test_holo_atlas.py`.
- Modify: `r6/scripts/NightMap/Debug/SelfTestGps.reds` (add `RouteCases`)

**Interfaces:**
- Consumes: `NMRouteGeom` (Task 2), `NMCamera.WorldToMap`, `NMTheme`.
- Produces:
  - `NMRouteLayer.Create(parent: ref<inkCanvas>, scale: Float, effects: Bool) -> ref<NMRouteLayer>`;
  - `SetRoutes(quest: array<Vector2>, questColor: HDRColor, tracked: array<Vector2>)` (world space). It applies
    `NMRouteGeom.Changed` per route, and an empty array clears that route;
  - `Update(cam: ref<NMCamera>, px: Float, py: Float, dtMs: Float, mapW: Float, mapH: Float)`. Each frame: trim,
    re-project when the camera revision changed or the route was rebuilt, simplify at 1 px, clip to the map area
    plus 64 px, advance the flow phase;
  - `SetVisible(on: Bool)`;
  - `HasRoute() -> Bool`, for Task 6.

- [ ] **Step 1: The 30-minute try** (spec §4.4). This step decides the approach and produces no commit.
  1. In a scratch build, spawn `new inkLinePattern()` on the `routes` canvas. Give it
     `SetAtlasResource(NMTheme.HoloAtlas())` and the existing part `n"holo_halo"`, tinted white. Set its `vertexList`
     to three map-pixel points.
  2. Animate `startOffset` each frame.
  3. Install it, open the map, and check that it follows the points, takes tint and thickness, and flows.
  4. Note the result here: **preferred** or **fallback**, and why.

- [ ] **Step 2: Preferred path only, add the `holo_dash` atlas part.**
  - Add `"holo_dash": (32, 16)` at `(828, 0)` in `SIZES`/`LAYOUT`: a white, horizontally centred capsule 24 × 6 px
    with 1 px soft edges, transparent elsewhere.
  - Add `test_dash_is_a_centred_capsule_with_transparent_ends` to `test_holo_atlas.py`:
    - alpha is 0 at x < 4 and x ≥ 28;
    - alpha is 255 at the centre row for x 6 to 25;
    - alpha is 0 at rows 0 to 3 and 12 to 15.
  - Run `cd tools/tiles && python3 -m pytest -q tests/test_holo_atlas.py`. Expected: the new test fails, then passes
    once implemented, and all tests pass.
  - Rebuild: `cd tools/tiles && python3 -m nmtiles.build --game ~/cyberpunk_symlink`. Expected: it ends without error,
    and `TileManifest.reds` is regenerated.

- [ ] **Step 3: Write the self-tests** (`RouteCases`). They run on a detached `inkCanvas`, with no game state.
  - `route.clear_on_empty`: `SetRoutes(R, yellow, R)`, then `SetRoutes([], yellow, [])` → `HasRoute() == false`;
  - `route.has_route`: `SetRoutes(R, yellow, [])` → `HasRoute() == true`;
  - `route.dash_cap`, fallback path only: a 10 km straight route at mpp 0.5 never shows more than 400 dashes;
  - `route.order`: the tracked route's widget(s) have a higher child index than the quest route's.

- [ ] **Step 4: Run the compile check; it must fail.** Run `tools/check.sh`. Expected: `COMPILE FAILED`, naming
  `NMRouteLayer`.

- [ ] **Step 5: Implement `NMRouteLayer`** with the style, colours and order from the Global Constraints.
  - **Preferred:** one `inkLinePattern` per route for the core, plus one for the glow when `effects` is on. Each uses
    `holo_dash`, with `spacing`/`startOffset` giving the 16/8 rhythm and the flow.
  - **Fallback:** pooled rotated `inkRectangle` dashes, cap 400 for both routes, plus one widened rectangle per dash
    for the glow when `effects` is on.
  - Thickness and dash lengths are multiplied by `scale`.

- [ ] **Step 6: Run the checks.** Run `tools/check.sh`. Expected: `COMPILE OK`. On the preferred path, the atlas tests
  from Step 2 pass.

- [ ] **Step 7: Commit.** Name the approach in the message body.

```bash
git add r6/scripts/NightMap/Render/RouteLayer.reds r6/scripts/NightMap/Render/Panel.reds r6/scripts/NightMap/Render/MapLayer.reds r6/scripts/NightMap/Debug/SelfTestGps.reds tools/tiles r6/scripts/NightMap/Generated
git commit -m "feat(gps): route layer with flowing dashes"
```

---

### Task 5: Wire it into the map + setting + first in-game checkpoint

**Files:**
- Modify: `r6/scripts/NightMap/Core/Settings.reds`. Add `showRoutes` (see Global Constraints) in category "Display"
  with `category.order` "1", after `hologramEffects`.
- Modify: `r6/scripts/NightMap/Core/NightMapSystem.reds`

**Interfaces:**
- Consumes: Task 3 (`Gps()`, `BeginOpen`, `Read`), Task 4 (`NMRouteLayer`), `NMQuestHeader.Read(gi).isQuest`.
- Produces: `public func SetRoutesEnabled(on: Bool)`, which overrides the setting for the perf suite, and
  `public func Routes() -> ref<NMRouteLayer>`.

- [ ] **Step 1: Implement the wiring.**
  - **`OnOpened`:** `this.gps.BeginOpen()`. Create `NMRouteLayer.Create(this.panel.routes, l.scale, this.holoEffects)`,
    then do one immediate read and apply it.
  - **`UpdateModules`:**
    - every 500 ms (`NMClock.NowMs()`), call `Read(GetPlayer(gi))`, then
      `SetRoutes(r.quest, questColor, r.tracked)`. The quest colour comes from `NMQuestHeader.Read` on each read;
    - every frame, call `routes.Update(this.camera, P.X, P.Y, dt, l.mapW, l.mapH)` before `renderer.Update`.
  - **`OnClosing`:** `this.routes = null`.
  - **Settings:** with `showRoutes` false, or `SetRoutesEnabled(false)`, skip the read and keep the layer hidden.
  - **Effects:** the layer reads `holoEffects` once per open, like the other effects.

- [ ] **Step 2: Run the compile check.** Run `tools/check.sh`. Expected: `COMPILE OK`.

- [ ] **Step 3: Install** (the game must be closed). Run `tools/install.sh`. Expected: `COMPILE OK`, then
  `installed scripts`. Then check that the probe is gone from the game:
  `test ! -e ~/cyberpunk_symlink/r6/scripts/NightMap/Debug/GpsProbe.reds && echo ok`.

- [ ] **Step 4: Commit**

```bash
git add r6/scripts/NightMap/Core/Settings.reds r6/scripts/NightMap/Core/NightMapSystem.reds
git commit -m "feat(gps): draw minimap routes on NightMap, GPS routes setting"
```

- [ ] **Step 5: In-game checkpoint A.** The user does this; ask them and wait.
  1. With Debug on, press Ctrl + the toggle key (the self-tests). Then run
     `grep -a "TEST|FAIL\|TEST|SUMMARY" ~/cyberpunk_symlink/bin/x64/plugins/cyber_engine_tweaks/gamelog.log | tail`.
     Expected: `failed=0`, including every `gps.*`, `geom.*` and `route.*` case.
  2. Spec §7 checkpoint steps 1 to 7: quest route, custom waypoint, both together, walking off the route, driving
     with the map open, NUM 0 clear and a teal gig route, then the setting and effects toggles.
  3. If the look is off, tune the speed, glow opacity and thickness (spec §8). Re-install and re-check.
  4. Commit any tuning: `git commit -am "tune(gps): route look after checkpoint A"`.

---

### Task 6: Perf suite row `route_open` + `results.py`

**Files:**
- Modify: `r6/scripts/NightMap/Debug/PerfSuite.reds`.
  - Add a `routes: array<Bool>` column to `Add(...)`. It is true only for `route_open`; every other row is false.
  - Add `this.Add("route_open", 0, true, 0, 0.0, false, true)` after `vanilla_open`.
  - Call `sys.SetRoutesEnabled(this.routes[this.idx])` in phase 0, and `sys.Gps().ResetReadStats()` with the existing
    `ResetPollStats()`.
  - Record `routeDrawn = sys.Routes().HasRoute()` on the first measured frame.
  - Report `|route_drawn=0/1|route_read_ms_max=<3 dp>`. It is `0` and `0.000` for rows with the routes off.
  - Restore `SetRoutesEnabled(true)` when the suite ends.
- Modify: `tools/results.py`
- Test: `tools/test_results.py`

**Interfaces:**
- Consumes: `SetRoutesEnabled`, `Routes().HasRoute()`, `Gps().readMsMax`, `ResetReadStats()`.
- Produces, in `results.py`:
  - `ROUTE_ROW = "route_open"` and `ROUTE_READ_TARGET_MS = 0.5`;
  - `route_open` joins `SWEEP_ROWS` for gating, except that a run whose `route_open` has `route_drawn=0` makes that
    row `skipped: no route`: it neither passes nor fails;
  - a missing `route_open` row in a valid run fails, like any other missing row;
  - `route_read_ms_max` is printed as info, with the 0.5 ms target. It is never gated.

- [ ] **Step 1: Write the failing tests** in `tools/test_results.py`. Build each `LOG` line the way the existing
  `vanilla_open` tests do.
  - `test_route_open_is_gated_with_the_sweep_budget`: a `route_open` row with `route_drawn=1` over the sweep budget →
    the verdict fails, and the text names `route_open`.
  - `test_route_open_without_route_is_skipped`: with `route_drawn=0` and frames over budget, the verdict passes, and
    the text contains `route_open: skipped: no route`.
  - `test_missing_route_row_fails`.
  - `test_route_read_ms_is_reported_not_gated`: `route_read_ms_max=2.0` → passes, and the CLI output contains
    `route_read_ms_max 2.000 ms (target 0.5)`.

- [ ] **Step 2: Run them; they must fail.** Run `cd tools && python3 -m pytest -q test_results.py`. Expected: the 4
  new tests FAIL and the rest pass.

- [ ] **Step 3: Implement** in `results.py` (gating and printing) and in `PerfSuite.reds`.

- [ ] **Step 4: Verify.**
  - Run `cd tools && python3 -m pytest -q test_results.py`. Expected: all pass.
  - Run `tools/check.sh`. Expected: `COMPILE OK`.

- [ ] **Step 5: Commit**

```bash
git add r6/scripts/NightMap/Debug/PerfSuite.reds tools/results.py tools/test_results.py
git commit -m "perf(gps): route_open perf row, results gating and read-time report"
```

- [ ] **Step 6: In-game checkpoint B** (the user does this).
  1. Install.
  2. Track a quest about 700 m away.
  3. With Debug on, press Shift + the toggle key three times, letting each suite finish.
  4. Run `python3 tools/results.py`. Expected: PASS, with `route_open` gated (not skipped), and `route_read_ms_max`
     at or below 0.5 ms, or reported.

---

### Task 7: Docs and wrap-up

**Files:**
- Modify: `README.md`. Add one feature line: GPS routes for the waypoint and the tracked quest, mirrored from the
  minimap, with the "GPS routes" setting.
- Modify: `notes/CHECKPOINTS.md`. Add the checkpoint A and B results, with dates and verdicts, in the file's existing
  format.
- Modify: `docs/superpowers/specs/2026-10-27-nightmap-gps-route-design.md`. Change the status line to "implemented on
  `feat/gps-route`", and record the dash approach that was used.

- [ ] **Step 1: Write the three edits.**
- [ ] **Step 2: Run the final checks.** Run `tools/check.sh && (cd tools && python3 -m pytest -q) && (cd tools/tiles && python3 -m pytest -q)`.
  Expected: `COMPILE OK`, and all Python tests pass.
- [ ] **Step 3: Commit:** `git add README.md notes/CHECKPOINTS.md docs && git commit -m "docs(gps): route layer shipped"`.
