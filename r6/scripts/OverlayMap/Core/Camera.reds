module OverlayMap

// North-up 2D camera. World meters <-> map-area units (window units). mpp = meters per unit.
public class NMCamera {
    public let cx: Float;
    public let cy: Float;
    public let mpp: Float;
    public let minMpp: Float;
    public let maxMpp: Float;
    public let viewW: Float;
    public let viewH: Float;
    public let shiftX: Float;   // the centre (cx, cy) is drawn this far left of the view centre (photo drawer, spec §6.5)
    public let follow: Bool;
    public let revision: Int32;
    public let bounds: ref<NMRect>;
    private let easing: Bool;
    private let e0x: Float;
    private let e0y: Float;
    private let e0m: Float;
    private let e1x: Float;
    private let e1y: Float;
    private let e1m: Float;
    private let eT: Float;
    private let eDur: Float;

    public static func Create(viewW: Float, viewH: Float, bounds: ref<NMRect>, minMpp: Float, maxMpp: Float) -> ref<NMCamera> {
        let c = new NMCamera();
        c.viewW = viewW;
        c.viewH = viewH;
        c.bounds = bounds;
        c.minMpp = minMpp;
        c.maxMpp = maxMpp;
        c.mpp = ClampF(4.0, minMpp, maxMpp);
        c.cx = (bounds.minX + bounds.maxX) * 0.5;
        c.cy = (bounds.minY + bounds.maxY) * 0.5;
        c.follow = true;
        return c;
    }

    public func WorldToMap(wx: Float, wy: Float) -> Vector2 {
        return new Vector2((wx - this.cx) / this.mpp + this.viewW * 0.5 - this.shiftX, (this.cy - wy) / this.mpp + this.viewH * 0.5);
    }

    public func MapToWorld(px: Float, py: Float) -> Vector2 {
        return new Vector2(this.cx + (px - this.viewW * 0.5 + this.shiftX) * this.mpp, this.cy - (py - this.viewH * 0.5) * this.mpp);
    }

    public func VisibleRect(marginPx: Float) -> ref<NMRect> {
        let hw = (this.viewW * 0.5 + marginPx) * this.mpp;
        let hh = (this.viewH * 0.5 + marginPx) * this.mpp;
        let mx = this.cx + this.shiftX * this.mpp;   // world x at the view centre
        return NMRect.Create(mx - hw, this.cy - hh, mx + hw, this.cy + hh);
    }

    // The center stays inside the world bounds: at most half a view of empty space past the edge.
    // User-driven setters cancel an active ease; Tick uses the Apply* variants.
    public func SetCenter(x: Float, y: Float) {
        this.easing = false;
        this.ApplyCenter(x, y);
    }

    private func ApplyCenter(x: Float, y: Float) {
        let nx = ClampF(x, this.bounds.minX, this.bounds.maxX);
        let ny = ClampF(y, this.bounds.minY, this.bounds.maxY);
        if nx != this.cx || ny != this.cy {
            this.cx = nx;
            this.cy = ny;
            this.revision += 1;
        }
    }

    public func SetScreenShift(px: Float) {
        if px != this.shiftX {
            this.shiftX = px;
            this.revision += 1;
        }
    }

    public func SetMpp(m: Float) {
        this.easing = false;
        this.ApplyMpp(m);
    }

    private func ApplyMpp(m: Float) {
        let nm = ClampF(m, this.minMpp, this.maxMpp);
        if nm != this.mpp {
            this.mpp = nm;
            this.revision += 1;
        }
    }

    // factor > 1 zooms in.
    public func ZoomBy(factor: Float) {
        if factor > 0.0 {
            this.SetMpp(this.mpp / factor);
        }
    }

    // One mouse wheel notch zooms by this factor.
    public static func WheelStep() -> Float = 1.25

    // Wheel zoom: eases to the new zoom; notches during an ease stack on its target, so fast scrolling isn't lost.
    public func ZoomSteps(notches: Int32, durMs: Float) {
        if notches == 0 {
            return;
        }
        let base = this.easing ? this.e1m : this.mpp;
        let x = this.easing ? this.e1x : this.cx;
        let y = this.easing ? this.e1y : this.cy;
        let follow = this.follow;
        this.EaseTo(x, y, base / PowF(NMCamera.WheelStep(), Cast<Float>(notches)), durMs);
        this.follow = follow;
    }

    public func PanPixels(dx: Float, dy: Float) {
        this.follow = false;
        this.easing = false;
        this.SetCenter(this.cx + dx * this.mpp, this.cy - dy * this.mpp);
    }

    public func EaseTo(x: Float, y: Float, m: Float, durMs: Float) {
        this.e0x = this.cx;
        this.e0y = this.cy;
        this.e0m = this.mpp;
        this.e1x = x;
        this.e1y = y;
        this.e1m = ClampF(m, this.minMpp, this.maxMpp);
        this.eT = 0.0;
        this.eDur = MaxF(durMs, 1.0);
        this.easing = true;
    }

    public func IsEasing() -> Bool {
        return this.easing;
    }

    public func Tick(dtMs: Float) {
        if !this.easing {
            return;
        }
        this.eT += dtMs;
        let t = MinF(this.eT / this.eDur, 1.0);
        let k = NMMath.EaseOut(t);
        this.ApplyMpp(NMMath.Lerp(this.e0m, this.e1m, k));
        this.ApplyCenter(NMMath.Lerp(this.e0x, this.e1x, k), NMMath.Lerp(this.e0y, this.e1y, k));
        if t >= 1.0 {
            this.easing = false;
        }
    }
}
