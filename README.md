# NightMap

Hologram-style 2D world map overlay for Cyberpunk 2077 (redscript + Codeware). Opens on `'` alongside the vanilla map.

- Spec: docs/superpowers/specs/2026-10-11-nightmap-core-design.md
- Plan: docs/superpowers/plans/2026-10-11-nightmap-core.md
- Map layer (sub-project 1b): docs/superpowers/specs/2026-10-12-nightmap-vector-layer-design.md §11

## Requirements
- Cyberpunk 2077 2.31 or later (tiles are built for 2.31; a different major.minor shows a warning in the panel). The
  waypoint plugin is tested on 2.5.
- redscript and Codeware (required)
- RED4ext (required by Codeware). NightMap also ships an optional RED4ext plugin, `NightMapNative`, for setting
  waypoints (see Using it). Without it everything else works; the plugin finds the game's own tracking function at
  runtime, checks its bytes, and switches the feature off on a game build where it can't find it.
- Mod Settings (optional): settings menu and key rebinding; without it the defaults apply
- RedFileSystem (optional): stores photo-pin spots in NightMap's own `photos.txt`; without it photo pins aren't kept
- RedIMGRetriever (optional): photo thumbnails (image items)

Every optional mod is detected with `@if(ModuleExists(...))`, so NightMap compiles and runs without it.

To build tiles: WolvenKit CLI (the build runs the executable named by `NIGHTMAP_WOLVENKIT`, default `WolvenKit.CLI`), Wine + `texconv.exe`, Python 3 with numpy, Pillow, scipy and shapely.

## Build & install
    cd tools/tiles && python3 -m nmtiles.build --game ~/cyberpunk_symlink   # tiles + UI atlas -> archive + manifest
    # WolvenKit.CLI 8.19 cannot read the LOD-3 EP1 sectors of game 2.31+ (0-byte JSON). Use WolvenKit 10:
    NIGHTMAP_WOLVENKIT=~/.local/share/nightmap-tools/wk10 python3 -m nmtiles.build --game ~/cyberpunk_symlink
    tools/check.sh                                                          # offline redscript compile
    tools/native/build.sh                                                   # optional plugin -> dist-native/ (mingw-w64)
    tools/native/test.sh                                                    # host tests for the plugin's byte matchers
    tools/install.sh                                                        # check + copy into the game (plugin too)

Install only while the game is closed. If the archive is replaced while the game runs, every resource load fails until
a restart.

The map is drawn from the game's own minimap geometry:
- The build decodes the `minimapEncodedShapes` embedded in the `exterior_*` streaming sectors. EP1 copies replace the
  base ones.
- It classifies roads, then merges buildings into clean footprints.
- It bakes five colourless mask tile sets: `road_minor`, `road_major` (wide arterials, and short pieces bridging them),
  `bfill` (building fill with a baked dot matrix), `glow` (from road rims) and `outline`. Each has six levels from
  0.5 to 16 m/px, as BC7 512 px tiles.
- Scripts and the archive must be installed together: scripts that expect five sets over an older four-set archive
  draw no roads.
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
- Controller: hold View for half a second to open the map (a tap still does what it does in the game). While it is open the map takes the controller, so V stops: left stick pans, LT/RT zoom, A acts, RB sets a waypoint, X teleports, Y cycles the filter, R3 follows V, B (or View) closes. In a car the car coasts meanwhile. A map opened with the keyboard ignores the controller, so you can drive with a pad and use the numpad map. Mod Settings → NightMap → Controller → Open map button (Hold View / Off).
- Zoom crossfades between six baked levels, from 0.5 m/px (single buildings) to 16 m/px (the whole city).
- The game's own map markers (quests, gigs, NCPD, vendors, fast travel, …) appear with their vanilla icons, each on a dark plate ringed in its own colour. Move the map so a marker is nearest the centre to see its details card in the sidebar; `Numpad 0` tracks its quest, or clears your vanilla waypoint.
- `Enter` (controller: RB) sets waypoints, like right-clicking on the vanilla map. On an empty spot it places the
  game's own custom waypoint there, with its GPS route. On a job or gig it makes that quest the active one. On any other
  marker (vendor, fast travel, drop point, …) it tracks that marker. On photo or collectible pins it places the
  waypoint at the pin. On what is already tracked it clears it. There is one custom waypoint, as in vanilla: setting
  another moves it. The game reads Numpad Enter and the main Enter as one key, so both work; rebind it in Mod Settings.
  Everything but tracking a quest needs the `NightMapNative` plugin; without it Enter only tracks quests, and the hint
  shows only where Enter does something.
