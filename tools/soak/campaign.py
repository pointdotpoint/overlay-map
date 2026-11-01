"""A campaign: lock, preflight, snapshot, then for each run: verify the install, stage, install,
reset data, run, check saves, collect. Always: release keys, kill the game it launched (never one already
running when it started), restore, unlock, report."""
from __future__ import annotations

import dataclasses
import re
import shutil
import time
from pathlib import Path

from .evidence import check_log, log_offset, run_log
from .paths import Paths
from .preflight import versions as read_versions
from .report import write_report
from .snapshot import Snapshot


class CampaignStop(RuntimeError):
    pass


def run_order(plan: dict) -> list[tuple[dict, int]]:
    return [(s, k) for s in plan["runs"] for k in range(s.get("repeats", 1))]


def validate_plan(plan: dict) -> None:
    """A mistake in a plan is a ValueError before anything is touched, not a surprise an hour in."""
    for spec in plan["runs"]:
        name = spec["name"]
        if not spec.get("steps"):
            raise ValueError(f"run {name}: no steps")
        patterns = list(spec.get("forbid", []))
        for want in spec.get("expect", []):
            if "log" not in want or want.get("min", 1) < 1:
                raise ValueError(f"run {name}: bad expect {want}")
            patterns.append(want["log"])
        patterns += [s["expect"] for s in spec["steps"] if "expect" in s]
        for pattern in patterns:
            try:
                re.compile(pattern)
            except re.error as e:
                raise ValueError(f"run {name}: bad regex {pattern!r}: {e}") from e


def retriable(result) -> bool:
    """The game never reached the world: a failed launch, not a result about what the run tests."""
    return result.verdict in ("infra_error", "load_crash") and "world" not in result.states


def run_campaign(plan: dict, save: str, paths: Paths, game, *, runner, lock, preflight, stage, collect,
                 stop=lambda: False, log=print, name: str | None = None) -> Path:
    validate_plan(plan)
    name = name or time.strftime("%Y%m%d-%H%M%S") + "-" + plan["name"]
    results = paths.soak / "results" / name
    records: list[dict] = []
    stopped: str | None = None
    restored = True
    lock.acquire(f"nightmap soak campaign {name}")
    snapshot = Snapshot(paths, name)
    owns_game = False   # a game running before preflight passed is the player's: never kill it
    try:
        failed = [c for c in preflight(paths, save, game, lock_free=True) if not c.ok]
        if failed:
            raise CampaignStop("preflight failed: " + "; ".join(f"{c.name} ({c.detail})" for c in failed))
        owns_game = True    # preflight saw no game, so any game from here on is one this campaign launched
        snapshot.take()
        infra_streak = 0
        for spec, k in run_order(plan):
            if stop():
                raise CampaignStop("stop requested")
            run_id = f"{spec['name']}-{k + 1}"
            if snapshot.journal.get("installed") and not snapshot.verify_installed():
                raise CampaignStop("the installed mod changed outside the harness (another deploy?)")
            build = stage(paths, spec["parts"])
            snapshot.install(build.dir, build.id)
            retried, saves_ok = "", True
            while True:
                snapshot.reset_run_data()
                since = time.time()
                log_from = log_offset(paths)
                result = runner.run(run_id, build.id, save, spec["steps"], results / run_id / "screens")
                if result.verdict == "pass":      # the game has exited: its log is flushed
                    problems = check_log(run_log(paths, log_from), spec.get("expect", []), spec.get("forbid", []))
                    if problems:
                        result = dataclasses.replace(result, verdict="coverage_fail", detail="; ".join(problems))
                saves_ok = snapshot.check_saves() and saves_ok
                if retried or not retriable(result) or stop():
                    break
                retried = f"{result.verdict}: {result.detail}"
                collect(results / f"{run_id}.try1", paths, result, build, since, log_from)
                if (results / run_id / "screens").exists():
                    shutil.move(results / run_id / "screens", results / f"{run_id}.try1" / "screens")
                log(f"{run_id}: {retried}, retrying")
            collect(results / run_id, paths, result, build, since, log_from)
            records.append({"run": run_id, "build": build.id, "verdict": result.verdict,
                            "detail": result.detail + (f" (retried after {retried})" if retried else ""),
                            "seconds": result.seconds, "workload": result.workload_seconds, "saves_ok": saves_ok,
                            "counts": {}, "stages": result.stages, "answers": result.answers, "lumas": result.lumas})
            log(f"{run_id}: {result.verdict} {result.detail}")
            if result.verdict == "interrupted":
                raise CampaignStop("stop requested")
            infra_streak = infra_streak + 1 if result.verdict == "infra_error" else 0
            if infra_streak >= 2:
                raise CampaignStop("2 harness errors in a row")
    except CampaignStop as e:
        stopped = str(e)
    finally:
        game.release_all()
        if owns_game and (game.running() or (hasattr(game, "session_alive") and game.session_alive())):
            game.kill()
        if snapshot.journal.get("taken"):
            restored = snapshot.restore()
        lock.release()
    return write_report(results, plan, records, stopped, restored, read_versions(paths))
