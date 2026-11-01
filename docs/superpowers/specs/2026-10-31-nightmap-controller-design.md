# NightMap controller support

## Intent

NightMap is published on Nexus, and many players play Cyberpunk 2077 on a controller. Today every NightMap control is
a keyboard key (numpad by default), so a controller player cannot open or use the map at all. They need to open the
map, move it, zoom it and teleport anywhere with the controller alone.

The keyboard map is a live overlay: the game keeps running and V can keep walking or driving while it is open, because
the numpad keys do not clash with gameplay. A controller has no spare buttons (View opens the vanilla map, Start the
pause menu, every face button, bumper, trigger, stick and D-pad direction has a gameplay job), so on a controller the
map takes over the pad while it is open.

## Goals

- Open the map with the controller: **hold View** (the user's choice). A quick tap on View keeps doing what it does
  in the vanilla game.
- Move the map with the left stick, analog: a small tilt moves slowly, a full tilt at the keyboard pan speed, smooth
  in every direction.
- Zoom with the triggers: RT in, LT out, analog (harder press, faster zoom; full press at the keyboard zoom speed).
- Teleport anywhere with X, with exactly the rules of the keyboard teleport key (fast travel on a fast travel marker,
  the photo's spot on a photo pin, the collectible's spot on a collectible pin, else the spot under the crosshair;
  honours Display → Teleport being off).
- The other keyboard actions get buttons: A = act (track the quest, zoom into a cluster), Y = cycle filter,
  R3 = follow V, B = close.
- While the map holds the pad, the game does not act on pad input: V does not walk, shoot, jump or dodge, and the
  camera does not turn. The game keeps running (no pause).
- **In a car, the car keeps coasting** while the map holds the pad (the user's choice): NightMap neither steers nor
  brakes it.
- **Fallback if a coast is impossible** (the user's choice): if holding the game's input off brakes or holds the car,
  then in a car the map still opens with hold View but does not take the pad and does not pan: the sticks, triggers
  and buttons keep driving the car, and the map follows V. (My calls for that mode: no pad zoom, act, filter or
  teleport, since every button drives the car; holding View again closes it; the keyboard keys still work; the hint
  bar says `HOLD VIEW CLOSE` plus the keyboard keys.) Both modes are built; which one ships for cars is decided by the
  user's hand test of driving, since the harness cannot put V in a car.
- The hint bar shows controller buttons once the controller was last used, keyboard keys once the keyboard was.
- Mod Settings → NightMap → Controller → **Open map button**: Hold View (default) or Off. (My call, after review:
  hold D-pad Down and L3 + R3 were dropped. NightMap sees raw presses but cannot stop them reaching the game, so those
  would also use a consumable, sprint or melee every time the map opens; R3 is also Follow V inside the map.)

## Non-goals

- Rebinding the in-map controller buttons (A, B, X, Y, R3, sticks, triggers): the layout is fixed. Only the open
  button is a setting. (My call: keeps Mod Settings short; can be added later.)
- CET keybinds: CET binds are keyboard keys, and CET would be a new requirement for every Nexus user. NightMap reads
  the pad itself through Codeware, which it already needs.
- Debug chords (self-test, perf suite, calibration, debug layer) on the controller: they stay keyboard only.
- The right stick: unused while the map is open. (My call.)

## Anti-goals

- Any change to how the keyboard map behaves today. A map opened and used only with the keyboard stays a live
  overlay: V keeps walking and driving, nothing is blocked.
- The vanilla map, hub or pause menu opening as well when View is held to open NightMap.
- A button press that closes the map (B) or opens it (View) also reaching the game on its release, e.g. B's release
  making V crouch or dodge.
- The pad staying locked after the map closed, after loading a save, or after the map failed to open.
- Any cost while the map is closed beyond reading the raw button events NightMap already receives.

## Constraints

- Requirements stay: redscript, Codeware, Mod Settings (plus the existing optional plugins). Nothing new.
- Input comes from Codeware's raw callbacks: `Input/Key` (`KeyInputEvent`, already registered in `NightMapSystem`)
  for buttons, and Codeware's axis callback (`AxisInputEvent`, `GetValue()`) for the sticks and triggers. Raw events
  keep arriving while the game's own actions are held off.
- Pad keys are the `EInputKey.IK_Pad_*` values (`IK_Pad_Back_Select` is View, `IK_Pad_LeftAxisX/Y`,
  `IK_Pad_LeftTrigger`, `IK_Pad_RightTrigger`, `IK_Pad_A_CROSS`, `IK_Pad_B_CIRCLE`, `IK_Pad_X_SQUARE`,
  `IK_Pad_Y_TRIANGLE`, `IK_Pad_RightThumb`, `IK_Pad_LeftThumb`, `IK_Pad_DigitDown`).
- Holding the game's actions off: the user's photo mode mod (`~/photomode_ui_improvements/src/r6/scripts/
  PhotoModeUIImprovements/PadNav.reds`) pushes `UIGameContext.ModalPopup` on the UI system while its pad navigation
  is active, with a short cooldown after leaving so the leaving button's release cannot reach the game. That is the
  starting point; whether it also stops V's locomotion, camera and combat in normal gameplay and in a car (and lets a
  car coast rather than brake) must be proven in the real game. If it falls short, `GameplayRestriction.*` status
  effects (NoMovement, NoCameraControl, NoWeapons, NoJump, NoRadialMenus, ...) are the fallback.
- Hold threshold for opening: half a second (my call), measured with NightMap's clock from the press.

## Decided behaviour

- **When the pad is taken:** only when the map is opened with the pad (my call, after review). A map opened with the
  keyboard ignores the pad completely, so a player who drives with a controller and uses the numpad for NightMap keeps
  full control of the car, exactly as today. With Open map button = Off, NightMap never reads the pad. The map gives
  the pad back when it closes (after a short cooldown so the close press's release does not reach the game), on
  session teardown (`OnDetach`), and if opening failed. While the pad is taken, the keyboard still drives the map.
- **Open button while open:** pressing the open button again also closes the map, like the keyboard toggle.
- **Display → Hold key to show:** applies to the pad too: the map opens once View has been held for the threshold and
  closes when View is released.
- **Deadzone and curves:** sticks and triggers ignore small values, and speed follows the tilt or pull beyond that
  (exact deadzone and curve left to the builder; the game's `inputDeadzones.xml` is a reference).
- **Snap on release:** letting the left stick go counts like letting the pan keys go (the existing snap-to-marker
  behaviour).
- **Hint bar, pad version:** `LS PAN · LT/RT ZOOM · R3 FOLLOW · A ACT · X <TELEPORT|FAST TRAVEL> · Y FILTER: <view> ·
  B CLOSE`, with "RELEASE VIEW CLOSE" when Hold to show is on. It switches to whichever device sent the last input.

## Verification

- In-game self-tests (the existing `NMSelfTest` style) for the pure parts: pad button mapping, open-hold timing,
  axis deadzone and curve, the pad vector, last-device hint text, pad-taken state transitions.
- The soak harness drives the real game with keyboard input only (xdotool). Add a virtual Xbox controller through
  `/dev/uinput` (the user's account can write it) so plans can press pad buttons and move sticks and triggers. Then a
  real-game plan that proves: hold View opens NightMap and the vanilla map does not open; a tap of View still does
  what it does in vanilla; the left stick pans and V does not move; the triggers zoom; X teleports; A, Y, R3 act;
  B closes and V does not crouch or dodge on its release; after closing, the stick walks V again; with the keyboard
  only, V still walks while the map is open.
- Driving with the map open (the car coasts) cannot be set up by the harness (it cannot put V in a car); the user
  checks that by hand.
- All existing self-tests and plans keep passing.

## Left to the builder

- Where the pad code lives (extend `NMInput` or a sibling) and how axis events reach it.
- Exact deadzone, response curves and the open-hold timing mechanism.
- The cooldown length after closing.
- How to keep View's hold from also opening the vanilla map, if the vanilla map opens on press rather than release.
- The virtual controller implementation (raw uinput in Python, no new system packages) and its harness plan format.
