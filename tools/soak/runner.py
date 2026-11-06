"""One run: launch, load the save, walk the plan's steps, exit, and a verdict.

Steps, in order:
  {"cmd": "open"}                     a command for the in-game hooks; it must answer. "expect": regex on its answer
  {"key": "apostrophe"}               a real key press in the game's display
  {"keydown": "94"}, {"keyup": "94"}   the same, held across the steps between them. A key names an X keysym or a
                                      keycode; the session's layout decides what the game sees, so a keysym can land on
                                      another key. Under gamescope, keycode 94 is the one the game calls IK_SingleQuote.
  {"wait": 2.0}                       seconds, still watching for crashes
  {"shot": "name"}                    a screenshot into the run's screens/; "min_luma" fails it as black_screen
  {"await_visible": 90, "min_luma": 0.02}   screenshots until the frame isn't black, else black_screen
  {"await_moved": 100, "timeout": 90}       the player moved that many metres from where the step began
  {"await_state": "ft_load_finished", "timeout": 60}   the game reported that state, else coverage_fail;
                                      "shoot_on": "hold" photographs each time the game raises that state meanwhile
  {"pad": "A"}, {"padhold": "VIEW", "seconds": 0.8}   a virtual Xbox 360 pad (tools/soak/pad.py): a press, a hold
  {"paddown": "B"}, {"padup": "B"}    held across the steps between them
  {"padaxis": "LX", "value": 1.0}     a stick (-1..1, up/right positive) or trigger (LT/RT, 0..1); stays until changed
                                      A plan with any pad step gets the pad before launch; it is released at the end.
  {"kbd": "W", "seconds": 1.0}        a virtual keyboard and mouse (tools/soak/kbm.py): a held key, reaching the game
  {"kbddown": "D"}, {"kbdup": "D"}    on a Wayland desktop where xdotool can't; held across the steps between them
  {"wheel": 3}                        mouse wheel notches, + is up. The device exists only for plans that use it.

pass: every step done and the game exited by itself. crash: a new crash report, or the process gone.
hang: no heartbeat for Timeouts.beat, or the game not exiting. black_screen: the game runs but shows nothing.
coverage_fail: a command's answer missed its expect. infra_error: the harness couldn't drive the game.
interrupted: the stop file or Ctrl+C. load_crash: the game died before the world was up."""
from __future__ import annotations

import math
import re
import subprocess
import time
from dataclasses import dataclass, field
from pathlib import Path

from .channel import read_beat, read_states, write_command, write_plan
from .paths import Paths


@dataclass
class Timeouts:
    launch: float = 180.0
    menu: float = 180.0
    load: float = 300.0
    exit: float = 120.0
    grace: float = 30.0
    exit_settle: float = 3.0
    beat: float = 90.0
    command: float = 20.0
    shot_gap: float = 3.0
    shot_tries: int = 3
    tick: float = 0.25


@dataclass
class RunResult:
    verdict: str
    detail: str
    seconds: float
    workload_seconds: float
    states: list[str] = field(default_factory=list)
    reports: list[Path] = field(default_factory=list)
    answers: list[str] = field(default_factory=list)
    lumas: dict[str, float] = field(default_factory=dict)
    stages: list[tuple[str, float]] = field(default_factory=list)   # (state, seconds from the run's start), in order


class Verdict(Exception):
    def __init__(self, verdict: str, detail: str):
        super().__init__(f"{verdict}: {detail}")
        self.verdict, self.detail = verdict, detail


def changed_cells(a: Path, b: Path) -> float | None:
    """How many of the map area's 34x20 blocks (the sidebar left out) differ clearly between two pictures of the same view, None if unreadable.
    The panel is see-through, so a small difference in every block is the world behind it, not the map."""
    r = subprocess.run(["magick", str(a), str(b), "-alpha", "off", "-crop", "1700x1000+130+180", "+repage",
                        "-compose", "difference", "-composite", "-colorspace", "Gray", "-resize", "34x20!",
                        "-threshold", "8%", "-format", "%[fx:mean*w*h]", "info:"],
                       capture_output=True, text=True, timeout=30)
    try:
        return float(r.stdout.strip())
    except ValueError:
        return None


def image_luma(path: Path) -> float | None:
    """Mean brightness 0..1 of a picture, None when it can't be read."""
    r = subprocess.run(["magick", str(path), "-alpha", "off", "-colorspace", "Gray", "-format", "%[fx:mean]", "info:"],
                       capture_output=True, text=True, timeout=30)
    try:
        return float(r.stdout.strip())
    except ValueError:
        return None


PAD_STEPS = ("pad", "padhold", "paddown", "padup", "padaxis")


def _virtual_pad():
    from .pad import VirtualPad
    return VirtualPad()


