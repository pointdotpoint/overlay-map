#!/usr/bin/env bash
# Copy NightMap into the game, or remove it with --uninstall.
set -euo pipefail
GAME="${GAME:-$HOME/cyberpunk_symlink}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$GAME/r6/scripts/NightMap"
ARCH="$GAME/archive/pc/mod/NightMap.archive"

if [ "${1:-}" = "--uninstall" ]; then
  rm -rf "$DEST" "$ARCH"; echo "removed $DEST and $ARCH"; exit 0
fi
"$HERE/tools/check.sh"
rm -rf "$DEST"; cp -r "$HERE/r6/scripts/NightMap" "$DEST"
if [ -f "$HERE/archive/pc/mod/NightMap.archive" ]; then
  mkdir -p "$(dirname "$ARCH")"; cp "$HERE/archive/pc/mod/NightMap.archive" "$ARCH"
  echo "installed archive -> $ARCH"
else
  echo "WARNING: no archive built yet (run tools/tiles build); map will show the fallback grid"
fi
echo "installed scripts -> $DEST (restart the game to compile)"
