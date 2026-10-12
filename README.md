# NightMap

Hologram-style 2D world map overlay for Cyberpunk 2077 (redscript + Codeware). Opens on `'` alongside the vanilla map.

- Spec: docs/superpowers/specs/2026-10-11-nightmap-core-design.md
- Plan: docs/superpowers/plans/2026-10-11-nightmap-core.md

## Requirements
- Cyberpunk 2077 2.31 (tiles are built for it; a different major.minor shows a warning in the panel)
- redscript and Codeware (required)
- Mod Settings (optional): keybinds and settings
- RedIMGRetriever (optional): image items

To build tiles: WolvenKit.CLI, Wine + `texconv.exe`, Python 3 with numpy, Pillow and scipy.

## Build & install
    cd tools/tiles && python3 -m nmtiles.build --game ~/cyberpunk_symlink   # tiles + UI atlas -> archive + manifest
    tools/check.sh                                                          # offline redscript compile
    tools/install.sh                                                        # check + copy into the game

The tile build also extracts the vanilla 3D-map building boxes; calibration lives in `tools/tiles/calibration.json`.

## Using it
- `'` open/close · Numpad 8/4/6/2 (7/9/1/3) pan · Numpad +/- zoom · Numpad 5 follow V · Numpad 0 act. Every key can be rebound in Mod Settings → NightMap.
- Arrow keys are never used (they steer vehicles). Keep NumLock on.

### Debug tools
With Debug on (Mod Settings → NightMap → Debug tools), chords on the toggle key: Ctrl = self-test, Shift = perf suite (`python3 tools/results.py`), Alt = calibration dump (`cd tools/tiles && python3 -m nmtiles.calib`), Ctrl+Shift = debug layer.

## For mod authors
See docs/api.md.
