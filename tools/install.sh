#!/usr/bin/env bash
# Copy OverlayMap into the game, or remove it with --uninstall.
set -euo pipefail
GAME="${GAME:-$HOME/cyberpunk_symlink}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$GAME/r6/scripts/OverlayMap"
ARCH="$GAME/archive/pc/mod/OverlayMap.archive"

# Replacing the archive under a running game makes every OverlayMap resource load fail until a restart.
# Match the program (argv[0]) only: a shell whose command line merely mentions the name is not the game.
if ps -eo args | awk '{print $1}' | grep -qiE '(^|[\\/])Cyberpunk2077\.exe$'; then
  echo "Cyberpunk 2077 is running: close the game, then install." >&2; exit 1
fi

# A soak campaign (tools/soak) holds this lock while its build is installed: installing now would break that run.
LOCK="$GAME/.pmui-deploy.lock"
if [ -e "$LOCK" ] && ! flock -n "$LOCK" true; then
  echo "game folder locked by: $(cat "$LOCK.owner" 2>/dev/null || echo unknown holder)" >&2; exit 1
fi

PLUGIN="$GAME/red4ext/plugins/OverlayMapNative"
if [ "${1:-}" = "--uninstall" ]; then
  rm -rf "$DEST" "$ARCH" "$PLUGIN"; echo "removed $DEST, $ARCH and $PLUGIN"; exit 0
fi
# Optional native plugin (waypoints), decided before anything in the game folder changes. A failed build only skips the
# plugin: OverlayMap works without it.
WITH_PLUGIN=0
if [ -d "$GAME/red4ext" ]; then
  if "$HERE/tools/native/build.sh" && "$HERE/tools/check.sh" --native; then
    WITH_PLUGIN=1
  else
    echo "WARNING: waypoint plugin not built (see above): installing OverlayMap without it" >&2
  fi
else
  echo "NOTE: RED4ext not installed: skipped the waypoint plugin (OverlayMap works without it)"
fi
"$HERE/tools/check.sh"

# The mod used to be called NightMap. Remove that install (both copies would run side by side) and carry over the
# player's Mod Settings values and photo pins, so the rename loses nothing. Each step runs once: it skips when the old
# files are gone or the new ones already exist.
OLD="Night""Map"     # split so a project-wide rename never rewrites it
rm -rf "$GAME/r6/scripts/$OLD" "$GAME/archive/pc/mod/$OLD.archive" "$GAME/red4ext/plugins/${OLD}Native"
INI="$GAME/red4ext/plugins/mod_settings/user.ini"
if [ -f "$INI" ] && grep -q "^\[$OLD\.${OLD}Settings\]" "$INI" && ! grep -q '^\[OverlayMap\.OverlayMapSettings\]' "$INI"; then
  cp "$INI" "$INI.before-overlaymap"
  sed -i "s/^\[$OLD\.${OLD}Settings\]/[OverlayMap.OverlayMapSettings]/" "$INI"
  echo "carried over the Mod Settings values (backup: $INI.before-overlaymap)"
fi
if [ -d "$GAME/r6/storages/$OLD" ] && [ ! -e "$GAME/r6/storages/OverlayMap" ]; then
  mv "$GAME/r6/storages/$OLD" "$GAME/r6/storages/OverlayMap"
  echo "carried over the photo pins"
fi

rm -rf "$DEST"; cp -r "$HERE/r6/scripts/OverlayMap" "$DEST"
if [ "$WITH_PLUGIN" = 1 ]; then
  rm -rf "$PLUGIN"; cp -r "$HERE/dist-native/red4ext/plugins/OverlayMapNative" "$PLUGIN"
  echo "installed plugin -> $PLUGIN"
elif [ -d "$PLUGIN" ]; then
  rm -rf "$PLUGIN"; echo "removed the previous plugin (it may not match these scripts)"
fi
if [ -f "$HERE/archive/pc/mod/OverlayMap.archive" ]; then
  mkdir -p "$(dirname "$ARCH")"
  cmp -s "$HERE/archive/pc/mod/OverlayMap.archive" "$ARCH" || cp "$HERE/archive/pc/mod/OverlayMap.archive" "$ARCH"
  echo "installed archive -> $ARCH"
else
  echo "WARNING: no archive built yet (run tools/tiles build); map will show the fallback grid"
fi
echo "installed scripts -> $DEST (restart the game to compile)"
