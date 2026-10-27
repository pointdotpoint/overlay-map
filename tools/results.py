#!/usr/bin/env python3
"""Summarize NightMap PerfSuite results from CET's gamelog.log (latest suite run) and judge the spec target."""
import argparse
import re
import statistics
import sys
from pathlib import Path

GAMELOG = Path.home() / "cyberpunk_symlink/bin/x64/plugins/cyber_engine_tweaks/gamelog.log"
AVG_BUDGET_MS = 3.0
P95_BUDGET_MS = 6.0
# Spec 11.5, all measured against the closed-map baseline.
IDLE_AVG_BUDGET_MS = 1.0
IDLE_P95_BUDGET_MS = 2.0
SWEEP_AVG_BUDGET_MS = 1.5
SWEEP_P95_BUDGET_MS = 3.0
IDLE_ROWS = ("idle_0p5", "idle_2", "idle_8")
SWEEP_ROWS = ("open_empty", "vanilla_open", "route_open", "panzoom_0p5_16")   # open_empty: cold sweep, no markers; vanilla_open: real markers
# route_open: the sweep with the GPS routes on. Gated only when a route was drawn (route_drawn=1); otherwise
# "skipped: no route", neither pass nor fail. route_read_ms_max (one minimap read) is reported, never gated.
ROUTE_ROW = "route_open"
ROUTE_READ_TARGET_MS = 0.5
# vanilla_open script cost (the CPU-bound proxy; frame deltas hide it on GPU-bound machines), within the same run:
SCRIPT_ROW, SCRIPT_REF_ROW = "vanilla_open", "open_empty"
SCRIPT_AVG_MARGIN_MS = 0.5     # vanilla_open.script_avg <= open_empty.script_avg + this
SCRIPT_P95_MARGIN_MS = 1.5     # vanilla_open.script_p95 <= open_empty.script_p95 + this
POLL_MAX_MS = 1.0              # vanilla_open.poll_ms_max <= this (one poll, absolute)
DRIFT_MAX_MS = 0.5       # |closed_end - closed_baseline| above this: the run's machine state moved, exclude it
LOADED_MARK = "[NightMap] loaded"  # logged at every game start; --all-sessions ignores it
# (scenario, avg budget, p95 budget) in report order
GATES = ([("items_50000", AVG_BUDGET_MS, P95_BUDGET_MS)] + [(n, IDLE_AVG_BUDGET_MS, IDLE_P95_BUDGET_MS) for n in IDLE_ROWS]
         + [(n, SWEEP_AVG_BUDGET_MS, SWEEP_P95_BUDGET_MS) for n in SWEEP_ROWS])


class SuiteError(Exception):
    pass


def _rows(run: list[str]) -> list[dict]:
    rows = []
    for l in run:
        m = re.search(r"RESULT\|([^|]+)\|(.*)$", l)
        if not m:
            continue
        row = {"name": m.group(1)}
        try:
            for part in m.group(2).split("|"):
                k, sep, v = part.partition("=")
                if not sep:
                    raise ValueError(part)
                row[k] = float(v)
        except ValueError:
            print(f"warning: skipping malformed RESULT line: {l.strip()}", file=sys.stderr)
            continue
        rows.append(row)
    return rows


def parse(text: str) -> list[dict]:
    """Rows of the latest suite run; raises SuiteError unless it has a start and a following done."""
    lines = [l for l in text.splitlines() if "[NightMap]" in l]
    starts = [i for i, l in enumerate(lines) if "PERF|SUITE|start" in l]
    if not starts:
        raise SuiteError("no PERF|SUITE|start found")
    run = lines[starts[-1]:]
    if not any("PERF|SUITE|done" in l for l in run):
        raise SuiteError("incomplete suite (no PERF|SUITE|done after the last start)")
    return _rows(run)


def parse_suites(text: str) -> list[list[dict]]:
    """Rows of every complete suite (start followed by done before the next start) in the log, oldest first."""
    lines = [l for l in text.splitlines() if "[NightMap]" in l]
    starts = [i for i, l in enumerate(lines) if "PERF|SUITE|start" in l]
    out = []
    for k, i in enumerate(starts):
        run = lines[i:starts[k + 1] if k + 1 < len(starts) else len(lines)]
        if any("PERF|SUITE|done" in l for l in run):
            out.append(_rows(run))
    return out


def drift(rows: list[dict]) -> float | None:
    """|closed_end - closed_baseline| frame_avg in ms, or None when either row is missing."""
    by = {r["name"]: r for r in rows}
    try:
        return abs(by["closed_end"]["frame_avg"] - by["closed_baseline"]["frame_avg"])
    except KeyError:
        return None


