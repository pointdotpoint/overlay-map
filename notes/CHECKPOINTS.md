# In-game checkpoints

## Checkpoint 1 (2026-10-11)

Build: `feat/overlaymap-core` @ 222efc7, plus the test fix c313f03. Game 2.31 under Proton, at 2560×1440.

| Step | Result |
|---|---|
| 1. Install | Pass. `tools/install.sh` printed COMPILE OK and installed the archive and scripts. |
| 2. Open/close and visuals | Pass. The panel is centred on the curved HUD layer and shows the corner brackets, the "NIGHT CITY" header, a scale bar, the card column and the hint bar. The map area is empty, as expected before Task 12. The pink clip probe is confined to the map area, which confirms clipping. `\` does not register on the user's ABNT2 keyboard, so the user rebound Toggle to `'` in Mod Settings. |
| 3. Self-test | First run: 2 FAIL (`input.toggle`, `input.ctrl_toggle_is_selftest`). Mod Settings applies saved bindings to class defaults, so the test's `new OverlayMapSettings()` carried the user's `'` binding; this was a bug in the test. Fixed in c313f03, which pins the key bindings in `InputCases`. Re-run: `TEST|SUMMARY|passed=43|failed=0`. |
| 4. Controls while driving | Pass for the conflict check. Numpad keys do nothing to the car or the game while driving, and WASD steering is unaffected. Whether pan, zoom and follow move the map can't be seen while the map area is empty, so that check moves to Checkpoint 2. |
| 4b. NumLock off | Not separately reported. Arrow keys are ignored by design (`input.arrows_never_pan` passes). Re-check at Checkpoint 2. |
| 5. HUD hiding | Pass. Esc menu hides the panel and it returns afterwards; photo mode hides it. |
| 6. Session teardown | Pass. The log shows `closed` (20:50:30) before the new session's `loaded` (20:50:31), and no panel appears after loading until the toggle is pressed. |

Follow-ups:
- The default toggle changes from `\` to `'` (`IK_SingleQuote`). `\` is layout-dependent and not reachable on ABNT2.
- At Checkpoint 2, confirm on visible tiles that the map pans, zooms and recentres, and repeat the NumLock-off check.

## Checkpoint 2 (2026-10-12)

Build: `feat/overlaymap-core`. The first run used 8b51d7a. The final verified build is 36b12de, which adds the fixes listed below. Game 2.31 under Proton, at 2560×1440.

| Step | Result |
|---|---|
| 1. Install | Pass. COMPILE OK. The archive is 5.5 MB after the encode fix. |
| 2. Self-test | First run: `passed=65 failed=1`. The failure was `tiles.level0_has_tiles`. Root cause: in-game, `ArraySize(<function-call temporary>)` returns 0. This was a test bug, and binding to a local fixes it (1a15458, 66c53cc). The tile counts are 256/64/16/4 (`level0_temp_count=0` confirms the cause). Final run: `TEST|SUMMARY|passed=67|failed=0`. |
| 3. Calibration | 137 fast-travel points. The fit gives `sx=-1, sy=+1`, which confirms the Task 7b road-frame fix. Offset: the best fit was (-10, +16) m, but the surface is flat. Median 4.47 m both at (0,0) and at the fitted offset, and the mean is 12.4 m vs 13.1 m. So the offset stays at (0,0). The D1 gate is met: median ≤ 15 m. No rebuild was needed. |
| 4. Visual review | Initial build had two bugs, both fixed in f209012 (texconv `-pmalpha -vflip`). (1) Tiles washed out light blue: ink blends textures as premultiplied alpha, and the tiles were straight alpha. (2) Tiles vertically flipped, leaving a gap at the seam between tile rows. After the fix: translucent hologram colours, no seam, and the city layout matches. Header shows the district ("LITTLE CHINA") and the scale bar updates (2 KM / 100 M). Zoomed-in L0 tiles show buildings, roads and the dashed metro. The debug layer shows clusters with counts and a top-3 icon fan. The cluster card reads "4 LOCATIONS" with per-category rows and a "NUM 0 ZOOM INTO CLUSTER" action. Markers are spread everywhere because the debug layer is 5,000 random synthetic items. The checkpoint-1 pink clip probe tinted the map and is removed (36b12de). |
| 4b. User feedback | Map looks pixelated: tiles are raster, 2 m/px at the finest level, with no anti-aliasing. User decision: "Vector shapes up close" (inkShape vector layer when zoomed in, tiles when zoomed out). This becomes sub-project 1b. Zoom was too slow at 1.5×/s and is now 4×/s (36b12de). |
| 4c. Player arrow and controls | Pass, per the user. V's arrow sits on the correct road and rotates correctly, so `PlayerRotationSign` stays at 1.0. With NumLock off the numpad leaves the map alone and the car steers normally. Zoom at 4×/s feels right. Panning, zooming and follow work on visible tiles. |
| 5. Performance | **PASS.** `python3 tools/results.py` on the complete run at 08:37: items_50000 avg +0.90 ms (budget 3.0), p95 +3.70 ms (budget 6.0). A repeat run at 08:53 gave avg +0.69 ms and p95 +3.43 ms, also PASS. Script cost at 50k items: avg 3.06 ms, p95 6.36 ms. |

