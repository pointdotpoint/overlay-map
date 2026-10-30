#!/usr/bin/env bash
# Copy NightMap into the game, or remove it with --uninstall.
set -euo pipefail
GAME="${GAME:-$HOME/cyberpunk_symlink}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$GAME/r6/scripts/NightMap"
ARCH="$GAME/archive/pc/mod/NightMap.archive"

# Replacing the archive under a running game makes every NightMap resource load fail until a restart.
if ps -eo args | grep -qi "[C]yberpunk2077.exe"; then
  echo "Cyberpunk 2077 is running: close the game, then install." >&2; exit 1
fi

# A soak campaign (tools/soak) holds this lock while its build is installed: installing now would break that run.
LOCK="$GAME/.pmui-deploy.lock"
if [ -e "$LOCK" ] && ! flock -n "$LOCK" true; then
  echo "game folder locked by: $(cat "$LOCK.owner" 2>/dev/null || echo unknown holder)" >&2; exit 1
fi

if [ "${1:-}" = "--uninstall" ]; then
  rm -rf "$DEST" "$ARCH"; echo "removed $DEST and $ARCH"; exit 0
fi
"$HERE/tools/check.sh"
rm -rf "$DEST"; cp -r "$HERE/r6/scripts/NightMap" "$DEST"
if [ -f "$HERE/archive/pc/mod/NightMap.archive" ]; then
  mkdir -p "$(dirname "$ARCH")"
  cmp -s "$HERE/archive/pc/mod/NightMap.archive" "$ARCH" || cp "$HERE/archive/pc/mod/NightMap.archive" "$ARCH"
  echo "installed archive -> $ARCH"
else
  echo "WARNING: no archive built yet (run tools/tiles build); map will show the fallback grid"
fi
echo "installed scripts -> $DEST (restart the game to compile)"