def deltas(rows: list[dict]) -> tuple[dict[str, tuple[float, float] | None], list[str]]:
    """Per-scenario (avg, p95) deltas against this run's own closed_baseline, plus problems (missing/truncated rows).

    A route_open row that drew no route maps to None: skipped, not gated."""
    by = {r["name"]: r for r in rows}
    base = by.get("closed_baseline")
    if base is None or "frame_avg" not in base or "frame_p95" not in base:
        return {}, ["missing closed_baseline or items_50000 row"]
    out, problems = {}, []
    for name, _, _ in GATES:
        r = by.get(name)
        if r is None:
            problems.append(f"{name}: row missing")
        elif "frame_avg" not in r or "frame_p95" not in r:
            problems.append(f"{name}: lacks frame_avg/frame_p95")
        elif name == ROUTE_ROW and r.get("route_drawn", 1) == 0:
            out[name] = None
        else:
            out[name] = (r["frame_avg"] - base["frame_avg"], r["frame_p95"] - base["frame_p95"])
    return out, problems


def script_vals(rows: list[dict]) -> tuple[tuple[float, float, float] | None, list[str]]:
    """(script_avg delta, script_p95 delta, poll_ms_max) of vanilla_open against this run's open_empty, plus problems.

    A wholly missing row is reported by ``deltas`` already; a present row that lacks a field fails here."""
    by = {r["name"]: r for r in rows}
    van, ref = by.get(SCRIPT_ROW), by.get(SCRIPT_REF_ROW)
    if van is None or ref is None:
        return None, []
    problems = []
    if any(k not in ref for k in ("script_avg", "script_p95")):
        problems.append(f"{SCRIPT_REF_ROW}: lacks script_avg/script_p95")
    if any(k not in van for k in ("script_avg", "script_p95", "poll_ms_max")):
        problems.append(f"{SCRIPT_ROW}: lacks script_avg/script_p95/poll_ms_max")
    if problems:
        return None, problems
    return (van["script_avg"] - ref["script_avg"], van["script_p95"] - ref["script_p95"], van["poll_ms_max"]), []


def _script_gate(sv: tuple[float, float, float]) -> tuple[bool, str]:
    da, dp, poll = sv
    good_a, good_p, good_poll = da <= SCRIPT_AVG_MARGIN_MS, dp <= SCRIPT_P95_MARGIN_MS, poll <= POLL_MAX_MS
    return good_a and good_p and good_poll, (
        f"{SCRIPT_ROW} script: avg +{da:.2f} ms (budget {SCRIPT_AVG_MARGIN_MS}){'' if good_a else ' OVER'}, "
        f"p95 +{dp:.2f} ms (budget {SCRIPT_P95_MARGIN_MS}){'' if good_p else ' OVER'}, "
        f"poll_ms_max {poll:.2f} ms (budget {POLL_MAX_MS}){'' if good_poll else ' OVER'}")


def _gate(d: dict[str, tuple[float, float]], problems: list[str], sv: tuple[float, float, float] | None = None) -> tuple[bool, str]:
    if problems and not d:
        return False, "; ".join(problems)
    ok, parts = not problems, list(problems)
    for name, avg_b, p95_b in GATES:
        if name not in d:
            continue
        if d[name] is None:
            parts.append(f"{name}: skipped: no route")
            continue
        va, vp = d[name]
        good = va <= avg_b and vp <= p95_b
        ok = ok and good
        parts.append(f"{name}: avg +{va:.2f} ms (budget {avg_b}), p95 +{vp:.2f} ms (budget {p95_b}){'' if good else ' OVER'}")
    if sv is not None:
        good, text = _script_gate(sv)
        ok = ok and good
        parts.append(text)
    return ok, "; ".join(parts)


def verdict(rows: list[dict]) -> tuple[bool, str]:
    """Gate a single run against its own closed_baseline (no drift or median handling; see ``judge``)."""
    d, problems = deltas(rows)
    sv, sproblems = script_vals(rows)
    return _gate(d, problems + sproblems, sv)


def select_valid(suites: list[list[dict]], n: int) -> tuple[list[list[dict]], list[str]]:
    """The last ``n`` non-drifted suites (newest first), plus a note for each drifted suite skipped on the way."""
    valid, skipped = [], []
    for i in range(len(suites) - 1, -1, -1):
        if len(valid) >= n:
            break
        dr = drift(suites[i])
        if dr is None or dr > DRIFT_MAX_MS:
            skipped.append(f"run {i + 1} drifted ({'no closed_end row' if dr is None else f'|closed_end - closed_baseline| = {dr:.2f} ms'}), excluded")
        else:
            valid.append(suites[i])
    return valid, skipped


def current_session(text: str) -> str:
    """The log from the last NightMap load on, so suites from earlier game sessions (older builds) are not judged."""
    i = text.rfind(LOADED_MARK)
    return text if i < 0 else text[i:]


