module NightMap

// The focus reticle: four corner brackets and a small plus. The plus marks the focus point (the middle of the map
// left of the sidebar). The brackets sit open around it in the theme colour, and lock around the focused marker in
// yellow, sized to the pin. Sizes are 4K units, scaled on Create.
public class NMReticle {
    private let s: Float;
    private let legs: array<ref<inkRectangle>>;   // TL h, TL v, TR h, TR v, BL h, BL v, BR h, BR v
    private let plus: array<ref<inkRectangle>>;
    private let idleColor: HDRColor;
    private let cx: Float;
    private let cy: Float;
    private let w: Float;
    private let h: Float;
    private let locked: Bool;
    private let started: Bool;

    public static func Leg() -> Float { return 26.0; }
    public static func Thick() -> Float { return 5.0; }
    public static func PlusSize() -> Float { return 26.0; }
    public static func EaseMs() -> Float { return 120.0; }

    // Bracket box size (4K units): open when nothing is focused, tighter around a marker, landscape around a photo pin.
    public static func BoxFor(locked: Bool, photo: Bool) -> Vector2 {
        if !locked { return new Vector2(170.0, 170.0); }
        if photo { return new Vector2(NMItemRenderer.ThumbW() + 30.0, NMItemRenderer.ThumbH() + 30.0); }
        return new Vector2(130.0, 130.0);
    }

    // The 8 bracket legs of a w x h box centred on (cx, cy), each as (centre x, centre y, width, height).
    public static func Corners(cx: Float, cy: Float, w: Float, h: Float, leg: Float, thick: Float) -> array<Vector4> {
        let out: array<Vector4>;
        let x0 = cx - w * 0.5;
        let y0 = cy - h * 0.5;
        let x1 = cx + w * 0.5;
        let y1 = cy + h * 0.5;
        ArrayPush(out, new Vector4(x0 + leg * 0.5, y0 + thick * 0.5, leg, thick));
        ArrayPush(out, new Vector4(x0 + thick * 0.5, y0 + leg * 0.5, thick, leg));
        ArrayPush(out, new Vector4(x1 - leg * 0.5, y0 + thick * 0.5, leg, thick));
        ArrayPush(out, new Vector4(x1 - thick * 0.5, y0 + leg * 0.5, thick, leg));
        ArrayPush(out, new Vector4(x0 + leg * 0.5, y1 - thick * 0.5, leg, thick));
        ArrayPush(out, new Vector4(x0 + thick * 0.5, y1 - leg * 0.5, thick, leg));
        ArrayPush(out, new Vector4(x1 - leg * 0.5, y1 - thick * 0.5, leg, thick));
        ArrayPush(out, new Vector4(x1 - thick * 0.5, y1 - leg * 0.5, thick, leg));
        return out;
    }

    // Moves cur toward target, all the way after EaseMs().
    public static func Ease(cur: Float, target: Float, dtMs: Float) -> Float {
        let f = ClampF(dtMs / NMReticle.EaseMs(), 0.0, 1.0);
        return cur + (target - cur) * f;
    }

    public static func Create(parent: ref<inkCanvas>, scale: Float, theme: Int32) -> ref<NMReticle> {
        let r = new NMReticle();
        r.s = scale;
        r.idleColor = NMTheme.HoloHighlight(theme);
        let i = 0;
        while i < 8 {
            let q = NMUi.Rect(parent, 0.0, 0.0, 1.0, 1.0, r.idleColor, 0.9);
            q.SetAnchorPoint(new Vector2(0.5, 0.5));
            ArrayPush(r.legs, q);
            i += 1;
        }
        let k = NMReticle.PlusSize() * scale;
        let t = NMReticle.Thick() * scale;
        ArrayPush(r.plus, NMUi.Rect(parent, 0.0, 0.0, k, t, r.idleColor, 0.9));
        ArrayPush(r.plus, NMUi.Rect(parent, 0.0, 0.0, t, k, r.idleColor, 0.9));
        for p in r.plus { p.SetAnchorPoint(new Vector2(0.5, 0.5)); }
        return r;
    }

    // fx, fy: the focus point; sx, sy: the focused marker's screen position when hasSel.
    public func Update(fx: Float, fy: Float, hasSel: Bool, sx: Float, sy: Float, photo: Bool, dtMs: Float) {
        let box = NMReticle.BoxFor(hasSel, photo);
        let tx = hasSel ? sx : fx;
        let ty = hasSel ? sy : fy;
        let tw = box.X * this.s;
        let th = box.Y * this.s;
        if !this.started {
            this.cx = tx; this.cy = ty; this.w = tw; this.h = th;
            this.started = true;
        } else {
            this.cx = NMReticle.Ease(this.cx, tx, dtMs);
            this.cy = NMReticle.Ease(this.cy, ty, dtMs);
            this.w = NMReticle.Ease(this.w, tw, dtMs);
            this.h = NMReticle.Ease(this.h, th, dtMs);
        }
        if NotEquals(hasSel, this.locked) {
            this.locked = hasSel;
            let c = hasSel ? NMTheme.Yellow() : this.idleColor;
            for q in this.legs { q.SetTintColor(c); }
        }
        let rs = NMReticle.Corners(this.cx, this.cy, this.w, this.h, NMReticle.Leg() * this.s, NMReticle.Thick() * this.s);
        let i = 0;
        while i < 8 {
            this.legs[i].SetTranslation(new Vector2(rs[i].X, rs[i].Y));
            this.legs[i].SetSize(new Vector2(rs[i].Z, rs[i].W));
            i += 1;
        }
        for p in this.plus { p.SetTranslation(new Vector2(fx, fy)); }
    }
}
