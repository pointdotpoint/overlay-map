module OverlayMap

// The focus reticle: four corner brackets and a small plus. The plus marks the focus point (the middle of the map
// left of the sidebar). The brackets (light #d8f4ff, spec 5.2) sit open and dimmed around it, and lock at full strength
// around the focused marker, sized to the pin and its tier scale. Sizes are 4K units, scaled on Create.
public class NMReticle {
    private let s: Float;
    private let legs: array<ref<inkRectangle>>;   // TL h, TL v, TR h, TR v, BL h, BL v, BR h, BR v
    private let plus: array<ref<inkRectangle>>;
    // Mouse-only teleport hold: a "TELEPORTING" label over a bar under the focus point, filling left to right.
    private let holdPlate: ref<inkRectangle>;    // dark backing so the label reads over bright roads
    private let holdLabel: ref<inkText>;
    private let holdTrack: ref<inkRectangle>;
    private let holdFill: ref<inkRectangle>;
    private let holdShown: Bool;
    private let idleColor: HDRColor;
    private let legColor: HDRColor;
    private let cx: Float;
    private let cy: Float;
    private let w: Float;
    private let h: Float;
    private let locked: Bool;
    private let started: Bool;
    private let drawn: Bool;   // the legs were placed for dCx..dFy (Update skips when nothing moved)
    private let dCx: Float;
    private let dCy: Float;
    private let dW: Float;
    private let dH: Float;
    private let dFx: Float;
    private let dFy: Float;

    public static func Leg() -> Float { return 26.0; }
    public static func Thick() -> Float { return 5.0; }
    public static func PlusSize() -> Float { return 26.0; }
    public static func EaseMs() -> Float { return 120.0; }
    public static func HoldBarW() -> Float { return 320.0; }
    public static func HoldBarH() -> Float { return 10.0; }
    public static func HoldBarGap() -> Float { return 150.0; }  // focus point to the top of the bar
    public static func HoldLabelSize() -> Float { return 40.0; }
    public static func HoldPad() -> Float { return 18.0; }

    public static func IdleOpacity() -> Float { return 0.6; }
    public static func LockOpacity() -> Float { return 1.0; }

