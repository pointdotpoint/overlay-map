"""A virtual keyboard and mouse on /dev/uinput, so plans can press keys and turn the mouse wheel in the real game.
xdotool presses never reach the game on a Wayland desktop; kernel input devices do, as the virtual pad does.
Standard library only, set up like tools/soak/pad.py.

Keys: the names in KEYS (Linux key codes, so the layout doesn't matter). Wheel: notches, + is up (zoom in).
The device is system-wide while open: whatever window has focus gets the input, so focus the game first."""
from __future__ import annotations

import fcntl
import os
import struct
import time

from .pad import EV_KEY, EV_SYN, UI_DEV_CREATE, UI_DEV_DESTROY, UI_SET_EVBIT, UI_SET_KEYBIT, encode_event

EV_REL = 0x02
UI_SET_RELBIT = 0x40045566
REL_X, REL_Y, REL_WHEEL = 0x00, 0x01, 0x08
BTN_LEFT = 0x110
BUS_VIRTUAL = 0x06

KEYS = {"ESC": 1, "Q": 16, "W": 17, "E": 18, "R": 19, "T": 20, "O": 24, "ENTER": 28, "A": 30, "S": 31, "D": 32,
        "F": 33, "APOSTROPHE": 40, "SPACE": 57, "UP": 103, "LEFT": 105, "RIGHT": 106, "DOWN": 108}


def key_events(name: str, down: bool) -> list[tuple[int, int, int]]:
    return [(EV_KEY, KEYS[name], 1 if down else 0)]


def wheel_events(notches: int) -> list[list[tuple[int, int, int]]]:
    """One report per notch, as a real wheel sends them."""
    step = 1 if notches > 0 else -1
    return [[(EV_REL, REL_WHEEL, step)] for _ in range(abs(notches))]


def move_events(dx: int, dy: int, steps: int) -> list[list[tuple[int, int, int]]]:
    """A relative mouse move split into `steps` reports; the remainder goes on the last one so the total is exact."""
    n = max(1, steps)
    sx, sy = int(dx / n), int(dy / n)
    out = []
    for i in range(n):
        x = sx + (dx - sx * n if i == n - 1 else 0)
        y = sy + (dy - sy * n if i == n - 1 else 0)
        report = []
        if x:
            report.append((EV_REL, REL_X, x))
        if y:
            report.append((EV_REL, REL_Y, y))
        out.append(report)
    return out


def user_dev_record() -> bytes:
    name = b"OverlayMap soak keyboard and mouse".ljust(80, b"\0")
    zeros = struct.pack("64i", *([0] * 64))
    return name + struct.pack("HHHH", BUS_VIRTUAL, 0x1234, 0x5679, 1) + struct.pack("I", 0) + zeros * 4


def _open_uinput():
    return os.fdopen(os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK), "wb", buffering=0)


class VirtualKbm:
    def __init__(self, opener=_open_uinput, ioctl=fcntl.ioctl, sleep=time.sleep):
        self.opener, self.ioctl, self.sleep = opener, ioctl, sleep
        self.f = None
        self.held: set[str] = set()

    def open(self) -> None:
        self.f = self.opener()
        fd = self.f.fileno()
        for ev in (EV_KEY, EV_REL, EV_SYN):
            self.ioctl(fd, UI_SET_EVBIT, ev)
        for code in list(KEYS.values()) + [BTN_LEFT]:
            self.ioctl(fd, UI_SET_KEYBIT, code)
        for code in (REL_X, REL_Y, REL_WHEEL):
            self.ioctl(fd, UI_SET_RELBIT, code)
        self.f.write(user_dev_record())
        self.ioctl(fd, UI_DEV_CREATE, 0)
        self.sleep(1.0)   # let udev and the compositor pick the device up

    def _emit(self, events: list[tuple[int, int, int]]) -> None:
        for e in events:
            self.f.write(encode_event(*e))
        self.f.write(encode_event(EV_SYN, 0, 0))

    def down(self, name: str) -> None:
        self.held.add(name)
        self._emit(key_events(name, True))

    def up(self, name: str) -> None:
        self.held.discard(name)
        self._emit(key_events(name, False))

    def wheel(self, notches: int, gap: float = 0.08) -> None:
        for report in wheel_events(notches):
            self._emit(report)
            self.sleep(gap)

    def move(self, dx: int, dy: int, steps: int = 10, gap: float = 0.02) -> None:
        for report in move_events(dx, dy, steps):
            if report:
                self._emit(report)
            self.sleep(gap)

    def release_all(self) -> None:
        for name in sorted(self.held):
            self.up(name)

    def close(self) -> None:
        if self.f is None:
            return
        try:
            self.ioctl(self.f.fileno(), UI_DEV_DESTROY, 0)
        finally:
            self.f.close()
            self.f = None
