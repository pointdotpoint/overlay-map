module NightMap

// One route on the map: cached world polyline, its smoothed screen polyline and its dash pools.
public class NMRouteLine {
    public let world: array<Vector2>;
    public let screen: array<Vector2>;
    public let cum: array<Float>;          // cumulative screen length at each screen point
    public let color: HDRColor;
    public let tintDirty: Bool;
    public let dirty: Bool;                // world changed since the last projection
    public let cursor: Int32;              // last matched world segment (the trim search starts here)
    public let canvas: ref<inkCanvas>;
    public let glowCanvas: ref<inkCanvas>;
    public let coreCanvas: ref<inkCanvas>;
    public let dashGlow: array<ref<inkRectangle>>;
    public let dashCore: array<ref<inkRectangle>>;
    public let used: Int32;                // dashes shown in the last layout
}

// The look of the HUD minimap's GPS path widget (an inkLinePattern of unrotated `pathCircle` dots), copied so
// NightMap's routes read like the minimap's. Sizes are in minimap units; NMRouteLayer scales them to the map.
public class NMRouteStyle {
    public let atlas: ResRef;
    public let part: CName;
    public let size: Vector2;
    public let spacing: Float;
    public let rotate: Bool;

    public static func From(src: ref<inkLinePattern>) -> ref<NMRouteStyle> {
        let st = new NMRouteStyle();
        st.atlas = ResourceAsyncRef.GetPath(src.textureAtlas);
        st.part = src.texturePart;
        st.size = src.GetSize();
        st.spacing = src.spacing;
        st.rotate = src.rotateWithSegment;
        return st;
    }

    // No texture, the minimap's measured geometry (13 x 13 dots, spacing 5). Self-tests only.
    public static func Test() -> ref<NMRouteStyle> {
        let st = new NMRouteStyle();
        st.size = new Vector2(13.0, 13.0);
        st.spacing = 5.0;
        return st;
    }

    public func Describe() -> String {
        return "part=" + NameToString(this.part) + "|size=" + FloatToStringPrec(this.size.X, 2) + "x" + FloatToStringPrec(this.size.Y, 2)
            + "|spacing=" + FloatToStringPrec(this.spacing, 2) + "|rotate=" + ToString(this.rotate);
    }
}

// GPS routes as dashes: the screen route is rounded off (corner cutting), then short dashes are laid along it at a
// fixed spacing measured back from the destination, so they stay pinned to the road while V moves and only the flow
// phase moves them toward the destination. Pooled rectangles, at most DashCap() for both routes; the waypoint route
// claims the cap first and is drawn over the quest route. Projection reruns only when the camera, the player or a
// route changed; each frame only advances the flow.
public class NMRouteLayer {
    private let root: ref<inkCanvas>;
    private let s: Float;
    private let effects: Bool;
    private let style: ref<NMRouteStyle>;
    private let quest: ref<NMRouteLine>;
    private let tracked: ref<NMRouteLine>;
    private let camRev: Int32;
    private let phase: Float;
    private let lastPx: Float;
    private let lastPy: Float;
    private let shown: Int32;

    public static func DashCap() -> Int32 { return 400; }       // shared by both routes; the waypoint route first
    public static func LineWidth() -> Float { return 24.0; }    // dash width, 4K units (before the UI scale)
    public static func DashLen() -> Float { return 1.5; }       // dash length, times the width
    public static func DashGap() -> Float { return 1.0; }       // gap between dashes, times the width
    public static func FlowSpeed() -> Float { return 30.0; }    // 4K units per second, toward the destination
    public static func GlowSize() -> Float { return 2.2; }      // glow width, times the dash's
    public static func GlowOpacity() -> Float { return 0.25; }
    public static func ClipMargin() -> Float { return 64.0; }
    public static func WaypointColor() -> HDRColor { return new HDRColor(1.0, 1.0, 1.0, 1.0); }

    public static func Create(parent: ref<inkCanvas>, scale: Float, effects: Bool) -> ref<NMRouteLayer> {
        let L = new NMRouteLayer();
        L.s = scale;
        L.effects = effects;
        L.camRev = -1;
        L.root = NMUi.Canvas(parent, 0.0, 0.0, 1.0, 1.0);
        L.quest = L.NewLine(n"quest");
        L.tracked = L.NewLine(n"tracked");   // created second: drawn on top
        L.tracked.color = NMRouteLayer.WaypointColor();
        return L;
    }

    private func NewLine(name: CName) -> ref<NMRouteLine> {
        let l = new NMRouteLine();
        l.canvas = NMUi.Canvas(this.root, 0.0, 0.0, 1.0, 1.0);
        l.canvas.SetName(name);
        l.glowCanvas = NMUi.Canvas(l.canvas, 0.0, 0.0, 1.0, 1.0);
        l.coreCanvas = NMUi.Canvas(l.canvas, 0.0, 0.0, 1.0, 1.0);
        return l;
    }

