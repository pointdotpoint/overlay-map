#!/usr/bin/env python3
"""Pull every quest's id, title key and type out of the game's journals, for gen.py's quest notes.

  quests.py --wolvenkit ~/.cache/nightmap-sectors/wk10/WolvenKit.CLI --dotnet ~/.cache/nightmap-sectors/dotnet10
writes tools/collectibles/journal_quests.json: {"q304_stadium": [79421, "MainQuest", 1], ...} = quest id ->
[title LocKey, journal quest type, 1 if Phantom Liberty]. Only keys ship; the game localises the titles.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import tempfile
from pathlib import Path

OUT = Path(__file__).with_name("journal_quests.json")
JOURNALS = ("archive/pc/content", "archive/pc/ep1")


def quests_in(o, ep1: int, out: dict) -> None:
    if isinstance(o, dict):
        if o.get("$type") == "gameJournalQuest" and isinstance(o.get("id"), str):
            v = (o.get("title") or {}).get("value", "")
            if v.startswith("LocKey#") and v[7:].isdigit():
                out[o["id"].lower()] = [int(v[7:]), o.get("type", ""), ep1]
        for v in o.values():
            quests_in(v, ep1, out)
    elif isinstance(o, list):
        for v in o:
            quests_in(v, ep1, out)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--game", type=Path, default=Path.home() / "cyberpunk_symlink")
    ap.add_argument("--wolvenkit", required=True)
    ap.add_argument("--dotnet", type=Path, required=True)
    ap.add_argument("--out", type=Path, default=OUT)
    args = ap.parse_args(argv)
    env = dict(os.environ, DOTNET_ROOT=str(args.dotnet))
    out: dict = {}
    with tempfile.TemporaryDirectory() as td:
        raw, src, dst = Path(td) / "raw", Path(td) / "in", Path(td) / "out"
        # Base archives first, then Phantom Liberty's: its archives also carry an updated base journal, which wins.
        for folder in JOURNALS:
            for a in sorted((args.game / folder).glob("*.archive")):
                subprocess.run([args.wolvenkit, "extract", str(a), "-r", r"cooked_journal\.journal$", "-o", str(raw)],
                               env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        src.mkdir()
        dst.mkdir()
        for j in raw.rglob("*.journal"):
            (src / f"{j.relative_to(raw).parts[0]}.journal").symlink_to(j)   # base.journal, ep1.journal
        subprocess.run([args.wolvenkit, "convert", "s", str(src), "-o", str(dst)], env=env,
                       stdout=subprocess.DEVNULL, check=True)
        for j in sorted(dst.glob("*.json")):
            quests_in(json.loads(j.read_text()), int(j.name.startswith("ep1")), out)
    args.out.write_text(json.dumps(dict(sorted(out.items())), indent=0) + "\n")
    print(f"{len(out)} quests -> {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
