#!/usr/bin/env bash
# Compile-check OverlayMap offline with the game's own redscript compiler under Wine.
# Sandbox copy of scc + vanilla final.redscripts; the game install is never touched.
set -euo pipefail

GAME="${GAME:-$HOME/cyberpunk_symlink}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SANDBOX="${SANDBOX:-$HERE/.scratch/nightmap-scc}"

rm -rf "$SANDBOX"
mkdir -p "$SANDBOX/engine/tools" "$SANDBOX/r6/cache" "$SANDBOX/r6/scripts"/{Codeware,RedIMGRetriever,ModSettings}
cp "$GAME/engine/tools/scc.exe" "$GAME/engine/tools/scc_lib.dll" "$SANDBOX/engine/tools/"
cp "$GAME/r6/cache/final.redscripts" "$SANDBOX/r6/cache/"
cp "$GAME"/red4ext/plugins/Codeware/Scripts/*.reds "$SANDBOX/r6/scripts/Codeware/"
# RedIMGRetriever is optional; OverlayMap compiles either way through @if(ModuleExists).
if [ -d "$GAME/r6/scripts/RedIMGRetriever" ]; then
  cp "$GAME"/r6/scripts/RedIMGRetriever/*.reds "$SANDBOX/r6/scripts/RedIMGRetriever/"
fi
cp "$GAME"/red4ext/plugins/mod_settings/*.reds "$SANDBOX/r6/scripts/ModSettings/"
# RedFileSystem is optional (photo spot storage); OverlayMap compiles either way through @if(ModuleExists).
if [ -d "$GAME/r6/scripts/RedFileSystem" ]; then
  mkdir -p "$SANDBOX/r6/scripts/RedFileSystem"
  cp "$GAME"/r6/scripts/RedFileSystem/*.reds "$SANDBOX/r6/scripts/RedFileSystem/"
fi
# TweakXL adds GetRecords, used only by the harness's spike commands.
if [ -d "$GAME/red4ext/plugins/TweakXL/Scripts" ]; then
  mkdir -p "$SANDBOX/r6/scripts/TweakXL"
  cp "$GAME"/red4ext/plugins/TweakXL/Scripts/*.reds "$SANDBOX/r6/scripts/TweakXL/"
fi
cp -r "$HERE/r6/scripts/OverlayMap" "$SANDBOX/r6/scripts/OverlayMap"
# --native: also compile against the optional OverlayMapNative plugin's declarations (tools/native/build.sh stages them).
NATIVE=0; SOAK=0
for arg in "$@"; do
  case "$arg" in --native) NATIVE=1 ;; --soak) SOAK=1 ;; esac
done
if [ "$NATIVE" = 1 ]; then
  mkdir -p "$SANDBOX/r6/scripts/OverlayMapNative"
  cp "$HERE"/native/OverlayMapNative/*.reds "$SANDBOX/r6/scripts/OverlayMapNative/"
fi
# --soak: also compile the harness's bootstrap and hooks, which only exist in a campaign build.
if [ "$SOAK" = 1 ]; then
  cp "$HERE/tools/soak/autopilot/SoakHooks.reds" "$SANDBOX/r6/scripts/OverlayMap/Debug/"
  cp "$HERE/tools/soak/autopilot/MinimapSpike.reds" "$SANDBOX/r6/scripts/OverlayMap/Debug/"
  python3 "$HERE/tools/soak/builds.py" "$SANDBOX/r6/scripts/OverlayMap" "$HERE/tools/soak/autopilot"
  mkdir -p "$SANDBOX/r6/scripts/SoakBootstrap"
  cp "$HERE"/tools/soak/bootstrap/*.reds "$SANDBOX/r6/scripts/SoakBootstrap/"
  echo 'module SoakBootstrap' > "$SANDBOX/r6/scripts/SoakBootstrap/SoakBuild.reds"
  echo 'public func Soak_BuildId() -> String = "check"' >> "$SANDBOX/r6/scripts/SoakBootstrap/SoakBuild.reds"
fi

# scc only scans the scripts dir reliably when given a path relative to its own tree.
# On a compile error scc hangs instead of exiting, so bound it with a timeout.
(cd "$SANDBOX" && WINEDEBUG=-all timeout -k 5 90 wine engine/tools/scc.exe -compile 'r6\scripts' \
   -customCacheDir 'r6\cache' >/dev/null 2>&1) || true

LOG="$SANDBOX/r6/logs/redscript_rCURRENT.log"
[ -f "$LOG" ] || { echo "no compiler log at $LOG"; exit 1; }
grep -vE '\.reds$' "$LOG" | grep -v '^\[INFO' || true
if grep -q "ERROR" "$LOG"; then echo "COMPILE FAILED"; exit 1; fi
grep -q "OverlayMap" "$LOG" || { echo "OverlayMap was not compiled"; exit 1; }
echo "COMPILE OK"
