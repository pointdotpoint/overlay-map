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

## Using it
- `'` open/close · Numpad 8/4/6/2 (7/9/1/3) pan · Numpad +/- zoom · Numpad 5 follow V · Numpad 0 act. Every key can be rebound in Mod Settings → NightMap.
- Arrow keys are never used (they steer vehicles). Keep NumLock on.
- Zoom crossfades between six baked levels, from 0.5 m/px (single buildings) to 16 m/px (the whole city).
- The game's own map markers (quests, gigs, NCPD, vendors, fast travel, …) appear with their vanilla icons. Crosshair a marker for details; `Numpad 0` tracks its quest, or clears your vanilla waypoint. Setting new waypoints comes with the optional native plugin (later).
- `Numpad /` cycles the markers shown: All → Jobs (quests, gigs, psycho) → Services (ripperdoc, vendors, autofixer, drop points, fast travel, your property), like the vanilla quick lists; NCPD scanner and apartments to rent show only in All. Mod Settings → NightMap → Map filters turns each vanilla category on or off.
- The header shows the tracked quest and its current objective.
- Mods can add their own items through the layer API.

### Debug tools
With Debug on (Mod Settings → NightMap → Debug tools), chords on the toggle key: Ctrl = self-test, Shift = perf suite (`python3 tools/results.py`), Alt = calibration dump (`cd tools/tiles && python3 -m nmtiles.calib`), Ctrl+Shift = debug layer.

## For mod authors
See docs/api.md.
