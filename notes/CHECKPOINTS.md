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