- `Numpad /` cycles the markers shown: All → Jobs (quests, gigs, psycho) → Services (ripperdoc, vendors, autofixer, drop points, fast travel, your property), like the vanilla quick lists; NCPD scanner and apartments to rent show only in All. A filter keeps its categories visible as long as quests and fast travel when zooming out.
- There is no clustering. Markers shrink and fade out by tier as the map zooms out: minor ones (gigs, vendors, NCPD, collectibles, photo pins) first, quests and fast travel last, the tracked quest and V never. Markers never overlap: where two would, the more important one is drawn, and the district title and scale bar stay clear. Mod Settings → NightMap → Map filters turns each vanilla category on or off.
- NCART lines (Map filters → NCART lines, off by default) draws the five metro lines over the map in their NCART colours (A red, B yellow, C cyan, D green, E orange), on the real track positions from the game's 3D map. Where lines share track they run side by side, like the NCART diagram; short connectors join the line to station markers that sit off the track. The lines keep their colours in every theme.
- The district title sits top left (with the active filter under it) and the scale bar top right. The sidebar's bottom shows the tracked quest and its current objective.
- The map background is half see-through by default (Display → Panel opacity, 0.5); installs still on the old 0.45 default move to 0.5 once.
- Display → Map marker size scales the open map's markers; the default is half the original size (0.5).
- Glow strength (Display, 0 to 3, default 1.5; 0 turns it off) makes the roads glow, with or without Hologram effects, so a plain background can still glow. The glow layer is blurred by the engine so bright roads bloom.
- VHS look on the open map (Display, all need Hologram effects): Scanline strength (0 to 0.6, default 0.3), VHS tracking band (a noisy band rolls down the map every 11 s) and VHS glitch (two short engine glitch bursts every 6.5 s). Each applies on the next open.
- GPS routes: the route to your vanilla waypoint (white) and to the tracked quest (yellow, teal for gigs) are mirrored from the minimap as flowing dots. Mod Settings → NightMap → Display → GPS routes.
- The game's HUD fades out while the map is open (Display → Hide HUD while open).
- Numpad . on any spot teleports V there: onto the roof or ground below, or into the water. On a fast travel marker it fast-travels, on a photo pin it goes to the photo's spot, and V's car comes along. Long jumps show the game's loading screen for a few seconds first.
- Collectibles: every shard, tarot graffiti, iconic weapon, legendary cyberware and clothing, and skill shard placed in the world has its own pin (All view only). Collected ones stay on the map, scratched out and faded. Shards and tarot follow your journal; items count once they have been in V's inventory (the list is saved with the game; an item sold before this version doesn't count). Teleporting to a pin lands on the spot. Mod Settings → NightMap → Collectibles turns each category on or off, and hides collected ones.
- Display → Hold key to show keeps the map up only while `'` is held, instead of pressing to open and again to close.
- `Numpad .` on a selected fast travel marker fast travels there with the game's own fast travel (arrival at the dataterm, the game's own locks during some quests or combat). On foot only; your vehicle stays behind. Display → Fast travel key.
- Mods can add their own items through the layer API.

### Colours
- Themes: Display → Hologram colour picks a prebuilt theme: Cyan (default), Green, Red, Purple or Amber. Each tints the tiles, overlays, frame, sidebar, hint bar and header text.
- Display → Follow HUD Painter colours (off by default) takes every NightMap colour from the game's HUD palette, so a [HUD Painter](https://www.nexusmods.com/cyberpunk2077/mods/14935) preset recolours the map. Off keeps NightMap's own colours. NightMap has no per-colour settings of its own; HUD Painter is optional.
- Display → Map size sets the size of the map panel.

A corner minimap that replaces the game's own is shelved for now: its code is still in `r6/scripts/NightMap/Corner/` but it is switched off (`NMCornerHost.Shelved`) and its settings are hidden.

### Debug tools
With Debug on (Mod Settings → NightMap → Debug tools), chords on the toggle key: Ctrl = self-test, Shift = perf suite (`python3 tools/results.py`), Alt = calibration dump (`cd tools/tiles && python3 -m nmtiles.calib`), Ctrl+Shift = debug layer.

## For mod authors
See docs/api.md.

## Zoom

The map zooms in to 0.1 m per pixel, 5x past the finest tiles, so roads and buildings get softer below the 100 M scale.
Photo pins grow with the zoom past that point, up to 5x, and the first open of a session stays at 0.5 m per pixel.

## Automated testing

`tools/soak` drives the real game headless in gamescope: it stages a build, backs up the install, saves and settings,
loads a save, follows a plan in `tools/soak/plans`, and restores everything. The game must be closed: if it is open,
preflight waits 30 s, then stops the campaign and leaves the game running (a campaign only kills a game it launched). Steam's launch
options need `~/photomode_ui_improvements/scripts/soak/gamescope-wrap.sh` before `%command%`; normal launches pass through it.

    python3 tools/soak/soak.py preflight --save QuickSave-7 --allow-cloud
    python3 tools/soak/soak.py campaign tools/soak/plans/regression.json --save QuickSave-7 --allow-cloud

Results land in `.soak/results/<campaign>/report.md`. `tools/check.sh --soak` compiles with the harness's hooks.