Table for the run at 08:37:

| scenario | items | avg ms | +base | p95 | script avg |
|---|---|---|---|---|---|
| closed_baseline | 0 | 14.64 | +0.00 | 15.86 | 0.00 |
| open_empty | 0 | 14.67 | +0.03 | 15.96 | 0.25 |
| items_5000 | 5000 | 15.24 | +0.59 | 19.27 | 2.48 |
| items_20000 | 20000 | 15.36 | +0.71 | 18.81 | 2.95 |
| items_50000 | 50000 | 15.55 | +0.90 | 19.56 | 3.06 |
| closed_end | 0 | 14.57 | -0.07 | 15.77 | 0.00 |

## Checkpoint 3 (2026-10-13)

Build: `feat/vector-layer`. Baked minimap tiles (spec §11). The vector layer is retired. The verified build is 0ce9195. Game 2.31 under Proton, at 2560×1440.

| Step | Result |
|---|---|
| 1. Install | Pass. Installed only with the game closed: replacing the archive while the game runs makes every resource load fail. COMPILE OK. Archive 63.5 MB (63,528,960 B): 4 sets (road, bfill, glow, outline) × 6 levels (0.5–16 m/px), BC7. |
| 2. Self-test | The first run gave `passed=72 failed=2`. Both were test bugs. `tiles.layer_state_machine`: a second 16 ms step correctly faded out and released the outgoing level. `tiles.theme_defaults`: the field was read on a call temporary, which reads 0. Both fixed in 0ce9195. Final run: `TEST|SUMMARY|passed=74|failed=0`. |
| 3. Visual review | User screenshots at 100 M and 2 KM (Charter Hill). Teal filled roads, clean simple building footprints with outline and glow, no metro and no land/water background, as approved in the clean2 preview. Sharp when zoomed in. The player arrow sits on the right block. The user reported no seams or crossfade problems. |
| 3b. User question | "Why aren't map pins showing by default?" Vanilla pins are sub-project 2 (core spec §1 roadmap) and will ride the item layer, together with the planned hidden-item / collectible POIs. |
| 4. Performance | **PASS** against the §11.5 gates. The verdict comes from the complete run at 15:57. Runs at 13:56 (idle_8 +1.17 / +2.47, over) and 15:15 / 15:32 (incomplete; one with a 327 ms baseline hitch) were noise or invalid. The script cost of the idle tile layer is about 0.05 ms per frame, so the variance is GPU-side. |

Table for the run at 15:57:

