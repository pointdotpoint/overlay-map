# Developing Overlay Map

Player documentation is in the [README](../README.md).

- Spec: docs/superpowers/specs/2026-10-11-overlaymap-core-design.md
- Plan: docs/superpowers/plans/2026-10-11-overlaymap-core.md
- Map layer (sub-project 1b): docs/superpowers/specs/2026-10-12-overlaymap-vector-layer-design.md §11
- Layer API for other mods: docs/api.md

Every optional mod is detected with `@if(ModuleExists(...))`, so Overlay Map compiles and runs without it.

The waypoint plugin (`OverlayMapNative`) finds the game's own tracking function at runtime, checks its bytes, and
switches the feature off on a game build where it can't find it. It is built against a RED4ext.SDK with game 2.5
support (`native/vendor/RED4ext.SDK`).

## Tools

To build tiles: WolvenKit CLI (the build runs the executable named by `OVERLAYMAP_WOLVENKIT`, default `WolvenKit.CLI`),
Wine + `texconv.exe`, Python 3 with numpy, Pillow, scipy and shapely. The waypoint plugin cross-compiles with mingw-w64,
CMake and Ninja.

## Build & install

    cd tools/tiles && python3 -m nmtiles.build --game ~/cyberpunk_symlink   # tiles + UI atlas -> archive + manifest
    # WolvenKit.CLI 8.19 cannot read the LOD-3 EP1 sectors of game 2.31+ (0-byte JSON). Use WolvenKit 10:
    OVERLAYMAP_WOLVENKIT=~/.local/share/overlaymap-tools/wk10 python3 -m nmtiles.build --game ~/cyberpunk_symlink
    tools/check.sh                                                          # offline redscript compile
    tools/install.sh                                                        # copy into the game (game closed)
    python3 tools/collectibles/gen.py --scan ~/.cache/overlaymap-sectors/scan --dump <run>/dump-1/channel/lootdump.txt

The tile build stamps the game version it was built from (`--game-version`, default 2.5) into the manifest; the panel
warns players whose game reports another major.minor.

Area names come from the game's world sectors (area outlines) plus hand-made outlines in `tools/areas/custom_areas.json`:

    python3 tools/areas/scan.py    # outlines -> ~/.cache/nightmap-sectors/areas/outlines.json (WolvenKit 10)
    python3 tools/areas/gen.py     # -> r6/scripts/OverlayMap/Generated/AreaData.reds; --preview PNG draws them

UI atlas only (new icons): `cd tools/tiles && python3 -m nmtiles.build --ui-only`.

Installing over the old NightMap install (`tools/install.sh`) removes it and keeps its Mod Settings values and photo pins.

## Release

    tools/native/build.sh          # stripped waypoint plugin -> dist-native/
    python3 tools/package.py       # -> dist/OverlayMap-<VERSION>.zip

The zip mirrors the game folder (`archive/`, `r6/scripts/`, `red4ext/plugins/`). It is refused when the tile archive is
missing or the plugin still carries debug info. Bump `VERSION` for each release.

## Debug tools

With Debug on (Mod Settings → Overlay Map → Debug tools), chords on the toggle key: Ctrl = self-test, Shift = perf suite
(`python3 tools/results.py`), Alt = calibration dump (`cd tools/tiles && python3 -m nmtiles.calib`), Ctrl+Shift = debug
layer.

A corner minimap that replaces the game's own is shelved for now: its code is still in `r6/scripts/OverlayMap/Corner/`
but it is switched off (`NMCornerHost.Shelved`) and its settings are hidden.

## Automated testing

`tools/soak` drives the real game headless in gamescope: it stages a build, backs up the install, saves and settings,
loads a save, follows a plan in `tools/soak/plans`, and restores everything. The game must be closed: if it is open,
preflight waits 30 s, then stops the campaign and leaves the game running (a campaign only kills a game it launched).
Steam's launch options need `~/photomode_ui_improvements/scripts/soak/gamescope-wrap.sh` before `%command%`; normal
launches pass through it. Without the wrapper, campaigns run in desktop mode (`--desktop`), where keys reach the game
through a virtual keyboard, mouse and pad (`tools/soak/kbm.py`, `tools/soak/pad.py`).

    python3 tools/soak/soak.py preflight --save QuickSave-7 --allow-cloud
    python3 tools/soak/soak.py campaign tools/soak/plans/regression.json --save QuickSave-7 --allow-cloud

Results land in `.soak/results/<campaign>/report.md`. `tools/check.sh --soak` compiles with the harness's hooks.
