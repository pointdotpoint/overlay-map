"""Checks before a campaign touches anything; any failure stops it (spec: Preflight)."""
from __future__ import annotations

import hashlib
import os
import re
import shutil
import time
import subprocess
from dataclasses import dataclass
from pathlib import Path

from .game import steam_running
from .paths import APP_ID, Paths


@dataclass(frozen=True)
class Check:
    name: str
    ok: bool
    detail: str


def _app_block(text: str, app: str) -> str | None:
    lines = text.split("\n")
    for i, line in enumerate(lines):
        if line.strip() == f'"{app}"':
            indent = line[: len(line) - len(line.lstrip("\t"))]
            out = []
            for later in lines[i + 1:]:
                if later == indent + "}":
                    return "\n".join(out)
                out.append(later)
    return None


def cloud_enabled(steam: Path) -> bool | None:
    """True if any Steam user has cloud saves on for the game, False if all have it off, None if unknown."""
    seen = []
    for cfg in steam.glob("userdata/*/7/remote/sharedconfig.vdf"):
        block = _app_block(cfg.read_text(errors="replace"), APP_ID)
        if block is None:
            continue
        m = re.search(r'"cloudenabled"\s+"(\d)"', block)
        if m:
            seen.append(m.group(1) == "1")
    return any(seen) if seen else None


def launch_options(steam: Path) -> list[str]:
    """The game's Steam launch options, one per Steam user that set any."""
    out = []
    for cfg in steam.glob("userdata/*/config/localconfig.vdf"):
        text = cfg.read_text(errors="replace")
        for m in re.finditer(rf'^(\t*)"{APP_ID}"\n\1{{\n(.*?)\n\1}}', text, re.M | re.S):
            lo = re.search(r'"LaunchOptions"\s+"((?:[^"\\]|\\.)*)"', m.group(2))
            if lo:
                out.append(lo.group(1).replace('\\"', '"'))
    return out


def _acf_field(paths: Paths, key: str) -> str | None:
    acf = paths.steam / f"steamapps/appmanifest_{APP_ID}.acf"
    if not acf.exists():
        return None
    m = re.search(rf'"{key}"\s+"([^"]*)"', acf.read_text(errors="replace"))
    return m.group(1) if m else None


def waive(checks: list[Check], names: set[str]) -> list[Check]:
    """The user waived these checks (e.g. --allow-cloud): they pass, and say so."""
    return [Check(c.name, True, "waived by the user") if c.name in names and not c.ok else c for c in checks]


def run_preflight(paths: Paths, save: str, game, lock_free: bool, min_free_gb: float = 30.0,
                  proc: Path = Path("/proc"), closing_wait: float = 0.0, sleep=time.sleep) -> list[Check]:
    checks = [Check("steam running", steam_running(proc), "start Steam and log in")]
    cloud = cloud_enabled(paths.steam)
    checks.append(Check("steam cloud off", cloud is False,
                        "turn Steam Cloud off for Cyberpunk 2077 (Properties > General)" if cloud is not False else ""))
    flags = _acf_field(paths, "StateFlags")
    checks.append(Check("game installed and updated", flags == "4", f"StateFlags {flags} (4 = ready, no update pending)"))
    target = paths.game if paths.game.exists() else paths.game.parent
    free = shutil.disk_usage(target).free / 1e9 if target.exists() else 0.0
    checks.append(Check("free disk", free >= min_free_gb, f"{free:.0f} GB free, {min_free_gb:.0f} GB needed"))
    waited = 0.0
    while game.running() and waited < closing_wait:     # the last run's game may still be shutting down
        sleep(5.0)
        waited += 5.0
    checks.append(Check("game closed", not game.running(), "close the game"))
    checks.append(Check("deploy lock free", lock_free, "another campaign or deploy holds the game folder"))
    checks.append(Check("test save exists", (paths.saves / save).is_dir(), f"{paths.saves / save}"))
    checks.append(Check("display and tools", bool(os.environ.get("DISPLAY")) and all(
        shutil.which(t) for t in ("xdotool", "import", "steam")), "needs DISPLAY, xdotool, ImageMagick import, steam"))
    if getattr(game, "gamescope", None) is not None:
        opts = launch_options(paths.steam)
        checks.append(Check("gamescope wrapper in launch options",
                            any("gamescope-wrap.sh" in o for o in opts) and all(
                                shutil.which(t) for t in ("gamescope", "gamescopectl")),
                            "put ~/photomode_ui_improvements/scripts/soak/gamescope-wrap.sh before %command% in the game's launch options "
                            "(or run with --desktop); needs gamescope + gamescopectl"))
    return checks


def versions(paths: Paths) -> dict[str, str]:
    out = {"buildid": _acf_field(paths, "buildid") or "?"}
    if paths.exe.exists():
        st = paths.exe.stat()
        out["exe"] = f"{st.st_size}:{int(st.st_mtime)}"
    info = paths.steam / f"steamapps/compatdata/{APP_ID}/config_info"
    out["proton"] = info.read_text(errors="replace").split("\n")[0] if info.exists() else "?"
    head = subprocess.run(["git", "-C", str(paths.repo), "rev-parse", "HEAD"], capture_output=True, text=True)
    diff = subprocess.run(["git", "-C", str(paths.repo), "diff", "HEAD"], capture_output=True)
    out["mod_head"] = head.stdout.strip() or "?"
    out["mod_diff"] = hashlib.sha256(diff.stdout).hexdigest()[:16]
    return out
