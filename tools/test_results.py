import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location("results", Path(__file__).with_name("results.py"))
results = importlib.util.module_from_spec(spec)
spec.loader.exec_module(results)

LOG = """
[t] [1] [NightMap] PERF|SUITE|start
[t] [1] [NightMap] RESULT|closed_baseline|items=0|frames=300|setup_ms=0.1|frame_avg=20.0|frame_p95=29.0|frame_p99=40.0|frame_max=60.0|script_avg=0.01|script_p95=0.02
[t] [1] [NightMap] RESULT|items_50000|items=50000|frames=300|setup_ms=900.0|frame_avg=22.5|frame_p95=33.0|frame_p99=45.0|frame_max=70.0|script_avg=1.9|script_p95=3.0
[t] [1] [NightMap] PERF|SUITE|done
"""


def test_parse_reads_latest_suite():
    rows = results.parse("[t] [1] [NightMap] RESULT|old|items=1|frames=1|setup_ms=0|frame_avg=1|frame_p95=1|frame_p99=1|frame_max=1|script_avg=0|script_p95=0\n" + LOG)
    assert [r["name"] for r in rows] == ["closed_baseline", "items_50000"]
    assert rows[1]["frame_avg"] == 22.5


def test_verdict_pass_and_fail():
    ok, msg = results.verdict(results.parse(LOG))
    assert ok, msg
    bad = LOG.replace("frame_avg=22.5", "frame_avg=24.0")
    ok, msg = results.verdict(results.parse(bad))
    assert not ok and "avg" in msg


def test_verdict_requires_both_rows():
    ok, msg = results.verdict([])
    assert not ok
