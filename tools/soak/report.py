"""soak/results/<campaign>/report.md."""
from __future__ import annotations

import json
from pathlib import Path


def classify(records: list[dict]) -> str:
    verdicts = [r["verdict"] for r in records]
    if "crash" in verdicts:
        return "crashes"
    # exit_crash: the workload ran clean; the game crashed only quitting with photo mode open.
    if verdicts.count("pass") + verdicts.count("exit_crash") >= 5:
        return "clean at 50%"
    return "inconclusive"


def write_report(results_dir: Path, plan: dict, records: list[dict], stopped: str | None,
                 restored: bool, versions: dict) -> Path:
    results_dir.mkdir(parents=True, exist_ok=True)
    lines = [f"# Soak campaign {results_dir.name}", "",
             f"plan: {plan['name']}", f"stopped: {stopped or 'no (all runs done)'}",
             f"restored: {'yes' if restored else 'NO - run tools/soak/soak.py restore'}",
             f"versions: {json.dumps(versions)}", "",
             "| run | verdict | minutes | workload min | saves untouched | detail |",
             "|---|---|---|---|---|---|"]
    for r in records:
        lines.append(f"| {r['run']} | {r['verdict']} | {r['seconds'] / 60:.1f} | {r['workload'] / 60:.1f} | "
                     f"{'yes' if r['saves_ok'] else 'NO (restored)'} | {r['detail']} |")
    counts: dict[str, int] = {}
    for r in records:
        counts[r["verdict"]] = counts.get(r["verdict"], 0) + 1
    lines += ["", "totals: " + ", ".join(f"{k} {v}" for k, v in sorted(counts.items()))]
    configs: dict[str, list[dict]] = {}
    for r in records:
        configs.setdefault(r["run"].rsplit("-", 1)[0], []).append(r)
    lines += ["", "## Configurations", "",
              "| config | runs | crash | pass | exit_crash | coverage_fail | hang | infra_error | minutes to crash | result |",
              "|---|---|---|---|---|---|---|---|---|---|"]
    for name, rs in configs.items():
        v = [r["verdict"] for r in rs]
        crash_min = ", ".join(f"{r['seconds'] / 60:.1f}" for r in rs if r["verdict"] == "crash")
        lines.append(f"| {name} | {len(rs)} | {v.count('crash')} | {v.count('pass')} | {v.count('exit_crash')} | {v.count('coverage_fail')} | "
                     f"{v.count('hang')} | {v.count('infra_error')} | {crash_min} | {classify(rs)} |")
    lines += ["", "## Actions", ""]
    for r in records:
        top = sorted(((k, n) for k, n in r.get("counts", {}).items() if k.endswith(":completed")),
                     key=lambda x: -x[1])[:8]
        lines.append(f"- {r['run']}: " + ", ".join(f"{k.split(':')[0]} {n}" for k, n in top))
    lines += ["", "## Stages", ""]
    for r in records:
        if r.get("stages"):
            lines.append(f"- {r['run']}: " + ", ".join(f"{name} {t:.0f}" for name, t in r["stages"]) + " (s)")
    path = results_dir / "report.md"
    path.write_text("\n".join(lines) + "\n")
    (results_dir / "records.json").write_text(json.dumps(records, indent=1))
    return path
