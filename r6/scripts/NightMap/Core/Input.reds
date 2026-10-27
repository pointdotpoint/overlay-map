module NightMap

// Key state for the live overlay. Arrow keys are never used: they steer vehicles, and with NumLock off
// the numpad reports arrows, so seeing one sets arrowSeen (the hint bar then asks for NumLock).
public class NMInput {
    public let toggle: Bool;
    public let recenter: Bool;
    public let act: Bool;
    public let teleport: Bool;
    public let filter: Bool;
    public let zoomIn: Bool;
    public let zoomOut: Bool;
    public let debugSelfTest: Bool;
    public let debugPerf: Bool;
    public let debugCalib: Bool;
    public let debugLayer: Bool;
    public let arrowSeen: Bool;
    private let up: Bool;
    private let down: Bool;
    private let left: Bool;
    private let right: Bool;
    private let d7: Bool;
    private let d9: Bool;
    private let d1: Bool;
    private let d3: Bool;

    // Returns true when NightMap uses the key.
    public func Handle(s: ref<NightMapSettings>, key: EInputKey, action: EInputAction, shift: Bool, ctrl: Bool, alt: Bool, mapOpen: Bool) -> Bool {
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
                } else {
                    this.toggle = true;
                }
            }
            return true;
        }
        if !mapOpen {
            return false;
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
        this.recenter = false;
        this.act = false;
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

    public static func HintText(s: ref<NightMapSettings>, view: String) -> String {
        return NMInput.KeyName(s.keyPanUp) + "/" + NMInput.KeyName(s.keyPanLeft) + "/" + NMInput.KeyName(s.keyPanRight) + "/" + NMInput.KeyName(s.keyPanDown) + " PAN"
            + "   ·   " + NMInput.KeyName(s.keyZoomIn) + " " + NMInput.KeyName(s.keyZoomOut) + " ZOOM"
            + "   ·   " + NMInput.KeyName(s.keyRecenter) + " FOLLOW"
            + "   ·   " + NMInput.KeyName(s.keyAct) + " ACT"
            + (s.teleportEnabled ? "   ·   " + NMInput.KeyName(s.keyTeleport) + " TELEPORT" : "")
            + "   ·   " + NMInput.KeyName(s.keyFilter) + " FILTER: " + view
            + "   ·   " + NMInput.KeyName(s.keyToggle) + " CLOSE";
    }
}
