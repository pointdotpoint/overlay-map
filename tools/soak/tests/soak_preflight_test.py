"""scripts/soak/preflight.py: refuse to start unless the machine is ready for an unattended campaign."""
import sys, tempfile
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "scripts"))
from soak.paths import Paths
from soak.preflight import cloud_enabled, run_preflight

VDF = '''"UserRoamingConfigStore"
{
	"Software"
	{
		"Valve"
		{
			"Steam"
			{
				"apps"
				{
					"1091500"
					{
						"cloudenabled"		"%s"
						"other"		"1"
					}
					"292030"
					{
						"cloudenabled"		"1"
					}
				}
			}
		}
	}
}
'''

class Game:
    def __init__(self, running): self._r = running
    def running(self): return self._r

with tempfile.TemporaryDirectory() as d:
    root = Path(d)
    p = Paths(game=root / "game", user=root / "user", steam=root / "steam", soak=root / "soak", repo=root)
    cfg = p.steam / "userdata/123/7/remote/sharedconfig.vdf"
    cfg.parent.mkdir(parents=True)
    cfg.write_text(VDF % "1")
    assert cloud_enabled(p.steam) is True
    cfg.write_text(VDF % "0")
    assert cloud_enabled(p.steam) is False, "only the game's own block counts"
    (p.steam / "steamapps").mkdir(parents=True)
    (p.steam / "steamapps/appmanifest_1091500.acf").write_text('"AppState"\n{\n\t"StateFlags"\t\t"4"\n\t"buildid"\t\t"1"\n}\n')
    (p.saves / "ManualSave-1").mkdir(parents=True)
    p.game.mkdir(parents=True)
    proc = root / "proc"
    (proc / "5").mkdir(parents=True)
    (proc / "5/cmdline").write_bytes(b"/x/ubuntu12_32/steam\0")
    checks = {c.name: c for c in run_preflight(p, "ManualSave-1", Game(False), lock_free=True, min_free_gb=0.0, proc=proc)}
    must_pass = ["steam running", "steam cloud off", "game installed and updated", "free disk",
                 "game closed", "deploy lock free", "test save exists"]
    for name in must_pass:
        assert checks[name].ok, (name, checks[name].detail)
    bad = {c.name: c for c in run_preflight(p, "ManualSave-9", Game(True), lock_free=False, min_free_gb=1e9, proc=proc)}
    for name in ["free disk", "game closed", "deploy lock free", "test save exists"]:
        assert not bad[name].ok, name
    cfg.write_text(VDF % "1")
    assert not {c.name: c for c in run_preflight(p, "ManualSave-1", Game(False), True, 0.0, proc)}["steam cloud off"].ok
from soak.preflight import Check, waive
w = waive([Check("steam cloud off", False, "turn it off"), Check("game closed", False, "close it")], {"steam cloud off"})
assert w[0].ok and w[0].detail == "waived by the user", w[0]
assert not w[1].ok, "only the named check is waived"
from soak.preflight import launch_options
with tempfile.TemporaryDirectory() as d2:
    st = Path(d2)
    cfg = st / "userdata/1/config/localconfig.vdf"
    cfg.parent.mkdir(parents=True)
    cfg.write_text('"UserLocalConfigStore"\n{\n\t"apps"\n\t{\n\t\t"1091500"\n\t\t{\n\t\t\t"cloud"\t\t"1"\n\t\t}\n\t}\n'
                   '\t"Software"\n\t{\n\t\t"1091500"\n\t\t{\n\t\t\t"LaunchOptions"\t\t"MANGOHUD=1 gamemoderun '
                   '/r/scripts/soak/gamescope-wrap.sh %command% --launcher-skip"\n\t\t}\n\t}\n}\n')
    assert launch_options(st) == ["MANGOHUD=1 gamemoderun /r/scripts/soak/gamescope-wrap.sh %command% --launcher-skip"]
    class GsGame:
        gamescope = Path("/x")
        def running(self): return False
    gsc = {c.name: c for c in run_preflight(Paths(game=st / "g", user=st / "u", steam=st, soak=st / "s", repo=st),
                                            "ManualSave-1", GsGame(), True, 0.0, Path("/proc"))}
    assert gsc["gamescope wrapper in launch options"].ok, gsc["gamescope wrapper in launch options"]
    cfg.write_text(cfg.read_text().replace("/r/scripts/soak/gamescope-wrap.sh ", ""))
    gsc = {c.name: c for c in run_preflight(Paths(game=st / "g", user=st / "u", steam=st, soak=st / "s", repo=st),
                                            "ManualSave-1", GsGame(), True, 0.0, Path("/proc"))}
    assert not gsc["gamescope wrapper in launch options"].ok
    assert "gamescope wrapper in launch options" not in {c.name for c in run_preflight(
        Paths(game=st / "g", user=st / "u", steam=st, soak=st / "s", repo=st), "ManualSave-1", Game(False), True, 0.0, Path("/proc"))}

# A game still shutting down (the last run's kill) gets up to closing_wait seconds to close.
class Closing:
    def __init__(self, n): self.n = n
    def running(self):
        self.n -= 1
        return self.n >= 0
slept = []
c = {c.name: c for c in run_preflight(p, "ManualSave-1", Closing(3), lock_free=True, min_free_gb=0.0, proc=Path("/proc"),
                                      closing_wait=60.0, sleep=slept.append)}
assert c["game closed"].ok and sum(slept) <= 60.0 and slept, slept
slept = []
c = {c.name: c for c in run_preflight(p, "ManualSave-1", Closing(10**6), lock_free=True, min_free_gb=0.0, proc=Path("/proc"),
                                      closing_wait=60.0, sleep=slept.append)}
assert not c["game closed"].ok and abs(sum(slept) - 60.0) < 5.1, sum(slept)
print("RESULT: PASS")
