module OverlayMap

// Controller input for the map. Raw pad events (Codeware's Input/Key and Input/Axis) become map intents; nothing
// here touches the game. Holding View opens the map; while the map owns the pad (opened with it), LS pans, LT/RT zoom,
// A acts, X teleports, Y cycles the filter, R3 follows V, and B or View close. A map opened with the keyboard ignores
// the pad. In a car with pass-through on, the map is opened from the pad but does not own it: holding View again
// closes it and every other button keeps driving.
public class NMPad {
    public let act: Bool;
    public let waypoint: Bool;
    public let teleport: Bool;
    public let filter: Bool;
    public let recenter: Bool;
    public let close: Bool;
    public let tap: Bool;               // View tapped (released before the hold): the game's pause menu should open
    public let lastWasPad: Bool;
    private let lx: Float;
    private let ly: Float;
    private let lt: Float;
    private let rt: Float;
    private let viewDown: Bool;
    private let viewDownMs: Float;
    private let holdFired: Bool;
    private let held: array<EInputKey>;      // pad buttons currently down (EnumInt), axes excluded
    private let stickGated: Bool;        // after ClearAxes: the stick pans only once it has been back at rest
    private let triggerGated: Bool;

    public static func HoldMs() -> Float = 500.0
    public static func CooldownFrames() -> Int32 = 8
    public static func StickDeadzone() -> Float = 0.2
    public static func TriggerDeadzone() -> Float = 0.1
    // In a car the map owns the pad and the car coasts (the user's choice). True: the pass-through fallback.
    public static func CarPassThrough() -> Bool = false

    // A DualSense (the game's native support) reports View's button, Options, as IK_PS4_OPTIONS: the game binds both
    // to the same actions (inputUserMappings.xml). The map treats it as View.
    public static func Normalize(key: EInputKey) -> EInputKey {
        return Equals(key, EInputKey.IK_PS4_OPTIONS) ? EInputKey.IK_Pad_Back_Select : key;
    }

    public static func IsPad(key: EInputKey) -> Bool {
        let k = EnumInt(key);
        return k >= EnumInt(EInputKey.IK_Pad_A_CROSS) && k <= EnumInt(EInputKey.IK_Pad_RightAxisY);
    }

    // The buttons the open map uses (Button): pressing one hands a keyboard-opened map to the pad. Sticks and the d-pad
    // are not among them.
    public static func IsMapButton(key: EInputKey) -> Bool {
        return Equals(key, EInputKey.IK_Pad_A_CROSS) || Equals(key, EInputKey.IK_Pad_B_CIRCLE) || Equals(key, EInputKey.IK_Pad_X_SQUARE)
            || Equals(key, EInputKey.IK_Pad_Y_TRIANGLE) || Equals(key, EInputKey.IK_Pad_RightShoulder) || Equals(key, EInputKey.IK_Pad_RightThumb)
            || Equals(key, EInputKey.IK_Pad_LeftTrigger) || Equals(key, EInputKey.IK_Pad_RightTrigger) || Equals(key, EInputKey.IK_Pad_Back_Select);
    }

    // mapOpen: the map is up. fromPad: it was opened with the pad. owned: the map holds the pad (game actions held off).
    // Returns true when the map used the button.
    public func Button(key: EInputKey, action: EInputAction, nowMs: Float, mapOpen: Bool, fromPad: Bool, owned: Bool, holdToShow: Bool, enabled: Bool) -> Bool {
        if !enabled {
            this.viewDown = false;
            return false;
        }
        let pressed = Equals(action, EInputAction.IACT_Press);
        let released = Equals(action, EInputAction.IACT_Release);
        if !pressed && !released {
            return false;
        }
        this.TrackHeld(key, pressed);
        if Equals(key, EInputKey.IK_Pad_LeftTrigger) {
            this.lt = pressed ? 1.0 : 0.0;
            return owned;
        }
        if Equals(key, EInputKey.IK_Pad_RightTrigger) {
            this.rt = pressed ? 1.0 : 0.0;
            return owned;
        }
        if Equals(key, EInputKey.IK_Pad_Back_Select) {
            if pressed {
                if mapOpen && owned && !holdToShow {
                    this.close = true;
                    this.lastWasPad = true;
                    return true;
                }
                if !mapOpen || (fromPad && !owned) {
                    this.viewDown = true;
                    this.viewDownMs = nowMs;
                    this.holdFired = false;
                }
                return false;
            }
            let wasDown = this.viewDown;
            this.viewDown = false;
            if wasDown && !this.holdFired {
                this.tap = true;
            }
            if wasDown && holdToShow && mapOpen && fromPad && this.holdFired {
                this.close = true;
                return true;
            }
            return false;
        }
        if !mapOpen || !owned || !pressed {
            return mapOpen && owned;
        }
        this.lastWasPad = true;
        if Equals(key, EInputKey.IK_Pad_A_CROSS) { this.act = true; return true; }
        if Equals(key, EInputKey.IK_Pad_RightShoulder) { this.waypoint = true; return true; }
        if Equals(key, EInputKey.IK_Pad_X_SQUARE) { this.teleport = true; return true; }
        if Equals(key, EInputKey.IK_Pad_Y_TRIANGLE) { this.filter = true; return true; }
        if Equals(key, EInputKey.IK_Pad_RightThumb) { this.recenter = true; return true; }
        if Equals(key, EInputKey.IK_Pad_B_CIRCLE) { this.close = true; return true; }
        return true;
    }

    private func TrackHeld(key: EInputKey, pressed: Bool) {
        if EnumInt(key) > EnumInt(EInputKey.IK_Pad_RightTrigger) {
            return;   // axes
        }
        let i = -1;
        let j = 0;
        while j < ArraySize(this.held) {
            if Equals(this.held[j], key) { i = j; }
            j += 1;
        }
        if pressed && i < 0 {
            ArrayPush(this.held, key);
        } else if !pressed && i >= 0 {
            ArrayErase(this.held, i);
        }
    }

