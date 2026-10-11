# NightMap

Hologram-style 2D world map overlay for Cyberpunk 2077 (redscript + Codeware). Opens on `\` alongside the vanilla map.

- Spec: docs/superpowers/specs/2026-10-11-nightmap-core-design.md
- Plan: docs/superpowers/plans/2026-10-11-nightmap-core.md

## Build & install
    cd tools/tiles && python3 -m nmtiles.build --game ~/cyberpunk_symlink   # tiles + UI atlas -> archive + manifest
    tools/check.sh                                                          # offline redscript compile
    tools/install.sh                                                        # check + copy into the game
