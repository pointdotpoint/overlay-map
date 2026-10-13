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
    ok, msg = results.verdict(results.parse(_tiles()))
    assert ok, msg
    bad = _tiles().replace("frame_avg=22.5", "frame_avg=24.0")
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
    good.write_text(_tiles())
    bad = tmp_path / "bad.log"
    bad.write_text(_tiles().replace("frame_avg=22.5", "frame_avg=24.0"))
    part = tmp_path / "part.log"
    part.write_text(LOG.replace("PERF|SUITE|done", ""))
    run = lambda p: subprocess.run([sys.executable, str(script), str(p)], capture_output=True, text=True)
    assert run(good).returncode == 0
    assert run(bad).returncode == 1
    r = run(part)
    assert r.returncode == 1 and "incomplete suite" in r.stdout


def _row(name, avg, p95):
    return (f"[t] [1] [NightMap] RESULT|{name}|items=0|frames=300|setup_ms=0|frame_avg={avg}|frame_p95={p95}"
            "|frame_p99=40.0|frame_max=60.0|script_avg=0.1|script_p95=0.2\n")


def _tiles(idle_avg=20.5, idle_p95=30.5, sweep_avg=21.0, sweep_p95=31.5, skip=()):
    rows = {"idle_0p5": (idle_avg, idle_p95), "idle_2": (idle_avg, idle_p95), "idle_8": (idle_avg, idle_p95),
            "panzoom_0p5_16": (sweep_avg, sweep_p95)}
    body = "".join(_row(n, a, p) for n, (a, p) in rows.items() if n not in skip)
    return LOG.replace("[t] [1] [NightMap] PERF|SUITE|done", body + "[t] [1] [NightMap] PERF|SUITE|done")


def test_tile_rows_pass_within_budget():
    # base avg 20.0 / p95 29.0: idle +0.5/+1.5, sweep +1.0/+2.5
    ok, msg = results.verdict(results.parse(_tiles()))
    assert ok, msg
    assert "idle_0p5" in msg and "panzoom_0p5_16" in msg


def test_idle_over_budget_fails():
    ok, msg = results.verdict(results.parse(_tiles(idle_avg=21.01)))
    assert not ok and "idle_0p5" in msg
    ok, msg = results.verdict(results.parse(_tiles(idle_p95=31.01)))
    assert not ok and "idle_8" in msg


def test_sweep_over_budget_fails():
    ok, msg = results.verdict(results.parse(_tiles(sweep_avg=21.51)))
    assert not ok and "panzoom_0p5_16" in msg
    ok, msg = results.verdict(results.parse(_tiles(sweep_p95=32.01)))
    assert not ok and "panzoom_0p5_16" in msg


def test_budget_boundaries():
    ok, msg = results.verdict(results.parse(_tiles(idle_avg=21.0, idle_p95=31.0, sweep_avg=21.5, sweep_p95=32.0)))
    assert ok, msg


def test_missing_tile_row_fails():
    ok, msg = results.verdict(results.parse(_tiles(skip=("idle_2",))))
    assert not ok and "idle_2: row missing" in msg
    ok, msg = results.verdict(results.parse(LOG))
    assert not ok and "panzoom_0p5_16: row missing" in msg


def test_cli_truncated_tile_row_fails(tmp_path):
    import subprocess, sys
    script = Path(__file__).with_name("results.py")
    log = tmp_path / "trunc.log"
    log.write_text(_tiles().replace("|frame_p95=30.5", "", 1))
    r = subprocess.run([sys.executable, str(script), str(log)], capture_output=True, text=True)
    assert r.returncode == 1 and "idle_0p5" in r.stdout