def uses_pad(steps: list[dict]) -> bool:
    return any(k in step for step in steps for k in PAD_STEPS)


KBM_STEPS = ("kbd", "kbddown", "kbdup", "wheel")


def _virtual_kbm():
    from .kbm import VirtualKbm
    return VirtualKbm()


def uses_kbm(steps: list[dict]) -> bool:
    return any(k in step for step in steps for k in KBM_STEPS)


class Runner:
    def __init__(self, paths: Paths, game, clock=time.monotonic, sleep=time.sleep,
                 timeouts: Timeouts | None = None, stop=lambda: False, luma=image_luma, changed=changed_cells,
                 pad_factory=None, kbm_factory=None):
        self.paths, self.game, self.clock, self.sleep = paths, game, clock, sleep
        self.pad_factory = pad_factory or _virtual_pad
        self.pad = None
        self.kbm_factory = kbm_factory or _virtual_kbm
        self.kbm = None
        self.t = timeouts or Timeouts()
        self.stop, self.luma, self.changed = stop, luma, changed

    def run(self, run_id: str, build_id: str, save: str, steps: list[dict], shots: Path) -> RunResult:
        self.run_id, self.build_id, self.shots = run_id, build_id, shots
        self.t0 = self.clock()
        self.known = self._report_dirs()
        self.fresh: list[Path] = []
        self.states: list[str] = []
        self.details: list[str] = []
        self.stages: list[tuple[str, float]] = []
        self.answers: list[str] = []
        self.lumas: dict[str, float] = {}
        self.shot_seen: dict[str, int] = {}
        self.started = self.world = self.exiting = False
        self.seq = 0
        self.beat_ok = True
        self.last_count, self.last_change = -1, self.t0
        self.work_start = None
        self.workload_seconds = 0.0
        write_plan(self.paths.channel, run_id, build_id, save)
        try:
            if self._session_alive():            # the last run's crash reporter / gamescope
                self.game.kill()
            if uses_pad(steps):
                try:
                    self.pad = self.pad_factory()
                    self.pad.open()
                except OSError as e:
                    self.pad = None
                    raise Verdict("infra_error", f"no virtual pad: {e}")
            if uses_kbm(steps):
                try:
                    self.kbm = self.kbm_factory()
                    self.kbm.open()
                except OSError as e:
                    self.kbm = None
                    raise Verdict("infra_error", f"no virtual keyboard: {e}")
            self.game.launch()
            self._wait(self.game.running, self.t.launch, "infra_error", "the game didn't start")
            self.started = True
            self._stage("game")
            self._wait(lambda: "menu" in self.states, self.t.menu, "infra_error", "no main menu (start screen or a dialog?)")
            self._wait(lambda: "world" in self.states, self.t.load, "infra_error", "the save didn't load")
            self.world = True
            self.last_change = self.clock()
            self.work_start = self.clock()
            for step in steps:
                self._step(step)
            self.workload_seconds = self.clock() - self.work_start
            self.work_start = None
            write_command(self.paths.channel, run_id, "exit")
            self.exiting = True
            self._wait(lambda: not self.game.running(), self.t.exit, "hang", "the game didn't exit")
            self._after_exit()
            return self._result("pass", "")
        except Verdict as v:
            if self.game.running() and v.verdict not in ("crash", "load_crash"):
                self.game.screenshot(self.shots / f"{v.verdict}.png")
            if v.verdict in ("crash", "load_crash") and self.fresh:
                # The crash reporter is still writing the report: let it finish (".ready") first.
                self._wait_for(lambda: all((d / ".ready").exists() for d in self.fresh), self.t.grace)
            if self.game.running() or self._session_alive():
                self.game.kill()   # the crash reporter too: it keeps Steam's launch alive
            return self._result(v.verdict, v.detail)
        finally:
            self.game.release_all()
            if self.kbm is not None:
                try:
                    self.kbm.release_all()
                finally:
                    self.kbm.close()
                    self.kbm = None
            if self.pad is not None:
                try:
                    self.pad.neutral()
                finally:
                    self.pad.close()
                    self.pad = None

    # ---- steps ----

    def _step(self, step: dict) -> None:
        if "cmd" in step:
            self._command(step["cmd"], step.get("expect"), step.get("timeout", self.t.command))
        elif "key" in step:
            if not self.game.key(step["key"]):
                raise Verdict("infra_error", f"key {step['key']} didn't reach the game")
        elif "keydown" in step:
            if not self.game.key_down(step["keydown"]):
                raise Verdict("infra_error", f"key {step['keydown']} didn't reach the game")
        elif "keyup" in step:
            if not self.game.key_up(step["keyup"]):
                raise Verdict("infra_error", f"key {step['keyup']} didn't reach the game")
        elif "hold" in step:
            if not self.game.hold(step["hold"], step.get("seconds", 1.0)):
                raise Verdict("infra_error", f"key {step['hold']} didn't reach the game")
        elif "pad" in step:
            self.pad.press(step["pad"], step.get("seconds", 0.1))
        elif "padhold" in step:
            self.pad.down(step["padhold"])
            try:
                self._pause(step.get("seconds", 1.0))
            finally:
                self.pad.up(step["padhold"])
        elif "paddown" in step:
            self.pad.down(step["paddown"])
        elif "padup" in step:
            self.pad.up(step["padup"])
        elif "padaxis" in step:
            self.pad.axis(step["padaxis"], float(step.get("value", 0.0)))
        elif "kbd" in step:
            self.game.focus()
            self.kbm.down(step["kbd"])
            try:
                self._pause(step.get("seconds", 0.1))
            finally:
                self.kbm.up(step["kbd"])
        elif "kbddown" in step:
            self.game.focus()
            self.kbm.down(step["kbddown"])
        elif "kbdup" in step:
            self.kbm.up(step["kbdup"])
        elif "wheel" in step:
            self.game.focus()
            self.kbm.wheel(int(step["wheel"]))
        elif "wait" in step:
            self._pause(step["wait"])
        elif "shot" in step:
            luma = self._shot(step["shot"])
            if luma is None and "min_luma" in step:
                raise Verdict("infra_error", f"no picture for {step['shot']}")
            if "min_luma" in step and luma < step["min_luma"]:
                raise Verdict("black_screen", f"{step['shot']}: luma {luma}")
        elif "await_visible" in step:
            self._await_visible(step["await_visible"], step.get("min_luma", 0.02))
        elif "await_moved" in step:
            self._await_moved(step["await_moved"], step.get("timeout", 120.0))
        elif "await_state" in step:
            self._await_state(step["await_state"], step.get("timeout", 60.0), step.get("shoot_on"),
                              step.get("shoot_gap", 1.0), step.get("max_changed"))
        else:
            raise Verdict("infra_error", f"unknown step {step}")

    def _command(self, text: str, expect: str | None, timeout: float) -> str:
        self.seq += 1
        tag = f"{self.seq} "
        write_command(self.paths.channel, self.run_id, tag + text)
        start = self.clock()
        while True:
            self._check()
            for state, detail in zip(self.states, self.details):
                if state == "done" and detail.startswith(tag):
                    answer = detail[len(tag):]
                    self.answers.append(f"{text} -> {answer}")
                    if expect and not re.search(expect, answer):
                        raise Verdict("coverage_fail", f"{text}: {answer}")
                    return answer
            if self.clock() - start > timeout:
                raise Verdict("infra_error", f"no answer to {text}")
            self.sleep(self.t.tick)

    def _shot(self, name: str) -> float | None:
        """Brightness of a new picture, None if none could be taken: gamescopectl sometimes writes nothing, and a
        picture that doesn't exist says nothing about the screen."""
        out = self.shots / f"{name}.png"
        for _ in range(self.t.shot_tries):
            out.unlink(missing_ok=True)
            luma = self.luma(out) if self.game.screenshot(out) else None
            if luma is not None:
                self.lumas[name] = luma
                return luma
            self._pause(self.t.tick)
        return None

    def _await_visible(self, timeout: float, min_luma: float) -> None:
        """A black frame is a legitimate moment of a loading screen, so only a timeout counts. The heartbeat may
        stop meanwhile, which is why this is its own verdict, not a hang."""
        start = self.clock()
        self.beat_ok = False
        n, luma = 0, None
        while self.clock() - start <= timeout:
            self._check()
            n += 1
            luma = self._shot(f"await-{n:03d}")
            if luma is not None and luma >= min_luma:
                self.beat_ok = True
                self.last_change = self.clock()
                return
            self._pause(self.t.shot_gap)
        raise Verdict("black_screen", f"{timeout:.0f} s, last luma {luma}")

    def _await_moved(self, metres: float, timeout: float) -> None:
        start = self.clock()
        self.beat_ok = False
        from_pos = self._position()
        while self.clock() - start <= timeout:
            self._check()
            now = self._position()
            if from_pos is None:
                from_pos = now
            elif now is not None and math.dist(from_pos, now) >= metres:
                self.beat_ok = True
                self.last_change = self.clock()
                return
            self.sleep(self.t.tick)
        luma = self._shot("stuck")
        verdict = "black_screen" if luma is not None and luma < 0.02 else "hang"
        raise Verdict(verdict, f"the player didn't move {metres:.0f} m in {timeout:.0f} s, luma {luma}")

    def _await_state(self, state: str, timeout: float, shoot_on: str | None = None, shoot_gap: float = 1.0,
                     max_changed: float | None = None) -> None:
        """shoot_on: a state the game raises at a moment worth seeing; two pictures, at once and shoot_gap later, and
        how many map blocks differ between them. max_changed fails the step when that is exceeded."""
        start = self.clock()
        self.beat_ok = False
        shot = self.shot_seen.get(shoot_on, 0)    # across steps: the game can raise one before this step starts
        while state not in self.states:
            self._check()
            if shoot_on and self.states.count(shoot_on) > shot:
                shot += 1
                self.shot_seen[shoot_on] = shot
                self._shot(f"{shoot_on}-{shot}a")
                self._pause(shoot_gap)
                self._shot(f"{shoot_on}-{shot}b")
                cells = self.changed(self.shots / f"{shoot_on}-{shot}a.png", self.shots / f"{shoot_on}-{shot}b.png")
                if cells is not None:
                    self.lumas[f"{shoot_on}-{shot}-changed"] = cells
                    if max_changed is not None and cells > max_changed:
                        raise Verdict("coverage_fail", f"{shoot_on} {shot}: {cells:.0f} map blocks changed")
            if self.clock() - start > timeout:
                raise Verdict("coverage_fail", f"no {state} in {timeout:.0f} s")
            self.sleep(self.t.tick)
        self.beat_ok = True
        self.last_change = self.clock()

    def _position(self):
        beat = read_beat(self.paths.channel, self.run_id)
        return beat.camera if beat else None

    # ---- every tick ----

    def _check(self) -> None:
        if self.stop():
            raise Verdict("interrupted", "stop requested")
        fresh = [d for d in self._report_dirs() if d not in self.known]
        if fresh:
            self.fresh = fresh
            raise Verdict("crash" if self.world else "load_crash", f"crash report {fresh[0].name}")
        lines = read_states(self.paths.channel, self.run_id)
        for line in lines:
            if line.build != self.build_id:
                raise Verdict("infra_error", f"build mismatch: the game runs {line.build}, staged {self.build_id}")
            if line.state == "infra_error":
                raise Verdict("infra_error", line.detail)
        for line in lines[len(self.states):]:
            self._stage(line.state)
        self.states = [line.state for line in lines]
        self.details = [line.detail for line in lines]
        if self.started and not self.exiting and not self.game.running():
            self._wait_for(lambda: bool([d for d in self._report_dirs() if d not in self.known]), self.t.grace)
            self.fresh = [d for d in self._report_dirs() if d not in self.known]
            raise Verdict("crash" if self.world else "load_crash",
                          "the game process ended" + (f" ({self.fresh[0].name})" if self.fresh else ""))
        if self.world and not self.exiting:
            beat = read_beat(self.paths.channel, self.run_id)
            count = beat.count if beat else -1
            if count != self.last_count:
                self.last_count, self.last_change = count, self.clock()
            elif self.beat_ok and self.clock() - self.last_change > self.t.beat:
                raise Verdict("hang", f"no heartbeat for {int(self.t.beat)} s")

    # ---- helpers ----

    def _stage(self, name: str) -> None:
        self.stages.append((name, round(self.clock() - self.t0, 1)))

    def _session_alive(self) -> bool:
        alive = getattr(self.game, "session_alive", None)
        return bool(alive and alive())

    def _report_dirs(self) -> list[Path]:
        r = self.paths.reports
        return sorted(d for d in r.iterdir() if d.is_dir()) if r.is_dir() else []

    def _after_exit(self) -> None:
        """A crash report can still come: wait while Steam's session is up, at most the grace period."""
        start = self.clock()
        self._pause(self.t.exit_settle)
        while self._session_alive() and self.clock() - start < self.t.grace:
            self._check()
            self.sleep(self.t.tick)

    def _wait(self, cond, timeout: float, verdict: str, detail: str) -> None:
        start = self.clock()
        while True:
            self._check()
            if cond():
                return
            if self.clock() - start > timeout:
                raise Verdict(verdict, detail)
            self.sleep(self.t.tick)

    def _wait_for(self, cond, timeout: float) -> bool:
        start = self.clock()
        while self.clock() - start <= timeout:
            if cond():
                return True
            self.sleep(self.t.tick)
        return cond()

    def _pause(self, seconds: float) -> None:
        start = self.clock()
        while self.clock() - start < seconds:
            self._check()
            self.sleep(self.t.tick)

    def _result(self, verdict: str, detail: str) -> RunResult:
        if verdict == "pass" and self.fresh:
            verdict, detail = "crash", f"crash report {self.fresh[0].name}"
        if self.work_start is not None:
            self.workload_seconds += self.clock() - self.work_start
        return RunResult(verdict, detail, self.clock() - self.t0, self.workload_seconds, list(self.states),
                         list(self.fresh), list(self.answers), dict(self.lumas), list(self.stages))
