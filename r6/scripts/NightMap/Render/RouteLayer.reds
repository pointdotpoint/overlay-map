module NightMap

// One route on the map: cached world polyline, its projected screen polyline and its dot pools.
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
    public let glow: array<ref<inkImage>>;
    public let core: array<ref<inkImage>>;
    public let used: Int32;                // dots shown in the last layout
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

// GPS routes drawn the way the HUD minimap draws them: a row of its own path dots, unrotated, so bends read smooth
// (spec §4.4; the native line-pattern widget cannot be created from script). Pooled inkImages, at most DotCap() for
// both routes; the waypoint route claims the cap first and is drawn over the quest route. Nothing is drawn until the
// minimap's style is known. Projection reruns only when the camera, the player or a route changed; each frame only
// moves the flow phase.
public class NMRouteLayer {
    private let root: ref<inkCanvas>;
    private let s: Float;
    private let effects: Bool;
    private let style: ref<NMRouteStyle>;
    private let quest: ref<NMRouteLine>;
    private let tracked: ref<NMRouteLine>;
    private let phase: Float;
    private let camRev: Int32;
    private let lastPx: Float;
    private let lastPy: Float;
    private let shown: Int32;

    public static func DotCap() -> Int32 { return 400; }
    public static func FlowSpeed() -> Float { return 30.0; }   // units per second, toward the destination
    public static func RouteScale() -> Float { return 1.25; }  // minimap units to map units, before the UI scale
    public static func GlowSize() -> Float { return 2.0; }     // glow dot size, times the core dot's
    public static func GlowOpacity() -> Float { return 0.25; }
    public static func ClipMargin() -> Float { return 64.0; }
    public static func WaypointColor() -> HDRColor { return new HDRColor(1.0, 1.0, 1.0, 1.0); }

    // x modulo p, in [0, p).
    public static func Wrap(x: Float, p: Float) -> Float {
        if p <= 0.0 { return 0.0; }
        return x - Cast<Float>(FloorF(x / p)) * p;
    }

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
    public func DotsShown() -> Int32 { return this.shown; }
    public func DotsUsed(tracked: Bool) -> Int32 { return tracked ? this.tracked.used : this.quest.used; }
    public func SetVisible(on: Bool) { this.root.SetVisible(on); }
    public func HasStyle() -> Bool { return IsDefined(this.style); }

    // Once per layer; dots are created lazily from it.
    public func SetStyle(st: ref<NMRouteStyle>) {
        if !IsDefined(this.style) { this.style = st; }
    }

    // Distance between dots along the line, in map units.
    public func Pitch() -> Float {
        if !IsDefined(this.style) { return 0.0; }
        return (this.style.size.X + this.style.spacing) * this.K();
    }

    private func K() -> Float { return this.s * NMRouteLayer.RouteScale(); }

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
        let pitch = this.Pitch();
        this.phase = NMRouteLayer.Wrap(this.phase + NMRouteLayer.FlowSpeed() * this.s * dtMs / 1000.0, pitch);
        let moved = (px - this.lastPx) * (px - this.lastPx) + (py - this.lastPy) * (py - this.lastPy) > 0.0625;
        let reproject = moved || cam.revision != this.camRev;
        if reproject {
            this.camRev = cam.revision;
            this.lastPx = px;
            this.lastPy = py;
        }
        this.Project(this.tracked, cam, px, py, reproject);
        this.Project(this.quest, cam, px, py, reproject);
        let budget = NMRouteLayer.DotCap();
        this.Layout(this.tracked, pitch, mapW, mapH, budget);
        budget -= this.tracked.used;
        this.Layout(this.quest, pitch, mapW, mapH, budget);
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

    // A dot every `pitch` along the screen polyline, counted back from the destination and offset by the flow phase.
    // Clipped to the map area plus a margin; at most `budget` dots.
    private func Layout(l: ref<NMRouteLine>, pitch: Float, mapW: Float, mapH: Float, budget: Int32) {
        let n = ArraySize(l.screen);
        let used = 0;
        if n >= 2 && budget > 0 && pitch > 0.0 {
            let total = l.cum[n - 1];
            let m = NMRouteLayer.ClipMargin() * this.s;
            let seg = 0;
            // Dots sit at fixed distances back from the destination (pitch - phase + k * pitch), so they are pinned
            // to the road while V moves and only the flow phase moves them; the phase moves them toward the
            // destination.
            let d = NMRouteLayer.Wrap(total - (pitch - this.phase), pitch);
            while d <= total && used < budget {
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
                d += pitch;
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
                ArrayPush(l.glow, this.Dot(l.glowCanvas, NMRouteLayer.GlowSize(), l.color, NMRouteLayer.GlowOpacity()));
            }
            ArrayPush(l.core, this.Dot(l.coreCanvas, 1.0, l.color, 1.0));
        }
        let p = new Vector2(x, y);
        let c = l.core[i];
        c.SetTranslation(p);
        if this.style.rotate { c.SetRotation(angle); }
        c.SetVisible(true);
        if this.effects {
            let g = l.glow[i];
            g.SetTranslation(p);
            if this.style.rotate { g.SetRotation(angle); }
            g.SetVisible(true);
        }
    }

    private func Dot(parent: ref<inkCanvas>, sizeMul: Float, color: HDRColor, opacity: Float) -> ref<inkImage> {
        let st = this.style;
        let k = this.K() * sizeMul;
        let img = new inkImage();
        img.SetAnchor(inkEAnchor.TopLeft);
        img.SetAnchorPoint(new Vector2(0.5, 0.5));
        img.SetRenderTransformPivot(new Vector2(0.5, 0.5));
        img.SetInteractive(false);
        if IsNameValid(st.part) {
            img.SetAtlasResource(st.atlas);
            img.SetTexturePart(st.part);
        }
        img.SetSize(new Vector2(st.size.X * k, st.size.Y * k));
        img.SetTintColor(color);
        img.SetOpacity(opacity);
        img.Reparent(parent);
        return img;
    }
}
