module NightMap

// One route on the map: cached world polyline, its projected screen polyline and its dash pools.
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
    public let glow: array<ref<inkRectangle>>;
    public let core: array<ref<inkRectangle>>;
    public let used: Int32;                // dashes shown in the last layout
}

// GPS routes as flowing dashes (spec 2026-10-27-nightmap-gps-route-design.md §4.3). Pooled rotated rectangles
// (the §4.4 fallback), at most DashCap() for both routes; the waypoint route claims the cap first. Quest route drawn
// under the waypoint route. Projection reruns only when the camera, the player or a route changed; each frame only
// moves the dash phase.
public class NMRouteLayer {
    private let root: ref<inkCanvas>;
    private let s: Float;
    private let effects: Bool;
    private let quest: ref<NMRouteLine>;
    private let tracked: ref<NMRouteLine>;
    private let phase: Float;
    private let camRev: Int32;
    private let lastPx: Float;
    private let lastPy: Float;
    private let shown: Int32;

    public static func DashCap() -> Int32 { return 400; }
    public static func DashLen() -> Float { return 16.0; }
    public static func GapLen() -> Float { return 8.0; }
    public static func Thickness() -> Float { return 4.0; }
    public static func GlowThickness() -> Float { return 8.0; }
    public static func GlowOpacity() -> Float { return 0.25; }
    public static func FlowSpeed() -> Float { return 30.0; }   // units per second, toward the destination
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
    public func SetVisible(on: Bool) { this.root.SetVisible(on); }

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
        let period = (NMRouteLayer.DashLen() + NMRouteLayer.GapLen()) * this.s;
        this.phase += NMRouteLayer.FlowSpeed() * this.s * dtMs / 1000.0;
        while this.phase >= period { this.phase -= period; }
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
        this.Layout(this.tracked, period, mapW, mapH, budget);
        budget -= this.tracked.used;
        this.Layout(this.quest, period, mapW, mapH, budget);
        this.shown = this.tracked.used + this.quest.used;
    }

    // Trim the passed part (world metres), project, simplify at 1 px, and cache cumulative lengths.
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
        l.screen = NMRouteGeom.Simplify(proj, 1.0);
        let acc = 0.0;
        let i = 0;
        while i < ArraySize(l.screen) {
            if i > 0 { acc += SqrtF(NMRouteGeom.Dist2(l.screen[i - 1], l.screen[i])); }
            ArrayPush(l.cum, acc);
            i += 1;
        }
    }

    // Dashes every `period` along the screen polyline, offset by the flow phase; one rectangle per dash, centred on the
    // dash midpoint and turned to its segment. Clipped to the map area plus a margin; at most `budget` dashes.
    private func Layout(l: ref<NMRouteLine>, period: Float, mapW: Float, mapH: Float, budget: Int32) {
        let n = ArraySize(l.screen);
        let used = 0;
        if n >= 2 && budget > 0 {
            let total = l.cum[n - 1];
            let dash = NMRouteLayer.DashLen() * this.s;
            let m = NMRouteLayer.ClipMargin() * this.s;
            let seg = 0;
            let d = this.phase - period + dash * 0.5;   // midpoint of the first (possibly partial) dash
            while d <= total && used < budget {
                if d >= 0.0 {
                    while seg < n - 2 && l.cum[seg + 1] < d { seg += 1; }
                    let a = l.screen[seg];
                    let b = l.screen[seg + 1];
                    let segLen = l.cum[seg + 1] - l.cum[seg];
                    let u = segLen > 0.0 ? (d - l.cum[seg]) / segLen : 0.0;
                    let x = a.X + (b.X - a.X) * u;
                    let y = a.Y + (b.Y - a.Y) * u;
                    if x >= -m && x <= mapW + m && y >= -m && y <= mapH + m {
                        this.Place(l, used, x, y, Rad2Deg(AtanF(b.Y - a.Y, b.X - a.X)));
                        used += 1;
                    }
                }
                d += period;
            }
        }
        let k = used;
        while k < l.used {
            l.core[k].SetVisible(false);
            if this.effects { l.glow[k].SetVisible(false); }
            k += 1;
        }
        if l.tintDirty {
            l.tintDirty = false;
            let j = 0;
            while j < ArraySize(l.core) {
                l.core[j].SetTintColor(l.color);
                if this.effects { l.glow[j].SetTintColor(l.color); }
                j += 1;
            }
        }
        l.used = used;
    }

    private func Place(l: ref<NMRouteLine>, i: Int32, x: Float, y: Float, angle: Float) {
        if i >= ArraySize(l.core) {
            if this.effects {
                ArrayPush(l.glow, this.Dash(l.glowCanvas, (NMRouteLayer.DashLen() + 4.0) * this.s, NMRouteLayer.GlowThickness() * this.s, l.color, NMRouteLayer.GlowOpacity()));
            }
            ArrayPush(l.core, this.Dash(l.coreCanvas, NMRouteLayer.DashLen() * this.s, NMRouteLayer.Thickness() * this.s, l.color, 1.0));
        }
        let p = new Vector2(x, y);
        let c = l.core[i];
        c.SetTranslation(p);
        c.SetRotation(angle);
        c.SetVisible(true);
        if this.effects {
            let g = l.glow[i];
            g.SetTranslation(p);
            g.SetRotation(angle);
            g.SetVisible(true);
        }
    }

    private func Dash(parent: ref<inkCanvas>, w: Float, h: Float, color: HDRColor, opacity: Float) -> ref<inkRectangle> {
        let r = NMUi.Rect(parent, 0.0, 0.0, w, h, color, opacity);
        r.SetAnchorPoint(new Vector2(0.5, 0.5));
        r.SetRenderTransformPivot(new Vector2(0.5, 0.5));
        return r;
    }
}
