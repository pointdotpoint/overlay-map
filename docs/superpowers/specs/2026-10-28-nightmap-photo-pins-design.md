# NightMap photo pins — design

Status: draft awaiting user approval (2026-10-28); builder check done

## 1. Intent

Every photo mode shot the player takes becomes a spot on NightMap that they can teleport back to. On the map the
spot shows as a small thumbnail of the shot, pinned where it was taken (Google Maps style). Focusing a pin opens a
large preview of the shot in a drawer on the right half of the map. The teleport key on a focused pin puts V back on
that spot.

This is one of the mod's main features. It also brings back real teleporting, which failed for arbitrary map points
(spec `2026-10-27-nightmap-teleport-design.md` §12): a photo spot has a full 3D position, so V can land on it in one
step, the case that already worked on foot for exact marker landings.

## 2. Goals

1. **Save the spot** of every photo taken in photo mode from now on: V's position at capture, the time, and whatever
   the game needs to load that shot again.
2. **Show it on the map** as a framed thumbnail with a point at the bottom touching the spot.
3. **One pin per place:** shots within about 10 m of each other count as one place; only the newest is shown.
4. **Preview on focus:** with the crosshair on a photo pin, a drawer covers the right half of the map and shows the
   shot close to full size, plus date and time, distance, district and the teleport key.
5. **Teleport:** the teleport key (default Numpad .) on a focused photo pin lands V on the saved spot.

## 3. Non-goals

- Photos taken before this ships. They have no saved position and never appear (the user agreed).
- Opening the full-size shot, browsing older shots of a place, editing or deleting shots from NightMap.
- Teleport to anything other than photo pins (fast travel markers keep using fast travel).
- Taking photos outside photo mode (F12 / Steam screenshots).

## 4. Anti-goals (a failure even if it technically works)

- A thumbnail on the map that is a different photo from the one taken there.
- V landing inside a wall, under the map, or dying from the teleport.
- The map getting slow to open or pan once there are hundreds of photo spots.
- Photo mode itself behaving differently, slower capture, or a broken shot because of NightMap.
- Losing saved spots when loading an older save or starting a new game.

## 5. What the user decided

- **Purpose:** teleport back to a photo's spot. Which spot doesn't matter; any shot counts.
- **Scope:** only photos taken from now on.
- **On focus:** a drawer covering the right half of the map with a bigger preview (mockup option C).
- **Many shots at one place:** show only the latest one taken there.
- The user had nothing to add when asked what would make them wince.

## 6. Behaviour (my calls, unless marked)

### 6.1 Capture
- Photo mode calls `OnHideForScreenshot` on `PhotoModeMenuController` when it captures a shot
  (`photoModeMenuController.script:586`). NightMap wraps it and records the capture: V's world position
  (`player.GetWorldPosition()`, where V stands, **not** the photo-mode camera, which can float metres away into the air
  or through walls), the wall-clock time, and V's yaw.
- If V is in a vehicle when the shot is taken, record V's position anyway (my call). Teleporting there later lands
  V on foot on that spot; the car is not part of it.
- The capture must not delay or alter the shot (anti-goal). The wrap only stores a record and returns.

### 6.2 Linking the capture to its shot — the one unknown
The game can load a photo mode shot into an `inkImage` by itself:
`SystemRequestsHandler.RequestGameScreenshotByHash(hash, image, listener, callback)` and
`RequestGameScreenshot(index, …)` (`systemRequestsHandler.script:48-50`). The apartment picture frames use the hash
form and persist the hash (`devices/frame/frame.script:154,265`), so the hash is stable across sessions. Each shot's
`GameScreenshotInfo` carries `path`, `creationDate`, `pathHash` and `screenshotIndex` (`gallery.script:10-18`).

What is unknown is how a script gets the new shot's `pathHash`. The list arrives through
`RequestGameScreenshotsForLoad()` → `OnScreenshotsForLoadReady(array<GameScreenshotInfo>)`, an event delivered to the
gallery menu controller that asked. It is not known whether a non-gallery controller can receive it.

