"""The game process (found by argv[0], never by a substring), its window and input (xdotool on
XWayland, with KWin scripting for focus; proved in the live probe), and screenshots (ImageMagick
import of the game window)."""
from __future__ import annotations

import os
import signal
import subprocess
import time
from pathlib import Path

from .paths import APP_ID

WINDOW_CLASS = f"steam_app_{APP_ID}"
WINDOW_TITLE = "Cyberpunk 2077"
KWIN_ACTIVATE = """
const list = workspace.windowList ? workspace.windowList() : workspace.clientList();
for (const w of list) {
  if (String(w.resourceClass).toLowerCase() === "%s" && String(w.caption).indexOf("%s") === 0) {
    if (workspace.activeWindow !== undefined) { workspace.activeWindow = w; } else { workspace.activeClient = w; }
  }
}
""" % (WINDOW_CLASS, WINDOW_TITLE)


def run_cmd(args: list[str], timeout: float = 10.0) -> subprocess.CompletedProcess:
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout)


def _cmdlines(proc: Path) -> list[tuple[int, list[str]]]:
    out = []
    for d in proc.iterdir():
        if not d.name.isdigit():
            continue
        try:
            argv = (d / "cmdline").read_bytes().decode(errors="replace").split("\0")
        except OSError:
            continue
        out.append((int(d.name), argv))
    return out


def _argv0_names(proc: Path) -> list[tuple[int, str]]:
    out = []
    for d in proc.iterdir():
        if not d.name.isdigit():
            continue
        try:
            argv0 = (d / "cmdline").read_bytes().split(b"\0")[0].decode(errors="replace")
        except OSError:
            continue
        out.append((int(d.name), argv0.replace("\\", "/").rsplit("/", 1)[-1].lower()))
    return out


def steam_running(proc: Path = Path("/proc")) -> bool:
    return any(name == "steam" for _, name in _argv0_names(proc))


