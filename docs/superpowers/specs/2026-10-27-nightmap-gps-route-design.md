# NightMap: GPS route layer

**Status:** implemented on `feat/gps-route` (2026-10-27). The drawing changed after in-game review: see §4.4
"Outcome". Two user requests were added on the same branch: the quest header moved to the map's bottom right, and the
HUD fades out while the map is open (§10).
**Branch:** `spike/gps-probe` (holds the probe and the findings). The build goes on a new `feat/gps-route` from `main`.
**Spike evidence:** `2026-10-27-gps-route-spike/FINDINGS.md`. The probe is `r6/scripts/NightMap/Debug/GpsProbe.reds`.

## 1. Intent and user decisions

The player sets a waypoint on the vanilla world map, then opens NightMap to see how to get there. Today NightMap shows
the waypoint pin but no route, so the player has to read the route off the small HUD minimap. NightMap should draw the
same route the game's GPS computes, in NightMap's hologram look, for the waypoint and for the tracked quest.

| Topic | Decision (user, 2026-10-27) |
|---|---|
| Which routes | **The waypoint route** (the one the user asked for) **and the tracked quest's route.** |
| Setting the waypoint | **From the vanilla map is fine.** Placing a waypoint from NightMap stays out of scope (it needs the native plugin, sub-project 3). |
| Line style | **Flowing dashes**: bright dashes with a soft glow that crawl toward the destination (mockup option B). |
| Colours | **Waypoint route white. Quest route in the quest's colour**: Quest yellow `#FFFF4E` for main/side/minor/courier jobs, Gigs teal `#00FFD5` for gigs, NCPD and contracts (the marker colours, `NMTheme.VanillaStateColor`). |
| Both at once | Both routes are drawn together when both exist (mockup option A). |
| Extras | The line alone is enough. No distance, ETA or fit-to-route. |

The binding product constraints from sub-project 1b (spec `2026-10-12-...` §11.5) apply: very light at runtime, a
state-of-the-art look, themeable.

## 2. Goals, non-goals, anti-goals
**Goals**
- While NightMap is open, draw the route the HUD minimap is showing to the player-tracked pin (the custom waypoint, or
  any pin tracked from the vanilla map), and to the tracked quest objective.
- It follows the player: the route re-plans as V moves or strays, and NightMap shows the new route within about half a
  second.

**Non-goals**
- Setting waypoints or tracking non-quest pins from NightMap (sub-project 3).
- Delamain taxi and autodrive routes. They are in the same data (`gpsDelamainPathWidget`, `autodrivePathWidget`) and
  can be added later with one line each, but they are not part of this release.
- Computing routes ourselves. NightMap only mirrors what the game's GPS already computed.
- Distance or ETA readouts, fitting the camera to the route, or route selection and tooltips.

**Anti-goals** (failure even if it technically works)
- A route that visibly lags behind the player or jumps while driving.
- A route drawn in the wrong place: rotated, mirrored, or offset from the roads. A wrong route is worse than none, so
  a reading that fails its sanity checks (§4.2) is dropped, not drawn.
- Any measurable cost while NightMap is closed.
- Cluttering the map so the markers become hard to read.

## 3. Facts the design rests on (spike, game 2.31, Codeware)
All of these are measured. Details and numbers are in `FINDINGS.md`.
- **Source.** `MappinsContainerController` (the HUD minimap) has the native fields `gpsQuestPathWidget` and
  `gpsPlayerTrackedPathWidget`. Codeware exposes them as `inkLinePatternRef`; `.widget` is an `inkLinePatternWidget`.
  `inkLinePattern.vertexList: array<inkLineVertex>` (`.int: Vector2`) holds the live route.
- **Catching the controller.** Wrap `MinimapContainerController.OnPlayerAttach` and `OnPlayerDetach`.
- **Whole route.** A 790 m route had 329 to 390 points. When no route exists the widget has 1 point and
  `IsVisible() == false`.
