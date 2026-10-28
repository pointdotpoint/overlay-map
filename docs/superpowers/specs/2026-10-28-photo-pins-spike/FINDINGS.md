# Photo pins spike — findings (2026-10-28)

Probe: `r6/scripts/NightMap/Debug/PhotoProbe.reds` (commit `5eaa741`, removed in Task 7). Two game sessions on
2.5 under Proton, with RedIMGRetriever 0.3.1 installed temporarily. Raw lines: `photoprobe|` in CET `gamelog.log`.

## 1. Capture hook
- `gameuiPhotoModeMenuController.OnHideForScreenshot` fires on capture, but **twice per shot**: 6 calls for 3 shots
  (11:05:20/25, 28/33, 35/39), and 2 calls for 1 shot in session 2. The second call comes about 5 s later, when the
  file is finished. Counting calls cannot be used to count shots.
- V cannot move in photo mode: every call in a session logged the same position and yaw. So **one position per
  photo mode session** is exact for every shot of that session.

## 2. The screenshot list
- `RequestGameScreenshotsForLoad()` → `OnScreenshotsForLoadReady(array<GameScreenshotInfo>)` reaches any
  `IScriptable` registered with `handler.RegisterToCallback(n"OnScreenshotsForLoadReady", obj, n"cb")`.
- **Works from the HUD minimap controller's handler** (`MinimapContainerController.GetSystemRequestsHandler()`):
  every map open delivered the list in under 1 s (1315 → 1318 entries after 3 new shots).
- **Does not work from the photo mode controller's `OnUninitialize`**: requested 3 times, never delivered.
- `pathHash` equals `GetPathHash(path)` for every entry; `path` is the Windows path
  (`C:\users\steamuser\Pictures\Cyberpunk 2077\photomode_28102026_110520.png`).
- `creationDate` is **Unix seconds** of the file write: `photomode_28102026_110520.png` → `1793196325`
  (11:05:25 local), about 5 s after the time in the file name. `screenshotIndex` is 0 in every entry (not usable).

## 3. Loading a shot outside the gallery
- `RequestGameScreenshotByHash(hash, inkImage, listener, n"cb")` into NightMap-created `inkImage`s, with the map
  open: returns `true`, callback `(size: Vector2, err: Int32)` reports `2560x1440`, `err 0`.
- First load ≈ 0.45 s. 21 at once finish one after another, ≈ 3.7 s total (≈ 170 ms each).
- The texture is the **full-size shot** (2560×1440) even for a 68×48 widget, so on-screen thumbnails must be capped.

## 4. Exact teleport
- On foot, 1335 m from the saved spot: one `TeleportationFacility.Teleport(player, pos, yaw)`. V's Z read
  `target − 0.03 m` from 100 ms to 3 s, X/Y exact. No fall, no damage (user confirmed "the teleport worked").
- **The hold fallback (spec §6.6) is not needed.**

## 5. RedIMGRetriever on 2.5
- Loads (`RedIMGRetriever (version: 0.3.1) has been loaded`), and NightMap logs `precise clock true`, so the perf
  suite can run. It stays installed as an optional dependency for perf runs (spec §7).