class GameControl:
    """On the desktop (gamescope=None) keys go to the focused game window, so the PC can't be used
    meanwhile. With gamescope=<soak dir> the game runs in a headless gamescope through
    tools/soak/gamescope-wrap.sh (in the game's Steam launch options): its own X display, where
    gamescope keeps the game focused, so the desktop stays free (the gamescope probe, 2026-10-14)."""

    def __init__(self, cmd=run_cmd, spawn=subprocess.Popen, proc: Path = Path("/proc"), sleep=time.sleep,
                 gamescope: Path | None = None, lock: Path | None = None, size: tuple[int, int] = (2560, 1440),
                 os_kill=os.kill):
        self.cmd, self.spawn, self.proc, self.sleep, self.os_kill = cmd, spawn, proc, sleep, os_kill
        self.gamescope, self.lock, self.size = gamescope, lock, size
        self.held: set[str] = set()

    def _display(self) -> str | None:
        try:
            d = (self.gamescope / "gamescope.display").read_text().strip()
        except OSError:
            return None
        return d or None

    def _x(self, args: list[str], timeout: float = 10.0) -> subprocess.CompletedProcess:
        """An X command on the game's display: the desktop's, or gamescope's own."""
        if self.gamescope is None:
            return self.cmd(args, timeout=timeout)
        d = self._display()
        if d is None:
            return subprocess.CompletedProcess(args, 1, "", "no gamescope display yet")
        return self.cmd(["env", f"DISPLAY={d}", *args], timeout=timeout)

    def clear(self) -> None:
        """End of a campaign: normal launches pass straight through the wrapper again."""
        if self.gamescope is not None:
            for name in ("gamescope.flag", "gamescope.display"):
                (self.gamescope / name).unlink(missing_ok=True)

    def pids(self) -> list[int]:
        return sorted(pid for pid, name in _argv0_names(self.proc) if name == "cyberpunk2077.exe")

    def running(self) -> bool:
        return bool(self.pids())

    def launch(self) -> None:
        if self.gamescope is not None:
            self.gamescope.mkdir(parents=True, exist_ok=True)
            (self.gamescope / "gamescope.display").unlink(missing_ok=True)
            (self.gamescope / "gamescope.flag").write_text(f"{self.size[0]} {self.size[1]} headless {self.lock}\n")
        self.spawn(["steam", "-applaunch", APP_ID, "-skipStartScreen"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)

    def _crash_reporters(self) -> list[int]:
        return sorted(pid for pid, name in _argv0_names(self.proc) if name == "crashreporter.exe")

    def _session_pids(self) -> list[int]:
        """Steam's launcher for this game (reaper SteamLaunch AppId=<game>): alive while anything of the
        launch is, crash reporter and gamescope included."""
        return sorted(pid for pid, argv in _cmdlines(self.proc)
                      if "SteamLaunch" in argv and f"AppId={APP_ID}" in argv)

    def session_alive(self) -> bool:
        return bool(self._session_pids())

    def _signal(self, pids: list[int], sig) -> None:
        for pid in pids:
            try:
                self.os_kill(pid, sig)
            except ProcessLookupError:
                pass

    def kill(self, wait: float = 30.0) -> None:
        """The game, its crash reporter, and what's left of Steam's launch session: after a crash the
        reporter keeps the session (and gamescope) alive, and Steam ignores the next launch."""
        self._signal(self.pids() + self._crash_reporters(), signal.SIGKILL)
        end = time.monotonic() + wait
        half = time.monotonic() + wait / 2
        while (self.pids() or self.session_alive()) and time.monotonic() < end:
            if time.monotonic() >= half and self.session_alive():
                self._signal(self._crash_reporters(), signal.SIGKILL)
                self._signal(self._session_pids(), signal.SIGTERM)
                half = end
            self.sleep(0.5)

    def window(self) -> str | None:
        # The game's class is shared by 1x1 helper and IME windows (the probe): pick the titled one.
        r = self._x(["xdotool", "search", "--class", WINDOW_CLASS])
        if r.returncode != 0:
            return None
        for win in r.stdout.split():
            name = self._x(["xdotool", "getwindowname", win])
            if name.returncode == 0 and name.stdout.startswith(WINDOW_TITLE):
                return win
        return None

    def _active(self) -> str:
        r = self._x(["xdotool", "getactivewindow"])
        return r.stdout.strip() if r.returncode == 0 else ""

    def _kwin_activate(self) -> None:
        # KWin refuses an XWayland window's own activation while a Wayland window has focus (the
        # probe): its scripting interface can activate any window.
        script = Path("/tmp") / f"soak_activate_{os.getpid()}.js"
        script.write_text(KWIN_ACTIVATE)
        try:
            r = self.cmd(["gdbus", "call", "--session", "--dest", "org.kde.KWin", "--object-path", "/Scripting",
                          "--method", "org.kde.kwin.Scripting.loadScript", str(script), "soak_activate"])
            num = "".join(c for c in r.stdout if c.isdigit()) if r.returncode == 0 else ""
            if num:
                self.cmd(["gdbus", "call", "--session", "--dest", "org.kde.KWin", "--object-path",
                          f"/Scripting/Script{num}", "--method", "org.kde.kwin.Script.run"])
                self.sleep(0.5)
            self.cmd(["gdbus", "call", "--session", "--dest", "org.kde.KWin", "--object-path", "/Scripting",
                      "--method", "org.kde.kwin.Scripting.unloadScript", "soak_activate"])
        finally:
            script.unlink(missing_ok=True)

    def focus(self) -> bool:
        win = self.window()
        if not win:
            return False
        if self.gamescope is not None:
            return self._active() == win
        self._x(["xdotool", "windowactivate", "--sync", win])
        if self._active() == win:
            return True
        self._kwin_activate()
        return self._active() == win

    def key(self, name: str) -> bool:
        if not self.focus():
            return False
        return self._x(["xdotool", "key", name]).returncode == 0

    def hold(self, name: str, seconds: float) -> bool:
        if not self.focus():
            return False
        self._x(["xdotool", "keydown", name])
        self.held.add(name)
        try:
            self.sleep(seconds)
        finally:
            self._x(["xdotool", "keyup", name])
            self.held.discard(name)
        return True

    def release_all(self) -> None:
        for name in sorted(self.held):
            self._x(["xdotool", "keyup", name])
        self.held.clear()

    def screenshot(self, out: Path) -> bool:
        out.parent.mkdir(parents=True, exist_ok=True)
        if self.gamescope is not None:
            # X can't read gamescope's frames (a black image); gamescopectl writes the composed one.
            if self.cmd(["gamescopectl", "screenshot", str(out)], timeout=30.0).returncode != 0:
                return False
            for _ in range(20):
                if out.exists():
                    return True
                self.sleep(0.5)
            return False
        # The root window can't be captured on Wayland (the probe); the game's own window can.
        win = self.window()
        if not win:
            return False
        return self._x(["import", "-window", win, str(out)], timeout=30.0).returncode == 0
