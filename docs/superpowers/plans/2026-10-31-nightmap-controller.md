# NightMap Controller Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Open, pan, zoom, act, filter and teleport on NightMap with a controller; the map takes the pad while open.

**Architecture:** Raw pad buttons arrive on the existing Codeware `Input/Key` callback and sticks/triggers on
Codeware's axis callback. A pure `NMPad` class turns them into map intents (analog pan vector, zoom rate, one-shot
actions, open-hold timing, last device). `NightMapSystem` owns taking the pad (pushing `UIGameContext.ModalPopup`,
cooldown on release) and a car branch. The soak harness gains a virtual Xbox 360 pad on `/dev/uinput`.

**Tech Stack:** redscript, Codeware, Mod Settings; Python 3 (stdlib only) for the harness.

**Spec:** `docs/superpowers/specs/2026-10-31-nightmap-controller-design.md`

## Global Constraints

- No new requirements: redscript, Codeware, Mod Settings only. Harness: Python stdlib only, no system packages.
- Keyboard behaviour unchanged; a map opened with the keyboard ignores the pad completely.
- Open map button setting: Hold View (default) or Off; Off = NightMap never reads the pad.
- Open hold threshold: 500 ms from the View press.
- Pad layout (fixed): LS pan, RT zoom in, LT zoom out, A act, X teleport (honours `teleportEnabled`), Y filter,
  R3 follow V, B close, View (press while open) close.
- Hold to show applies to the pad: open after the hold threshold, close on View release.
- Pad hint: `LS PAN   ·   LT/RT ZOOM   ·   R3 FOLLOW   ·   A ACT   ·   X <label>   ·   Y FILTER: <view>   ·   B CLOSE`
  (`RELEASE VIEW CLOSE` in place of `B CLOSE` with Hold to show); car pass-through mode: `HOLD VIEW CLOSE` followed by
  the keyboard hint.
- Car: coast mode (pad taken) is the default; pass-through mode (pad not taken, no pad map actions, map follows V,
  holding View again closes) is selected by `NMPad.CarPassThrough()`; the user's hand test decides.
- Nothing runs while the map is closed beyond the raw event callbacks.

## Review Focus

- Map closed by teardown (save load, quit) while the pad is taken: the context must be popped (OnDetach test).
- B's release right after closing must not reach the game: cooldown keeps the context ~8 frames; plan checks V
  didn't crouch/dodge (vpos unchanged, last_keys).
- View tap (shorter than 500 ms) must open nothing in NightMap: `NMPad` test `pad.view_tap_no_open`.
- Stick drift (small LS values at rest) must not pan or cancel follow: deadzone test `pad.deadzone`.
- Map opened with keyboard, then pad used: map must not react and must not take the pad: test
  `pad.keyboard_open_ignores_pad` plus plan step.

---

### Task 1: Virtual pad in the harness, and a spike that proves the approach

**Files:**
- Create: `tools/soak/pad.py` (uinput Xbox 360 pad: `VirtualPad.open()`, `press(btn, seconds)`, `down(btn)`,
  `up(btn)`, `axis(name, value)`, `close()`; buttons `A B X Y LB RB VIEW START LS RS DUP DDOWN DLEFT DRIGHT`, axes
  `LX LY RX RY LT RT` with value -1..1 (triggers 0..1))
- Modify: `tools/soak/runner.py` (steps `{"pad": "A"}`, `{"padhold": "VIEW", "seconds": 0.8}`,
  `{"paddown": "B"}`, `{"padup": "B"}`, `{"padaxis": "LX", "value": 1.0}`; pad created at run start only when the plan
  uses a pad step, closed at run end)
- Modify: `tools/soak/autopilot/SoakHooks.reds`, `SystemBody.inc` (commands `in_menu` → "menu"/"game" from
  `UI_System.IsInMenu`; `hold_ctx on|off` pushes/pops `UIGameContext.ModalPopup`; `watch_axis` / `last_axis` log axis
  events like `watch_keys`)
- Create: `tools/soak/plans/pad-spike.json`
- Test: `tools/soak/tests/soak_pad_test.py`

- [ ] Test `test_event_encoding` (struct layout of `input_event` 24 bytes, EV_KEY/EV_ABS/EV_SYN codes), and
  `test_axis_scaling` (LX 1.0 → 32767, -1.0 → -32768, LT 1.0 → 255). Run `python3 -m pytest tools/soak/tests/soak_pad_test.py` → FAIL.
- [ ] Implement `pad.py` with ctypes-free `fcntl.ioctl` + `struct` (UI_SET_EVBIT/KEYBIT/ABSBIT, uinput_user_dev with
  vendor 0x045e product 0x028e, name "Microsoft X-Box 360 pad"). Tests PASS.
- [ ] Runner steps + unit test of the step parsing in `soak_game_test.py` style. PASS.
- [ ] Spike plan, real game: `watch_keys`, `watch_axis`, pad A / LX 1.0 → `last_keys` contains `IK_Pad_A_CROSS`,
  `last_axis` contains `IK_Pad_LeftAxisX`; `padhold VIEW 0.8` then `in_menu` (does vanilla open on press/hold?);
  `pad VIEW` (tap) then `in_menu`; `hold_ctx on`, LY 1.0 for 2 s, `vpos` before/after (V must not move); `hold_ctx off`,
  LY again (V moves). Record findings in the plan's Notes section. If the pad never reaches the game, stop and report.
