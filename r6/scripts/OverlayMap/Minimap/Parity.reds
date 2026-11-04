module OverlayMap

// Geometry for vanilla-minimap behaviours OverlayMap reproduces: markers clamped to the rim when off the view, and the
// above / below arrows. Positions are map px inside a w x h view; round = the Circle style's disc.
public abstract class NMParity {
    public static func IsOff(px: Float, py: Float, w: Float, h: Float, round: Bool, inset: Float) -> Bool {
        if round {
            let r = MinF(w, h) * 0.5 - inset;
            let dx = px - w * 0.5;
            let dy = py - h * 0.5;
            return dx * dx + dy * dy > r * r;
        }
        return px < inset || py < inset || px > w - inset || py > h - inset;
    }

    // The point where the ray from the view centre to (px, py) meets the rim, `inset` px inside it.
    public static func ClampToRim(px: Float, py: Float, w: Float, h: Float, round: Bool, inset: Float) -> Vector2 {
        let cx = w * 0.5;
        let cy = h * 0.5;
        let dx = px - cx;
        let dy = py - cy;
        let len = SqrtF(dx * dx + dy * dy);
        if len < 0.001 { return new Vector2(cx, cy); }
        if round {
            let r = MinF(w, h) * 0.5 - inset;
            return new Vector2(cx + dx / len * r, cy + dy / len * r);
        }
        let hx = cx - inset;
        let hy = cy - inset;
        let t = 1000000000.0;
        if AbsF(dx) > 0.001 { t = MinF(t, hx / AbsF(dx)); }
        if AbsF(dy) > 0.001 { t = MinF(t, hy / AbsF(dy)); }
        return new Vector2(cx + dx * t, cy + dy * t);
    }

    // Ink rotation (degrees, clockwise, 0 = up) of an arrow at the rim pointing towards (px, py).
    public static func ArrowAngle(px: Float, py: Float, w: Float, h: Float) -> Float {
        return Rad2Deg(AtanF(px - w * 0.5, -(py - h * 0.5)));
    }

    // An area shape vertex (vanilla minimap px, relative to its mappin) to world, with the GPS route transform.
    public static func AreaToWorld(v: Vector2, mx: Float, my: Float, camYaw: Float, s: Float) -> Vector2 {
        return NMGps.ToWorld(v, new Vector2(0.0, 0.0), mx, my, camYaw, s);
    }

    // Vanilla minimap px per metre from one marker: its root's offset from the minimap centre (px) over its
    // horizontal distance from V (m). 0 when the marker is closer than 10 m (too noisy).
    public static func ScaleFrom(offset: Vector2, dx: Float, dy: Float) -> Float {
        let d = SqrtF(dx * dx + dy * dy);
        if d < 10.0 { return 0.0; }
        return SqrtF(offset.X * offset.X + offset.Y * offset.Y) / d;
    }

    // holo_arrow points up: above = 0, below = 180.
    public static func VerticalRotation(v: Int32) -> Float {
        return v < 0 ? 180.0 : 0.0;
    }
}
