"""tools/soak/pad.py: the virtual Xbox 360 pad's event encoding, scaling and device setup (no /dev/uinput needed)."""
import struct, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))
from soak import pad

# struct input_event on x86_64: timeval (2 x long), u16 type, u16 code, s32 value = 24 bytes.
ev = pad.encode_event(pad.EV_KEY, pad.BUTTONS["A"], 1)
assert len(ev) == 24, len(ev)
assert struct.unpack("llHHi", ev)[2:] == (1, 0x130, 1)
assert struct.unpack("llHHi", pad.encode_event(pad.EV_SYN, 0, 0))[2:] == (0, 0, 0)

# Scaling: sticks are up-positive in the API (as the game reports them), evdev Y is down-positive.
assert pad.axis_events("LX", 1.0) == [(pad.EV_ABS, 0, 32767)]
assert pad.axis_events("LX", -1.0) == [(pad.EV_ABS, 0, -32768)]
assert pad.axis_events("LY", 1.0) == [(pad.EV_ABS, 1, -32768)]
assert pad.axis_events("LY", 0.0) == [(pad.EV_ABS, 1, 0)]
assert pad.axis_events("LT", 1.0) == [(pad.EV_ABS, 2, 255)]
assert pad.axis_events("RT", 0.5) == [(pad.EV_ABS, 5, 128)]
assert pad.axis_events("LT", 2.0) == [(pad.EV_ABS, 2, 255)]       # clamped
# D-pad is a hat on the 360 pad, not buttons.
assert pad.button_events("DUP", True) == [(pad.EV_ABS, 0x11, -1)]
assert pad.button_events("DDOWN", False) == [(pad.EV_ABS, 0x11, 0)]
assert pad.button_events("VIEW", True) == [(pad.EV_KEY, 0x13a, 1)]
try:
    pad.button_events("Z", True)
    raise AssertionError("unknown button accepted")
except KeyError:
    pass

# The device record: 80-byte name, input_id, ff_effects_max, then 4 x 64 s32 abs arrays.
rec = pad.user_dev_record()
assert len(rec) == 80 + 8 + 4 + 4 * 64 * 4, len(rec)
assert rec[:23] == b"Microsoft X-Box 360 pad"
bus, vendor, product, version = struct.unpack_from("HHHH", rec, 80)
assert (bus, vendor, product) == (0x03, 0x045E, 0x028E)
absmax = struct.unpack_from("64i", rec, 92)
absmin = struct.unpack_from("64i", rec, 92 + 256)
assert (absmin[0], absmax[0]) == (-32768, 32767) and (absmin[5], absmax[5]) == (0, 255) and (absmin[0x10], absmax[0x10]) == (-1, 1)

# The device writes through an injected file and ioctl, so setup order is testable.
calls, writes = [], []
class F:
    def write(self, b): writes.append(bytes(b)); return len(b)
    def fileno(self): return 3
    def close(self): calls.append(("close",))
p = pad.VirtualPad(opener=lambda: F(), ioctl=lambda fd, req, arg=0: calls.append((req, arg)), sleep=lambda s: None)
p.open()
assert (pad.UI_SET_EVBIT, pad.EV_KEY) in calls and (pad.UI_SET_ABSBIT, 5) in calls and (pad.UI_SET_KEYBIT, 0x13a) in calls
assert calls.index((pad.UI_DEV_CREATE, 0)) > calls.index((pad.UI_SET_KEYBIT, 0x13a))
assert writes[0] == rec
writes.clear()
p.press("A", 0.0)
types = [struct.unpack("llHHi", w)[2:] for w in writes]
assert types == [(pad.EV_KEY, 0x130, 1), (0, 0, 0), (pad.EV_KEY, 0x130, 0), (0, 0, 0)], types
p.close()
assert (pad.UI_DEV_DESTROY, 0) in calls and calls[-1] == ("close",)
print("RESULT: PASS")
