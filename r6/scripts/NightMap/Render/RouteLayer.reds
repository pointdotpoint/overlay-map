module NightMap

// One route on the map: cached world polyline, its projected screen polyline and its traced-line pools.
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
    public let segGlow: array<ref<inkRectangle>>;
    public let segCore: array<ref<inkRectangle>>;
    public let jointGlow: array<ref<inkImage>>;
    public let jointCore: array<ref<inkImage>>;
    public let used: Int32;                // segments shown in the last layout
    public let joints: Int32;              // round joints shown in the last layout
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

// GPS routes as a traced line: a rotated rectangle per screen segment and a round joint (the minimap's own path dot)
// at each end, so bends read smooth (the native line-pattern widget cannot be created from script). Pooled widgets,
// at most SegmentCap() segments for both routes; the waypoint route claims the cap first and is drawn over the quest
// route. Joints wait for the minimap's style. Layout reruns only when the camera, the player or a route changed.
public class NMRouteLayer {
    private let root: ref<inkCanvas>;
    private let s: Float;
    private let effects: Bool;
    private let style: ref<NMRouteStyle>;
    private let quest: ref<NMRouteLine>;
    private let tracked: ref<NMRouteLine>;
    private let camRev: Int32;
    private let lastPx: Float;
    private let lastPy: Float;
    private let shown: Int32;

    public static func SegmentCap() -> Int32 { return 400; }   // shared by both routes; the waypoint route first
    public static func LineWidth() -> Float { return 24.0; }    // traced line width, 4K units (before the UI scale)
    public static func GlowSize() -> Float { return 2.2; }      // glow width, times the line's
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
    public func SegmentsShown() -> Int32 { return this.shown; }
    public func JointsShown() -> Int32 { return this.tracked.joints + this.quest.joints; }
    public func SetVisible(on: Bool) { this.root.SetVisible(on); }
    public func HasStyle() -> Bool { return IsDefined(this.style); }

    // Once per layer: the round joints use the minimap's path dot image.
    public func SetStyle(st: ref<NMRouteStyle>) {
        if !IsDefined(this.style) {
            this.style = st;
            this.tracked.dirty = true;   // lay out again with joints
            this.quest.dirty = true;
        }
    }

