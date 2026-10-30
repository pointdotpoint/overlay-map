"""report.classify and the per-configuration table."""
import sys, tempfile
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "scripts"))
from soak.report import classify, write_report

def rec(run, verdict, minutes=30.0):
    return {"run": run, "build": "b", "verdict": verdict, "detail": "", "seconds": minutes * 60,
            "workload": minutes * 60, "saves_ok": True, "counts": {"look:completed": 9}, "missing": {}}

assert classify([rec("a-1", "pass")] * 5) == "clean at 50%"
assert classify([rec("a-1", "pass")] * 4) == "inconclusive"
assert classify([rec("a-1", "pass")] * 4 + [rec("a-5", "crash", 12)]) == "crashes"
assert classify([rec("a-1", "pass")] * 4 + [rec("a-5", "coverage_fail")]) == "inconclusive"
with tempfile.TemporaryDirectory() as d:
    plan = {"name": "x", "runs": [{"name": "on"}, {"name": "off"}]}
    recs = [rec("on-1", "crash", 7.5), rec("off-1", "pass"), rec("on-2", "pass"), rec("off-2", "coverage_fail")]
    text = write_report(Path(d), plan, recs, None, True, {}).read_text()
    assert "## Configurations" in text
    assert "| on | 2 | 1 | 1 | 0 | 0 | 0 | 0 | 7.5 | crashes |" in text, text
    assert "| off | 2 | 0 | 1 | 0 | 1 | 0 | 0 |  | inconclusive |" in text, text
    old = {k: v for k, v in rec("on-3", "pass").items() if k not in ("counts", "missing")}
    write_report(Path(d), plan, [old], None, True, {})
assert classify([rec("a-1", "pass")] * 4 + [rec("a-5", "load_crash", 2)]) == "inconclusive", "a load crash isn't a crash"

from soak.report import classify as _classify
assert _classify([{"verdict": "exit_crash"}] * 3 + [{"verdict": "pass"}] * 2) == "clean at 50%"
assert _classify([{"verdict": "exit_crash"}, {"verdict": "crash"}]) == "crashes"
print("RESULT: PASS")