**So the build starts with a throwaway in-game spike** that answers, in this order:
1. Can NightMap obtain the screenshot list (and thus the newest shot's `pathHash`) after a capture, from photo mode or
   any controller it can reach? Matching rule: the newest entry whose `creationDate` is at or after the capture time.
2. Does `RequestGameScreenshotByHash` load that shot into a NightMap-created `inkImage`, outside the gallery and
   outside photo mode?
3. How long a load takes, and whether many (20+) loads at once are fine.
4. Whether a single exact teleport to a spot about 1 km away lands V on the floor, on foot (see §6.6).
5. Whether RedIMGRetriever (the user's copy is in `~/Downloads/NexusMods/RedIMGRetriever-14315126154072.zip`) loads
   on 2.5. The spike installs it temporarily for this; it is removed again unless it becomes the chosen path or is
   kept for perf runs (§7).

Thumbnails are requested only when the map opens, never right after capture: the user's photo mode plugin rewrites
the shot file in place after capture (it keeps an `originals` folder), and an early load could show the unprocessed
version.

**Fallback** if the vanilla path fails: RedIMGRetriever, which NightMap already supports for image items
(`NightMapItem.Image(pos, cat, "shot://<file>|max256x256")`, `Optional.reds`), with `ListScreenshots()` to find the
new file (names like `photomode_27102026_225854.png` in `Pictures/Cyberpunk 2077`). It was removed from the game
before the 2.5 update and is untested on 2.5; the spike also checks whether it loads. If neither path works, stop and
come back to the user before building further.

The chosen path is recorded in the spec as an addendum after the spike.

### 6.3 Storage
- Spots are saved in a NightMap file of their own, **not** in the save game, so they show up in whichever save is
  loaded and survive loading older saves (anti-goal). My call: RedFileSystem (installed and loaded in this game), a
  small JSON file in NightMap's storage, written once per capture.
- Record: `{ hash or file name, x, y, z, yaw, takenAt }`.
- If the file is missing or unreadable: start empty and log one line; never crash or block the map.
- **Deleted shots:** when the shot behind a spot no longer exists (load fails, or not in the list), the spot is not
  shown. If it was the newest of its place, the next newest shown shot of that place takes over.

### 6.4 On the map
- A new layer "Photos" with its own filter category, so it can be hidden like other markers (my call).
- **Grouping:** shots within 10 m (2D) of each other form one place; the place shows its newest shot. The rule does
  not change with zoom, so places close together can overlap when zoomed far out, like other markers. No count badge.
- **Pin:** a small framed thumbnail of the shot (landscape, roughly icon-sized, about 34×24 px at 1080p), with a short
  point at the bottom touching the spot. Same size at every zoom. A plain frame shows until the thumbnail has loaded.
- Thumbnails load only for pins on screen while the map is open, so hundreds of spots stay cheap.

### 6.5 Focus drawer (user: option C)
- With the crosshair on a photo pin, a drawer covers the right half of the map panel: the shot on top, close to full
  size (16:9), then date and time, distance, district, and `NUM . TELEPORT`. For photo pins it replaces the usual
  tooltip.
- The hologram look applies to the drawer's frame and text, not to the photo.
- **Focus point while the drawer is open (my call, from the builder check).** NightMap selects the item nearest the
  map-area centre (`Render/Crosshair.reds:3`), which is exactly the drawer's left edge. So when the drawer opens, the
  focus point and the view both shift a quarter of the panel width to the left, together, so the focused pin sits at
  the centre of the visible left half and stays under the focus point. Because the pin and the focus point move
  together, opening the drawer cannot unselect the pin (no open/close loop). The shift eases in and out over about
  150 ms and reverses when the drawer closes.
- The map keeps panning and zooming normally while the drawer is open. The drawer closes when the focused item is
  no longer a photo pin.

### 6.6 Teleport
- The teleport key (Numpad ., the key fast travel uses today) is context-sensitive: on a fast travel marker it fast
  travels as now; on a photo pin it teleports. The hint bar label follows the selection ("TELEPORT" on a photo pin).
- **On foot:** `TeleportationFacility.Teleport` to the saved position and yaw, then the map closes. The removed
  `Teleport.reds` (commit `8a9b3a0`) has the call.
- **Not confirmed in game (builder check):** an exact-position teleport 1 km away has never been seen landing in the
  log. The earlier free-teleport sessions showed ground collision only streams in once V is within about 110 m of
  it, so V could arrive before the floor exists and fall. The spike (§6.2, step 4) tests this first. If V falls, the
  fallback is my call: give V the game's `BaseStatusEffect.Invulnerable` for the teleport, and re-teleport V to the
  saved spot every frame (zeroing the fall) until a `Static`+`Terrain` ray finds ground within 2 m below the spot or
  5 s pass; on timeout, return V to the start. V never free-falls more than one frame.
- **In a vehicle:** refused with a log line, like fast travel (my call). The map stays open.
- **Quest locks:** not blocked. Photo teleport works even where the game has fast travel locked. This was settled for
  the earlier free teleport ("teleporting during a scene can break quest scripting, like any teleport mod; I won't
  block it, it's your call when to use it"), and the user did not object; it carries over.
- **Refused or failed** cases are logged as `photo|teleport|refused|<reason>`; the map stays open.

## 7. Constraints

- redscript + Codeware, offline compile with `tools/check.sh`, in-game self-tests (Ctrl + ') for logic; the existing
  NightMap layer, item and tooltip APIs.
- Game version 2.5 under Proton. Photo mode shots are in
  `compatdata/1091500/pfx/drive_c/users/steamuser/Pictures/Cyberpunk 2077`.
- The user's own photo mode mods (PhotoModeUIImprovements, PMUI* plugins) are installed. NightMap's wrap of the
  photo mode controller must chain cleanly with theirs (`@wrapMethod`, always call `wrappedMethod()` first).
- Perf: no new per-frame cost while the map is closed; with the map open and 500 saved spots, the open and pan rows
  in the perf suite must stay within their current budgets.
- The perf suite needs RedIMGRetriever's precise clock and refuses to run without it
  (`Core/NightMapSystem.reds:171`). My call: if the spike shows RedIMG works on 2.5, it stays installed for perf runs
  (an optional dependency, as before). If it doesn't, the 500-spot gate becomes a manual check: open and pan the map
  with 500 seeded spots and compare the frame time on the FPS overlay with the same moves at 0 spots; the spec is
  amended to say so.

## 8. Left to the builder

- How the thumbnail is drawn (vanilla `inkImage` per pin vs the existing item renderer's image path), pooling, and
  load queueing.
- The exact JSON layout and file name, and the grouping implementation.
- Drawer animation (if any), exact type sizes, and how the drawer reuses the tooltip's styling.
- Self-test coverage: grouping (newest wins, 10 m edge, deleted newest), record round-trip, refusal reasons, and the
  key's context switch.

## 9. Checkpoint (in game)

1. Take 3 shots at one spot and 1 shot 50 m away. Open NightMap: two pins, the first showing the newest of the three.
2. Thumbnails match the shots taken there.
3. Focus each pin: the drawer shows the right shot, date, distance and district.
4. Walk 1 km away, focus a pin, press Numpad .: V lands on the spot, no damage.
5. In a car: Numpad . on a photo pin is refused; on a fast travel marker it still fast travels (on foot).
6. Delete the newest shot in the in-game gallery, reopen the map: that place shows the previous shot.
7. Load an older save: the pins are still there.
8. Hide "Photos" with the filter: no photo pins.

## 10. Addendum after the spike (2026-10-28)

Findings: `docs/superpowers/specs/2026-10-28-photo-pins-spike/FINDINGS.md`.

- **Load path:** vanilla `RequestGameScreenshotByHash` into NightMap's own `inkImage`s. RedIMG is not used for
  thumbnails.
- **List source:** always the HUD minimap controller's `GetSystemRequestsHandler()`; the photo mode controller's
  handler never delivered the list.
- **Linking by session, not by count (replaces §6.1/§6.2 matching).** The capture hook fires twice per shot, but V
  cannot move in photo mode, so every shot of one photo mode session shares V's spot. When photo mode opens,
  NightMap records V's position and yaw and requests the list to get a baseline (the newest `creationDate`). When
  photo mode closes, and again on every map open while a session is unresolved, it requests the list; every entry
  newer than the baseline whose hash is not yet saved becomes a spot at that session's position. A session whose
  baseline never arrived is dropped with a log line rather than guessed (so the 1,300 older shots are never
  claimed). Sessions with no new files are dropped.
- **Date shown in the drawer** comes from the file name (`photomode_DDMMYYYY_HHMMSS`), since `creationDate` is
  Unix seconds and the scripts have no date formatting.
- **Thumbnail cap (my call):** shots load full size (2560×1440), so at most 24 pins show a loaded thumbnail at once;
  the rest show the plain frame. The drawer's image counts separately.
- **Teleport:** a single exact teleport works (1335 m, 3 cm settle, no fall). No invulnerability or hold.
- **RedIMGRetriever** works on 2.5 and stays installed for perf runs; the perf gate in Task 7 is the real suite.
- **Storage format:** a `;`-separated line file (`photos.txt` in RedFileSystem storage `NightMap`) instead of JSON;
  the layout was left to the builder.
