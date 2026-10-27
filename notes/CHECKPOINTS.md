# In-game checkpoints

## Checkpoint 1 (2026-10-11)

Build: `feat/nightmap-core` @ 222efc7, plus the test fix c313f03. Game 2.31 under Proton, at 2560×1440.

| Step | Result |
|---|---|
| 1. Install | Pass. `tools/install.sh` printed COMPILE OK and installed the archive and scripts. |
| 2. Open/close and visuals | Pass. The panel is centred on the curved HUD layer and shows the corner brackets, the "NIGHT CITY" header, a scale bar, the card column and the hint bar. The map area is empty, as expected before Task 12. The pink clip probe is confined to the map area, which confirms clipping. `\` does not register on the user's ABNT2 keyboard, so the user rebound Toggle to `'` in Mod Settings. |
| 3. Self-test | First run: 2 FAIL (`input.toggle`, `input.ctrl_toggle_is_selftest`). Mod Settings applies saved bindings to class defaults, so the test's `new NightMapSettings()` carried the user's `'` binding; this was a bug in the test. Fixed in c313f03, which pins the key bindings in `InputCases`. Re-run: `TEST|SUMMARY|passed=43|failed=0`. |
| 4. Controls while driving | Pass for the conflict check. Numpad keys do nothing to the car or the game while driving, and WASD steering is unaffected. Whether pan, zoom and follow move the map can't be seen while the map area is empty, so that check moves to Checkpoint 2. |
| 4b. NumLock off | Not separately reported. Arrow keys are ignored by design (`input.arrows_never_pan` passes). Re-check at Checkpoint 2. |
| 5. HUD hiding | Pass. Esc menu hides the panel and it returns afterwards; photo mode hides it. |
| 6. Session teardown | Pass. The log shows `closed` (20:50:30) before the new session's `loaded` (20:50:31), and no panel appears after loading until the toggle is pressed. |

Follow-ups:
- The default toggle changes from `\` to `'` (`IK_SingleQuote`). `\` is layout-dependent and not reachable on ABNT2.
- At Checkpoint 2, confirm on visible tiles that the map pans, zooms and recentres, and repeat the NumLock-off check.

## Checkpoint 2 (2026-10-12)

Build: `feat/nightmap-core`. The first run used 8b51d7a. The final verified build is 36b12de, which adds the fixes listed below. Game 2.31 under Proton, at 2560×1440.

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

Build: `feat/gps-route`. Game 2.5 under Proton, at 2560×1440 (tiles built for 2.31; NightMap logs the version warning).

| Step | Result |
|---|---|
| 1. Install | Pass. COMPILE OK. |
| 2. Quest and waypoint routes | Pass (user). Both routes appear, end at their targets and follow the roads. The first build drew rotated dashes; the user found bends jagged. The native line widget cannot be created in-game, so routes now use the minimap's own `pathCircle` dots (spec §4.4 Outcome). The user then asked for wider dots (RouteScale 0.5 → 1.25). |
| 3. Header, HUD | Pass (user). Quest header at the bottom right; HUD fades out while open and comes back on close, minimap included, with routes still updating. |
| 4. Self-test | `passed=241 failed=9`. All `gps.*`, `geom.*`, `hud.*` and route tests pass except `route.flow_toward_dest` (reports 0). The user sees the flow working, so this is a test problem; 97ced85 makes the test log its numbers. The other 8 failures (`grow.*` ×5, `perf.wide_layer_exceeds_old_cap`, `vanilla.catalog_twelve` = 13, `tracking.live_accepted_are_quest_objectives`) are in code this branch does not touch and are left for a separate fix. |

Checkpoint B (perf suite with a route tracked, `route_open`) not run yet.
