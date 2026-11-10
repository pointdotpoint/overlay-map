#!/usr/bin/env bash
# Fetch one older game version's compiled vanilla scripts (r6/cache/final.redscripts, ~20 MB) from Steam, for a
# compile check against that version:
#
#   tools/compat/fetch-final-redscripts.sh 2.31 <steam-username>
#   FINAL_REDSCRIPTS=.scratch/game-2.31/r6/cache/final.redscripts tools/check.sh --native
#
# Today's compiler can't read an older version's scripts (they lack the engine's native type list), so also use that
# version's own redscript, Codeware and Mod Settings: unzip them into one folder (engine/tools/scc.exe,
# red4ext/plugins/Codeware/Scripts, red4ext/plugins/mod_settings) and pass it as GAME:
#
#   GAME=.scratch/compat-2.31/game SANDBOX=.scratch/compat-2.31/scc \
#     FINAL_REDSCRIPTS=.scratch/game-2.31/r6/cache/final.redscripts tools/check.sh --native
#
# 2.31 passed on 2026-11-10 with redscript 0.5.31, Codeware 1.19.0 and Mod Settings 0.2.21.
#
# Needs a Steam account that owns the game. DepotDownloader asks for the password (and a Steam Guard code) itself and
# remembers the login under ~/.local/share/IsolatedStorage, so run it in a terminal the first time (`! <command>` in
# Claude Code). Only that one file is downloaded, not the 60 GB game. The game install is never touched.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/../.." && pwd)"
VERSION="${1:?usage: $0 <game version, e.g. 2.31> <steam username>}"
USER_NAME="${2:?usage: $0 <game version> <steam username>}"

# Base game depot 1091501 manifests, from the RED Modding wiki's downgrade page
# (https://wiki.redmodding.org/cyberpunk-2077-modding/for-mod-users/users-modding-cyberpunk-2077/users-downgrading-preventing-auto-updates);
# SteamDB's depot history (https://steamdb.info/depot/1091501/history/) lists the rest.
case "$VERSION" in
  2.31) MANIFEST=3389237510439361019 ;;
  2.3)  MANIFEST=6814019010317238099 ;;
  *) echo "no manifest id for game $VERSION: add it here from SteamDB's depot 1091501 history" >&2; exit 1 ;;
esac

DD_VERSION=3.4.0
TOOLS="$HERE/.scratch/tools/DepotDownloader-$DD_VERSION"
if [ ! -x "$TOOLS/DepotDownloader" ]; then
  mkdir -p "$TOOLS"
  curl -fsSL -o "$TOOLS/dd.zip" \
    "https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_$DD_VERSION/DepotDownloader-linux-x64.zip"
  (cd "$TOOLS" && unzip -q -o dd.zip && rm dd.zip && chmod +x DepotDownloader)
fi

OUT="$HERE/.scratch/game-$VERSION"
mkdir -p "$OUT"
LIST="$OUT/filelist.txt"
printf 'r6/cache/final.redscripts\n' > "$LIST"
"$TOOLS/DepotDownloader" -app 1091500 -depot 1091501 -manifest "$MANIFEST" \
  -filelist "$LIST" -dir "$OUT" -username "$USER_NAME" -remember-password

FILE="$OUT/r6/cache/final.redscripts"
[ -s "$FILE" ] || { echo "download finished but $FILE is missing" >&2; exit 1; }
echo "$VERSION scripts: $FILE ($(du -h "$FILE" | cut -f1))"
echo "check: FINAL_REDSCRIPTS=$FILE tools/check.sh --native"