    // Pad buttons still down: the game gets the pad back only once this is 0, so no release reaches it.
    public func IsHeld(key: EInputKey) -> Bool {
        for k in this.held {
            if Equals(k, key) { return true; }
        }
        return false;
    }

    public func HeldCount() -> Int32 {
        return ArraySize(this.held);
    }

    public func ClearHeld() {
        ArrayClear(this.held);
    }

    // Sticks and triggers (game convention: stick up is positive).
    public func Axis(key: EInputKey, value: Float) {
        if Equals(key, EInputKey.IK_Pad_LeftAxisX) || Equals(key, EInputKey.IK_Pad_LeftAxisY) {
            if Equals(key, EInputKey.IK_Pad_LeftAxisX) { this.lx = value; } else { this.ly = value; }
            if this.stickGated && SqrtF(this.lx * this.lx + this.ly * this.ly) < NMPad.StickDeadzone() {
                this.stickGated = false;
            }
            return;
        }
        if Equals(key, EInputKey.IK_Pad_LeftTrigger) || Equals(key, EInputKey.IK_Pad_RightTrigger) {
            if Equals(key, EInputKey.IK_Pad_LeftTrigger) { this.lt = value; } else { this.rt = value; }
            if this.triggerGated && this.lt < NMPad.TriggerDeadzone() && this.rt < NMPad.TriggerDeadzone() {
                this.triggerGated = false;
            }
        }
    }

    // True once when View has been held for HoldMs: open the map while it is closed, or close a pass-through map.
    public func PollHold(nowMs: Float, mapOpen: Bool, fromPad: Bool, owned: Bool) -> Bool {
        if !this.viewDown || this.holdFired || nowMs - this.viewDownMs < NMPad.HoldMs() {
            return false;
        }
        if mapOpen && !(fromPad && !owned) {
            return false;
        }
        this.holdFired = true;
        return true;
    }

    // View is down and its hold has not fired yet: the system keeps polling meanwhile.
    public func HoldPending() -> Bool {
        return this.viewDown && !this.holdFired;
    }

    // The map opened or closed: a stick held for walking, or a trigger held for driving, must not move the map
    // until it has been let go once. Only an input held right now is gated: one at rest sends no events, so a gate on
    // it would swallow its first use.
    public func ClearAxes() {
        this.stickGated = SqrtF(this.lx * this.lx + this.ly * this.ly) >= NMPad.StickDeadzone();
        this.triggerGated = this.lt >= NMPad.TriggerDeadzone() || this.rt >= NMPad.TriggerDeadzone();
    }

    // View is down: its release may still matter (Hold to show).
    public func Waiting() -> Bool {
        return this.viewDown;
    }

    // Unit pan direction in screen space (+Y = south). Radial deadzone, then a squared response for fine control.
    public func PanVector() -> Vector2 {
        let mag = SqrtF(this.lx * this.lx + this.ly * this.ly);
        let dz = NMPad.StickDeadzone();
        if mag < dz || this.stickGated {
            return new Vector2(0.0, 0.0);
        }
        let m = MinF(1.0, (mag - dz) / (1.0 - dz));
        let k = m * m / mag;
        return new Vector2(this.lx * k, -this.ly * k);
    }

    // -1..1: positive zooms in (RT), negative out (LT).
    public func ZoomRate() -> Float {
        if this.triggerGated {
            return 0.0;
        }
        return NMPad.TriggerCurve(this.rt) - NMPad.TriggerCurve(this.lt);
    }

    private static func TriggerCurve(v: Float) -> Float {
        let dz = NMPad.TriggerDeadzone();
        if v < dz {
            return 0.0;
        }
        return MinF(1.0, (v - dz) / (1.0 - dz));
    }

    // One-shots, axes and the View hold.
    public func Reset() {
        this.act = false;
        this.waypoint = false;
        this.teleport = false;
        this.filter = false;
        this.recenter = false;
        this.close = false;
        this.tap = false;
        this.lx = 0.0;
        this.ly = 0.0;
        this.lt = 0.0;
        this.rt = 0.0;
        this.viewDown = false;
        this.holdFired = false;
    }

    public static func Hints(view: String, teleportLabel: String, teleportOn: Bool, holdToShow: Bool) -> array<NMHint> {
        let h: array<NMHint>;
        ArrayPush(h, NMHints.Of("LS", "PAN"));
        ArrayPush(h, NMHints.Of("LT/RT", "ZOOM"));
        ArrayPush(h, NMHints.Of("R3", "FOLLOW"));
        if teleportOn {
            ArrayPush(h, NMHints.Of("X", teleportLabel));
        }
        ArrayPush(h, NMHints.Of("Y", "FILTER: " + view));
        ArrayPush(h, holdToShow ? NMHints.Of("VIEW", "CLOSE", "RELEASE") : NMHints.Of("B", "CLOSE"));
        return h;
    }

    public static func HintText(view: String, teleportLabel: String, teleportOn: Bool, holdToShow: Bool) -> String {
        return NMHints.Join(NMPad.Hints(view, teleportLabel, teleportOn, holdToShow));
    }

    // A pass-through map (opened from the pad in a car, the keyboard hints shown): holding View again closes it, last.
    public static func PassThroughHints(base: array<NMHint>) -> array<NMHint> {
        let h: array<NMHint>;
        for e in base {
            ArrayPush(h, e);
        }
        ArrayPush(h, NMHints.Of("VIEW", "CLOSE", "HOLD"));
        return h;
    }
}
