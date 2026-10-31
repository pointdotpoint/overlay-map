#!/usr/bin/env python3
"""Pull every placed entity with item or loot data (or a tarot name) out of the world streaming sectors.

Needs WolvenKit 10 (8.x and 9.x cannot read the 2.3 sectors) and the .NET 10 runtime it was built for:
  scan.py --wolvenkit ~/.cache/nightmap-sectors/wk10/WolvenKit.CLI --dotnet ~/.cache/nightmap-sectors/dotnet10
Output: one JSON line per node in <out>/b*.jsonl: sector, type, entity template, debug name, item and loot IDs,
appearance and world positions.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ARCHIVES = ("archive/pc/content/basegame_3_nightcity.archive", "archive/pc/ep1/ep1_1_nightcity.archive")
SECTOR_RE = r"(exterior|interior|quest|always)[^\\]*\.streamingsector$"
NEEDLES = (b"tarot", b"mq033", b"entEntityInstanceData", b"base\\gameplay\\loot", b"itemTDBID", b"gameLootSlot")
BATCH = 120


def tweak_ids(o, found: set[str]) -> None:
    if isinstance(o, dict):
        if o.get("$type") == "TweakDBID" and o.get("$storage") == "string" and o.get("$value") not in (None, "", "None"):
            found.add(o["$value"])
        for v in o.values():
            tweak_ids(v, found)
    elif isinstance(o, list):
        for v in o:
            tweak_ids(v, found)


def coord(v):
    return v.get("Bits", 0) / 131072.0 if isinstance(v, dict) else v


def extract(path: Path, w) -> None:
    text = path.read_text()
    has_tarot = "tarot" in text
    root = json.loads(text)["Data"]["RootChunk"]
    pos: dict[int, list] = {}
    for x in root["nodeData"]["Data"]:
        p = (x.get("transform") or {}).get("position")
        if p:
            pos.setdefault(int(x.get("nodeIdx", -1)), []).append([round(coord(p.get(k)), 3) for k in "XYZ"])
    sector = path.name.replace(".streamingsector.json", "")
    for i, nr in enumerate(root["nodes"]):
        n = nr.get("Data", nr)
        e = n.get("entityTemplate")
        tpl = e.get("DepotPath", {}).get("$value", "") if isinstance(e, dict) else ""
        name = (n.get("debugName") or {}).get("$value", "")
        ids: set[str] = set()
        if n.get("instanceData"):
            tweak_ids(n["instanceData"], ids)
        keep = bool(ids) or "loot" in tpl or "mq033" in name or (has_tarot and "tarot" in json.dumps(n).lower())
        if keep and i in pos:
            w.write(json.dumps({"s": sector, "i": i, "t": n.get("$type", ""), "tpl": tpl, "n": name,
                                "ids": sorted(ids), "a": (n.get("appearanceName") or {}).get("$value", ""),
                                "p": pos[i][:8]}) + "\n")


def run_batch(k: int, files: list[Path], out: Path, wk: str, env: dict) -> int:
    mark = out / f"b{k:05}.done"
    if mark.exists():
        return 0
    with tempfile.TemporaryDirectory(dir=out) as td:
        src, dst = Path(td) / "in", Path(td) / "out"
        src.mkdir()
        dst.mkdir()
        for f in files:
            (src / f.name).symlink_to(f)
        subprocess.run([wk, "convert", "s", str(src), "-o", str(dst)], env=env, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=1200, check=False)
        made = 0
        with open(out / f"b{k:05}.jsonl", "w") as w:
            for j in dst.glob("*.json"):
                try:
                    extract(j, w)
                    made += 1
                except (ValueError, KeyError):
                    print(f"unreadable {j.name}", flush=True)
                j.unlink()
    mark.write_text(f"{made}\n")
    return made


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--game", type=Path, default=Path.home() / "cyberpunk_symlink")
    ap.add_argument("--work", type=Path, default=Path.home() / ".cache/nightmap-sectors")
    ap.add_argument("--wolvenkit", required=True)
    ap.add_argument("--dotnet", type=Path, required=True)
    ap.add_argument("--jobs", type=int, default=3)
    args = ap.parse_args(argv)
    env = dict(os.environ, DOTNET_ROOT=str(args.dotnet))
    raw, out = args.work / "raw", args.work / "scan"
    out.mkdir(parents=True, exist_ok=True)
    for a in ARCHIVES:
        subprocess.run([args.wolvenkit, "extract", str(args.game / a), "-r", SECTOR_RE, "-o", str(raw)], env=env,
                       stdout=subprocess.DEVNULL, check=True)
    files = sorted(p for p in raw.rglob("*.streamingsector")
                   if not p.name.startswith("always_loaded") and any(n in p.read_bytes() for n in NEEDLES))
    print(f"{len(files)} sectors with items or tarot", flush=True)
    batches = [files[i:i + BATCH] for i in range(0, len(files), BATCH)]
    with ThreadPoolExecutor(args.jobs) as ex:
        total = sum(ex.map(lambda kb: run_batch(kb[0], kb[1], out, args.wolvenkit, env), enumerate(batches)))
    print(f"converted {total}; output in {out}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
