"""The soak supervisor: the runner against a fake game, builds, plans, and the tests ported from the other harness."""
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))

from soak.builds import stage_build  # noqa: E402
from soak.campaign import validate_plan  # noqa: E402
from soak.channel import read_states  # noqa: E402
from soak.game import GameControl  # noqa: E402
from soak.paths import Paths  # noqa: E402
from soak.runner import Runner, Timeouts, image_luma  # noqa: E402


class FakeGame:
    """Answers the plan like the bootstrap would: every command gets a done, keys run `on_key`."""

    def __init__(self, paths, run="r-1", build="b", on_key=None, die_after=None):
        self.paths, self.run, self.build = paths, run, build
        self.alive, self.pos, self.seq, self.beats = False, (0.0, 0.0, 0.0), 0, 0
        self.answered, self.keys, self.killed = set(), [], False
        self.on_key, self.die_after = on_key, die_after
        self.frozen = False

    def state(self, state, detail=""):
        self.seq += 1
        with (self.paths.channel / "state.txt").open("a") as f:
            f.write(f"{self.run}\t{self.seq}\t{self.build}\t{self.beats}\t{state}\t{detail}\n")

    def tick(self):
        ch = self.paths.channel
        if not self.frozen:
            self.beats += 1
            (ch / "heartbeat.txt").write_text(f"{self.run}\t{self.beats}\tworld\t{self.pos[0]},{self.pos[1]},{self.pos[2]}\n")
        cmd = ch / "command.txt"
        if not cmd.exists():
            return
        text = cmd.read_text().strip().split("\t", 1)[1]
        if text == "exit":
            self.alive = False
        elif text not in self.answered and not self.frozen:
            self.answered.add(text)
            tag, name = text.split(" ", 1)
            self.state("done", f"{tag} ok {name}")

    def launch(self):
        self.alive = True
        self.state("menu")
        self.state("world")

    def running(self):
        self.tick()
        return self.alive

    def session_alive(self):
        return False

    def kill(self):
        self.killed, self.alive = True, False

    def release_all(self):
        pass

    def key(self, name):
        self.keys.append(name)
        if self.on_key:
            self.on_key(self)
        return True

    def hold(self, name, seconds):
        return True

    def key_down(self, name):
        self.keys.append("down " + name)
        return True

    def key_up(self, name):
        self.keys.append("up " + name)
        return True

    def screenshot(self, out):
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(b"png")
        return True


@pytest.fixture
def paths(tmp_path):
    p = Paths(game=tmp_path / "game", user=tmp_path / "user", steam=tmp_path / "steam", soak=tmp_path / "soak",
              wrapper_state=tmp_path / "state", repo=tmp_path / "repo")
    p.channel.mkdir(parents=True)
    return p


class FakePad:
    def __init__(self, log, fail=False):
        self.log, self.fail = log, fail

    def open(self):
        if self.fail:
            raise PermissionError("/dev/uinput")
        self.log.append("open")

    def press(self, name, seconds=0.1):
        self.log.append(f"press {name}")

    def down(self, name):
        self.log.append(f"down {name}")

    def up(self, name):
        self.log.append(f"up {name}")

    def axis(self, name, value):
        self.log.append(f"axis {name} {value}")

    def neutral(self):
        self.log.append("neutral")

    def close(self):
        self.log.append("close")


def drive(paths, game, steps, luma=0.5, pad_factory=None):
    clock = {"t": 0.0}

    def sleep(s):
        clock["t"] += s
        game.tick()

    return Runner(paths, game, clock=lambda: clock["t"], sleep=sleep, luma=lambda _: luma, changed=lambda a, b: 3.0,
                  timeouts=Timeouts(exit_settle=0.0, grace=0.0),
                  pad_factory=pad_factory).run("r-1", "b", "Save", steps, paths.soak / "shots")


def test_pad_steps_drive_the_virtual_pad_and_release_it(paths):
    log = []
    r = drive(paths, FakeGame(paths), [{"pad": "A"}, {"padhold": "VIEW", "seconds": 0.8}, {"paddown": "B"},
                                        {"padup": "B"}, {"padaxis": "LX", "value": 1.0}], pad_factory=lambda: FakePad(log))
    assert r.verdict == "pass", r.detail
    assert log == ["open", "press A", "down VIEW", "up VIEW", "down B", "up B", "axis LX 1.0", "neutral", "close"]


def test_a_plan_without_pad_steps_makes_no_pad(paths):
    log = []
    r = drive(paths, FakeGame(paths), [{"wait": 1}], pad_factory=lambda: FakePad(log))
    assert r.verdict == "pass" and log == []


def test_no_uinput_access_is_a_harness_error(paths):
    r = drive(paths, FakeGame(paths), [{"pad": "A"}], pad_factory=lambda: FakePad([], fail=True))
    assert r.verdict == "infra_error" and "virtual pad" in r.detail