- **Transform.** For points `v[0..n-1]`, player world position `P` and camera yaw `c`:
  - `v[0] = s * (P.y, P.x)`, so `s = |v[0]| / |P.xy|`, in minimap units per metre. It varies: 3.18 on foot,
    0.8 to 1.6 in a car.
  - Inverse: `W[i] = P + flipY(R(-c) * (v[i] - v[0])) / s`, with `flipY(x, y) = (x, -y)`.
  - `c` is the **camera** yaw: `atan2(-fwd.x, fwd.y)` of `CameraSystem.GetActiveCameraForward()`. It is not the
    player yaw.
- **Accuracy.** Under 1 m on foot, about 5 m in a car at speed. The quest route's end landed 0.3 m from its mappin.
  The tracked route ended about 4.5 m from its pin, at the nearest walkable point.
- **The waypoint route is `gpsPlayerTrackedPath`.** Confirmed with a real custom waypoint 441 m away: the converted
  endpoint was within 1 m of the waypoint.
  - The same path also carries the route to any other pin tracked from the vanilla map. It is drawn white in either
    case.
  - Draw whatever the widget holds. Do not gate it on `GetManuallyTrackedMappinID()`, which did not match the waypoint
    in the probe.
- **Live while NightMap is open.** It updates while the map is open; checked by walking 35 m with the map open.

## 4. Architecture
New pieces, in the existing module layout:

| Unit | Responsibility | Depends on |
|---|---|---|
| `Vanilla/Gps.reds` (`NMGps`) | Holds a weak ref to the HUD minimap controller, which the two wraps register on the system. `Read()` returns the current world-space polylines for the `quest` and `tracked` paths: empty when absent or rejected. Pure static `ToWorld(...)` and `Scale(...)` do the §3 maths. | Codeware fields, CameraSystem, player |
| `Render/RouteLayer.reds` (`NMRouteLayer`) | Owns the route canvas. It keeps the last world polylines, re-projects them through `NMCamera` when the camera moves, and lays out and animates the dashes. Not selectable. | `NMCamera`, `NMTheme` |
| `Render/Panel.reds` | One new canvas `routes` between `holo.AddScan` and `items`: over the tiles and scanlines, under the markers. | — |
| `Core/NightMapSystem.reds` | Creates the route layer in `OnOpened`, drops it in `OnClosing`, calls `NMGps.Read()` every 500 ms from `UpdateModules`, and updates the layer every frame. | the above |
| `Core/Settings.reds` | `showRoutes: Bool = true` in the **Display** category: "GPS routes: show the waypoint and quest routes from the minimap." It turns both routes on or off. | — |
| `Debug/GpsProbe.reds` | **Deleted** in this work. | — |

### 4.1 Reading (`NMGps.Read`, every 500 ms while open)
1. If there is no controller, or the setting is off, return nothing. Log "gps|no minimap" once per open, because a HUD
   mod may hide the minimap.
2. For each of the two widgets, skip it unless it is visible and has at least 2 points.
3. Read `P` (player world position) and `c` (camera yaw) in the same call as the vertex list.
4. Compute `s` (§3). Near the world origin (`|P.xy| < 50 m`), reuse the last accepted `s` for this open, or skip the
   reading if there is none.
5. Convert every point to world space.

### 4.2 Sanity checks (drop the reading, keep the last good one)
- `s` lies outside `[0.2, 10]`.
- The two axis estimates `v[0].x / P.y` and `v[0].y / P.x` disagree by more than 5 %. Skip this check when either
  divisor is under 50 m.
- The converted first point is more than 15 m from `P`.

A dropped reading is logged at most once per open, as "gps|reject|<reason>".

### 4.3 Drawing (`NMRouteLayer`)
- **Style** (as on the mockup, 4K units × `layout.scale`):
  - core dash 16 long, 8 gap, 4 thick;
  - a soft glow under it, 8 thick at about 25 % opacity, only with the hologram effects on;
  - dashes flow from the player toward the destination at about 30 units per second.
- **Order:** the quest route first, then the waypoint route on top, so the waypoint wins where they share a road.
- **Colours:**
  - waypoint white;
  - quest yellow or gig teal, picked by the same rule as `NMQuestHeader.isQuest`;
  - the same in both the cyan and the green themes. White, yellow and teal contrast with both.
- **Updates:**
  - Geometry is rebuilt only when a new reading changes the polyline: a different point count, or any endpoint moved
    by more than 0.5 m.
  - On camera change, the cached world points are re-projected and the dashes laid out again.
  - The flow animation only advances the dash phase each frame. It does not re-project.