    public func Root() -> ref<inkCanvas> { return this.root; }
    public func DashesShown() -> Int32 { return this.shown; }
    public func DashesUsed(tracked: Bool) -> Int32 { return tracked ? this.tracked.used : this.quest.used; }
    public func SetVisible(on: Bool) { this.root.SetVisible(on); }
    public func HasStyle() -> Bool { return IsDefined(this.style); }

    // Kept for the minimap style log; dashes are plain rectangles and do not need it.
    public func SetStyle(st: ref<NMRouteStyle>) {
        if !IsDefined(this.style) { this.style = st; }
    }

    public func HasRoute() -> Bool {
        return ArraySize(this.quest.world) >= 2 || ArraySize(this.tracked.world) >= 2;
    }

    // World-space routes from the latest reading; an empty array clears that route.
    public func SetRoutes(questPts: array<Vector2>, questColor: HDRColor, trackedPts: array<Vector2>) {
        this.Assign(this.quest, questPts);
        this.Assign(this.tracked, trackedPts);
        let c = this.quest.color;
        if c.Red != questColor.Red || c.Green != questColor.Green || c.Blue != questColor.Blue {
            this.quest.color = questColor;
            this.quest.tintDirty = true;
        }
    }

    private func Assign(l: ref<NMRouteLine>, pts: array<Vector2>) {
        if NMRouteGeom.Changed(l.world, pts) {
            l.world = pts;
            l.dirty = true;
            l.cursor = 0;
        }
    }

    public func Update(cam: ref<NMCamera>, px: Float, py: Float, dtMs: Float, mapW: Float, mapH: Float) {
        let period = this.Period();
        this.phase = this.phase + NMRouteLayer.FlowSpeed() * this.s * MaxF(dtMs, 0.0) / 1000.0;
        this.phase -= Cast<Float>(FloorF(this.phase / period)) * period;
        let moved = (px - this.lastPx) * (px - this.lastPx) + (py - this.lastPy) * (py - this.lastPy) > 0.0625;
        let reproject = moved || cam.revision != this.camRev;
        if reproject {
            this.camRev = cam.revision;
            this.lastPx = px;
            this.lastPy = py;
        }
        this.Project(this.tracked, cam, px, py, reproject);
        this.Project(this.quest, cam, px, py, reproject);
        let budget = NMRouteLayer.DashCap();
        this.Layout(this.tracked, mapW, mapH, budget);
        budget -= this.tracked.used;
        this.Layout(this.quest, mapW, mapH, budget);
        this.shown = this.tracked.used + this.quest.used;
    }

    private func W() -> Float { return NMRouteLayer.LineWidth() * this.s; }
    private func Period() -> Float { return (NMRouteLayer.DashLen() + NMRouteLayer.DashGap()) * this.W(); }

    // Trim the passed part (world metres), project, simplify at 1 px, round the corners and cache cumulative lengths.
    private func Project(l: ref<NMRouteLine>, cam: ref<NMCamera>, px: Float, py: Float, force: Bool) {
        if !force && !l.dirty { return; }
        l.dirty = false;
        ArrayClear(l.screen);
        ArrayClear(l.cum);
        if ArraySize(l.world) < 2 { return; }
        let proj: array<Vector2>;
        l.cursor = Max(NMRouteGeom.Closest(l.world, px, py, l.cursor), 0);
        for w in NMRouteGeom.TrimAt(l.world, px, py, l.cursor) {
            ArrayPush(proj, cam.WorldToMap(w.X, w.Y));
        }
        l.screen = NMRouteLayer.Smooth(NMRouteGeom.Simplify(proj, 1.0), 2);
        let acc = 0.0;
        let i = 0;
        while i < ArraySize(l.screen) {
            if i > 0 { acc += SqrtF(NMRouteGeom.Dist2(l.screen[i - 1], l.screen[i])); }
            ArrayPush(l.cum, acc);
            i += 1;
        }
    }

    // Chaikin corner cutting, `passes` times; the end points stay where they are.
    public static func Smooth(pts: array<Vector2>, passes: Int32) -> array<Vector2> {
        let cur = pts;
        let k = 0;
        while k < passes && ArraySize(cur) > 2 {
            let out: array<Vector2>;
            ArrayPush(out, cur[0]);
            let i = 0;
            while i < ArraySize(cur) - 1 {
                let a = cur[i];
                let b = cur[i + 1];
                ArrayPush(out, new Vector2(a.X * 0.75 + b.X * 0.25, a.Y * 0.75 + b.Y * 0.25));
                ArrayPush(out, new Vector2(a.X * 0.25 + b.X * 0.75, a.Y * 0.25 + b.Y * 0.75));
                i += 1;
            }
            ArrayPush(out, cur[ArraySize(cur) - 1]);
            cur = out;
            k += 1;
        }
        return cur;
    }