def test_a_black_frame_with_an_alpha_channel_measures_black(tmp_path):
    # gamescopectl writes RGBA: a mean over all channels reads an all-black opaque frame as 0.5.
    out = tmp_path / "black.png"
    subprocess.run(["magick", "-size", "16x16", "xc:black", "-alpha", "on", "-define", "png:color-type=6", str(out)], check=True)
    assert image_luma(out) == 0.0


def test_a_clean_plan_passes_and_keeps_the_commands_answers(paths):
    r = drive(paths, FakeGame(paths), [{"cmd": "open"}, {"wait": 1}, {"shot": "a", "min_luma": 0.02}])
    assert r.verdict == "pass"
    assert r.answers == ["open -> ok open"]
    assert r.lumas == {"a": 0.5}


def test_a_wrong_answer_is_a_coverage_fail(paths):
    r = drive(paths, FakeGame(paths), [{"cmd": "selected", "expect": "^ft"}])
    assert r.verdict == "coverage_fail" and "selected" in r.detail


def test_an_unanswered_command_is_a_harness_error(paths):
    game = FakeGame(paths)
    game.frozen = True
    r = drive(paths, game, [{"cmd": "open"}])
    assert r.verdict == "infra_error"


def test_the_fast_travel_hang_is_a_black_screen_and_the_game_is_killed(paths):
    def freeze(game):
        game.frozen = True

    game = FakeGame(paths, on_key=freeze)
    r = drive(paths, game, [{"key": "KP_Decimal"}, {"await_moved": 100, "timeout": 30}], luma=0.0)
    assert r.verdict == "black_screen"
    assert game.killed


def test_a_frozen_but_lit_game_is_a_hang_not_a_black_screen(paths):
    r = drive(paths, FakeGame(paths), [{"await_moved": 100, "timeout": 5}], luma=0.5)
    assert r.verdict == "hang"


def test_a_real_trip_passes(paths):
    def travel(game):
        game.pos = (500.0, 0.0, 0.0)

    r = drive(paths, FakeGame(paths, on_key=travel), [{"key": "KP_Decimal"}, {"await_moved": 100, "timeout": 30},
                                                      {"await_visible": 10}])
    assert r.verdict == "pass"


def test_a_loading_screen_longer_than_the_beat_timeout_is_not_a_hang(paths):
    def travel(game):
        game.frozen = True

    game = FakeGame(paths, on_key=travel)
    steps = [{"key": "KP_Decimal"}, {"await_moved": 100, "timeout": 200}]
    r = drive(paths, game, steps, luma=0.0)
    assert r.seconds >= 200 and r.verdict == "black_screen"


def test_a_screen_that_stays_black_fails_await_visible(paths):
    r = drive(paths, FakeGame(paths), [{"await_visible": 10, "min_luma": 0.02}], luma=0.0)
    assert r.verdict == "black_screen"


def test_a_screenshot_that_fails_is_retried_not_called_black(paths):
    class Flaky(FakeGame):
        shots = 0

        def screenshot(self, out):
            Flaky.shots += 1
            return Flaky.shots > 1 and super().screenshot(out)

    r = drive(paths, Flaky(paths), [{"shot": "a", "min_luma": 0.02}])
    assert r.verdict == "pass" and r.lumas == {"a": 0.5}


def test_a_screenshot_that_never_works_is_a_harness_error(paths):
    class Blind(FakeGame):
        def screenshot(self, out):
            return False

    r = drive(paths, Blind(paths), [{"shot": "a", "min_luma": 0.02}])
    assert r.verdict == "infra_error"


def test_await_state_passes_when_the_game_reports_it(paths):
    def report(game):
        game.state("ft_load_finished", "true")

    r = drive(paths, FakeGame(paths, on_key=report), [{"key": "x"}, {"await_state": "ft_load_finished", "timeout": 5}])
    assert r.verdict == "pass"


def test_await_state_photographs_each_moment_the_game_flags(paths):
    def report(game):
        game.state("hold", "1|10,20")

    r = drive(paths, FakeGame(paths, on_key=report),
              [{"key": "x"}, {"await_state": "never", "timeout": 3, "shoot_on": "hold"}])
    assert "hold-1a" in r.lumas and "hold-1b" in r.lumas


def test_max_changed_fails_a_view_that_was_still_loading(paths):
    def report(game):
        game.state("hold", "1|L3")

    r = drive(paths, FakeGame(paths, on_key=report),
              [{"key": "x"}, {"await_state": "never", "timeout": 3, "shoot_on": "hold", "max_changed": 1}])
    assert r.verdict == "coverage_fail" and r.detail.startswith("hold 1: 3 map blocks")


def test_a_flagged_moment_raised_before_the_step_begins_is_still_photographed(paths):
    game = FakeGame(paths)
    steps = [{"cmd": "go"}, {"await_state": "never", "timeout": 3, "shoot_on": "hold"}]
    real = game.tick

    def tick():
        real()
        if "1 go" in game.answered and "hold" not in (paths.channel / "state.txt").read_text():
            game.state("hold", "1|L0")

    game.tick = tick
    r = drive(paths, game, steps)
    assert "hold-1a" in r.lumas