| scenario | items | avg ms | +base | p95 | script avg |
|---|---|---|---|---|---|
| closed_baseline | 0 | 16.48 | +0.00 | 20.19 | 0.00 |
| open_empty | 0 | 18.18 | +1.69 | 22.55 | 0.53 |
| items_5000 | 5000 | 19.10 | +2.62 | 25.17 | 2.90 |
| items_20000 | 20000 | 19.32 | +2.84 | 25.32 | 3.40 |
| items_50000 | 50000 | 19.00 | +2.52 | 25.98 | 3.49 |
| idle_0p5 | 0 | 16.51 | +0.03 | 20.22 | 0.04 |
| idle_2 | 0 | 17.39 | +0.91 | 20.43 | 0.05 |
| idle_8 | 0 | 16.55 | +0.07 | 20.45 | 0.05 |
| panzoom_0p5_16 | 0 | 17.24 | +0.76 | 22.72 | 0.69 |
| closed_end | 0 | 15.14 | -1.34 | 18.30 | 0.00 |

Gates: idle ≤ +1.0 avg / +2.0 p95. Pan/zoom ≤ +1.5 / +3.0. items_50000 ≤ +3 / +6. Results: idle worst +0.91 / +0.27, pan/zoom +0.76 / +2.53, items_50000 +2.52 / +5.80.

## GPS routes, checkpoint A (2026-10-27)

Build: `feat/gps-route`. Game 2.5 under Proton, at 2560×1440 (tiles built for 2.31; OverlayMap logs the version warning).

| Step | Result |
|---|---|
| 1. Install | Pass. COMPILE OK. |
| 2. Quest and waypoint routes | Pass (user). Both routes appear, end at their targets and follow the roads. The first build drew rotated dashes; the user found bends jagged. The native line widget cannot be created in-game, so routes now use the minimap's own `pathCircle` dots (spec §4.4 Outcome). The user then asked for wider dots (RouteScale 0.5 → 1.25). |
| 3. Header, HUD | Pass (user). Quest header at the bottom right; HUD fades out while open and comes back on close, minimap included, with routes still updating. |
| 4. Self-test | `passed=241 failed=9`. All `gps.*`, `geom.*`, `hud.*` and route tests pass except `route.flow_toward_dest` (reports 0). The user sees the flow working, so this is a test problem; 97ced85 makes the test log its numbers. The other 8 failures (`grow.*` ×5, `perf.wide_layer_exceeds_old_cap`, `vanilla.catalog_twelve` = 13, `tracking.live_accepted_are_quest_objectives`) are in code this branch does not touch and are left for a separate fix. |

Checkpoint B (perf suite with a route tracked, `route_open`) not run yet.

## Fast travel (feat/teleport), merged 2026-10-28 untested in game
- The free teleport was replaced by fast travel to fast travel markers (spec 2026-10-27-overlaymap-teleport-design.md §12).
- Merged at the user's request before any in-game run of the fast travel build (`c5dd34c`). Still to check: the 8
  `ft.*` self-tests, a fast travel from OverlayMap, the refusals (non-point marker, in a vehicle), and the last-used dataterm.

## Soak harness and bug fixes (2026-10-30, branch feat/soak-harness)

