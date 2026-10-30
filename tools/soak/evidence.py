"""Everything a run leaves behind, into .soak/results/<campaign>/<run>/."""
from __future__ import annotations

import dataclasses
import json
import re
import shutil
from pathlib import Path

from .paths import Paths

GAMELOG_TAIL = 3000


def log_offset(paths: Paths) -> int:
    """Where the next run's lines start in the game log, which keeps growing across runs."""
    return paths.gamelog.stat().st_size if paths.gamelog.exists() else 0


def run_log(paths: Paths, start: int) -> str:
    """The game log from `start`; all of it if it shrank (rotated), so a run never loses its lines."""
    if not paths.gamelog.exists():
        return ""
    data = paths.gamelog.read_bytes()
    return data[start if start <= len(data) else 0:].decode("utf-8", errors="replace")


def check_log(text: str, expect: list[dict], forbid: list[str]) -> list[str]:
    """What a plan's expect / forbid found wrong in a run's log lines; empty when all is well."""
    problems = []
    for want in expect:
        count, least = len(re.findall(want["log"], text)), want.get("min", 1)
        if count < least:
            problems.append(f"log: {want['log']} {count}/{least}")
    for pattern in forbid:
        count = len(re.findall(pattern, text))
        if count:
            problems.append(f"log: forbidden {pattern} ({count})")
    return problems


def collect_evidence(run_dir: Path, paths: Paths, result, build, since: float, log_from: int = 0) -> None:
    run_dir.mkdir(parents=True, exist_ok=True)
    for rep in result.reports:
        shutil.copytree(rep, run_dir / "reports" / rep.name, dirs_exist_ok=True)
    if paths.channel.is_dir():
        shutil.copytree(paths.channel, run_dir / "channel", dirs_exist_ok=True)
    if paths.gamelog.exists():
        lines = run_log(paths, log_from).splitlines()[-GAMELOG_TAIL:]
        (run_dir / "gamelog-tail.log").write_text("\n".join(lines) + "\n")
    if paths.red4ext_logs.is_dir():
        for log in paths.red4ext_logs.iterdir():
            if log.is_file() and log.stat().st_mtime >= since:
                (run_dir / "logs").mkdir(exist_ok=True)
                shutil.copy2(log, run_dir / "logs" / log.name)
    manifest = Path(build.dir) / "manifest.json"
    if manifest.exists():
        shutil.copy2(manifest, run_dir / "manifest.json")
    data = dataclasses.asdict(result)
    data["reports"] = [str(r) for r in result.reports]
    (run_dir / "result.json").write_text(json.dumps(data, indent=1))