def test_await_state_timing_out_fails_the_run(paths):
    r = drive(paths, FakeGame(paths), [{"await_state": "ft_load_finished", "timeout": 5}])
    assert r.verdict == "coverage_fail" and "ft_load_finished" in r.detail


def test_keydown_and_keyup_are_separate_steps(paths):
    game = FakeGame(paths)
    r = drive(paths, game, [{"keydown": "apostrophe"}, {"cmd": "is_open"}, {"keyup": "apostrophe"}])
    assert r.verdict == "pass" and game.keys == ["down apostrophe", "up apostrophe"]


def test_the_process_ending_is_a_crash(paths):
    def die(game):
        game.alive = False

    r = drive(paths, FakeGame(paths, on_key=die), [{"key": "x"}, {"wait": 5}])
    assert r.verdict == "crash"


def test_a_crash_report_is_a_crash(paths):
    paths.reports.mkdir(parents=True)

    def report(game):
        (paths.reports / "dump1").mkdir()

    r = drive(paths, FakeGame(paths, on_key=report), [{"key": "x"}, {"wait": 5}])
    assert r.verdict == "crash" and "dump1" in r.detail


def test_stage_build_overlays_the_hooks_and_stamps_the_id(tmp_path):
    repo = tmp_path / "repo"
    (repo / "r6/scripts/NightMap/Debug").mkdir(parents=True)
    (repo / "r6/scripts/NightMap/Debug/A.reds").write_text("a")
    (repo / "tools/soak/bootstrap").mkdir(parents=True)
    (repo / "tools/soak/bootstrap/SoakBootstrap.reds").write_text("b")
    (repo / "tools/soak/autopilot").mkdir(parents=True)
    (repo / "tools/soak/autopilot/SoakHooks.reds").write_text("h")
    (repo / "tools/soak/autopilot/SystemBody.inc").write_text("    func Soak_X();\n")
    (repo / "tools/soak/autopilot/RendererBody.inc").write_text("    let y;\n")
    (repo / "r6/scripts/NightMap/Core").mkdir()
    (repo / "r6/scripts/NightMap/Core/NightMapSystem.reds").write_text(
        "public class NightMapSystem {\n    private func UpdateModules(dt: Float) {\n    }\n}\n\nclass B {\n}\n")
    (repo / "r6/scripts/NightMap/Render").mkdir()
    (repo / "r6/scripts/NightMap/Render/ItemRenderer.reds").write_text(
        "public class NMItemRenderer {\n            ic.SetAtlasResource(this.icon.atlas);\n"
        "                        this.miniIcon[mi].SetAtlasResource(this.api.catAtlas[g2]);\n}\n")
    (repo / "archive/pc/mod").mkdir(parents=True)
    (repo / "archive/pc/mod/NightMap.archive").write_bytes(b"z")
    p = Paths(game=tmp_path, user=tmp_path, steam=tmp_path, soak=tmp_path / "soak", wrapper_state=tmp_path, repo=repo)
    b = stage_build(p, ["autopilot", "scripts", "archive", "bootstrap"])
    assert (b.dir / "r6/scripts/NightMap/Debug/SoakHooks.reds").read_text() == "h"
    assert f'"{b.id}"' in (b.dir / "r6/scripts/SoakBootstrap/SoakBuild.reds").read_text()
    assert not (repo / "r6/scripts/NightMap/Debug/SoakHooks.reds").exists()
    staged = (b.dir / "r6/scripts/NightMap/Core/NightMapSystem.reds").read_text()
    assert staged == ("public class NightMapSystem {\n    private func UpdateModules(dt: Float) {\n"
                      "        this.Soak_Frame(dt);\n    }\n    func Soak_X();\n}\n\nclass B {\n}\n")
    assert "soakIconLoads" in (b.dir / "r6/scripts/NightMap/Render/ItemRenderer.reds").read_text()
    assert "Soak_X" not in (repo / "r6/scripts/NightMap/Core/NightMapSystem.reds").read_text()


@pytest.mark.parametrize("plan", sorted((TOOLS / "soak/plans").glob("*.json")), ids=lambda p: p.stem)
def test_shipped_plans_are_valid(plan):
    validate_plan(json.loads(plan.read_text()))


def test_validate_rejects_a_run_with_no_steps():
    with pytest.raises(ValueError):
        validate_plan({"runs": [{"name": "x", "steps": []}]})


@pytest.mark.parametrize("script", sorted((TOOLS / "soak/tests").glob("soak_*_test.py")), ids=lambda p: p.stem)
def test_ported_supervisor_tests(script):
    if script.stem == "soak_lock_test" and GameControl().running():
        pytest.skip("install.sh refuses while the real game runs")
    env = dict(os.environ, PYTHONPATH=str(TOOLS))
    r = subprocess.run([sys.executable, str(script)], capture_output=True, text=True, timeout=120, env=env)
    assert r.returncode == 0 and "RESULT: PASS" in r.stdout, r.stdout[-800:] + r.stderr[-1500:]
