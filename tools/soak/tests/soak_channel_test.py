import tempfile
"""scripts/soak/channel.py: the supervisor <-> bootstrap files."""
import sys, tempfile
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "scripts"))
from soak.channel import read_beat, read_states, write_command, write_plan, write_shots

with tempfile.TemporaryDirectory() as d:
    ch = Path(d) / "SoakBootstrap"
    # Leftovers from an earlier run are removed by the next plan.
    ch.mkdir()
    (ch / "state.txt").write_text("old\t1\tb0\t0\tworld\t\n")
    (ch / "heartbeat.txt").write_text("old\t9\tworld\t\n")
    (ch / "command.txt").write_text("old\texit\n")
    write_plan(ch, "r1", "b1", "ManualSave-3")
    assert (ch / "plan.txt").read_text() == "run=r1\nbuild=b1\nsave=ManualSave-3\nend=1\n"
    assert not (ch / "state.txt").exists() and not (ch / "heartbeat.txt").exists()
    assert not (ch / "command.txt").exists()

    (ch / "state.txt").write_text(
        "r1\t1\tb1\t0\tmenu\t\n"
        "other\t1\tb1\t0\tworld\t\n"         # another run: ignored
        "r1\tx\tb1\t0\tbad\t\n"              # malformed: ignored
        "r1\t2\tb1\t0\tsaves\t2:A,B\n"
        "r1\t2\tb1\t0\tdup\t\n"               # seq not increasing: ignored
        "r1\t3\tb9\t4\tworld\t\n"             # another build: kept (the runner flags it)
        "r1\t4\tb1\t5\tphotomode_open")       # no newline yet: partial, ignored
    states = read_states(ch, "r1")
    assert [s.state for s in states] == ["menu", "saves", "world"], states
    assert states[1].detail == "2:A,B" and states[2].build == "b9" and states[2].beats == 4

    assert read_beat(ch, "r1") is None
    (ch / "heartbeat.txt").write_text("r1\t7\tphotomode\t1.5,-2.25,3.0\n")
    b = read_beat(ch, "r1")
    assert b.count == 7 and b.mode == "photomode" and b.camera == (1.5, -2.25, 3.0)
    (ch / "heartbeat.txt").write_text("r1\t8\tworld\t\n")
    assert read_beat(ch, "r1").camera is None
    (ch / "heartbeat.txt").write_text("r1\t9\tworld\t")          # partial
    assert read_beat(ch, "r1") is None
    assert read_beat(ch, "r2") is None

    write_command(ch, "r1", "exit")
    assert (ch / "command.txt").read_text() == "r1\texit\n"
from soak.channel import ActionLine, action_counts, read_actions
with tempfile.TemporaryDirectory() as d3:
    ch = Path(d3)
    write_plan(ch, "r2", "b2", "QuickSave-9", extra={"recipe": "transitions", "seed": "7"})
    plan = (ch / "plan.txt").read_text()
    assert plan == "run=r2\nbuild=b2\nsave=QuickSave-9\nrecipe=transitions\nseed=7\nend=1\n", plan
    (ch / "actions.txt").write_text(
        "r2\t1\t100\t1\tlook\tattempted\t\n"
        "r2\t2\t100\t1\tlook\taccepted\tcamera\n"
        "r1\t3\t101\t1\tlook\tcompleted\t\n"            # another run: ignored
        "r2\t3\t130\t1\tlook\tcompleted\t\n"
        "r2\t4\t131\t2\tspawn\tattempted\t\n"
        "r2\t5\t131\t2\tspawn\tskipped\tno empty slot\n"
        "r2\t6\t140\t3\tpose\tattempted")               # no newline: still being written
    lines = read_actions(ch, "r2")
    assert [l.seq for l in lines] == [1, 2, 3, 4, 5]
    assert lines[1] == ActionLine("r2", 2, 100, 1, "look", "accepted", "camera")
    c = action_counts(lines)
    assert c["look:completed"] == 1 and c["spawn:skipped"] == 1 and c["look:attempted"] == 1

# shots.txt: how many pictures the supervisor has taken; a new plan clears it.
with tempfile.TemporaryDirectory() as d:
    ch = Path(d) / "SoakBootstrap"
    write_shots(ch, "r1", 3)
    assert (ch / "shots.txt").read_text() == "r1\t3\n"
    write_shots(ch, "r1", 4)
    assert (ch / "shots.txt").read_text() == "r1\t4\n" and not (ch / "shots.tmp").exists()
    write_plan(ch, "r2", "b1", "ManualSave-3")
    assert not (ch / "shots.txt").exists()
print("RESULT: PASS")
