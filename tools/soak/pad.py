"""A virtual Xbox 360 pad on /dev/uinput, so plans can press controller buttons and move sticks and triggers in the
real game. Standard library only (fcntl + struct, the legacy uinput_user_dev setup the kernel still accepts).

Buttons: A B X Y LB RB VIEW START LS RS, and DUP DDOWN DLEFT DRIGHT (the 360 pad's D-pad is a hat axis).
Axes: LX LY RX RY in -1..1, up and right positive (as the game reports them); LT RT in 0..1.
The device is system-wide while open: Steam and the desktop see a controller too."""
from __future__ import annotations

import fcntl
import os
import struct
import time

EV_SYN, EV_KEY, EV_ABS = 0x00, 0x01, 0x03
UI_DEV_CREATE, UI_DEV_DESTROY = 0x5501, 0x5502
UI_SET_EVBIT, UI_SET_KEYBIT, UI_SET_ABSBIT = 0x40045564, 0x40045565, 0x40045567
BUS_USB = 0x03

BUTTONS = {"A": 0x130, "B": 0x131, "X": 0x133, "Y": 0x134, "LB": 0x136, "RB": 0x137,
           "VIEW": 0x13A, "START": 0x13B, "GUIDE": 0x13C, "LS": 0x13D, "RS": 0x13E}
HAT = {"DLEFT": (0x10, -1), "DRIGHT": (0x10, 1), "DUP": (0x11, -1), "DDOWN": (0x11, 1)}
STICKS = {"LX": (0x00, 1), "LY": (0x01, -1), "RX": (0x03, 1), "RY": (0x04, -1)}   # sign: API up-positive, evdev down
TRIGGERS = {"LT": 0x02, "RT": 0x05}
# code -> (min, max, fuzz, flat), as the xpad driver declares them.
ABS = {0x00: (-32768, 32767, 16, 128), 0x01: (-32768, 32767, 16, 128), 0x03: (-32768, 32767, 16, 128),
       0x04: (-32768, 32767, 16, 128), 0x02: (0, 255, 0, 0), 0x05: (0, 255, 0, 0),
       0x10: (-1, 1, 0, 0), 0x11: (-1, 1, 0, 0)}


def encode_event(etype: int, code: int, value: int) -> bytes:
    t = time.time()
    return struct.pack("llHHi", int(t), int((t % 1) * 1e6), etype, code, value)


def axis_events(name: str, value: float) -> list[tuple[int, int, int]]:
    if name in TRIGGERS:
        v = min(max(value, 0.0), 1.0)
        return [(EV_ABS, TRIGGERS[name], int(round(v * 255)))]
    code, sign = STICKS[name]
    v = min(max(value * sign, -1.0), 1.0)
    return [(EV_ABS, code, 32767 if v >= 1.0 else -32768 if v <= -1.0 else int(round(v * 32767)))]


def button_events(name: str, down: bool) -> list[tuple[int, int, int]]:
    if name in HAT:
        code, v = HAT[name]
        return [(EV_ABS, code, v if down else 0)]
    return [(EV_KEY, BUTTONS[name], 1 if down else 0)]


def user_dev_record() -> bytes:
    absmax, absmin, absfuzz, absflat = [0] * 64, [0] * 64, [0] * 64, [0] * 64
    for code, (lo, hi, fuzz, flat) in ABS.items():
        absmin[code], absmax[code], absfuzz[code], absflat[code] = lo, hi, fuzz, flat
    name = b"Microsoft X-Box 360 pad".ljust(80, b"\0")
    return (name + struct.pack("HHHH", BUS_USB, 0x045E, 0x028E, 0x0114) + struct.pack("I", 0)
            + struct.pack("64i", *absmax) + struct.pack("64i", *absmin)
            + struct.pack("64i", *absfuzz) + struct.pack("64i", *absflat))


def _open_uinput():
    return os.fdopen(os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK), "wb", buffering=0)


class VirtualPad:
    def __init__(self, opener=_open_uinput, ioctl=fcntl.ioctl, sleep=time.sleep):
        self.opener, self.ioctl, self.sleep = opener, ioctl, sleep
        self.f = None

    def open(self) -> None:
        self.f = self.opener()
        fd = self.f.fileno()
        for ev in (EV_KEY, EV_ABS, EV_SYN):
            self.ioctl(fd, UI_SET_EVBIT, ev)
        for code in BUTTONS.values():
            self.ioctl(fd, UI_SET_KEYBIT, code)
        for code in ABS:
            self.ioctl(fd, UI_SET_ABSBIT, code)
        self.f.write(user_dev_record())
        self.ioctl(fd, UI_DEV_CREATE, 0)
        self.sleep(1.0)   # let udev, SDL and Steam pick the device up

    def _emit(self, events: list[tuple[int, int, int]]) -> None:
        for e in events:
            self.f.write(encode_event(*e))
        self.f.write(encode_event(EV_SYN, 0, 0))

    def down(self, name: str) -> None:
        self._emit(button_events(name, True))

    def up(self, name: str) -> None:
        self._emit(button_events(name, False))

    def press(self, name: str, seconds: float = 0.1) -> None:
        self.down(name)
        self.sleep(seconds)
        self.up(name)

    def axis(self, name: str, value: float) -> None:
        self._emit(axis_events(name, value))

    def neutral(self) -> None:
        for name in STICKS:
            self._emit(axis_events(name, 0.0))
        for name in TRIGGERS:
            self._emit(axis_events(name, 0.0))
        for name in list(BUTTONS) + list(HAT):
            self._emit(button_events(name, False))

    def close(self) -> None:
        if self.f is None:
            return
        try:
            self.ioctl(self.f.fileno(), UI_DEV_DESTROY, 0)
        finally:
            self.f.close()
            self.f = None
