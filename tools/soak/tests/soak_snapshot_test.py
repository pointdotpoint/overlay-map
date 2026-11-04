"""scripts/soak/snapshot.py: back up once, swap builds in, put everything back (even from a new process)."""
import sys, tempfile
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "scripts"))
from soak.paths import PARTS, Paths, rels, tree_hash
from soak.snapshot import Snapshot, latest_unrestored

ALL = rels(list(PARTS))

def fake_paths(root: Path) -> Paths:
    return Paths(game=root / "game", user=root / "user", steam=root / "steam", soak=root / "soak", repo=root)

with tempfile.TemporaryDirectory() as d:
    root = Path(d)
    p = fake_paths(root)
    # The normal install: the mod's scripts and ACM present, the bootstrap absent.
    (p.game / "r6/scripts/OverlayMap").mkdir(parents=True)
    (p.game / "r6/scripts/OverlayMap/A.reds").write_text("normal")
    p.persistent.parent.mkdir(parents=True)
    p.persistent.write_text("favorites")
    (p.saves / "ManualSave-1").mkdir(parents=True)
    (p.saves / "ManualSave-1/sav.dat").write_text("save")
    before = tree_hash(p.game, ALL)

    s = Snapshot(p, "c1")
    s.take()
    s.take()  # idempotent
    assert s.journal["present"]["r6/scripts/OverlayMap"] is True
    assert s.journal["present"]["r6/scripts/SoakBootstrap"] is False

    # A build: test scripts + the bootstrap, no ACM.
    build = root / "build"
    (build / "r6/scripts/OverlayMap").mkdir(parents=True)
    (build / "r6/scripts/OverlayMap/A.reds").write_text("test")
    (build / "r6/scripts/SoakBootstrap").mkdir(parents=True)
    (build / "r6/scripts/SoakBootstrap/B.reds").write_text("boot")
    s.install(build, "b1")
    assert (p.game / "r6/scripts/OverlayMap/A.reds").read_text() == "test"
    assert (p.game / "r6/scripts/SoakBootstrap/B.reds").exists()
    assert s.verify_installed()
    # A foreign writer between runs is noticed.
    (p.game / "r6/scripts/OverlayMap/A.reds").write_text("other session")
    assert not s.verify_installed()
    s.install(build, "b1")
    assert s.verify_installed()

    # Per-run data reset: Codeware's data back to the snapshot, the channel gone.
    p.persistent.write_text("rewritten by Codeware on exit")
    p.channel.mkdir(parents=True)
    (p.channel / "state.txt").write_text("x")
    s.reset_run_data()
    assert p.persistent.read_text() == "favorites" and not p.channel.exists()

    # A save changed during a run: restored and reported.
    assert s.check_saves()
    (p.saves / "AutoSave-9").mkdir()
    (p.saves / "AutoSave-9/sav.dat").write_text("auto")
    assert not s.check_saves()
    assert not (p.saves / "AutoSave-9").exists() and (p.saves / "ManualSave-1/sav.dat").read_text() == "save"

    # The supervisor dies here; a new process finds the campaign and restores it.
    assert latest_unrestored(p) == "c1"
    s2 = Snapshot(p, "c1")
    assert s2.restore()
    assert tree_hash(p.game, ALL) == before
    assert not (p.game / "r6/scripts/SoakBootstrap").exists()
    assert latest_unrestored(p) is None

# prune(): staged builds go; restored backups beyond the newest `keep` go; an unrestored one never.
import json as _j, tempfile as _t
from soak.snapshot import prune
with _t.TemporaryDirectory() as dd:
    pp = Paths(game=Path(dd) / "g", user=Path(dd) / "u", steam=Path(dd) / "s", soak=Path(dd) / "soak", repo=Path(dd))
    (pp.soak / "builds/abc").mkdir(parents=True)
    for i, restored in enumerate([True, True, False, True, True]):
        b = pp.soak / "backup" / f"2026101{i}-x"
        b.mkdir(parents=True)
        (b / "journal.json").write_text(_j.dumps({"taken": True, "restored": restored}))
    prune(pp, keep=2)
    left = sorted(x.name for x in (pp.soak / "backup").iterdir())
    assert left == ["20261012-x", "20261013-x", "20261014-x"], left
    assert not (pp.soak / "builds").exists() or not any((pp.soak / "builds").iterdir())
print("RESULT: PASS")
