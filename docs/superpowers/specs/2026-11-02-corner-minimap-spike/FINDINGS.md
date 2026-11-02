# Corner minimap parity — findings (static)

Date: 2026-11-02. **Source: decompiled game scripts** (`UI/widgets/minimap/minimap.script`,
`UI/mappins/minimapMappins.script`, `mappinsControllers.script`) plus the spike instrumentation that compiles against the
installed game (`tools/soak/autopilot/MinimapSpike.reds`, commit 0b8676a). The in-game spike run (plan Task 1 Step 3)
was **skipped at the user's request**; rows marked *runtime* are unverified until the first hand test, and the code
for them logs what it finds (Debug setting on) so that hand test settles them.

## How NightMap gets parity

The vanilla minimap keeps running at opacity 0. Every minimap marker is a `BaseMinimapMappinController` whose
`Update()` (wrappable) runs each frame on the native side's schedule. NightMap wraps `Update()` and copies what the
controller just decided — world position, visibility, icon part / atlas / tint / opacity, clamp state, vertical
relation, tracked state — into an `NMMinimapMirror`. This is parity by construction: whatever the vanilla controller
shows, the mirror sees, including types not listed here. NightMap then draws the copies north-up at its own zoom.

## Parity checklist

| # | What vanilla shows | Vanilla source | Readable | How NightMap gets it |
|---|---|---|---|---|
| 1 | Map body (streets, buildings) | native 3D minimap render | n/a | NightMap tiles (exists) |
| 2 | V's icon | container player icon | yes | `NMPlayerMarker` (exists) |
| 3 | V's override icon (autodrive / vehicle) | `m_alternativeIconContainer`, `OverridePlayerIcon` | partial | NightMap arrow kept; autodrive shown by #8 |
| 4 | District / location name | `m_locationTextWidget` ← `UI_Map.currentLocation` blackboard | yes | strip text (SquareStrip) / label |
| 5 | Security zone label (Restricted / Hostile / …) | `m_securityAreaText`, `ZoneToTextKey(m_currentZoneType)` | yes (`@addMethod`, spike compiled) | label in the corner, vanilla text |
| 6 | Zone vignette (frame tint by zone) | `m_securityAreaVignetteWidget` state `ZoneToState` | yes | corner frame tinted by zone state |
| 7 | Combat highlight | `m_combatModeHighlight`, `m_playerInCombat` | yes | corner frame "Combat" state |
| 8 | Autodrive highlight | `m_autoDriveModeHighlight` ← `UI_AutodriveData.AutoDriveEnabled` | yes | corner frame accent + "AUTODRIVE" in label line |
| 9 | Courier countdown timer | `m_courierTimerContainer` ← `UI_HUDCountdownTimer` | yes | timer text in the corner label line |
| 10 | Fluff text (decorative digits) | `m_fluffText1` | yes | **not copied** — decorative chrome, replaced by NightMap's frame (ruling) |
| 11 | Hostile NPC dot, states, fade-out on death | `MinimapStealthMappinController.Update` | yes (spike compiled) | mirror: icon copy |
| 12 | Vision cones | `visionConeWidget`; geometry `StealthMappin.GetSenseCone()` (length, width, angleDegrees, position1/2, world) | yes | shape layer cone from world geometry, tint/opacity copied from `visionConeWidget` |
| 13 | Cameras / turrets / devices, effect radius | stealth (`m_isCamera`, `m_isTurret`) + `MinimapDeviceMappinController` (`effectAreaWidget`, `GameplayRoleMappinData.m_range`) | yes | mirror icon; radius circle from `m_range` |
| 14 | Loot / bodies | stealth `m_highestLootQuality`, `m_hasBeenLooted` → icon part | yes | mirror icon copy |
| 15 | Clamped markers at the rim + clamp arrow | `IsClamped()`, `clampArrowWidget` | yes | `NMParity.ClampToRim` for tracked + vanilla-clamped entries |
| 16 | Above / below arrows | `GetVerticalRelationToPlayer()` (native thresholds) | yes | mirror `vertical`; arrow parts `above`/`below` |
| 17 | Tracked marker emphasis | `IsTracked()`, `playerTrackedWidget` | yes | mirror `tracked` |
| 18 | Quest area (while tracked and inside) | `MinimapQuestAreaMappinController.areaShapeWidget` (inkShape) | *runtime* | shape vertices → world with the GPS transform (`NMGps.ToWorld`, mappin as origin) |
| 19 | Security areas (Safe / Restricted / Dangerous) | `MinimapSecurityAreaMappinController.areaShapeWidget`, `area.GetType()` | *runtime* | as #18, tinted by state |
| 20 | Ping markers | `MinimapPingSystemMappinController` | yes | mirror icon copy |
| 21 | Dynamic events (pulse) | `MinimapDynamicEventMappinController` | yes | mirror icon copy |
| 22 | Police / prevention vehicles, road blockades | `MinimapPreventionVehicleMappinController`, `MinimapStubMappinController`, `RoadBlockadeMappinController` | yes | police: `NMVanilla.IsPolice` (exists); blockades: mirror |
| 23 | Quest / POI / vehicle mappins | `MinimapQuestMappinController`, `MinimapPOIMappinController` (+ `VehicleMinimapMappinComponent`) | yes | already from world-map mirroring (`NMVanilla`); the minimap mirror skips these classes to avoid duplicates |
| 24 | GPS routes | container `gpsQuestPathWidget` / `gpsPlayerTrackedPathWidget` | yes | `NMGps` (exists) |
| 25 | Remote players | `MinimapRemotePlayerMappinController` | n/a | multiplayer only; not in the shipped game |

## Other facts

- **Container:** `MinimapContainerController extends MappinsContainerController extends inkProjectedHUDGameController`;
  not reachable from `inkWidget.GetController()`. NightMap already holds it (`NMGps.ctrl`, set from the
  `OnPlayerAttach` wrap in `Vanilla/Gps.reds`). Its root is `GetRootWidget()`.
- **Vanilla box:** the container root widget's absolute box. *Runtime:* confirm it is the circle's box and not a larger
  canvas; the probe logs the root and its children's boxes once (Debug on).
- **Hiding:** menus and photo mode hide the whole HUD layer, which hides NightMap's widgets in the same window
  (Checkpoint 1). The container itself hides its root for a remote-controlled vehicle in TPP
  (`m_rootWidget.SetVisible`). So the corner follows `root.IsVisible()`; NightMap fades **children** of the root, never
  the root, so the game's own root visibility/opacity stays readable. *Runtime:* scanner, braindance, the game's
  "minimap off" interface option.
- **What is faded:** every child of the container root except nothing — all vanilla chrome is redrawn by NightMap
  (#4–#9), so the whole vanilla subtree below the root goes to opacity 0.
- **Palette:** an `inkRectangle` styled with `base\gameplay\gui\common\main_colors.inkstyle` and
  `BindProperty(n"tintColor", slot)` compiles (spike). *Runtime:* that `GetTintColor()` returns the bound value; if
  not, fall back to today's colours and log once.
- **Circular clip:** *runtime.* Plan: `inkMaskWidget` over the map canvas with the mask texture the vanilla minimap
  uses; until confirmed, the Circle style draws the map in a square clip under a ring with circular culling of
  markers, and logs the mask result (Debug on).
