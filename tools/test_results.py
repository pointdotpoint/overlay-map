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
    good.write_text(_tiles() * 3)
    bad = tmp_path / "bad.log"
    bad.write_text((_tiles().replace("frame_avg=22.5", "frame_avg=24.0")) * 3)
    part = tmp_path / "part.log"
    part.write_text(LOG.replace("PERF|SUITE|done", ""))
    run = lambda p: subprocess.run([sys.executable, str(script), str(p)], capture_output=True, text=True)
    assert run(good).returncode == 0
    assert run(bad).returncode == 1
    short = tmp_path / "short.log"
    short.write_text(_tiles())
    r = run(short)
    assert r.returncode == 2 and "INCONCLUSIVE: 1 of 3 valid runs" in r.stdout
    r = run(part)
    assert r.returncode == 1 and "incomplete suite" in r.stdout


def _row(name, avg, p95, script_avg=0.1, script_p95=0.2, extra=""):
    return (f"[t] [1] [NightMap] RESULT|{name}|items=0|frames=300|setup_ms=0|frame_avg={avg}|frame_p95={p95}"
            f"|frame_p99=40.0|frame_max=60.0|script_avg={script_avg}|script_p95={script_p95}{extra}\n")


def _tiles(idle_avg=20.5, idle_p95=30.5, sweep_avg=21.0, sweep_p95=31.5, skip=(), open_avg=None, open_p95=None, end_avg=20.0, vanilla_avg=None, vanilla_p95=None,
           open_script=(0.4, 1.0), van_script=(0.8, 2.0), poll=0.5, poll_field=True, van_script_fields=True):
    rows = {"idle_0p5": (idle_avg, idle_p95), "idle_2": (idle_avg, idle_p95), "idle_8": (idle_avg, idle_p95),
            "open_empty": (open_avg or sweep_avg, open_p95 or sweep_p95),
            "vanilla_open": (vanilla_avg or open_avg or sweep_avg, vanilla_p95 or open_p95 or sweep_p95), "panzoom_0p5_16": (sweep_avg, sweep_p95),
            "closed_end": (end_avg, 29.0)}
    def row(n, a, p):
        if n == "open_empty":
            return _row(n, a, p, *open_script)
        if n == "vanilla_open":
            line = _row(n, a, p, *van_script, extra=f"|poll_ms_max={poll}" if poll_field else "")
            return line if van_script_fields else line.replace(f"|script_avg={van_script[0]}", "")
        return _row(n, a, p)
    body = "".join(row(n, a, p) for n, (a, p) in rows.items() if n not in skip)
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


def _suites(*suites):
    return results.parse_suites("".join(suites))


def test_open_empty_is_gated_with_the_sweep_budget():
    ok, msg = results.verdict(results.parse(_tiles(open_avg=21.5, open_p95=32.0)))
    assert ok, msg
    ok, msg = results.verdict(results.parse(_tiles(open_avg=21.51)))
    assert not ok and "open_empty" in msg and "OVER" in msg
    ok, msg = results.verdict(results.parse(_tiles(open_p95=32.01)))
    assert not ok and "open_empty" in msg
    ok, msg = results.verdict(results.parse(_tiles(skip=("open_empty",))))
    assert not ok and "open_empty: row missing" in msg


def test_median_of_three_runs_ignores_one_outlier():
    s = _suites(_tiles(idle_avg=22.5), _tiles(), _tiles())          # one run over budget, two fine -> median fine
    status, msg = results.judge(s, 3)
    assert status == "PASS", msg
    s = _suites(_tiles(idle_avg=22.5), _tiles(idle_avg=22.5), _tiles())     # two over budget -> median over
    status, msg = results.judge(s, 3)
    assert status == "FAIL" and "idle_0p5" in msg and "OVER" in msg


def test_judge_uses_only_the_last_n_runs():
    s = _suites(_tiles(idle_avg=25.0), _tiles(), _tiles(), _tiles())
    assert results.judge(s, 3)[0] == "PASS"


def test_drifted_runs_are_excluded_and_listed():
    s = _suites(_tiles(), _tiles(end_avg=18.5), _tiles(), _tiles())          # run 2 drifted by 1.5 ms
    status, msg = results.judge(s, 3)
    assert status == "PASS" and "run 2 drifted" in msg
    s = _suites(_tiles(), _tiles(end_avg=18.5), _tiles(end_avg=21.0), _tiles())
    status, msg = results.judge(s, 3)
    assert status == "INCONCLUSIVE" and msg.startswith("2 of 3 valid runs") and "run 3 drifted" in msg


def test_inconclusive_with_too_few_runs_and_exit_code(tmp_path):
    import subprocess, sys
    assert results.judge(_suites(_tiles(), _tiles()), 3)[1].startswith("2 of 3 valid runs")
    assert results.judge(_suites(_tiles(), _tiles()), 2)[0] == "PASS"
    log = tmp_path / "d.log"
    log.write_text(_tiles() * 2)
    script = Path(__file__).with_name("results.py")
    r = subprocess.run([sys.executable, str(script), str(log), "--runs", "2"], capture_output=True, text=True)
    assert r.returncode == 0 and "medians" in r.stdout and "PASS" in r.stdout
    r = subprocess.run([sys.executable, str(script), str(log)], capture_output=True, text=True)
    assert r.returncode == 2 and "INCONCLUSIVE: 2 of 3 valid runs" in r.stdout


