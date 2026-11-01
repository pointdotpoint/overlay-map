"""tools/soak/campaign.py: a campaign only kills a game it launched, never one the player started."""
import sys, tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))
from soak.campaign import run_campaign
from soak.paths import Paths
from soak.preflight import Check

PLAN = {"name": "t", "runs": [{"name": "r", "steps": [{"wait": 1}]}]}


class FakeGame:
    def __init__(self, running):
        self.is_running, self.kills = running, 0

    def running(self):
        return self.is_running

    def release_all(self):
        pass

    def kill(self):
        self.kills += 1
        self.is_running = False


class FakeLock:
    def acquire(self, owner):
        pass

    def release(self):
        pass


def campaign(game, checks, stop):
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        for sub in ("game", "user", "steam", "soak"):
            (root / sub).mkdir()
        paths = Paths(game=root / "game", user=root / "user", steam=root / "steam", soak=root / "soak")
        report = run_campaign(PLAN, "QuickSave-7", paths, game, runner=None, lock=FakeLock(),
                              preflight=lambda *a, **k: checks, stage=None, collect=None,
                              stop=stop, log=lambda *a: None, name="t")
        return (report / "report.md").read_text() if report.is_dir() else report.read_text()


# The player's game is open: preflight fails, and the campaign must leave that game alone.
player = FakeGame(running=True)
text = campaign(player, [Check("game closed", False, "close the game")], stop=lambda: False)
assert "preflight failed" in text, text
assert player.kills == 0, "killed a game the campaign never launched"
assert player.is_running

# Preflight passed (no game was running), so a game running at the end is the campaign's own: kill it.
own = FakeGame(running=False)
def stop_after_launch():
    own.is_running = True       # stands in for the campaign's run having started the game
    return True
campaign(own, [Check("game closed", True, "")], stop=stop_after_launch)
assert own.kills == 1, "left the campaign's own game running"

print("RESULT: PASS")