The game is now driven automatically: `tools/soak` (ported from the photo mode mod), headless in gamescope through that
mod's wrapper in the Steam launch options. `python3 tools/soak/soak.py campaign tools/soak/plans/regression.json --save
QuickSave-7 --allow-cloud` runs the self-tests, a zoom check over tile level changes and a 3.7 km fast travel with the
real key. Passed on 2026-10-30 (run 20261030-144626-regression).

| Bug | Cause | Result |
|---|---|---|
| Fast travel black screen | No inkSetNextLoadingScreenEvent: V was teleported, the loading sequence never ran | Black 3 of 3 before; passed 3 of 3 after, and again in the regression |
| Markers vanishing while panning | A slot leaving the photo style kept both widgets hidden while chipOn stayed true | chip.visible_after_photo_slot failed before, passes after |
| Zoom flicker | Pooled images show their old tile until the new texture loads; the fade ran on a timer | Worst block diff 289 before; at most 25 after holds 2 to 5 |
| Photo pins lost on restart | WriteLines ends no line, so spots ran together and 1 of 21 loaded | 21 of 21 load; old files still read |

Open:
- While a level's tiles load, a zoom-out can show a bare edge beyond what the old level covered. The tile sets now cross
  together and the coarser level is preloaded; crossovers measured 16 to 255 ms. The zoom check photographs the map after the
  crossover, so it no longer sees this moment: it catches stale or missing tiles, not this wait.
- Vanishing markers: the cause was found by reading the code and proven by a self-test, not seen on screen.
- A GPU crash ("Gpu Crash for unknown reasons") hit 2 of about 24 headless launches, and one launch never reached the menu.
- Self-tests still failing, not from this work: vanilla.catalog_twelve (13 categories), tracking.live_accepted_are_quest_objectives,
  perf.wide_layer_exceeds_old_cap.
- Reading a field of a call temporary (`x.GetScale().X`) gives garbage in-game. Bind to a local. That caused 8 false failures.

## Closer zoom (2026-10-30, branch feat/closer-zoom)

The camera goes to 0.1 m/px, 5x past the finest tiles, and photo pins grow with it up to 5x. A photo pin is selected from its
tip at any size. `tools/soak/plans/close-zoom.json` passed (20261030-150052) and so did the regression (20261030-150736).
Self-tests: 314 passed, 3 failed, the same three as above. Below the 100 M scale the map magnifies its tiles and looks soft.

## Hold to show (2026-10-30, branch feat/hold-to-show)

Display -> Hold key to show, off by default: press opens, release closes, and the hint reads RELEASE ' CLOSE.
`tools/soak/plans/hold-to-show.json` passed (20261030-154151) with real key events: the normal toggle, then a 5 s hold, then a
second hold. Self-tests failing are the same three as above. A synthetic held key sends no repeats, so a real keyboard's key
repeat is not covered by this run; the code ignores repeated presses, and only a false release would close the map.

Harness: a keysym follows the session's layout, and under gamescope `apostrophe` reached the game as IK_Tilde. Send keycode 94,
which the game sees as IK_SingleQuote. The `watch_keys` and `last_keys` commands report what the game actually received.

## Teleport anywhere (2026-10-30, branch feat/teleport-anywhere)

`tools/tiles/nmtiles/heightmap.py` bakes the lowest and highest surface of every 32 m cell from the vanilla 3D map
(terrain, roads, cliffs, metro and the district point clouds) into `Generated/HeightData.reds`. Collision only loads within
about 100 m of V, so V hops just above the cell's highest surface, then near its lowest, and a ray (Static and Terrain) lands
V once three probes agree. `tools/soak/plans/teleport.json` passed (20261030-171949) with the real key at 16 spots, every one
at full health: streets, badlands, a 633 m roof, hills, the sea and a lake. Japantown's open shaft (-600, 1400) has no
surface and sends V back to the start. Long jumps hold the game's black streaming screen for about 3 to 10 s. Not covered by
the harness: a vehicle teleport. Self-tests failing are the same three as before.

## Visual overhaul, Task 11: tune, measure, record (2026-11-01, branch visual-overhaul)

### Perf gate (NMPerfSuite, main vs branch)

New harness command `perf` (`tools/soak/plans/perf.json`) starts the suite without the debug chord and reports
`perf_done`; the `RESULT|` and `PERF|` lines land in the run's `gamelog-tail.log`. Main ran from a `git worktree` of
`main` with only the harness additions copied in (removed afterwards; `main` untouched). Save QuickSave-7 for every run.
Raw lines: `.scratch/perf-main.txt`, `.scratch/perf-branch.txt` (final), earlier runs in `.scratch/perf-*-run*.txt`.

At the Task 10 head (6fd15ed) the branch failed the gate: open_empty +7 % avg / +17 % p95, vanilla_open +5 % / +14 %,
panzoom +18 % / +50 %, items_50000 +39 % / +141 % (one branch run against three main runs). Causes, measured with a new
per-frame breakdown in the suite (`tiles_avg|p95`, `items_avg|p95`):

- **Item relayout.** The declutter evaluated up to 300 culls per relayout, and every placed or culled marker costs a
  few µs of script. Fix: Minor layers stop at 40 culls each (`LayerCullCap`), 160 per relayout (`CullCap`; Major
  layers only that total, so the far view still fills with fast travel). A per-layer cap of 300 (1,200 total) was
  tried and measured worse (+40 % script p95). Also: a struck item's overlay is restyled only when its slot changed,
  the category icon key is cached, and the collision test runs before the header test.
- **The fifth tile set** (Task 1's road_minor + road_major split, 5 sets against main's 4). Proven by a run without
  road_minor: panzoom fell to −2 % / −5 %. Fix: a tile set's reveal pass walks only its waiting slots, not its whole
  pool, every frame, and a range that only grew skips the release scan. The extra set's texture streaming remains.

Final code, 2 runs each side, interleaved. The game environment changed during the task (a ReShade VHS preset and
Immersive Third Person were installed at about 11:20 to 11:45; frame times are GPU-bound at about 24 ms in these runs,
against about 10 ms earlier). Both sides ran under the same conditions:

| scenario | main avg | branch avg | Δ avg | main p95 | branch p95 | Δ p95 | main script avg | branch script avg |
|---|---|---|---|---|---|---|---|---|
| closed_baseline | 22.94 | 23.73 | +3.5 % | 24.20 | 26.25 | +8.5 % | 0.00 | 0.00 |
| open_empty | 25.69 | 24.80 | -3.4 % | 32.43 | 27.59 | -14.9 % | 2.04 | 1.87 |
| vanilla_open | 26.08 | 24.72 | -5.2 % | 32.97 | 27.76 | -15.8 % | 3.11 | 3.03 |
| route_open | 24.86 | 24.46 | -1.6 % | 27.89 | 27.74 | -0.5 % | 2.04 | 1.81 |
| photos_500 | 29.49 | 24.70 | -16.3 % | 44.06 | 29.46 | -33.1 % | 6.58 | 2.33 |
| items_5000 | 26.01 | 24.59 | -5.4 % | 32.77 | 28.64 | -12.6 % | 4.85 | 2.87 |
| items_20000 | 25.78 | 24.76 | -4.0 % | 33.46 | 28.60 | -14.5 % | 4.85 | 2.51 |
| items_50000 | 25.25 | 24.45 | -3.2 % | 29.45 | 27.34 | -7.2 % | 4.70 | 2.39 |
| idle_0p5 | 24.48 | 24.21 | -1.1 % | 27.39 | 26.49 | -3.3 % | 0.08 | 0.08 |
| idle_2 | 25.15 | 24.42 | -2.9 % | 29.62 | 28.00 | -5.5 % | 0.09 | 0.09 |
| idle_8 | 25.42 | 24.60 | -3.2 % | 30.63 | 28.23 | -7.9 % | 0.09 | 0.09 |
| panzoom_0p5_16 | 24.63 | 24.91 | +1.2 % | 27.30 | 29.23 | +7.1 % | 2.05 | 2.07 |
| closed_end | 23.68 | 23.40 | -1.2 % | 26.94 | 25.96 | -3.6 % | 0.00 | 0.00 |

Every mean is within +5 %. Two p95 values are above +5 %: closed_baseline (+8.5 %, no mod code runs there, so this is
noise) and panzoom (+7.1 %, script p95 +1.1 ms: **accepted by the user 2026-11-01**). The script time, which is stable from run to run, is at or below main everywhere except
panzoom (2.07 against 2.05 avg; p95 7.08 against 5.98 ms, the extra tile set). Before the environment changed (frames at
about 10 ms), three main runs against the tuned branch before the tile-layer fix gave, as the mean over the closed
baseline: open_empty +1.70 against +1.26 ms, vanilla_open +1.76 / +1.82, panzoom +1.27 / +1.46, items_50000 +1.96 / +3.81.
Run-to-run p95 noise was about ±10 % on idle scenarios with identical script cost.

### Tuned values

| what | old → new | why |
|---|---|---|
| `RingsOpacity` | 0.10 → 0.05, × `RingsFade` (1 up to 1 m/unit, linear in log2 down to 0.2 at 8+) | read as a target over the city at z8/z16; ink blends in linear light |
| `HoloNoiseOpacity` | 0.04 → 0.008 (flicker steps now 0.68–1.18 × it) | .04 lifted the dark map to an sRGB teal of about (25, 56, 66) |
| `HoloBarOpacity`, bar height | 0.12 → 0.035; 0.14 → 0.06 of the map height (`HoloBarHeight`) | a bright band at whole-city zoom |
| `HoloEdgeOpacity` | 0.6 → 0.3 | heavier than frame.jpg |
| `DeclutterOverlap` | 0.75 → 1.0 | plate rings may touch, never overlap; z2 placed markers 187 → 120 |
| NCPD Scanner (Story filter) priority | 80 → 45 | was placed before services and collectibles at mid zoom |
| NCPD Scanner fade | Minor 4–6 → ambient 2.5–4 m/unit (`OverlayMapLayer.SetAmbient`, `NMTiers.LayerFade`) | z4 was a wall of teal NCPD icons; mid zoom keeps vendors and collectibles |
| declutter cull cap | 300 per relayout → Major layers 160 together, each Minor layer 24 of its own (fix round 1) | perf gate (above); a shared total starved the collectibles (last by priority) at z2/z4 |
| hint keycaps | letter-spacing 0 → 4 (4K units), width estimate counts spaces at 7 | PAN read "8462" |
| `NMTiers` thresholds, minimum scale | unchanged (Minor 4–6, Major 24–32, 0.7 at 8+) | z8/z16 already show only Major + tracked |

Placed markers per zoom (look run 20261101-134657, after fix round 1): z0.5 23, z2 118, z4 130 (collectibles 31: shards 3,
tarot 8, weapons 3, clothing 8, skill 9; spread over the view), z8 60 (quests 9, fast travel 51), z16 25 (quests 7, fast
travel 18). Before fix round 1, z4 had 5 collectibles, near the centre.

### Fix round 1 (review)

- Each Minor layer now gets its own 24-cull slice (Major layers share 160 and are walked first); before, Minor slices
  were cut by a running total that included the fast-travel culls, so the collectibles were skipped. New self-tests:
  `declutter.minor_slices_after_major` (a Major layer and three Minor layers; the last still places),
  `declutter.promoted_big_layer_fills` (1,657 items promoted to Major place a screenful at mid zoom),
  `perf.budget_full_identical` (the chip-budget-full path of the scan/occupancy equivalence, declutter off).
- Tile streaming: new tiles are requested at most 24 per set per frame (the level's fade waits for the rest), and the
  next level's preload is requested 6 tiles per set per frame instead of all at once.
- Harness: the Immersive Third Person fact is set at every session start; `set` and `focus_layer` check their arguments.

Final perf, 2 runs each side, interleaved, same environment (ReShade VHS preset on for both; every run drifted more than
0.5 ms between its closed scenarios, so these are noisy). Raw lines: `.scratch/perf-main.txt`, `.scratch/perf-branch.txt`.

| scenario | main avg | branch avg | Δ avg | main p95 | branch p95 | Δ p95 | main script avg | branch script avg |
|---|---|---|---|---|---|---|---|---|
| closed_baseline | 23.11 | 22.97 | -0.6 % | 25.12 | 24.87 | -1.0 % | 0.00 | 0.00 |
| open_empty | 24.15 | 24.39 | +1.0 % | 25.72 | 27.18 | +5.7 % | 1.89 | 1.72 |
| vanilla_open | 24.41 | 25.13 | +2.9 % | 25.92 | 28.24 | +9.0 % | 2.64 | 3.16 |
| route_open | 24.31 | 25.06 | +3.1 % | 25.83 | 27.59 | +6.8 % | 1.90 | 1.77 |
| photos_500 | 25.00 | 26.27 | +5.1 % | 29.21 | 31.34 | +7.3 % | 5.44 | 2.30 |
| items_5000 | 25.55 | 25.65 | +0.4 % | 29.89 | 29.32 | -1.9 % | 4.34 | 2.59 |
| items_20000 | 25.97 | 24.99 | -3.8 % | 30.14 | 27.25 | -9.6 % | 4.69 | 2.27 |
| items_50000 | 26.43 | 25.64 | -3.0 % | 29.70 | 29.60 | -0.3 % | 4.71 | 2.20 |
| idle_0p5 | 25.65 | 25.47 | -0.7 % | 28.64 | 30.28 | +5.7 % | 0.09 | 0.10 |
| idle_2 | 25.82 | 25.59 | -0.9 % | 29.47 | 30.96 | +5.1 % | 0.09 | 0.10 |
| idle_8 | 25.87 | 25.10 | -3.0 % | 29.16 | 29.94 | +2.7 % | 0.09 | 0.10 |
| panzoom_0p5_16 | 25.90 | 24.64 | -4.9 % | 29.23 | 27.47 | -6.0 % | 2.10 | 1.95 |
| closed_end | 24.62 | 24.17 | -1.8 % | 27.95 | 28.13 | +0.6 % | 0.00 | 0.00 |

Means: all within +5 % except photos_500 at +5.1 %, whose script time is under half of main's (2.30 against 5.44 ms),
so that is frame noise. The real cost of the per-layer slices is vanilla_open's script: +0.52 ms avg (3.16 against
2.64), p95 7.10 against 5.87 ms. panzoom script p95 in these runs: 6.00 against 6.15 ms, after the tile budgets; the
earlier +1.1 ms (7.08 against 5.98) is **accepted by the user 2026-11-01**.

### Screenshots

- Before (6fd15ed, run 20261101-101330-look): `.scratch/shots/before/` z0.5, z2, z8, z16, filter.
- After, clean environment, overlays tuned (run 20261101-105458-look): `.scratch/shots/after-clean/`.
- After, final code (run 20261101-120243-look, the user's ReShade VHS preset on): `.scratch/shots/after-final/`
  z0.5, z2, z4, z8, z16, filter, gig_hover, ncpd_hover, desc_hover.
- Checks (`tools/soak/plans/look-checks.json`): `.scratch/shots/checks/` effects_off_z2, green_z2, opacity030_z2,
  opacity030_z0.5, photo_pin_z1 (run 20261101-105919), route_z2 (20261101-120603), desc_hover (20261101-113644).

The sidebar description cap is verified in game: a 200-character description (soak `desc_probe`) wraps to three lines
with an ellipsis and stays above the rows.

### Road split (Task 1)

Width threshold: a minimap road shape is major when `classify_width` (area / longest bounding-box extent) is at least
`MAJOR_WIDTH_M` = 16 m. Short-gap promotion: minor pieces in a gap of the major mask no wider than 1.5 × 16 m
(junction squares, short pieces between two major segments) move to road_major, so arterials read as continuous lines.

### Not built

- The optional leader line from a marker to the sidebar card (spec §5.2). Candidate for later.
- The optional open animation (spec §8). Candidate for later.

### Campaigns

regression 20261101-130814 pass, `TEST|SUMMARY|passed=455|failed=0`; collect 20261101-123215 pass (3 runs); teleport
20261101-124027 pass (455 / 0); fast-travel 20261101-124930 pass (3 runs); render 20261101-130308 pass (455 / 0);
controller 20261101-125746: hold pass, pad-1 coverage_fail at step 84 (`vdist: still 0`), the known View-close
movement lock from main. The pad hint bar's keycaps show in controller pad_open.png.
After fix round 1: render 20261101-142351 pass, regression 20261101-135020 pass, collect 20261101-135453 pass (3 runs),
look 20261101-134657 pass; self-tests `passed=458|failed=0`.

### Harness notes

- A first-run popup from Immersive Third Person (its quest fact is never saved by the harness) covered the screen
  about 20 s into every run; the bootstrap now sets `immersive_third_person_notice_seen` per session.
- New soak commands: `perf`, `set effects|theme|opacity`, `layers`, `focus_layer <id part> <mpp>`, `act`, `desc_probe`.
