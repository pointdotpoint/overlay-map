#!/usr/bin/env bash
# Compile-check NightMap offline with the game's own redscript compiler under Wine.
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
# RedIMGRetriever is optional; NightMap compiles either way through @if(ModuleExists).
if [ -d "$GAME/r6/scripts/RedIMGRetriever" ]; then
  cp "$GAME"/r6/scripts/RedIMGRetriever/*.reds "$SANDBOX/r6/scripts/RedIMGRetriever/"
fi
cp "$GAME"/red4ext/plugins/mod_settings/*.reds "$SANDBOX/r6/scripts/ModSettings/"
cp -r "$HERE/r6/scripts/NightMap" "$SANDBOX/r6/scripts/NightMap"

# scc only scans the scripts dir reliably when given a path relative to its own tree.
# On a compile error scc hangs instead of exiting, so bound it with a timeout.
(cd "$SANDBOX" && WINEDEBUG=-all timeout -k 5 90 wine engine/tools/scc.exe -compile 'r6\scripts' \
   -customCacheDir 'r6\cache' >/dev/null 2>&1) || true

LOG="$SANDBOX/r6/logs/redscript_rCURRENT.log"
[ -f "$LOG" ] || { echo "no compiler log at $LOG"; exit 1; }
grep -vE '\.reds$' "$LOG" | grep -v '^\[INFO' || true
if grep -q "ERROR" "$LOG"; then echo "COMPILE FAILED"; exit 1; fi
grep -q "NightMap" "$LOG" || { echo "NightMap was not compiled"; exit 1; }
echo "COMPILE OK"
