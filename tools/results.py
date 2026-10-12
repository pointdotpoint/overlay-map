#!/usr/bin/env python3
"""Summarize NightMap PerfSuite results from CET's gamelog.log (latest suite run) and judge the spec target."""
import re
import sys
from pathlib import Path

GAMELOG = Path.home() / "cyberpunk_symlink/bin/x64/plugins/cyber_engine_tweaks/gamelog.log"
AVG_BUDGET_MS = 3.0
P95_BUDGET_MS = 6.0


def parse(text: str) -> list[dict]:
    lines = [l for l in text.splitlines() if "[NightMap]" in l]
    starts = [i for i, l in enumerate(lines) if "PERF|SUITE|start" in l]
    run = lines[starts[-1]:] if starts else lines
    rows = []
    for l in run:
        m = re.search(r"RESULT\|([^|]+)\|(.*)$", l)
        if not m:
            continue
        row = {"name": m.group(1)}
        for part in m.group(2).split("|"):
            k, _, v = part.partition("=")
            row[k] = float(v)
        rows.append(row)
    return rows


def verdict(rows: list[dict]) -> tuple[bool, str]:
    by = {r["name"]: r for r in rows}
    if "closed_baseline" not in by or "items_50000" not in by:
        return False, "missing closed_baseline or items_50000 row"
    base, test = by["closed_baseline"], by["items_50000"]
    d_avg = test["frame_avg"] - base["frame_avg"]
    d_p95 = test["frame_p95"] - base["frame_p95"]
    ok = d_avg <= AVG_BUDGET_MS and d_p95 <= P95_BUDGET_MS
    return ok, f"items_50000: avg +{d_avg:.2f} ms (budget {AVG_BUDGET_MS}), p95 +{d_p95:.2f} ms (budget {P95_BUDGET_MS})"


def main() -> int:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else GAMELOG
    rows = parse(path.read_text(errors="replace"))
    if not rows:
        print(f"no RESULT lines in {path}")
        return 1
    base = next((r["frame_avg"] for r in rows if r["name"] == "closed_baseline"), None)
    print(f"{'scenario':18} {'items':>7} {'setup ms':>9} {'avg':>7} {'+base':>7} {'p95':>7} {'p99':>7} {'max':>7} {'script':>7}")
    for r in rows:
        delta = f"{r['frame_avg'] - base:+.2f}" if base is not None else "?"
        print(f"{r['name']:18} {int(r['items']):>7} {r['setup_ms']:>9.1f} {r['frame_avg']:>7.2f} {delta:>7} "
              f"{r['frame_p95']:>7.2f} {r['frame_p99']:>7.2f} {r['frame_max']:>7.2f} {r['script_avg']:>7.2f}")
    ok, msg = verdict(rows)
    print(("PASS: " if ok else "FAIL: ") + msg)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
