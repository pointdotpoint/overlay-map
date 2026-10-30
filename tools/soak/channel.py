"""The file channel between the supervisor and the in-game bootstrap (r6/storages/SoakBootstrap).

plan.txt (supervisor -> game): key=value lines, `end=1` last; written to a temp file and renamed.
state.txt (game -> supervisor): appended `run<TAB>seq<TAB>build<TAB>beats<TAB>state<TAB>detail`.
heartbeat.txt (game -> supervisor): `run<TAB>count<TAB>mode<TAB>x,y,z`, rewritten each beat.
command.txt (supervisor -> game): `run<TAB>command`.
shots.txt (supervisor -> game): `run<TAB>count`, the pictures taken so far; a `shot` step waits for it.
actions.txt (game -> supervisor): `run<TAB>seq<TAB>frame<TAB>macro<TAB>kind<TAB>state<TAB>detail`
  (state: attempted, accepted, skipped, completed, rejected, timeout).
events.txt (game -> supervisor): `run<TAB>frame<TAB>key<TAB>value` (a watched field changed).
plan.txt may carry extra key=value lines (recipe, seed) before `end=1`.
A line without its newline is still being written and is ignored.
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class StateLine:
    run: str
    seq: int
    build: str
    beats: int
    state: str
    detail: str


@dataclass(frozen=True)
class Beat:
    count: int
    mode: str
    camera: tuple[float, float, float] | None


def _complete_lines(path: Path) -> list[str]:
    if not path.exists():
        return []
    return path.read_text(encoding="utf-8", errors="replace").split("\n")[:-1]


def write_plan(channel: Path, run: str, build: str, save: str, extra: dict[str, str] | None = None) -> None:
    channel.mkdir(parents=True, exist_ok=True)
    for name in ("state.txt", "heartbeat.txt", "command.txt", "shots.txt", "actions.txt", "events.txt"):
        (channel / name).unlink(missing_ok=True)
    tmp = channel / "plan.tmp"
    lines = [f"run={run}", f"build={build}", f"save={save}"]
    lines += [f"{k}={v}" for k, v in (extra or {}).items()]
    tmp.write_text("\n".join(lines) + "\nend=1\n", encoding="utf-8")
    tmp.replace(channel / "plan.txt")


@dataclass(frozen=True)
class ActionLine:
    run: str
    seq: int
    frame: int
    macro: int
    kind: str
    state: str
    detail: str


def read_states(channel: Path, run: str) -> list[StateLine]:
    out: list[StateLine] = []
    last = 0
    for line in _complete_lines(channel / "state.txt"):
        f = line.split("\t")
        if len(f) != 6 or f[0] != run:
            continue
        try:
            seq, beats = int(f[1]), int(f[3])
        except ValueError:
            continue
        if seq <= last:
            continue
        last = seq
        out.append(StateLine(f[0], seq, f[2], beats, f[4], f[5]))
    return out


def read_beat(channel: Path, run: str) -> Beat | None:
    lines = _complete_lines(channel / "heartbeat.txt")
    if not lines:
        return None
    f = lines[-1].split("\t")
    if len(f) != 4 or f[0] != run:
        return None
    try:
        count = int(f[1])
    except ValueError:
        return None
    camera = None
    xyz = f[3].split(",")
    if len(xyz) == 3:
        try:
            camera = (float(xyz[0]), float(xyz[1]), float(xyz[2]))
        except ValueError:
            camera = None
    return Beat(count, f[2], camera)


def write_command(channel: Path, run: str, command: str) -> None:
    channel.mkdir(parents=True, exist_ok=True)
    tmp = channel / "command.tmp"
    tmp.write_text(f"{run}\t{command}\n", encoding="utf-8")
    tmp.replace(channel / "command.txt")


def write_shots(channel: Path, run: str, count: int) -> None:
    channel.mkdir(parents=True, exist_ok=True)
    tmp = channel / "shots.tmp"
    tmp.write_text(f"{run}\t{count}\n", encoding="utf-8")
    tmp.replace(channel / "shots.txt")


def read_actions(channel: Path, run: str) -> list[ActionLine]:
    out: list[ActionLine] = []
    for line in _complete_lines(channel / "actions.txt"):
        f = line.split("\t")
        if len(f) != 7 or f[0] != run:
            continue
        try:
            out.append(ActionLine(f[0], int(f[1]), int(f[2]), int(f[3]), f[4], f[5], f[6]))
        except ValueError:
            continue
    return out


def action_counts(lines: list[ActionLine]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for a in lines:
        key = f"{a.kind}:{a.state}"
        counts[key] = counts.get(key, 0) + 1
    return counts
