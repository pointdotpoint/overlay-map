"""Where everything the soak harness touches lives. Tests build a Paths over a temp folder.

Ported from ~/photomode_ui_improvements/scripts/soak. One Steam launch option can name one wrapper, so OverlayMap
shares that repo's gamescope-wrap.sh and its flag folder, and the deploy lock: only one harness may hold the game."""
from __future__ import annotations

import hashlib
import os
from dataclasses import dataclass
from pathlib import Path

APP_ID = "1091500"
REPO = Path(__file__).resolve().parents[2]
PMUI_REPO = Path.home() / "photomode_ui_improvements"

# Game-relative paths of each installable part. builds.py stages them, snapshot.py swaps them.
PARTS: dict[str, list[str]] = {
    "scripts": ["r6/scripts/OverlayMap"],
    "archive": ["archive/pc/mod/OverlayMap.archive"],
    "bootstrap": ["r6/scripts/SoakBootstrap"],
    "native": ["red4ext/plugins/OverlayMapNative"],   # the optional plugin, staged by tools/native/build.sh
    "autopilot": ["r6/scripts/OverlayMap/Debug/SoakHooks.reds", "r6/scripts/OverlayMap/Debug/MinimapSpike.reds"],
}
# Parts nothing writes into at runtime: a change between runs means another writer.
VERIFY_PARTS = ["scripts", "archive", "bootstrap"]


def rels(parts: list[str]) -> list[str]:
    return sorted({rel for part in parts for rel in PARTS[part]})


@dataclass(frozen=True)
class Paths:
    game: Path
    user: Path  # the Proton prefix's steamuser folder
    steam: Path  # ~/.local/share/Steam
    soak: Path  # the harness's state, builds, backups, results (gitignored)
    wrapper_state: Path = PMUI_REPO / "soak"  # where gamescope-wrap.sh reads its flag
    repo: Path = REPO

    @property
    def saves(self) -> Path:
        return self.user / "Saved Games/CD Projekt Red/Cyberpunk 2077"

    @property
    def reports(self) -> Path:
        return self.user / "AppData/Local/REDEngine/ReportQueue"

    @property
    def settings(self) -> Path:
        return self.user / "AppData/Local/CD Projekt Red/Cyberpunk 2077"

    @property
    def persistent(self) -> Path:
        return self.game / "red4ext/plugins/Codeware/Persistent/ScriptableServiceContainer.dat"

    @property
    def mod_storage(self) -> Path:
        return self.game / "r6/storages/OverlayMap"

    @property
    def channel(self) -> Path:
        return self.game / "r6/storages/SoakBootstrap"

    @property
    def lock(self) -> Path:
        return self.game / ".pmui-deploy.lock"

    @property
    def exe(self) -> Path:
        return self.game / "bin/x64/Cyberpunk2077.exe"

    @property
    def gamelog(self) -> Path:
        return self.game / "bin/x64/plugins/cyber_engine_tweaks/gamelog.log"

    @property
    def red4ext_logs(self) -> Path:
        return self.game / "red4ext/logs"


def default_paths() -> Paths:
    steam = Path.home() / ".local/share/Steam"
    game = Path(os.environ.get("CP2077_DIR", str(steam / "steamapps/common/Cyberpunk 2077")))
    user = steam / "steamapps/compatdata" / APP_ID / "pfx/drive_c/users/steamuser"
    state = Path(os.environ.get("NM_SOAK_WRAPPER_STATE", str(PMUI_REPO / "soak")))
    return Paths(game=game, user=user, steam=steam, soak=REPO / ".soak", wrapper_state=state)


def tree_hash(root: Path, rel_paths: list[str]) -> str:
    """Hash of names and contents under root; a missing path hashes as missing."""
    h = hashlib.sha256()
    for rel in sorted(rel_paths):
        p = root / rel
        if not p.exists():
            h.update(f"missing:{rel}\n".encode())
            continue
        files = sorted(f for f in p.rglob("*") if f.is_file()) if p.is_dir() else [p]
        for f in files:
            h.update(f.relative_to(root).as_posix().encode() + b"\n")
            with open(f, "rb") as fh:
                while chunk := fh.read(1 << 20):
                    h.update(chunk)
    return h.hexdigest()
