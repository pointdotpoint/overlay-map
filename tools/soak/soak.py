#!/usr/bin/env python3
"""Soak harness CLI: drives the real game, headless in gamescope, through a plan's steps.

  python3 tools/soak/soak.py preflight --save QuickSave-7
  python3 tools/soak/soak.py campaign tools/soak/plans/fast-travel.json --save QuickSave-7
  python3 tools/soak/soak.py restore [--campaign NAME]

Stop a campaign cleanly: create .soak/STOP, or press Ctrl+C."""
from __future__ import annotations

import argparse
import json
import signal
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from soak.builds import stage_build  # noqa: E402
from soak.campaign import run_campaign  # noqa: E402
from soak.evidence import collect_evidence  # noqa: E402
from soak.game import GameControl  # noqa: E402
from soak.lock import DeployLock  # noqa: E402
from soak.paths import default_paths  # noqa: E402
from soak.preflight import run_preflight, waive  # noqa: E402
from soak.runner import Runner  # noqa: E402
from soak.snapshot import Snapshot, latest_unrestored, prune  # noqa: E402

# Preflight runs once, at a campaign's start. A game still running then is either the last campaign's, already
# killed and finishing its exit, or one the player started; wait briefly for the first, never minutes for the second.
CLOSING_WAIT = 30.0
CLOUD_HELP = "waive the Steam Cloud check (the bootstrap blocks fast travel's autosave)"
DESKTOP_HELP = "drive the game on the desktop (takes focus; the PC can't be used) instead of headless gamescope"


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(prog="soak.py")
    sub = ap.add_subparsers(dest="cmd", required=True)
    pf = sub.add_parser("preflight")
    pf.add_argument("--save", required=True)
    pf.add_argument("--allow-cloud", action="store_true", help=CLOUD_HELP)
    pf.add_argument("--desktop", action="store_true", help=DESKTOP_HELP)
    cp = sub.add_parser("campaign")
    cp.add_argument("plan")
    cp.add_argument("--save", required=True)
    cp.add_argument("--allow-cloud", action="store_true", help=CLOUD_HELP)
    cp.add_argument("--desktop", action="store_true", help=DESKTOP_HELP)
    rs = sub.add_parser("restore")
    rs.add_argument("--campaign")
    args = ap.parse_args(argv)
    paths = default_paths()
    game = GameControl(gamescope=None if getattr(args, "desktop", False) else paths.wrapper_state, lock=paths.lock)
    waived = {"steam cloud off"} if getattr(args, "allow_cloud", False) else set()
    preflight = lambda *a, **k: waive(run_preflight(*a, **{"closing_wait": CLOSING_WAIT, **k}), waived)  # noqa: E731

    if args.cmd == "preflight":
        lock = DeployLock(paths.lock)
        checks = preflight(paths, args.save, game, lock_free=lock.is_free())
        for c in checks:
            shown = c.detail and (not c.ok or c.detail == "waived by the user")
            print(f"{'ok  ' if c.ok else 'FAIL'} {c.name}" + (f": {c.detail}" if shown else ""))
        return 0 if all(c.ok for c in checks) else 1

    if args.cmd == "restore":
        name = args.campaign or latest_unrestored(paths)
        if not name:
            print("nothing to restore")
            return 0
        if game.running():
            game.kill()
        game.clear()
        lock = DeployLock(paths.lock)
        lock.acquire(f"overlaymap soak restore {name}")
        try:
            ok = Snapshot(paths, name).restore()
        finally:
            lock.release()
        print(f"{name}: {'restored' if ok else 'restored, but the install hash differs from the backup'}")
        return 0 if ok else 1

    plan = json.loads(Path(args.plan).read_text())
    if DeployLock(paths.lock).is_free():
        prune(paths)            # disk: old staged builds and restored backups (snapshot.prune)
    stop_file = paths.soak / "STOP"
    stop_file.unlink(missing_ok=True)
    interrupted = {"flag": False}
    signal.signal(signal.SIGINT, lambda *_: interrupted.update(flag=True))
    stop = lambda: interrupted["flag"] or stop_file.exists()  # noqa: E731
    try:
        report = run_campaign(plan, args.save, paths, game, runner=Runner(paths, game, stop=stop),
                              lock=DeployLock(paths.lock), preflight=preflight, stage=stage_build,
                              collect=collect_evidence, stop=stop)
    finally:
        game.clear()
    print(report.read_text())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