    private func W() -> Float { return NMRouteLayer.LineWidth() * this.s; }

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
        let moved = (px - this.lastPx) * (px - this.lastPx) + (py - this.lastPy) * (py - this.lastPy) > 0.0625;
        let reproject = moved || cam.revision != this.camRev;
        if reproject {
            this.camRev = cam.revision;
            this.lastPx = px;
            this.lastPy = py;
        }
        let drawT = this.Project(this.tracked, cam, px, py, reproject);
        let drawQ = this.Project(this.quest, cam, px, py, reproject);
        if !drawT && !drawQ && !this.tracked.tintDirty && !this.quest.tintDirty {
            return;   // nothing moved: the traced line stays as laid out
        }
        let budget = NMRouteLayer.SegmentCap();
        this.Layout(this.tracked, mapW, mapH, budget);
        budget -= this.tracked.used;
        this.Layout(this.quest, mapW, mapH, budget);
        this.shown = this.tracked.used + this.quest.used;
    }

    // Trim the passed part (world metres), project and simplify at 1 px. True when the screen polyline changed.
    private func Project(l: ref<NMRouteLine>, cam: ref<NMCamera>, px: Float, py: Float, force: Bool) -> Bool {
        if !force && !l.dirty { return false; }
        l.dirty = false;
        ArrayClear(l.screen);
        if ArraySize(l.world) < 2 { return true; }
        let proj: array<Vector2>;
        l.cursor = Max(NMRouteGeom.Closest(l.world, px, py, l.cursor), 0);
        for w in NMRouteGeom.TrimAt(l.world, px, py, l.cursor) {
            ArrayPush(proj, cam.WorldToMap(w.X, w.Y));
        }
        // Points about a line width apart: short segments much narrower than the line stagger their square ends
        // into a sawtooth edge on curves.
        let w = this.W();
        l.screen = NMRouteLayer.Thin(NMRouteGeom.Simplify(proj, MaxF(1.0, w * 0.25)), w * 0.75);
        return true;
    }

    // Keeps the first and last point and every point at least minLen from the previous kept one.
    public static func Thin(pts: array<Vector2>, minLen: Float) -> array<Vector2> {
        let n = ArraySize(pts);
        if n <= 2 { return pts; }
        let out: array<Vector2>;
        ArrayPush(out, pts[0]);
        let m2 = minLen * minLen;
        let i = 1;
        while i < n - 1 {
            if NMRouteGeom.Dist2(out[ArraySize(out) - 1], pts[i]) >= m2 {
                ArrayPush(out, pts[i]);
            }
            i += 1;
        }
        ArrayPush(out, pts[n - 1]);
        return out;
    }

    // One rotated rectangle per screen segment that touches the view (plus a margin), and a round joint at each of
    // their ends so bends stay smooth. At most `budget` segments.
    private func Layout(l: ref<NMRouteLine>, mapW: Float, mapH: Float, budget: Int32) {
        let n = ArraySize(l.screen);
        let used = 0;
        let joints = 0;
        let m = NMRouteLayer.ClipMargin() * this.s;
        let prevDrawn = false;
        let i = 0;
        while i < n - 1 && used < budget {
            let a = l.screen[i];
            let b = l.screen[i + 1];
            let on = MaxF(a.X, b.X) >= -m && MinF(a.X, b.X) <= mapW + m && MaxF(a.Y, b.Y) >= -m && MinF(a.Y, b.Y) <= mapH + m;
            if on {
                this.PlaceSegment(l, used, a, b);
                used += 1;
                if IsDefined(this.style) {
                    if !prevDrawn {
                        this.PlaceJoint(l, joints, a);
                        joints += 1;
                    }
                    this.PlaceJoint(l, joints, b);
                    joints += 1;
                }
            }
            prevDrawn = on;
            i += 1;
        }
        let k = used;
        while k < l.used {
            l.segCore[k].SetVisible(false);
            if this.effects { l.segGlow[k].SetVisible(false); }
            k += 1;
        }
        k = joints;
        while k < l.joints {
            l.jointCore[k].SetVisible(false);
            if this.effects { l.jointGlow[k].SetVisible(false); }
            k += 1;
        }
        if l.tintDirty {
            l.tintDirty = false;
            let j = 0;
            while j < ArraySize(l.segCore) {
                l.segCore[j].SetTintColor(l.color);
                if this.effects { l.segGlow[j].SetTintColor(l.color); }
                j += 1;
            }
            j = 0;
            while j < ArraySize(l.jointCore) {
                l.jointCore[j].SetTintColor(l.color);
                if this.effects { l.jointGlow[j].SetTintColor(l.color); }
                j += 1;
            }
        }
        l.used = used;
        l.joints = joints;
    }

    private func PlaceSegment(l: ref<NMRouteLine>, i: Int32, a: Vector2, b: Vector2) {
        if i >= ArraySize(l.segCore) {
            if this.effects {
                ArrayPush(l.segGlow, this.Bar(l.glowCanvas, l.color, NMRouteLayer.GlowOpacity()));
            }
            ArrayPush(l.segCore, this.Bar(l.coreCanvas, l.color, 1.0));
        }
        let mid = new Vector2((a.X + b.X) * 0.5, (a.Y + b.Y) * 0.5);
        let len = SqrtF(NMRouteGeom.Dist2(a, b));
        let ang = Rad2Deg(AtanF(b.Y - a.Y, b.X - a.X));
        let w = this.W();
        let c = l.segCore[i];
        c.SetTranslation(mid);
        c.SetSize(new Vector2(len, w));
        c.SetRotation(ang);
        c.SetVisible(true);
        if this.effects {
            let g = l.segGlow[i];
            g.SetTranslation(mid);
            g.SetSize(new Vector2(len, w * NMRouteLayer.GlowSize()));
            g.SetRotation(ang);
            g.SetVisible(true);
        }
    }

    private func PlaceJoint(l: ref<NMRouteLine>, i: Int32, p: Vector2) {
        if i >= ArraySize(l.jointCore) {
            if this.effects {
                ArrayPush(l.jointGlow, this.Dot(l.glowCanvas, NMRouteLayer.GlowSize(), l.color, NMRouteLayer.GlowOpacity()));
            }
            ArrayPush(l.jointCore, this.Dot(l.coreCanvas, 1.0, l.color, 1.0));
        }
        l.jointCore[i].SetTranslation(p);
        l.jointCore[i].SetVisible(true);
        if this.effects {
            l.jointGlow[i].SetTranslation(p);
            l.jointGlow[i].SetVisible(true);
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

    // A round joint the line's width across (the minimap's path dot image).
    private func Dot(parent: ref<inkCanvas>, sizeMul: Float, color: HDRColor, opacity: Float) -> ref<inkImage> {
        let st = this.style;
        let d = this.W() * sizeMul;
        let img = new inkImage();
        img.SetAnchor(inkEAnchor.TopLeft);
        img.SetAnchorPoint(new Vector2(0.5, 0.5));
        img.SetInteractive(false);
        img.SetAtlasResource(st.atlas);
        img.SetTexturePart(st.part);
        img.SetSize(new Vector2(d, d));
        img.SetTintColor(color);
        img.SetOpacity(opacity);
        img.Reparent(parent);
        return img;
    }
}