- [ ] Commit.

### Task 2: `NMPad`, the pure pad logic

**Files:**
- Create: `r6/scripts/NightMap/Core/Pad.reds`
- Modify: `r6/scripts/NightMap/Debug/SelfTest.reds` (group `pad.*`)

**Interfaces (Produces):**
- `public class NMPad` with fields `act, teleport, filter, recenter, close, openRequested: Bool`, `lastWasPad: Bool`
- `func Button(key: EInputKey, action: EInputAction, nowMs: Float, mapOpen: Bool, padOwned: Bool, holdToShow: Bool, enabled: Bool) -> Bool`
- `func Axis(key: EInputKey, value: Float)`; `func PanVector() -> Vector2` (deadzone 0.2 radial, rescaled, squared
  response); `func ZoomRate() -> Float` (RT − LT after 0.1 deadzone, -1..1)
- `func PollHold(nowMs: Float) -> Bool` (true once when View has been held ≥ 500 ms and the map is closed)
- `func Reset()`; `static func IsPad(key: EInputKey) -> Bool`; `static func HintText(view: String, teleportLabel: String, teleportOn: Bool, holdToShow: Bool) -> String`
- `static func CarPassThrough() -> Bool` (returns false: coast mode)
- `static func HoldMs() -> Float = 500.0`; `static func CooldownFrames() -> Int32 = 8`

- [ ] Tests: `pad.view_tap_no_open` (press t=0, release t=200 → no open), `pad.view_hold_opens` (press t=0,
  PollHold(499) false, PollHold(500) true once), `pad.deadzone` (LX 0.15 → zero vector), `pad.full_tilt` (LX 1.0 →
  (1,0)), `pad.diag_unit` (LX .9 LY .9 → length ≤ 1), `pad.zoom_rate` (RT 1 → 1, LT 1 → -1, both → 0),
  `pad.buttons_only_when_owned` (A with padOwned false → act false), `pad.buttons` (A act, X teleport only if teleportOn
  passed via Button? → teleport flag set, system checks setting), `pad.b_closes`, `pad.view_closes_when_open`,
  `pad.hold_to_show_release_closes`, `pad.disabled_ignores_all`, `pad.hint_text` (exact copy from Global Constraints).
  Axis Y: game's LeftAxisY is up-positive; PanVector Y is down-positive (screen).
- [ ] Implement; build with redscript (`tools/soak` staging compiles), run selftest in the next real-game run.
- [ ] Commit.

### Task 3: Settings and system wiring

**Files:**
- Modify: `r6/scripts/NightMap/Core/Settings.reds` (enum `NightMapPadOpen { HoldView = 0, Off = 1 }`, field
  `padOpen: NightMapPadOpen = HoldView`, category "Controller", order "5", display values "Hold View", "Off")
- Modify: `r6/scripts/NightMap/Core/NightMapSystem.reds`
- Modify: `README.md` (Using it: controller line)

**Interfaces (Consumes):** Task 2's `NMPad`.

- [ ] `OnAttach`: create `this.pad`, register Codeware axis callback (name verified in Task 1) → `OnAxisInput`;
  `OnDetach`: unregister, `ReleasePad(true)` (pop context immediately).
- [ ] `OnKeyInput`: pad keys go to `this.pad.Button(...)` (keyboard path unchanged); a View press while closed starts a
  short repeating DelayCallback that calls `PollHold` until release or open (no loop while idle).
- [ ] `OpenFromPad()`: `Open()`; if open and not (in car and `CarPassThrough()`), `TakePad()` (push ModalPopup once,
  `padOwned = true`). `Close()`: if `padOwned`, start cooldown; Tick pops the context after `CooldownFrames()`; if the
  loop stops first, pop at close (no frame left).
- [ ] `DriveCamera`: pan = keyboard vector + pad vector (pad only when `padOwned`); zoom by `ZoomRate()` scaled to
  `NMTheme.ZoomRatePerSecond()`; snap-on-release uses the combined vector; pad one-shots map to the existing act /
  teleport (only if `s.teleportEnabled`) / filter / recenter / close handling.
- [ ] Hint: pad hint when `pad.lastWasPad && padOwned`, car pass-through hint when open from pad in car without owning.
- [ ] Commit.

### Task 4: Real-game verification and install

**Files:**
- Create: `tools/soak/plans/controller.json`

- [ ] Plan runs: selftest (all pass); hold VIEW 0.8 → `is_open` open, `in_menu` game; LY 1.0 2 s → `vpos` unchanged;
  LX 1.0 1 s → camera moved (`selected`/counts or a new `cam` command returning centre); RT 1.0 1 s → mpp smaller;
  X on a spot → `tp_result` landed; B → closed, `vpos` unchanged after 1 s, `in_menu` game; LY 1.0 after close → V
  moves; tap VIEW → `is_open` closed; keyboard open (key 94) + LY 1.0 → V moves and map ignores pad; hold-to-show
  run: hold VIEW 1.5 s → open during, closed after release.
- [ ] Run `python3 tools/soak/soak.py campaign tools/soak/plans/controller.json` plus `regression.json`; all pass.
- [ ] Install (the repo's install step), update memory, commit.

## Notes (filled in during execution)
