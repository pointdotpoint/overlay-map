"""scripts/soak/lock.py and deploy.sh: one lock on the game folder."""
import os, subprocess, sys, tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))
from soak.lock import DeployLock, LockBusy

with tempfile.TemporaryDirectory() as d:
    game = Path(d) / "game"
    (game / "r6/scripts").mkdir(parents=True)
    path = game / ".pmui-deploy.lock"
    a = DeployLock(path)
    assert a.is_free()
    a.acquire("soak campaign test")
    assert not DeployLock(path).is_free()
    try:
        DeployLock(path).acquire("second")
        raise AssertionError("a second holder got the lock")
    except LockBusy as e:
        assert "soak campaign test" in str(e)
    # deploy.sh refuses while the campaign holds it, and says who holds it.
    env = dict(os.environ, GAME=str(game))
    r = subprocess.run([str(ROOT / "tools/install.sh"), "--uninstall"], env=env, capture_output=True, text=True)
    assert r.returncode != 0 and "soak campaign test" in r.stderr, (r.returncode, r.stderr)
    a.release()
    assert a.is_free() and a.holder() is None
    r = subprocess.run([str(ROOT / "tools/install.sh"), "--uninstall"], env=env, capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
print("RESULT: PASS")
