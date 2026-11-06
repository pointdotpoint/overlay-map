module OverlayMap

// Key state for the live overlay. While V keeps moving, arrow keys are never used: they steer vehicles, and with
// NumLock off the numpad reports arrows, so seeing one sets arrowSeen (the hint bar then asks for NumLock).
// takesKeys: the map holds keyboard and mouse (V stopped), so the any-keyboard set (WASD, arrows, wheel) drives it.
public class NMInput {
    public let toggle: Bool;
    public let recenter: Bool;
    public let act: Bool;
    public let waypoint: Bool;
    public let teleport: Bool;
    public let filter: Bool;
    public let zoomIn: Bool;
    public let zoomOut: Bool;
    public let debugSelfTest: Bool;
    public let debugPerf: Bool;
    public let debugCalib: Bool;
    public let debugLayer: Bool;
    public let arrowSeen: Bool;
    public let takesKeys: Bool;
    public let wheel: Int32;    // wheel notches since the last frame: + zooms in
    private let up: Bool;
    private let down: Bool;
    private let left: Bool;
    private let right: Bool;
    private let d7: Bool;
    private let d9: Bool;
    private let d1: Bool;
    private let d3: Bool;

    // Returns true when OverlayMap uses the key.
    public func Handle(s: ref<OverlayMapSettings>, key: EInputKey, action: EInputAction, shift: Bool, ctrl: Bool, alt: Bool, mapOpen: Bool) -> Bool {
        let pressed = Equals(action, EInputAction.IACT_Press);
        let released = Equals(action, EInputAction.IACT_Release);
        if !pressed && !released {
            return false;
        }
        if Equals(key, s.keyToggle) {
            if pressed {
                if ctrl && shift {
                    this.debugLayer = true;
                } else if ctrl {
                    this.debugSelfTest = true;
                } else if shift {
                    this.debugPerf = true;
                } else if alt {
                    this.debugCalib = true;
                } else if !s.holdToShow || !mapOpen {
                    this.toggle = true;
                }
            } else if s.holdToShow && mapOpen {
                this.toggle = true;
            }
            return true;
        }
        if !mapOpen {
            return false;
        }
        if this.takesKeys && this.HandleTaken(s, key, pressed) {
            return true;
        }
        if Equals(key, EInputKey.IK_Up) || Equals(key, EInputKey.IK_Down) || Equals(key, EInputKey.IK_Left) || Equals(key, EInputKey.IK_Right) {
            if pressed {
                this.arrowSeen = true;
            }
            return false;
        }
        if Equals(key, s.keyPanUp) { this.up = pressed; return true; }
        if Equals(key, s.keyPanDown) { this.down = pressed; return true; }
        if Equals(key, s.keyPanLeft) { this.left = pressed; return true; }
        if Equals(key, s.keyPanRight) { this.right = pressed; return true; }
        if Equals(key, EInputKey.IK_NumPad7) { this.d7 = pressed; return true; }
        if Equals(key, EInputKey.IK_NumPad9) { this.d9 = pressed; return true; }
        if Equals(key, EInputKey.IK_NumPad1) { this.d1 = pressed; return true; }
        if Equals(key, EInputKey.IK_NumPad3) { this.d3 = pressed; return true; }
        if Equals(key, s.keyZoomIn) { this.zoomIn = pressed; return true; }
        if Equals(key, s.keyZoomOut) { this.zoomOut = pressed; return true; }
        if Equals(key, s.keyRecenter) {
            if pressed { this.recenter = true; }
            return true;
        }
        if Equals(key, s.keyAct) {
            if pressed { this.act = true; }
            return true;
        }
        if Equals(key, s.keyWaypoint) {
            if pressed { this.waypoint = true; }
            return true;
        }
        if Equals(key, s.keyFilter) {
            if pressed { this.filter = true; }
            return true;
        }
        if s.teleportEnabled && Equals(key, s.keyTeleport) {
            if pressed { this.teleport = true; }
            return true;
        }
        return false;
    }

    // The any-keyboard set, only while the map holds the keyboard. The wheel arrives as presses (and releases).
    private func HandleTaken(s: ref<OverlayMapSettings>, key: EInputKey, pressed: Bool) -> Bool {
        if Equals(key, EInputKey.IK_MouseWheelUp) || Equals(key, EInputKey.IK_MouseWheelDown) {
            if pressed { this.wheel += Equals(key, EInputKey.IK_MouseWheelUp) ? 1 : -1; }
            return true;
        }
        if Equals(key, s.keyMapPanUp) || Equals(key, EInputKey.IK_Up) { this.up = pressed; return true; }
        if Equals(key, s.keyMapPanDown) || Equals(key, EInputKey.IK_Down) { this.down = pressed; return true; }
        if Equals(key, s.keyMapPanLeft) || Equals(key, EInputKey.IK_Left) { this.left = pressed; return true; }
        if Equals(key, s.keyMapPanRight) || Equals(key, EInputKey.IK_Right) { this.right = pressed; return true; }
        if Equals(key, s.keyMapRecenter) {
            if pressed { this.recenter = true; }
            return true;
        }
        if Equals(key, s.keyMapAct) {
            if pressed { this.act = true; }
            return true;
        }
        if Equals(key, s.keyMapFilter) {
            if pressed { this.filter = true; }
            return true;
        }
        if s.teleportEnabled && Equals(key, s.keyMapTeleport) {
            if pressed { this.teleport = true; }
            return true;
        }
        return false;
    }

    // The game reports the mouse wheel as the IK_MouseZ axis, one event per notch (+ is up). Only while the map
    // holds the keyboard: otherwise the wheel stays the game's (weapon switching). Returns true when used.
    public func Axis(key: EInputKey, value: Float, mapOpen: Bool) -> Bool {
        if !mapOpen || !this.takesKeys || !Equals(key, EInputKey.IK_MouseZ) {
            return false;
        }
        if value > 0.0 { this.wheel += 1; }
        if value < 0.0 { this.wheel -= 1; }
        return true;
    }