def test_missing_row_in_a_valid_run_fails():
    status, msg = results.judge(_suites(_tiles(), _tiles(skip=("open_empty",)), _tiles()), 3)
    assert status == "FAIL" and "open_empty: row missing" in msg


def test_only_the_current_game_session_is_judged(tmp_path):
    import subprocess, sys
    loaded = "[t] [1] [NightMap] loaded (tiles present, precise clock true)\n"
    log = tmp_path / "s.log"
    log.write_text(loaded + _tiles(idle_avg=25.0) * 3 + loaded + _tiles() * 3)   # old session over budget, new fine
    script = Path(__file__).with_name("results.py")
    r = subprocess.run([sys.executable, str(script), str(log)], capture_output=True, text=True)
    assert r.returncode == 0 and "PASS" in r.stdout and "in this session" in r.stdout
    log.write_text(loaded + _tiles() * 2 + loaded + _tiles())                    # new session has 1 run
    r = subprocess.run([sys.executable, str(script), str(log)], capture_output=True, text=True)
    assert r.returncode == 2 and "INCONCLUSIVE: 1 of 3 valid runs" in r.stdout
    r = subprocess.run([sys.executable, str(script), str(log), "--all-sessions"], capture_output=True, text=True)
    assert r.returncode == 0


def test_runs_must_be_positive(tmp_path):
    import subprocess, sys, pytest
    with pytest.raises(ValueError):
        results.judge(_suites(_tiles()), 0)
    log = tmp_path / "z.log"
    log.write_text(_tiles())
    r = subprocess.run([sys.executable, str(Path(__file__).with_name("results.py")), str(log), "--runs", "0"],
                       capture_output=True, text=True)
    assert r.returncode == 2 and "--runs must be >= 1" in r.stderr


def test_medians_table_uses_the_judged_runs():
    s = _suites(_tiles(), _tiles(), _tiles(end_avg=18.5), _tiles())              # newest-but-one drifted
    valid, skipped = results.select_valid(s, 3)
    assert len(valid) == 3 and skipped and "run 3 drifted" in skipped[0]


def test_vanilla_open_is_gated_with_the_sweep_budget():
    ok = results.verdict(results.parse(_tiles(vanilla_avg=21.4, vanilla_p95=31.9)))
    assert ok[0], ok[1]
    bad = results.verdict(results.parse(_tiles(vanilla_avg=21.6)))
    assert not bad[0] and "vanilla_open" in bad[1]


def test_missing_vanilla_row_fails():
    status, msg = results.judge(_suites(_tiles(), _tiles(skip=("vanilla_open",)), _tiles()), 3)
    assert status == "FAIL" and "vanilla_open: row missing" in msg


def test_vanilla_script_gates_pass_at_and_inside_the_margins():
    ok, msg = results.verdict(results.parse(_tiles(open_script=(0.4, 1.0), van_script=(0.9, 2.5), poll=1.0)))
    assert ok, msg
    assert "vanilla_open script" in msg and "poll_ms_max 1.00" in msg


def test_vanilla_script_avg_over_margin_fails():
    ok, msg = results.verdict(results.parse(_tiles(van_script=(0.91, 2.0))))
    assert not ok and "vanilla_open script: avg +0.51" in msg and "OVER" in msg


def test_vanilla_script_p95_over_margin_fails():
    ok, msg = results.verdict(results.parse(_tiles(van_script=(0.8, 2.51))))
    assert not ok and "p95 +1.51" in msg and "OVER" in msg


def test_vanilla_poll_over_budget_fails():
    ok, msg = results.verdict(results.parse(_tiles(poll=1.01)))
    assert not ok and "poll_ms_max 1.01 ms (budget 1.0) OVER" in msg


def test_vanilla_missing_poll_field_fails():
    ok, msg = results.verdict(results.parse(_tiles(poll_field=False)))
    assert not ok and "vanilla_open: lacks script_avg/script_p95/poll_ms_max" in msg
    status, msg = results.judge(_suites(_tiles(), _tiles(poll_field=False), _tiles()), 3)
    assert status == "FAIL" and "lacks" in msg


def test_vanilla_missing_script_field_fails():
    ok, msg = results.verdict(results.parse(_tiles(van_script_fields=False)))
    assert not ok and "lacks" in msg


def test_vanilla_script_gates_use_the_median_of_the_runs():
    over = dict(van_script=(2.0, 5.0), poll=3.0)
    status, msg = results.judge(_suites(_tiles(**over), _tiles(), _tiles()), 3)
    assert status == "PASS", msg                      # one outlier run
    status, msg = results.judge(_suites(_tiles(**over), _tiles(**over), _tiles()), 3)
    assert status == "FAIL" and "vanilla_open script" in msg and "OVER" in msg


def test_script_gate_compares_against_open_empty_of_the_same_run():
    ok, msg = results.verdict(results.parse(_tiles(open_script=(2.0, 5.0), van_script=(2.4, 6.4))))
    assert ok, msg
    ok, msg = results.verdict(results.parse(_tiles(open_script=(2.0, 5.0), van_script=(2.6, 6.4))))
    assert not ok