    // The point at screen distance d along the line, from the segment search position seg (advanced in place).
    private func At(l: ref<NMRouteLine>, d: Float, seg: Int32) -> Vector2 {
        let n = ArraySize(l.screen);
        let a = l.screen[seg];
        let b = l.screen[Min(seg + 1, n - 1)];
        let segLen = l.cum[Min(seg + 1, n - 1)] - l.cum[seg];
        let u = segLen > 0.0 ? (d - l.cum[seg]) / segLen : 0.0;
        return new Vector2(a.X + (b.X - a.X) * u, a.Y + (b.Y - a.Y) * u);
    }

    private func SegAt(l: ref<NMRouteLine>, d: Float, seg: Int32) -> Int32 {
        let n = ArraySize(l.screen);
        let s = seg;
        while s < n - 2 && l.cum[s + 1] < d { s += 1; }
        return s;
    }

    // Whole dashes only, every Period() back from the destination, shifted by the flow phase; clipped to the map area
    // plus a margin; at most `budget`.
    private func Layout(l: ref<NMRouteLine>, mapW: Float, mapH: Float, budget: Int32) {
        let n = ArraySize(l.screen);
        let used = 0;
        if n >= 2 && budget > 0 {
            let total = l.cum[n - 1];
            let w = this.W();
            let len = NMRouteLayer.DashLen() * w;
            let period = this.Period();
            let m = NMRouteLayer.ClipMargin() * this.s;
            // Dash ends sit at total - (period - phase) - k * period (k = 0, 1, ...): pinned to the destination, and a
            // growing phase moves them toward it.
            let first = total - (period - this.phase);
            while first - period >= 0.0 { first -= period; }   // the dash end nearest the start
            let seg = 0;
            let e = first;
            while e <= total && used < budget {
                let st = e - len;
                if st >= 0.0 {
                    seg = this.SegAt(l, st, seg);
                    let a = this.At(l, st, seg);
                    let seg2 = this.SegAt(l, e, seg);
                    let b = this.At(l, e, seg2);
                    if MaxF(a.X, b.X) >= -m && MinF(a.X, b.X) <= mapW + m && MaxF(a.Y, b.Y) >= -m && MinF(a.Y, b.Y) <= mapH + m {
                        this.PlaceDash(l, used, a, b);
                        used += 1;
                    }
                }
                e += period;
            }
        }
        let k = used;
        while k < l.used {
            l.dashCore[k].SetVisible(false);
            if this.effects { l.dashGlow[k].SetVisible(false); }
            k += 1;
        }
        if l.tintDirty {
            l.tintDirty = false;
            let j = 0;
            while j < ArraySize(l.dashCore) {
                l.dashCore[j].SetTintColor(l.color);
                if this.effects { l.dashGlow[j].SetTintColor(l.color); }
                j += 1;
            }
        }
        l.used = used;
    }

    private func PlaceDash(l: ref<NMRouteLine>, i: Int32, a: Vector2, b: Vector2) {
        if i >= ArraySize(l.dashCore) {
            if this.effects {
                ArrayPush(l.dashGlow, this.Bar(l.glowCanvas, l.color, NMRouteLayer.GlowOpacity()));
            }
            ArrayPush(l.dashCore, this.Bar(l.coreCanvas, l.color, 1.0));
        }
        let mid = new Vector2((a.X + b.X) * 0.5, (a.Y + b.Y) * 0.5);
        let len = SqrtF(NMRouteGeom.Dist2(a, b));
        let ang = Rad2Deg(AtanF(b.Y - a.Y, b.X - a.X));
        let w = this.W();
        let c = l.dashCore[i];
        c.SetTranslation(mid);
        c.SetSize(new Vector2(len, w));
        c.SetRotation(ang);
        c.SetVisible(true);
        if this.effects {
            let g = l.dashGlow[i];
            g.SetTranslation(mid);
            g.SetSize(new Vector2(len + w * (NMRouteLayer.GlowSize() - 1.0), w * NMRouteLayer.GlowSize()));
            g.SetRotation(ang);
            g.SetVisible(true);
        }
    }

    private func Bar(parent: ref<inkCanvas>, color: HDRColor, opacity: Float) -> ref<inkRectangle> {
        let r = new inkRectangle();
        r.SetAnchor(inkEAnchor.TopLeft);
        r.SetAnchorPoint(new Vector2(0.5, 0.5));
        r.SetRenderTransformPivot(new Vector2(0.5, 0.5));
        r.SetInteractive(false);
        r.SetTintColor(color);
        r.SetOpacity(opacity);
        r.Reparent(parent);
        return r;
    }
}