    // Snap: when the pan keys are let go and a marker is in focus range, the map eases it under the focus point.
    public static func SnapOnRelease(wasPanning: Bool, panning: Bool, hasSelection: Bool) -> Bool {
        return wasPanning && !panning && hasSelection;
    }

    // Unit pan direction in screen space (+Y = down/south).
    public func PanVector() -> Vector2 {
        let x = 0.0;
        let y = 0.0;
        if this.left || this.d7 || this.d1 { x -= 1.0; }
        if this.right || this.d9 || this.d3 { x += 1.0; }
        if this.up || this.d7 || this.d9 { y -= 1.0; }
        if this.down || this.d1 || this.d3 { y += 1.0; }
        if x != 0.0 && y != 0.0 {
            x *= 0.70710678;
            y *= 0.70710678;
        }
        return new Vector2(x, y);
    }

    public func ResetHeld() {
        this.up = false;
        this.down = false;
        this.left = false;
        this.right = false;
        this.d7 = false;
        this.d9 = false;
        this.d1 = false;
        this.d3 = false;
        this.zoomIn = false;
        this.zoomOut = false;
        this.wheel = 0;
        this.recenter = false;
        this.act = false;
        this.waypoint = false;
        this.filter = false;
        this.teleport = false;
    }

    public static func KeyName(key: EInputKey) -> String {
        let s = EnumValueToString("EInputKey", Cast<Int64>(EnumInt(key)));
        if StrBeginsWith(s, "IK_") {
            s = StrMid(s, 3, StrLen(s) - 3);
        }
        if StrBeginsWith(s, "NumPad") {
            return "NUM " + StrMid(s, 6, StrLen(s) - 6);
        }
        if Equals(s, "NumPlus") { return "NUM +"; }
        if Equals(s, "NumMinus") { return "NUM -"; }
        if Equals(s, "NumStar") { return "NUM *"; }
        if Equals(s, "NumSlash") { return "NUM /"; }
        if Equals(s, "NumPeriod") { return "NUM ."; }
        if Equals(s, "Backslash") { return "\\"; }
        if Equals(s, "SingleQuote") { return "'"; }
        return StrUpper(s);
    }

    // The hint bar's entries. teleportLabel: what the teleport key does for the current selection ("FAST TRAVEL" or
    // "TELEPORT"). Key names come from the user's bindings; CLOSE (the toggle key) is last.
    public static func Hints(s: ref<OverlayMapSettings>, view: String, teleportLabel: String) -> array<NMHint> {
        let h: array<NMHint>;
        ArrayPush(h, NMHints.Of(NMInput.KeyName(s.keyPanUp) + "/" + NMInput.KeyName(s.keyPanLeft) + "/" + NMInput.KeyName(s.keyPanRight) + "/" + NMInput.KeyName(s.keyPanDown), "PAN"));
        ArrayPush(h, NMHints.Of(NMInput.KeyName(s.keyZoomIn) + " " + NMInput.KeyName(s.keyZoomOut), "ZOOM"));
        ArrayPush(h, NMHints.Of(NMInput.KeyName(s.keyRecenter), "FOLLOW"));
        ArrayPush(h, NMHints.Of(NMInput.KeyName(s.keyAct), "ACT"));
        if s.teleportEnabled {
            ArrayPush(h, NMHints.Of(NMInput.KeyName(s.keyTeleport), teleportLabel));
        }
        ArrayPush(h, NMHints.Of(NMInput.KeyName(s.keyFilter), "FILTER: " + view));
        ArrayPush(h, NMHints.Of(NMInput.KeyName(s.keyToggle), "CLOSE", s.holdToShow ? "RELEASE" : ""));
        return h;
    }

    // The hint bar while the map holds the keyboard: the any-keyboard set (the numpad keys still work, unlisted).
    public static func TakeHints(s: ref<OverlayMapSettings>, view: String, teleportLabel: String) -> array<NMHint> {
        let h: array<NMHint>;
        ArrayPush(h, NMHints.Of(NMInput.KeyName(s.keyMapPanUp) + "/" + NMInput.KeyName(s.keyMapPanLeft) + "/" + NMInput.KeyName(s.keyMapPanDown) + "/" + NMInput.KeyName(s.keyMapPanRight), "PAN"));
        ArrayPush(h, NMHints.Of("WHEEL", "ZOOM"));
        ArrayPush(h, NMHints.Of(NMInput.KeyName(s.keyMapRecenter), "FOLLOW"));
        ArrayPush(h, NMHints.Of(NMInput.KeyName(s.keyMapAct), "ACT"));
        if s.teleportEnabled {
            ArrayPush(h, NMHints.Of(NMInput.KeyName(s.keyMapTeleport), teleportLabel));
        }
        ArrayPush(h, NMHints.Of(NMInput.KeyName(s.keyMapFilter), "FILTER: " + view));
        ArrayPush(h, NMHints.Of(NMInput.KeyName(s.keyToggle), "CLOSE", s.holdToShow ? "RELEASE" : ""));
        return h;
    }

    public static func HintText(s: ref<OverlayMapSettings>, view: String, teleportLabel: String) -> String {
        return NMHints.Join(NMInput.Hints(s, view, teleportLabel));
    }

    // An arrow key was seen (NumLock off): a plain-text notice before CLOSE.
    public static func NumLockHints(h: array<NMHint>) -> array<NMHint> {
        return NMHints.Notice(h, "ARROW KEYS IGNORED - TURN NUMLOCK ON");
    }
}
