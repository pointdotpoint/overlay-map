# NightMap

Hologram-style 2D world map overlay for Cyberpunk 2077 (redscript + Codeware). Opens on `'` alongside the vanilla map.

- Spec: docs/superpowers/specs/2026-10-11-nightmap-core-design.md
- Plan: docs/superpowers/plans/2026-10-11-nightmap-core.md
- Map layer (sub-project 1b): docs/superpowers/specs/2026-10-12-nightmap-vector-layer-design.md §11

## Requirements
- Cyberpunk 2077 2.31 (tiles are built for it; a different major.minor shows a warning in the panel)
- redscript and Codeware (required)
- Mod Settings (optional): keybinds and settings
- RedIMGRetriever (optional): image items

To build tiles: WolvenKit.CLI, Wine + `texconv.exe`, Python 3 with numpy, Pillow, scipy and shapely.

## Build & install
    cd tools/tiles && python3 -m nmtiles.build --game ~/cyberpunk_symlink   # tiles + UI atlas -> archive + manifest
    tools/check.sh                                                          # offline redscript compile
    tools/install.sh                                                        # check + copy into the game

Install only while the game is closed. If the archive is replaced while the game runs, every resource load fails until
a restart.

The map is drawn from the game's own minimap geometry:
- The build decodes the `minimapEncodedShapes` embedded in the `exterior_*` streaming sectors. EP1 copies replace the
  base ones.
- It classifies roads, then merges buildings into clean footprints.
- It bakes four colourless mask tile sets: `road`, `bfill`, `glow` and `outline`. Each has six levels from 0.5 to
  16 m/px, as BC7 512 px tiles.
- At runtime each set is tinted from `NMTheme` (`TileTint` / `TileOpacity`), so themes recolour the map without a
  rebuild.

Build options and caches:
- Decoded sectors and footprints are cached in `tools/tiles/build/`, and encoded tiles are cached by content hash.
  Rebuilds only redo what changed.
- `--jobs N` caps the worker processes (default 4; BC7 encoding uses at most 2). Everything runs at low priority.
- Previews are written to `tools/tiles/build/preview_minimap_{close,mid,far}.png`.
- Calibration lives in `tools/tiles/calibration.json`.

Collectible spots come from the game's own files (never from a fan map), regenerated after a game patch:
    python3 tools/collectibles/scan.py --wolvenkit <WolvenKit 10 CLI> --dotnet <.NET 10 runtime>   # world sectors
    python3 tools/soak/soak.py campaign tools/soak/plans/lootdump.json --save <save>              # item records
    python3 tools/collectibles/gen.py --scan ~/.cache/nightmap-sectors/scan --dump <run>/dump-1/channel/lootdump.txt
UI atlas only (new icons): `cd tools/tiles && python3 -m nmtiles.build --ui-only`.

## Using it
- `'` open/close · Numpad 8/4/6/2 (7/9/1/3) pan · Numpad +/- zoom · Numpad 5 follow V · Numpad 0 act. Every key can be rebound in Mod Settings → NightMap.
- Arrow keys are never used (they steer vehicles). Keep NumLock on.
- Zoom crossfades between six baked levels, from 0.5 m/px (single buildings) to 16 m/px (the whole city).
- The game's own map markers (quests, gigs, NCPD, vendors, fast travel, …) appear with their vanilla icons. Move the map so a marker is nearest the centre to see its tooltip; `Numpad 0` tracks its quest, or clears your vanilla waypoint. Setting new waypoints comes with the optional native plugin (later).
- `Numpad /` cycles the markers shown: All → Jobs (quests, gigs, psycho) → Services (ripperdoc, vendors, autofixer, drop points, fast travel, your property), like the vanilla quick lists; NCPD scanner and apartments to rent show only in All. Mod Settings → NightMap → Map filters turns each vanilla category on or off.
- The header (bottom right) shows the tracked quest and its current objective.
- GPS routes: the route to your vanilla waypoint (white) and to the tracked quest (yellow, teal for gigs) are mirrored from the minimap as flowing dots. Mod Settings → NightMap → Display → GPS routes.
- The game's HUD fades out while the map is open (Display → Hide HUD while open).
- Numpad . on any spot teleports V there: onto the roof or ground below, or into the water. On a fast travel marker it fast-travels, on a photo pin it goes to the photo's spot, and V's car comes along. Long jumps show the game's loading screen for a few seconds first.
- Collectibles: every shard, tarot graffiti, iconic weapon, legendary cyberware and clothing, and skill shard placed in the world has its own pin (All view only). Collected ones stay on the map, scratched out and faded. Shards and tarot follow your journal; items count once they have been in V's inventory (the list is saved with the game; an item sold before this version doesn't count). Teleporting to a pin lands on the spot. Mod Settings → NightMap → Collectibles turns each category on or off, and hides collected ones.
- Display → Hold key to show keeps the map up only while `'` is held, instead of pressing to open and again to close.
- `Numpad .` on a selected fast travel marker fast travels there with the game's own fast travel (arrival at the dataterm, the game's own locks during some quests or combat). On foot only; your vehicle stays behind. Display → Fast travel key.
- Mods can add their own items through the layer API.

### Debug tools
With Debug on (Mod Settings → NightMap → Debug tools), chords on the toggle key: Ctrl = self-test, Shift = perf suite (`python3 tools/results.py`), Alt = calibration dump (`cd tools/tiles && python3 -m nmtiles.calib`), Ctrl+Shift = debug layer.

## For mod authors
See docs/api.md.

## Zoom

The map zooms in to 0.1 m per pixel, 5x past the finest tiles, so roads and buildings get softer below the 100 M scale.
Photo pins grow with the zoom past that point, up to 5x, and the first open of a session stays at 0.5 m per pixel.

## Automated testing

`tools/soak` drives the real game headless in gamescope: it stages a build, backs up the install, saves and settings,
loads a save, follows a plan in `tools/soak/plans`, and restores everything. The game must be closed. Steam's launch
options need `~/photomode_ui_improvements/scripts/soak/gamescope-wrap.sh` before `%command%`; normal launches pass through it.

    python3 tools/soak/soak.py preflight --save QuickSave-7 --allow-cloud
    python3 tools/soak/soak.py campaign tools/soak/plans/regression.json --save QuickSave-7 --allow-cloud

Results land in `.soak/results/<campaign>/report.md`. `tools/check.sh --soak` compiles with the harness's hooks.
