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