- Simplify the projected polyline to about 1 px before laying the dashes, and clip to the map area plus a margin.
- The route starts at the player marker, never at a stale point. Each frame:
  1. trim the points V has already passed;
  2. then start the line at the current player position.

  The line never detaches from the arrow, and never runs backwards between readings. In a car at 30 m/s, 15 m pass
  between readings. *(Spec author's call, after review.)*
  - **Trim rule:** project `P` onto the first segments of the cached polyline. Search only the segments within 30 m
    of the route start, so the cost stays bounded.
  - Drop every point before the closest segment, and start from the projected point.
  - If `P` is more than 15 m from all of those segments, V has left the route: draw from `P` to the nearest segment
    point until the next reading re-plans.

### 4.4 How the dashes are drawn (the builder decides after a short in-game check)
- **Preferred:** one `inkLinePattern` widget of our own per route. Set its `vertexList` in map pixels and give it a
  dash image from NightMap's holo overlay atlas. Animate the flow by moving `startOffset`. Native, with one widget per
  route.
- **Fallback:** a pooled set of rotated `inkRectangle` dashes along the screen polyline, with a cap of about 400
  dashes for both routes. Hide dashes beyond the cap: at that zoom the route is too long to need every dash.

**Deciding** *(spec author's call, after review)*:
- **The 30-minute try:** spawn an `inkLinePattern` with an *existing* atlas part (any solid part, tinted). Check that
  it follows the vertex list in map pixels, takes tint and thickness, and flows when `startOffset` moves. The try does
  **not** include an atlas rebuild.
- **If it works:** add a `dash` part to NightMap's holo overlay atlas as a separate step. That means
  `tools/tiles/nmtiles/holo_atlas.py`, its layout test and an archive rebuild. NightMap owns that atlas, so changing it
  is in scope.
- **If it fails:** use the fallback, which needs no atlas change.
- Record which approach was used, and why, in the plan or the commit.

**Outcome** *(2026-10-27, in-game)*:
1. The fallback (rotated rectangle dashes) shipped first and worked, but the user found bends jagged: each straight
   dash is a chord, and its ends poke out on curves.
2. The preferred approach is not possible. Script cannot `new` an `inkLinePattern` (abstract), and creating one by
   name through Codeware reflection (`Reflection.GetClass(n"inkLinePattern").MakeInstance()`) compiles but returns
   null in-game (`gps|line widget unavailable`).
3. Copying the minimap's widget style showed what the minimap draws: `part=pathCircle`, 13×13, spacing 5,
   `rotateWithSegment=false`. Its route is a row of unrotated round dots, which is why it reads smooth on bends.
4. **Shipped:** pooled `inkImage` dots with the minimap's own atlas and `pathCircle` part, copied from the live
   minimap on the first read (`NMRouteStyle`), at `RouteScale` 1.25 × the UI scale (the user asked for a wider line
   than 0.5). Same cap (400, now `DotCap`), clipping, flow and pinning as the fallback. No atlas change was needed.

## 5. Behaviour rules
- No route in the minimap means no route in NightMap. That covers nothing tracked, an objective without a location,
  and interiors where the minimap shows none.
- Clearing the waypoint, from NightMap's NUM 0 or the vanilla map, removes the route on the next reading (within
  500 ms).
- Tracking another quest swaps the quest route and its colour on the next reading.
- Marker filters (NUM / and the Mod Settings filters) do not hide routes. Only `showRoutes` does.
- Opening NightMap shows the routes on the first frame after the first reading. `OnOpened` does one immediate read.

## 6. Performance
- **Closed:** zero cost. The two wraps only store or clear a weak ref; there is no polling and no callbacks.
- **Open:**
  - one read every 500 ms: at most about 2 × 400 points, converted with a handful of float operations each. Target
    under 0.5 ms of script time per read frame;
  - re-projection only on camera change;
  - the flow animation costs one phase update per route per frame (preferred approach) or one translation per visible
    dash (fallback).
- **Perf suite:**
  - the existing `open_empty` gate (+1.5 / +3.0 ms) must still pass with a route present;
  - add a measurement row, `route_open`. *(Spec author's call, after review.)*
    - **Setup:** the standard circle sweep, with the routes on and a tracked quest about 700 m away. The tester tracks
      the quest before starting the suite.
    - **Gate:** like `open_empty` (+1.5 / +3.0 ms).
    - **No route:** if no route was drawn during the row (no route on its first frame), report it as
      `skipped: no route`. It neither passes nor fails, and the rest of the run stands.
    - **The other rows:** switch the routes off in every other row, the way the suite already switches the vanilla
      markers per row. The existing rows then stay comparable with earlier runs, and `route_open` isolates the route
      cost.
    - **Read-frame time:** `results.py` reports the max script ms of a read frame as information only, with the
      0.5 ms target printed next to it. It is not a gate.
    - Extend `results.py` and its tests accordingly.

## 7. Testing
- **Self-tests** (the in-game Ctrl chord, a new group in `Debug/`):
  - `NMGps.ToWorld` round trip: build `v[]` with the forward transform from a known `P`, `c` (including 0°, ±90°,
    180°), `s` (0.8, 3.18) and world points. The inverse returns them within 0.01 m;
  - `NMGps.Scale` on the same data, plus the near-origin fallback;
  - the sanity rules: each rejection reason fires, and a good reading passes;
  - the change test (when the geometry is rebuilt): same reading, endpoint moved 0.4 m, endpoint moved 0.6 m, point
    count changed;
  - polyline simplification keeps the endpoints and corners above 1 px;
  - the trim rule (§4.3):
    - player on the route start: nothing dropped;
    - player 12 m along: earlier points dropped, and the line starts at the projection;
    - player 20 m off the route: the line runs from the player to the nearest point;
    - the search stays within the 30 m window.
- **Offline:** the `tools/check.sh` compile.
- **Checkpoint (in-game):**
  1. Track a quest about 700 m away and open NightMap: the yellow route lies on the roads and matches the minimap's.
     Take a screenshot of each side by side.
  2. Set a custom waypoint on the vanilla map: a white route appears, and it ends at the pin.
  3. Both at once: the white route draws over the yellow one where they share roads.
  4. Walk off the route: NightMap re-plans within about a second.
  5. Drive with the map open, turning often: the route stays on the roads and attached to the arrow.
  6. Clear the waypoint with NUM 0: the white route disappears. A gig shows a teal route.
  7. Turn `showRoutes` off: no routes. Turn the hologram effects off: no glow, dashes still flow.
  8. Run the perf suite 3 times: `route_open` and `open_empty` pass.

## 8. Left to the builder
- The dash drawing approach, preferred or fallback (§4.4).
- The exact dash speed, glow opacity and thicknesses, within the mockup's look. Tune them at the checkpoint.
- How the minimap wraps reach `NightMapSystem`, for example through `GameInstance.GetScriptableSystemsContainer`.
- How to handle `IsVisible() == false` with `n ≥ 2`, if it ever appears. The spike never saw it; treat it as no route.

## 9. Review focus (most likely to bite a user)
1. A route drawn rotated or mirrored, from a wrong yaw source or a sign error. The round-trip self-test plus the
   checkpoint's driving step cover it.
2. A route jumping in cars, from the zoom changing between readings. Each reading carries its own `s`. Check at the
   checkpoint.
3. No route when a HUD or minimap mod replaces or hides the minimap. Log it once. It is acceptable for this release.
4. Old routes left behind after clearing or re-tracking. Every reading replaces both routes, and an absent route
   clears.
5. Cost of the dash animation on long routes when zoomed in: the cap and clipping (§4.3, §4.4).

## 10. Added on the branch (user requests during review)
- **Quest header at the bottom right.** District, tracked quest and objective sit in a right-aligned vertical panel
  anchored at the map area's bottom-right corner, stacked from the bottom so a hidden quest or a two-line objective
  leaves no gap. The tile warning stays at the top left.
- **HUD hidden while open.** `NMHudHider` fades every other child of the HUD window to zero opacity on open and gives
  each its own opacity back on close; every 30 frames it fades HUD widgets added or faded back in meanwhile. Opacity,
  not visibility, so the minimap keeps running and the routes keep updating. Setting: Display → "Hide HUD while open",
  on by default.
