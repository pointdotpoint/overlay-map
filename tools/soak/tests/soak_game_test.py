"""scripts/soak/game.py: process discovery by argv[0], xdotool calls, held keys always released."""
import subprocess, sys, tempfile
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "scripts"))
from soak.game import GameControl, steam_running

with tempfile.TemporaryDirectory() as d:
    proc = Path(d)
    def fake_proc(pid, argv):
        (proc / str(pid)).mkdir()
        (proc / str(pid) / "cmdline").write_bytes(b"\0".join(a.encode() for a in argv) + b"\0")
    fake_proc(100, ["S:\\steamapps\\common\\Cyberpunk 2077\\bin\\x64\\Cyberpunk2077.exe"])
    fake_proc(101, ["/usr/bin/zsh", "-c", "pgrep Cyberpunk2077.exe"])   # mentions it, isn't it
    fake_proc(102, ["/home/u/.local/share/Steam/ubuntu12_32/steam", "-silent"])
    (proc / "self").mkdir()

    calls = []
    active = {"id": "42"}
    def cmd(args, timeout=10.0):
        calls.append(args)
        out = ""
        if args[:3] == ["xdotool", "search", "--class"]:
            out = "41\n42\n43\n"                          # the probe: helper windows share the class
        elif args[:2] == ["xdotool", "getwindowname"]:
            out = {"41": "", "42": "Cyberpunk 2077 (C) 2020 by CD Projekt RED", "43": "Default IME"}[args[2]] + "\n"
        elif args == ["xdotool", "getactivewindow"]:
            out = active["id"] + "\n"
        elif args[:2] == ["gdbus", "call"] and "org.kde.kwin.Script.run" in args:
            active["id"] = active.get("kwin_gives", active["id"])
        elif args[:2] == ["gdbus", "call"] and "org.kde.kwin.Scripting.loadScript" in args:
            out = "(1,)\n"
        return subprocess.CompletedProcess(args, 0, out, "")
    spawned = []
    g = GameControl(cmd=cmd, spawn=lambda a, **k: spawned.append(a), proc=proc, sleep=lambda s: None)
    assert g.pids() == [100] and g.running()
    assert steam_running(proc)
    g.launch()
    assert spawned == [["steam", "-applaunch", "1091500", "-skipStartScreen"]]
    assert g.window() == "42"
    assert g.key("n")
    assert ["xdotool", "windowactivate", "--sync", "42"] in calls and ["xdotool", "key", "n"] in calls
    active["id"] = "7"                                   # focus didn't stick, KWin can't help: no key sent
    calls.clear()
    assert not g.key("n") and ["xdotool", "key", "n"] not in calls
    active["kwin_gives"] = "42"                          # a Wayland window had focus: KWin scripting takes it back
    calls.clear()
    assert g.key("n") and ["xdotool", "key", "n"] in calls
    assert any(c[:2] == ["gdbus", "call"] and "org.kde.kwin.Script.run" in c for c in calls)
    assert any(c[:2] == ["gdbus", "call"] and "org.kde.kwin.Scripting.unloadScript" in c for c in calls), "script unloaded"
    del active["kwin_gives"]
    calls.clear()
    assert g.screenshot(proc / "shot.png")
    assert calls[-1][:3] == ["import", "-window", "42"], calls[-1]   # the game window: root fails on Wayland
    active["id"] = "42"
    calls.clear()
    assert g.hold("w", 1.5)
    assert calls[-1] == ["xdotool", "keyup", "w"] and not g.held
    def boom(s):
        raise KeyboardInterrupt
    g2 = GameControl(cmd=cmd, spawn=lambda a, **k: None, proc=proc, sleep=boom)
    try:
        g2.hold("a", 2.0)
    except KeyboardInterrupt:
        pass
    assert not g2.held and calls[-1] == ["xdotool", "keyup", "a"], "released even when interrupted"

# Gamescope mode: the game on its own headless display, so the desktop keeps its focus.
gs = Path(tempfile.mkdtemp())
lock = gs / "game/.pmui-deploy.lock"
gcalls = []
def gcmd(args, timeout=10.0):
    gcalls.append(args)
    inner = args[2:] if args[:1] == ["env"] else args
    out = ""
    if inner[:3] == ["xdotool", "search", "--class"]:
        out = "5\n6\n"
    elif inner[:2] == ["xdotool", "getwindowname"]:
        out = {"5": "Default IME", "6": "Cyberpunk 2077 (C) 2020 by CD Projekt RED"}[inner[2]] + "\n"
    elif inner == ["xdotool", "getactivewindow"]:
        out = "6\n"
    elif inner[:2] == ["gamescopectl", "screenshot"]:
        Path(inner[2]).write_bytes(b"png")
    return subprocess.CompletedProcess(args, 0, out, "")
gspawned = []
gg = GameControl(cmd=gcmd, spawn=lambda a, **k: gspawned.append(a), proc=proc, sleep=lambda s: None,
                 gamescope=gs, lock=lock)
(gs / "gamescope.display").write_text(":9\n")              # left from an earlier launch
gg.launch()
assert (gs / "gamescope.flag").read_text().split() == ["2560", "1440", "headless", str(lock)]
assert not (gs / "gamescope.display").exists(), "a stale display is never used"
assert gspawned and gg.window() is None, "no display yet: no window"
(gs / "gamescope.display").write_text(":2\n")
gcalls.clear()
assert gg.window() == "6"
assert gcalls[0][:2] == ["env", "DISPLAY=:2"], gcalls[0]
gcalls.clear()
assert gg.key("n")
assert ["env", "DISPLAY=:2", "xdotool", "key", "n"] in gcalls
assert not any("windowactivate" in c or c[:1] == ["gdbus"] for c in gcalls), "gamescope focuses the game itself"
assert gg.hold("w", 1.0) and gcalls[-1] == ["env", "DISPLAY=:2", "xdotool", "keyup", "w"]
assert gg.screenshot(gs / "shots/a.png") and (gs / "shots/a.png").exists()
assert ["gamescopectl", "screenshot", str(gs / "shots/a.png")] in gcalls
gg.clear()
assert not (gs / "gamescope.flag").exists() and not (gs / "gamescope.display").exists()

# After a crash, the crash reporter keeps Steam's launch session (and gamescope) alive, and Steam then
# ignores the next launch (the smoke run, 2026-10-14): kill() ends the whole session.
import shutil as _sh
kp = Path(tempfile.mkdtemp())
def kproc(pid, argv):
    (kp / str(pid)).mkdir()
    (kp / str(pid) / "cmdline").write_bytes(b"\0".join(a.encode() for a in argv) + b"\0")
kproc(300, ["S:\\steamapps\\common\\Cyberpunk 2077\\bin\\x64\\CrashReporter\\CrashReporter.exe"])
kproc(301, ["/home/u/.local/share/Steam/ubuntu12_32/reaper", "SteamLaunch", "AppId=1091500", "--", "x"])
kproc(302, ["/home/u/.local/share/Steam/ubuntu12_32/reaper", "SteamLaunch", "AppId=999", "--", "y"])   # another game
killed = []
def fake_kill(pid, sig):
    killed.append(pid)
    _sh.rmtree(kp / str(pid))
kg = GameControl(cmd=cmd, spawn=lambda a, **k: None, proc=kp, sleep=lambda s: None, os_kill=fake_kill)
assert not kg.running() and kg.session_alive()
kg.kill(wait=0.5)
assert 300 in killed and not kg.session_alive(), killed
assert 302 not in killed, "another game's session is never touched"
print("RESULT: PASS")
