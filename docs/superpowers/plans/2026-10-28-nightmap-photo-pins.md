# NightMap Photo Pins Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every photo mode shot becomes a thumbnail pin on NightMap at the spot V stood; focusing it opens a
preview drawer over the right half of the map, and the teleport key lands V back on that spot.

**Architecture:** A capture hook on the photo mode controller records V's position; the game's own screenshot list
(`OnScreenshotsForLoadReady`) links each capture to its shot's `pathHash`; spots persist in a RedFileSystem file.
A normal NightMap layer ("Photos") carries one item per place (newest shot within 10 m), the item renderer loads
the thumbnail into the pin with `RequestGameScreenshotByHash`, and a new drawer widget shows the large preview.
Task 1 is an in-game spike; its findings can change Tasks 3–4 and decide whether Task 6 needs the hold fallback.

**Tech Stack:** redscript, Codeware, RedFileSystem (installed), Mod Settings; offline compile `tools/check.sh`;
in-game self-tests (Ctrl + ' with Debug tools on).

**Spec:** `docs/superpowers/specs/2026-10-28-nightmap-photo-pins-design.md`

## Global Constraints

- Only photos taken from now on; older shots never appear.
- Saved position is V's (`player.GetWorldPosition()`), never the photo-mode camera's.
- One place = shots within **10 m** (2D); only the newest shown; no count badge; rule does not change with zoom.
- Pin: framed landscape thumbnail about **34×24 px at 1080p** with a point at the bottom; same size at every zoom; a
  plain frame until loaded; thumbnails requested only while the map is open, never right after capture.
- Drawer covers the **right half** of the map panel: shot (16:9) on top, then date and time, distance, district,
  `NUM . TELEPORT`. Replaces the tooltip for photo pins. Hologram look on frame and text, not on the photo.
- Drawer open → focus point and view shift **a quarter of the panel width** left together, eased over **~150 ms**.
- Teleport key (default Numpad ., `keyTeleport`): fast travel on fast travel markers, teleport on photo pins. Refused
  in a vehicle. Not blocked by quest/fast-travel locks. Log `photo|teleport|refused|<reason>`.
- Spots stored outside the save game; missing or unreadable file → start empty, one log line, never block the map.
- Photo mode capture must not be delayed or altered; every wrap calls `wrappedMethod()` first.
- No new per-frame cost while the map is closed; 500 spots must keep the open and pan perf rows in budget.

## Review Focus

1. **Several shots in quick succession** (burst of 5 before the list is read): each capture gets its own shot, in
   order, none dropped or swapped. → Task 3 test `photo.link_burst`.
2. **Shot deleted after its spot was saved**: the place falls back to its next newest shot that still exists, or
   disappears. → Task 2 test `photo.group_deleted_newest`, Task 4 wiring.
3. **Pooled pin widget reused for a different photo**: the thumbnail must change with it (no stale image on a
   moved pin). → Task 4 test `photo.icon_key_changes`.
4. **Following V while a photo is focused**: follow re-centres every frame and would cancel the focus shift. →
   Task 5 test `photo.drawer_stops_follow`.
5. **Corrupt or hand-edited photos file** (bad line, wrong field count): the good lines load, bad ones are skipped
   and counted in one log line. → Task 2 test `photo.parse_skips_bad`.

---

### Task 1: In-game spike (throwaway)

Answers spec §6.2 questions 1–5. Nothing here ships; the probe file is deleted in Task 7.

**Files:**
- Create: `r6/scripts/NightMap/Debug/PhotoProbe.reds`
- Create: `docs/superpowers/specs/2026-10-28-photo-pins-spike/FINDINGS.md`
- Modify: `docs/superpowers/specs/2026-10-28-nightmap-photo-pins-design.md` (addendum §10 with the chosen path)

- [ ] **Step 1: Write the probe.** All lines start `photoprobe|`.
  - `@wrapMethod(gameuiPhotoModeMenuController) protected cb func OnHideForScreenshot()`: call `wrappedMethod()`,
    then log V's position and yaw, and store `this.GetSystemRequestsHandler()` in a static-reachable holder.
  - Also wrap `OnUninitialize` (photo mode closing): register an `IScriptable` probe listener with
    `handler.RegisterToCallback(n"OnScreenshotsForLoadReady", probe, n"OnList")` and call
    `handler.RequestGameScreenshotsForLoad()`. `OnList(infos: array<GameScreenshotInfo>)` logs the count and the 3
    entries with the highest `creationDate`: `path`, `creationDate`, `pathHash`, `handler.GetPathHash(path)`.
  - Repeat the list request from the HUD minimap controller NightMap already holds (`NMGps` wref) when NightMap
    opens, to learn whether a non-photo-mode controller's handler also delivers the list.
  - On map open, create one 320×180 `inkImage` in the panel and call
    `RequestGameScreenshotByHash(newestHash, img, probe, n"OnLoaded")`; `OnLoaded(size: Vector2, err: Int32)` logs
    size, error and ms elapsed. Then request 20 of the newest at once into 20 small images and log total ms.
  - With Debug tools on, Shift+Numpad . teleports V on foot to the last logged capture position
    (`TeleportationFacility.Teleport(player, pos, EulerAngles(yaw))`) and logs V's Z every 100 ms for 3 s.
- [ ] **Step 2: Compile.** Run `tools/check.sh`. Expected: `COMPILE OK`.
- [ ] **Step 3: Install RedIMGRetriever temporarily** from `~/Downloads/NexusMods/RedIMGRetriever-14315126154072.zip`
  into the game (game closed), then `tools/install.sh`. Note the files added so they can be removed.
- [ ] **Step 4: User session (checkpoint).** Ask the user to: take 3 shots at one spot, exit photo mode, walk
  ~1 km, open NightMap, wait 5 s, close, press Shift+Numpad ., wait 3 s, quit. Then read `photoprobe|` lines and
  RedIMG's own log.
- [ ] **Step 5: Write FINDINGS.md** answering: list reachable from photo mode / from the HUD controller; does the
  newest entry match the capture (creationDate unit, path form); does `pathHash` equal `GetPathHash(path)`; does
  the by-hash load work outside the gallery and how fast (1 and 20); did V's Z hold at the spot or fall; does RedIMG
  load on 2.5.
- [ ] **Step 6: Gate.** If no list source works **and** RedIMG fails, stop and report to the user. Otherwise
  record the chosen link source, load path, whether Task 6 needs the hold, and whether RedIMG stays (perf runs) in
  spec §10. Remove RedIMG again if it is not kept.
- [ ] **Step 7: Commit** probe, findings and spec addendum: `spike(photos): probe capture, screenshot list, load
  and exact teleport`.

### Task 2: Spots, grouping and storage

**Files:**
- Create: `r6/scripts/NightMap/Photos/PhotoStore.reds`, `r6/scripts/NightMap/Photos/PhotoGroups.reds`
- Create: `r6/scripts/NightMap/Debug/SelfTestPhotos.reds`; Modify: `r6/scripts/NightMap/Debug/SelfTest.reds` (call
  `NMPhotoTests.Run(this)`)
- Modify: `tools/check.sh` (copy the installed `r6/scripts/RedFileSystem` into the sandbox when present, like Codeware)

**Interfaces:**
- Produces:
  - `public class NMPhotoSpot { hash: Uint32; path: String; x, y, z, yaw: Float; created: Uint64; }` with
    `static func Create(hash: Uint32, path: String, pos: Vector4, yaw: Float, created: Uint64) -> ref<NMPhotoSpot>`
  - `NMPhotoStore.ToLine(s: ref<NMPhotoSpot>) -> String` / `NMPhotoStore.FromLine(line: String) -> ref<NMPhotoSpot>`
    (null on a bad line). One spot per line, `;`-separated `hash;x;y;z;yaw;created;path`, floats with 2 decimals.
    (Builder's call over the spec's "small JSON file": a line file needs no JSON parser; record the deviation in §10.)
  - `NMPhotoStore.Parse(lines: array<String>) -> array<ref<NMPhotoSpot>>`, `NMPhotoStore.Skipped() -> Int32`
  - `NMPhotoStore.Load() -> array<ref<NMPhotoSpot>>`, `NMPhotoStore.Append(s: ref<NMPhotoSpot>) -> Bool`:
    RedFileSystem storage `FileSystem.GetStorage("NightMap")`, file `photos.txt`, `WriteLines(..., Append)`. Both
    behind `@if(ModuleExists("RedFileSystem"))`; without it `Load` returns empty and `Append` returns false, with
    one `photo|store|no RedFileSystem` error.
  - `NMPhotoGroups.Newest(spots: array<ref<NMPhotoSpot>>, exists: array<Bool>, radius: Float) -> array<Int32>`:
    indices of the shown spot per place. A place is formed greedily newest-first: each existing spot not within
    `radius` of an already chosen spot starts a place. Non-existing spots are ignored.
  - `NMPhotoGroups.Radius() -> Float` = `10.0`.

- [ ] **Step 1: Write failing tests** in `SelfTestPhotos.reds`:
  - `photo.line_roundtrip`: `FromLine(ToLine(s))` keeps hash, path, created exactly and x/y/z/yaw within 0.01.
  - `photo.parse_skips_bad`: `Parse(["<good>", "garbage", "1;2;3", "<good>"])` → 2 spots, `Skipped() == 2`.
  - `photo.path_with_semicolon`: a path containing `;` round-trips (path is the last field; split at most 6 times).
  - `photo.group_one_place`: 3 spots within 4 m, created 1,2,3 → `Newest` = `[index of created 3]`.
  - `photo.group_edge`: two spots 9.9 m apart → one place; 10.1 m apart → two places.
  - `photo.group_deleted_newest`: same 3 spots, newest `exists=false` → shown is created 2.
  - `photo.group_all_deleted`: every `exists=false` → empty.
- [ ] **Step 2: Compile** `tools/check.sh` → fails on the missing `NMPhotoStore`/`NMPhotoGroups`.
- [ ] **Step 3: Implement** both files to the interfaces above.
- [ ] **Step 4: Compile** → `COMPILE OK`. Mirror `Newest` and the line parser in Python in the scratchpad and run the
  same cases (the in-game run comes at Task 5's checkpoint).
- [ ] **Step 5: Commit** `feat(photos): photo spots, grouping and line storage`.

### Task 3: Capture and linking

**Files:**
- Create: `r6/scripts/NightMap/Photos/PhotoCapture.reds` (wraps), `r6/scripts/NightMap/Photos/Photos.reds` (module)
- Modify: `r6/scripts/NightMap/Core/NightMapSystem.reds` (own `photos: ref<NMPhotos>`, accessor `Photos()`)
- Test: `r6/scripts/NightMap/Debug/SelfTestPhotos.reds`

**Interfaces:**
- Consumes: Task 2 `NMPhotoSpot`, `NMPhotoStore.Append/Load`; Task 1 §10 (which controller's handler delivers the
  list, the `creationDate` unit).
- Produces (amended after the spike, spec §10 — linking is per photo mode session, not per capture):
  - `NMPhotoLink.NewSince(hashes: array<Uint32>, created: array<Uint64>, baseline: Uint64, known: array<Uint32>) ->
    array<Int32>`: indices of entries with `created > baseline` whose hash is not in `known`, oldest first.
  - `NMPhotoLink.Baseline(created: array<Uint64>) -> Uint64`: the newest `created` (0 for an empty list).
  - `class NMPhotos`: `OnPhotoModeOpened(pos: Vector4, yaw: Float)`, `OnPhotoModeClosed()`, `OnMapOpened()`,
    `cb func OnList(infos: array<GameScreenshotInfo>)`, `SetHandlerSource(m: wref<MinimapContainerController>)`,
    `Spots() -> array<ref<NMPhotoSpot>>`, `Exists(i: Int32) -> Bool`, `Revision() -> Int32` (bumped on any change).
- Behaviour: photo mode open records the session (V position, yaw) and requests the list for its baseline; the
  capture hook is not needed (it fires twice per shot). Photo mode close and every map open request the list while a
  session is unresolved. `OnList`: no baseline yet → set it; else every `NewSince` entry becomes a spot at the
  session position, is appended to the file, and the session closes. A session whose baseline never arrived is
  dropped with `photo|link|no baseline`. Every list also rebuilds `exists[]` (a saved hash not in the list →
  `false`). The list always comes from the HUD minimap controller's handler (§10).

- [ ] **Step 1: Write failing tests:**
  - `photo.link_session`: hashes `[5,7,9]`, created `[90,101,105]`, baseline `100`, known `[]` → `[1,2]`.
  - `photo.link_skips_known`: same, known `[9]` → `[1]`.
  - `photo.link_burst`: 5 entries created `101..105` (shuffled order `[103,101,105,102,104]`), baseline `100` →
    indices ordered by created (`[1,3,0,4,2]`).
  - `photo.link_none`: baseline `105` → empty.
  - `photo.baseline`: `Baseline([3,9,4]) == 9`, `Baseline([]) == 0`.
- [ ] **Step 2: Compile** → fails on missing `NMPhotoLink`.
- [ ] **Step 3: Implement** `NMPhotoLink`, `NMPhotos`, and the wraps on `gameuiPhotoModeMenuController`:
  `OnInitialize` → `wrappedMethod()` then `Photos().OnPhotoModeOpened(player.GetWorldPosition(),
  player.GetWorldYaw())`; `OnUninitialize` → `wrappedMethod()` then `Photos().OnPhotoModeClosed()`. The minimap
  controller wrap in `Gps.reds` also calls `Photos().SetHandlerSource(this)`.
- [ ] **Step 4: Compile** → `COMPILE OK`.
- [ ] **Step 5: Commit** `feat(photos): capture hook and screenshot linking`.

### Task 4: Photos layer and thumbnail pins

**Files:**
- Modify: `r6/scripts/NightMap/Api/NightMapItem.reds` (`shotHash: Uint32`, `static func Shot(pos: Vector4, category:
  CName, hash: Uint32) -> ref<NightMapItem>`), `r6/scripts/NightMap/Api/NightMapLayer.reds` (store `shot[]`, keep it
  in `Add`/`Update`)
- Modify: `r6/scripts/NightMap/Render/ItemRenderer.reds` (photo chip: frame + pointer background, landscape icon
  slot, by-hash load)
- Modify: `r6/scripts/NightMap/Photos/Photos.reds` (layer sync), `r6/scripts/NightMap/Core/Settings.reds`
  (`showPhotos: Bool = true`, Display → "Photo pins")
- Test: `r6/scripts/NightMap/Debug/SelfTestPhotos.reds`

**Interfaces:**
- Consumes: Task 3 `NMPhotos.Spots/Exists/Revision`, Task 2 `NMPhotoGroups.Newest`.
- Produces: layer id `n"NightMap.Photos"`, category `n"Photos"` (display "Photo"); `NMPhotos.SyncLayer()`;
  `NMPhotos.SpotOf(itemId: Int32) -> ref<NMPhotoSpot>`; `NMItemRenderer.IconKeyFor(L, id) -> String` returning
  `"shot:" + hash` for photo items (used for the pooled-widget change check).
- Behaviour: `SyncLayer` runs on map open and whenever `Revision()` changes while open; it clears and re-adds one
  `NightMapItem.Shot` per `Newest(...)` index. The layer has clustering off and is shown only when `showPhotos` and
  the filter view is ALL. In the renderer, a photo chip whose `chipIconKey` differs from `IconKeyFor` calls
  `GetSystemRequestsHandler().RequestGameScreenshotByHash(hash, ic, ...)` (handler per §10) once; until its callback
  reports a non-zero size the icon is hidden and the frame shows. Frame and pointer art: builder's choice from the
  existing atlases. At most `NMPhotos.ThumbCap()` = 24 photo chips request or keep a thumbnail at once (spec §10:
  shots load at 2560×1440); further chips show the frame only. Test `photo.thumb_cap`: `NMPhotos.ThumbAllowed(23, 24)`
  true, `ThumbAllowed(24, 24)` false.

- [ ] **Step 1: Write failing tests:**
  - `photo.item_shot`: `NightMapItem.Shot(pos, n"Photos", 42u).shotHash == 42u` and `hasAtlas == false`.
  - `photo.icon_key_changes`: a layer with two photo items (hash 1, 2): `IconKeyFor` gives `"shot:1"` and `"shot:2"`;
    after `Update(id0, Shot(..., 3u))` id0's key is `"shot:3"`.
  - `photo.sync_newest`: an `NMPhotos` fed 3 near spots + 1 far spot (test seam `SetSpotsForTest(spots, exists)`) →
    after `SyncLayer` the layer has 2 alive items, one with the newest near hash.
- [ ] **Step 2: Compile** → fails on missing members.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Compile** → `COMPILE OK`.
- [ ] **Step 5: Commit** `feat(photos): photos layer with thumbnail pins`.

### Task 5: Preview drawer and focus shift

**Files:**
- Create: `r6/scripts/NightMap/Render/PhotoDrawer.reds`
- Modify: `r6/scripts/NightMap/Render/Panel.reds` (drawer canvas above the tooltip), `r6/scripts/NightMap/Render/
  Crosshair.reds:66` (pick centre `viewW * 0.5 - shift`), `r6/scripts/NightMap/Core/NightMapSystem.reds`
  (`RefreshTooltip`: photo item → drawer instead of tooltip; shift easing in `UpdateModules`)
- Test: `r6/scripts/NightMap/Debug/SelfTestPhotos.reds`

**Interfaces:**
- Consumes: Task 4 `NMPhotos.SpotOf`, layer id; `NMPanelLayout` (`mapW`, `mapH`, `scale`); the system's private
  `DistrictName()`, passed into `Show` as a string.
- Produces: `NMPhotoDrawer.Create(parent: ref<inkCanvas>, l: ref<NMPanelLayout>) -> ref<NMPhotoDrawer>`,
  `Show(spot: ref<NMPhotoSpot>, distance: String, district: String, keyName: String)`, `Hide()`, `IsShown() -> Bool`;
  `NMPhotoDrawer.ShiftTarget(open: Bool, mapW: Float) -> Float` (= `mapW * 0.25` or `0.0`);
  `NMPhotoDrawer.EaseShift(cur: Float, target: Float, dtMs: Float) -> Float` (reaches target in 150 ms).
- Behaviour: each frame the system eases `shift` toward `ShiftTarget`, pans the camera by the change
  (`camera.PanPixels(delta, 0.0)`) and passes `shift` to the crosshair, so the pin and the focus point move
  together. Opening the drawer sets `camera.follow = false`. The drawer's image loads by hash into its own
  `inkImage` (16:9, width = half the map minus padding). Date row from the file name (§10):
  `NMPhotoDrawer.DateFromPath(path: String) -> String`, test `photo.date_from_path`:
  `DateFromPath("C:\\...\\photomode_28102026_110520.png") == "28 OCT 2026 · 11:05"`, and `""` for a name that
  does not match.

- [ ] **Step 1: Write failing tests:**
  - `photo.shift_target`: `ShiftTarget(true, 1600.0) == 400.0`, `ShiftTarget(false, 1600.0) == 0.0`.
  - `photo.shift_ease`: `EaseShift(0, 400, 75)` is between 150 and 250; `EaseShift(0, 400, 150) == 400`;
    `EaseShift(400, 0, 1000) == 0`.
  - `photo.pick_shifted`: `NMCrosshair.Pick` with a candidate at (100,100) and centre `(500 - 400, 100)` picks it.
  - `photo.drawer_stops_follow`: with `camera.follow = true`, opening the drawer on a photo selection (test seam
    `OpenDrawerForTest()`) leaves `camera.follow == false`.
- [ ] **Step 2: Compile** → fails on missing `NMPhotoDrawer`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Compile** → `COMPILE OK`; install (game closed).
- [ ] **Step 5: Checkpoint A (user, in game):** Ctrl + ' self-tests (all `photo.*` pass); spec §9 steps 1–3, 6, 7, 8.
- [ ] **Step 6: Commit** `feat(photos): preview drawer with focus shift`.

### Task 6: Teleport to a photo spot

**Files:**
- Create: `r6/scripts/NightMap/Photos/PhotoTeleport.reds`
- Modify: `r6/scripts/NightMap/Core/NightMapSystem.reds` (`StartFastTravel` → `OnTeleportKey`: photo selection →
  photo teleport, else fast travel), `r6/scripts/NightMap/Core/Input.reds` (`HintText(s, view, actLabel: String)`)
- Test: `r6/scripts/NightMap/Debug/SelfTestPhotos.reds`, `r6/scripts/NightMap/Debug/SelfTestFastTravel.reds`
  (update the two hint tests to the new signature)

**Interfaces:**
- Consumes: Task 4 `NMPhotos.SpotOf`; Task 1 §10 (hold needed or not).
- Produces: `NMPhotoTeleport.Refusal(isPhoto: Bool, inVehicle: Bool, playerReady: Bool) -> String` (`""`,
  `"not ready"`, `"not a photo"`, `"in vehicle"`, checked in that order); `NMPhotoTeleport.Go(gi, player, spot)`.
- Behaviour: on success log `photo|teleport|start|<hash>`, close the map, then `Teleport(player, pos, yaw)`. The
  hint label is `"TELEPORT"` on a photo pin, `"FAST TRAVEL"` otherwise. (§10: V did not fall, so the hold below
  is **not** built.) ~~If §10 says V fell:~~ `Go` also applies
  `BaseStatusEffect.Invulnerable`, then re-teleports V to the spot every frame until a `Static`+`Terrain` ray finds
  ground within 2 m below the spot or 5 s pass (timeout → back to start), then removes the effect; add the test
  `photo.hold_lands` with fake mover/ground seams as in the removed `TeleportDriver` (commit `465d684`).

- [ ] **Step 1: Write failing tests:** `photo.tp_ok` (`Refusal(true,false,true) == ""`), `photo.tp_vehicle`
  (`"in vehicle"`), `photo.tp_not_photo`, `photo.tp_not_ready_first` (`Refusal(false,true,false) == "not ready"`),
  `photo.hint_teleport` (`StrContains(HintText(s, "ALL", "TELEPORT"), "TELEPORT")`), and keep
  `ft.hint_on/off` passing with `"FAST TRAVEL"`.
- [ ] **Step 2: Compile** → fails.
- [ ] **Step 3: Implement** (with the hold only if §10 requires it).
- [ ] **Step 4: Compile** → `COMPILE OK`; install.
- [ ] **Step 5: Checkpoint B (user, in game):** spec §9 steps 4–5, plus fast travel still works on foot.
- [ ] **Step 6: Commit** `feat(photos): teleport to a photo spot`.

### Task 7: Perf, cleanup and docs

**Files:**
- Delete: `r6/scripts/NightMap/Debug/PhotoProbe.reds`
- Modify: `r6/scripts/NightMap/Debug/PerfSuite.reds` (row `photos_500`: seed 500 spots spread over the city via the
  test seam, sweep as `open_empty`), `tools/results.py` + `tools/test_results.py` (gate `photos_500` with the
  `open_empty` budgets; skipped, not failed, when absent)
- Modify: `README.md`, `notes/CHECKPOINTS.md`, spec status line
- [ ] **Step 1: Write failing pytest** `test_photos_500_gated` and `test_photos_500_missing_is_skipped`.
- [ ] **Step 2: Run** `python -m pytest tools -q` → the 2 new tests fail.
- [ ] **Step 3: Implement** the row and the gate; if §10 says RedIMG is not kept, replace the gate by the manual
  FPS-overlay check from spec §7 and say so in `CHECKPOINTS.md` instead.
- [ ] **Step 4: Run** `python -m pytest tools -q` and `tools/check.sh` → all pass, `COMPILE OK`.
- [ ] **Step 5: Checkpoint C (user):** three Shift + ' perf runs (if RedIMG kept).
- [ ] **Step 6: Docs and commit** `docs(photos): readme, checkpoints, spec status`.