def judge(suites: list[list[dict]], n: int = 3) -> tuple[str, str]:
    """PASS / FAIL / INCONCLUSIVE over the per-scenario median of the last ``n`` complete, non-drifted suites."""
    if n < 1:
        raise ValueError("n must be >= 1")
    valid, skipped = select_valid(suites, n)
    note = "; ".join(skipped)
    per = [deltas(r) for r in valid]
    svs = [script_vals(r) for r in valid]
    problems = sorted({p for _, ps in per for p in ps} | {p for _, ps in svs for p in ps})
    if problems:
        return "FAIL", "; ".join(problems + ([note] if note else []))
    if len(valid) < n:
        return "INCONCLUSIVE", f"{len(valid)} of {n} valid runs" + (f" ({note})" if note else "")
    med = {}
    for name, _, _ in GATES:
        vals = [d[name] for d, _ in per if d[name] is not None]
        med[name] = (statistics.median(v[0] for v in vals), statistics.median(v[1] for v in vals)) if vals else None
    sv_med = tuple(statistics.median(v[i] for v, _ in svs) for i in range(3)) if all(v is not None for v, _ in svs) else None
    ok, msg = _gate(med, [], sv_med)
    return ("PASS" if ok else "FAIL"), f"median of {n} runs: {msg}" + (f"; {note}" if note else "")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("log", nargs="?", type=Path, default=GAMELOG)
    ap.add_argument("--runs", type=int, default=3, help="number of valid suites whose median is judged (default 3)")
    ap.add_argument("--all-sessions", action="store_true", help="also judge suites from earlier game sessions in the log")
    args = ap.parse_args()
    if args.runs < 1:
        ap.error("--runs must be >= 1")
    path = args.log
    text = path.read_text(errors="replace")
    if not args.all_sessions:
        text = current_session(text)
    try:
        rows = parse(text)
    except SuiteError as e:
        print(f"FAIL: {e}")
        return 1
    if not rows:
        print(f"no RESULT lines in {path}")
        return 1
    base = next((r["frame_avg"] for r in rows if r["name"] == "closed_baseline"), None)
    print("most recent run:")
    print(f"{'scenario':22} {'items':>7} {'setup ms':>9} {'avg':>7} {'+base':>7} {'p95':>7} {'p99':>7} {'max':>7} {'script':>7}")
    full = [r for r in rows if all(k in r for k in ("items", "setup_ms", "frame_avg", "frame_p95", "frame_p99", "frame_max", "script_avg"))]
    for r in full:
        delta = f"{r['frame_avg'] - base:+.2f}" if base is not None else "?"
        print(f"{r['name']:22} {int(r['items']):>7} {r['setup_ms']:>9.1f} {r['frame_avg']:>7.2f} {delta:>7} "
              f"{r['frame_p95']:>7.2f} {r['frame_p99']:>7.2f} {r['frame_max']:>7.2f} {r['script_avg']:>7.2f}")
    dr = drift(rows)
    print(f"closed_end drift: {'n/a' if dr is None else f'{dr:.2f} ms'} (limit {DRIFT_MAX_MS})")
    suites = parse_suites(text)
    per = [deltas(r) for r in select_valid(suites, args.runs)[0]]
    print(f"\nmedians over {len(per)} valid run(s) of {len(suites)} in this {'log' if args.all_sessions else 'session'} (delta vs own closed_baseline):")
    print(f"{'scenario':22} {'avg':>7} {'p95':>7}")
    for name, _, _ in GATES:
        vals = [d[name] for d, _ in per if d.get(name) is not None]
        if vals:
            print(f"{name:22} {statistics.median(v[0] for v in vals):>+7.2f} {statistics.median(v[1] for v in vals):>+7.2f}")
    svs = [sv for sv, _ in (script_vals(r) for r in select_valid(suites, args.runs)[0]) if sv is not None]
    if svs:
        print(f"{SCRIPT_ROW} script vs {SCRIPT_REF_ROW}: avg {statistics.median(v[0] for v in svs):+.2f} ms, "
              f"p95 {statistics.median(v[1] for v in svs):+.2f} ms, poll_ms_max {statistics.median(v[2] for v in svs):.2f} ms")
    route = next((r for r in rows if r["name"] == ROUTE_ROW and "route_read_ms_max" in r), None)
    if route is not None:
        print(f"{ROUTE_ROW} route_read_ms_max {route['route_read_ms_max']:.3f} ms (target {ROUTE_READ_TARGET_MS})"
              + ("" if route.get("route_drawn", 1) else " (no route drawn)"))
    status, msg = judge(suites, args.runs)
    print(f"{status}: {msg}")
    return {"PASS": 0, "FAIL": 1}.get(status, 2)


if __name__ == "__main__":
    sys.exit(main())
