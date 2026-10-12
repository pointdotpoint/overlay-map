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


def _suite(extra=""):
    return LOG + extra


def test_parse_requires_done_after_last_start():
    partial = LOG + "[t] [1] [NightMap] PERF|SUITE|start\n[t] [1] [NightMap] RESULT|closed_baseline|items=0|frames=300|setup_ms=0.1|frame_avg=1.0|frame_p95=1.0|frame_p99=1.0|frame_max=1.0|script_avg=0|script_p95=0\n"
    try:
        results.parse(partial)
        assert False, "should raise"
    except results.SuiteError as e:
        assert "incomplete suite" in str(e)


def test_parse_no_start_fails():
    try:
        results.parse("[t] [1] [NightMap] RESULT|x|items=1\n")
        assert False
    except results.SuiteError as e:
        assert "no PERF|SUITE|start" in str(e)


def test_missing_baseline():
    ok, msg = results.verdict([r for r in results.parse(LOG) if r["name"] != "closed_baseline"])
    assert not ok and "missing" in msg


def test_malformed_line_skipped(capsys):
    bad = LOG.replace("PERF|SUITE|done", "PERF|SUITE|done\n[t] [1] [NightMap] RESULT|junk|items=abc|frames")
    rows = results.parse(bad)
    assert [r["name"] for r in rows] == ["closed_baseline", "items_50000"]
    assert "malformed" in capsys.readouterr().err


def test_cli_exit_codes(tmp_path):
    import subprocess, sys
    script = Path(results.__file__ if hasattr(results, "__file__") else Path(__file__).with_name("results.py"))
    good = tmp_path / "good.log"
    good.write_text(LOG)
    bad = tmp_path / "bad.log"
    bad.write_text(LOG.replace("frame_avg=22.5", "frame_avg=24.0"))
    part = tmp_path / "part.log"
    part.write_text(LOG.replace("PERF|SUITE|done", ""))
    run = lambda p: subprocess.run([sys.executable, str(script), str(p)], capture_output=True, text=True)
    assert run(good).returncode == 0
    assert run(bad).returncode == 1
    r = run(part)
    assert r.returncode == 1 and "incomplete suite" in r.stdout


VEC = """
[t] [1] [NightMap] PERF|SUITE|start
[t] [1] [NightMap] RESULT|closed_baseline|items=0|frames=300|setup_ms=0.1|frame_avg=20.0|frame_p95=29.0|frame_p99=40.0|frame_max=60.0|script_avg=0.01|script_p95=0.02
[t] [1] [NightMap] RESULT|items_50000|items=50000|frames=300|setup_ms=900.0|frame_avg=22.5|frame_p95=33.0|frame_p99=45.0|frame_max=70.0|script_avg=1.9|script_p95=3.0
[t] [1] [NightMap] RESULT|vector_V0_idle|items=0|frames=300|setup_ms=0|frame_avg=21.5|frame_p95=32.0|frame_p99=40.0|frame_max=60.0|script_avg=0.1|script_p95=0.2
[t] [1] [NightMap] RESULT|vector_panzoom|items=0|frames=300|setup_ms=0|frame_avg=21.0|frame_p95=31.0|frame_p99=40.0|frame_max=60.0|script_avg=0.5|script_p95=1.0
[t] [1] [NightMap] PERF|SUITE|done
"""


def test_vector_rows_pass_within_budget():
    ok, msg = results.verdict(results.parse(VEC))
    assert ok, msg
    assert "vector_V0_idle" in msg and "vector_panzoom" in msg


def test_vector_row_over_budget_fails():
    ok, msg = results.verdict(results.parse(VEC.replace("frame_avg=21.5", "frame_avg=22.5")))
    assert not ok and "vector_V0_idle" in msg


def test_vector_p95_over_budget_fails():
    ok, msg = results.verdict(results.parse(VEC.replace("frame_p95=31.0", "frame_p95=33.5")))
    assert not ok and "vector_panzoom" in msg


def test_cli_truncated_vector_row_fails(tmp_path):
    import subprocess, sys
    script = Path(__file__).with_name("results.py")
    log = tmp_path / "trunc.log"
    log.write_text(VEC.replace("|frame_p95=32.0", ""))
    r = subprocess.run([sys.executable, str(script), str(log)], capture_output=True, text=True)
    assert r.returncode == 1 and "vector_V0_idle" in r.stdout


def test_vector_budget_boundaries():
    # base avg 20.0 / p95 29.0 -> +2.00 / +4.00 is exactly on budget
    ok, msg = results.verdict(results.parse(VEC.replace("frame_avg=21.5", "frame_avg=22.0").replace("frame_p95=32.0", "frame_p95=33.0")))
    assert ok, msg
    ok, msg = results.verdict(results.parse(VEC.replace("frame_avg=21.5", "frame_avg=22.01")))
    assert not ok and "vector_V0_idle" in msg