    // Bracket box size (4K units): open when nothing is focused, tighter around a marker (times its tier scale k),
    // landscape around a photo pin (thumbZoom already carries the photo's tier scale).
    public static func BoxFor(locked: Bool, photo: Bool, thumbZoom: Float, k: Float) -> Vector2 {
        if !locked { return new Vector2(170.0, 170.0); }
        if photo { return new Vector2(NMItemRenderer.ThumbW() * thumbZoom + 30.0, NMItemRenderer.ThumbH() * thumbZoom + 30.0); }
        return new Vector2(130.0 * k, 130.0 * k);
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

    public func LegColor() -> HDRColor { return this.legs[0].GetTintColor(); }

    // Moves cur toward target, all the way after EaseMs().
    public static func Ease(cur: Float, target: Float, dtMs: Float) -> Float {
        let f = ClampF(dtMs / NMReticle.EaseMs(), 0.0, 1.0);
        return cur + (target - cur) * f;
    }

    public static func Create(parent: ref<inkCanvas>, scale: Float, theme: Int32) -> ref<NMReticle> {
        let r = new NMReticle();
        r.s = scale;
        r.idleColor = NMTheme.HoloHighlight(theme);
        r.legColor = NMTheme.ReticleColor(theme);
        let i = 0;
        while i < 8 {
            let q = NMUi.Rect(parent, 0.0, 0.0, 1.0, 1.0, r.legColor, NMReticle.IdleOpacity());
            q.SetAnchorPoint(new Vector2(0.5, 0.5));
            ArrayPush(r.legs, q);
            i += 1;
        }
        let k = NMReticle.PlusSize() * scale;
        let t = NMReticle.Thick() * scale;
        ArrayPush(r.plus, NMUi.Rect(parent, 0.0, 0.0, k, t, r.idleColor, 0.9));
        ArrayPush(r.plus, NMUi.Rect(parent, 0.0, 0.0, t, k, r.idleColor, 0.9));
        for p in r.plus { p.SetAnchorPoint(new Vector2(0.5, 0.5)); }
        let bw = NMReticle.HoldBarW() * scale;
        let bh = NMReticle.HoldBarH() * scale;
        let pad = NMReticle.HoldPad() * scale;
        r.holdPlate = NMUi.Rect(parent, 0.0, 0.0, bw + 2.0 * pad, bh + NMReticle.HoldLabelSize() * scale + 3.0 * pad, new HDRColor(0.0, 0.0, 0.0, 1.0), 0.7);
        r.holdPlate.SetVisible(false);
        r.holdTrack = NMUi.Rect(parent, 0.0, 0.0, bw, bh, r.idleColor, 0.25);
        r.holdFill = NMUi.Rect(parent, 0.0, 0.0, 0.0, bh, r.idleColor, 1.0);
        r.holdLabel = NMUi.Text(parent, NMTheme.BodyFont(), n"Semi-Bold", Cast<Int32>(NMReticle.HoldLabelSize() * scale), r.idleColor);
        r.holdLabel.SetText("TELEPORTING");
        r.holdLabel.SetLetterCase(textLetterCase.UpperCase);
        r.holdLabel.SetTracking(Cast<Int32>(3.0 * scale));
        r.holdLabel.SetAnchorPoint(new Vector2(0.5, 1.0));
        r.holdLabel.SetHorizontalAlignment(textHorizontalAlignment.Center);
        r.holdTrack.SetVisible(false);
        r.holdFill.SetVisible(false);
        r.holdLabel.SetVisible(false);
        return r;
    }

    // fx, fy: the focus point; sx, sy: the focused marker's screen position when hasSel; k: its tier scale.
    public func Update(fx: Float, fy: Float, hasSel: Bool, sx: Float, sy: Float, photo: Bool, thumbZoom: Float, k: Float, dtMs: Float) {
        let box = NMReticle.BoxFor(hasSel, photo, thumbZoom, k);
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
            let o = hasSel ? NMReticle.LockOpacity() : NMReticle.IdleOpacity();
            for q in this.legs { q.SetOpacity(o); }
        }
        // Every frame of an open map: skip the 16 widget writes while the box and the focus stay put (idle, or eased in).
        if this.drawn && AbsF(this.cx - this.dCx) < 0.05 && AbsF(this.cy - this.dCy) < 0.05 && AbsF(this.w - this.dW) < 0.05
            && AbsF(this.h - this.dH) < 0.05 && fx == this.dFx && fy == this.dFy {
            return;
        }
        this.drawn = true;
        this.dCx = this.cx; this.dCy = this.cy; this.dW = this.w; this.dH = this.h; this.dFx = fx; this.dFy = fy;
        let rs = NMReticle.Corners(this.cx, this.cy, this.w, this.h, NMReticle.Leg() * this.s, NMReticle.Thick() * this.s);
        let i = 0;
        while i < 8 {
            this.legs[i].SetTranslation(new Vector2(rs[i].X, rs[i].Y));
            this.legs[i].SetSize(new Vector2(rs[i].Z, rs[i].W));
            i += 1;
        }
        for p in this.plus { p.SetTranslation(new Vector2(fx, fy)); }
    }

    // The teleport hold bar under the focus point (fx, fy): p = 0 hides it, 1 fills it.
    public func SetHold(p: Float, fx: Float, fy: Float) {
        let on = p > 0.0;
        if !on && !this.holdShown {
            return;
        }
        if NotEquals(on, this.holdShown) {
            this.holdShown = on;
            this.holdPlate.SetVisible(on);
            this.holdTrack.SetVisible(on);
            this.holdFill.SetVisible(on);
            this.holdLabel.SetVisible(on);
        }
        if !on {
            return;
        }
        let bw = NMReticle.HoldBarW() * this.s;
        let bh = NMReticle.HoldBarH() * this.s;
        let x0 = fx - bw * 0.5;
        let y0 = fy + NMReticle.HoldBarGap() * this.s;
        this.holdTrack.SetTranslation(new Vector2(x0, y0));
        this.holdFill.SetTranslation(new Vector2(x0, y0));
        this.holdFill.SetSize(new Vector2(bw * ClampF(p, 0.0, 1.0), bh));
        this.holdLabel.SetTranslation(new Vector2(fx, y0 - 8.0 * this.s));
        let pad = NMReticle.HoldPad() * this.s;
        let lh = NMReticle.HoldLabelSize() * this.s;
        this.holdPlate.SetTranslation(new Vector2(x0 - pad, y0 - lh - 2.0 * pad));
    }
}
