module NightMap

// One route on the map: cached world polyline, its projected screen polyline and its line widgets.
public class NMRouteLine {
    public let world: array<Vector2>;
    public let screen: array<Vector2>;
    public let total: Float;               // screen length of `screen`
    public let color: HDRColor;
    public let dirty: Bool;                // world changed since the last projection
    public let cursor: Int32;              // last matched world segment (the trim search starts here)
    public let canvas: ref<inkCanvas>;
    public let glow: ref<inkLinePattern>;
    public let core: ref<inkLinePattern>;
}

// The look of the HUD minimap's GPS path widget, copied so NightMap's routes bend and repeat like the minimap's.
// Sizes are in minimap units; NMRouteLayer scales them to the map.
public class NMRouteStyle {
    public let atlas: ResourceAsyncRef;
    public let part: CName;
    public let size: Vector2;
    public let spacing: Float;
    public let looseSpacing: Float;
    public let rotate: Bool;

    public static func From(src: ref<inkLinePattern>) -> ref<NMRouteStyle> {
        let st = new NMRouteStyle();
        st.atlas = src.textureAtlas;
        st.part = src.texturePart;
        st.size = src.GetSize();
        st.spacing = src.spacing;
        st.looseSpacing = src.looseSpacing;
        st.rotate = src.rotateWithSegment;
        return st;
    }

    // No texture; the geometry of the old 16 + 8 dashes. Self-tests only.
    public static func Test() -> ref<NMRouteStyle> {
        let st = new NMRouteStyle();
        st.size = new Vector2(16.0, 4.0);
        st.spacing = 8.0;
        st.looseSpacing = 8.0;
        st.rotate = true;
        return st;
    }

    public func Describe() -> String {
        return "part=" + NameToString(this.part) + "|size=" + FloatToStringPrec(this.size.X, 2) + "x" + FloatToStringPrec(this.size.Y, 2)
            + "|spacing=" + FloatToStringPrec(this.spacing, 2) + "|loose=" + FloatToStringPrec(this.looseSpacing, 2)
            + "|rotate=" + ToString(this.rotate);
    }
}

// GPS routes drawn with the same native line-pattern widget the HUD minimap uses (spec §4.4), one per route plus a
// wider, fainter copy for the glow. Created by class name through Codeware reflection, since script cannot `new` it,
// and only once the minimap's style is known. Quest route under the waypoint route. Projection reruns only when the
// camera, the player or a route changed; each frame only moves the pattern's start offset (the flow).
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
    private let loggedNoWidget: Bool;

    public static func FlowSpeed() -> Float { return 30.0; }   // units per second, toward the destination
    public static func RouteScale() -> Float { return 1.0; }   // minimap units to map units, before the UI scale
    public static func GlowWidth() -> Float { return 2.5; }    // glow element height, times the core's
    public static func GlowOpacity() -> Float { return 0.25; }
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
        return l;
    }

    public func Root() -> ref<inkCanvas> { return this.root; }
    public func SetVisible(on: Bool) { this.root.SetVisible(on); }
    public func HasStyle() -> Bool { return IsDefined(this.style); }
    public func CoreWidget(tracked: Bool) -> ref<inkLinePattern> { return tracked ? this.tracked.core : this.quest.core; }
    public func LineLength(tracked: Bool) -> Float { return tracked ? this.tracked.total : this.quest.total; }

    // Distance between pattern elements along the line, in map units.
    public func Pitch() -> Float {
        if !IsDefined(this.style) { return 0.0; }
        return (this.style.size.X + this.style.spacing) * this.K();
    }

    private func K() -> Float { return this.s * NMRouteLayer.RouteScale(); }

    public func HasRoute() -> Bool {
        return ArraySize(this.quest.world) >= 2 || ArraySize(this.tracked.world) >= 2;
    }

    // Builds the line widgets from the minimap's look. Once per layer.
    public func SetStyle(st: ref<NMRouteStyle>) {
        if IsDefined(this.style) || !IsDefined(st) { return; }
        this.style = st;
        this.Build(this.quest);
        this.Build(this.tracked);
    }

    private func Build(l: ref<NMRouteLine>) {
        if this.effects {
            l.glow = this.Line(l.canvas, NMRouteLayer.GlowWidth(), NMRouteLayer.GlowOpacity(), l.color);
        }
        l.core = this.Line(l.canvas, 1.0, 1.0, l.color);
        l.dirty = true;
    }

    private func Line(parent: ref<inkCanvas>, widthMul: Float, opacity: Float, color: HDRColor) -> ref<inkLinePattern> {
        let w = FromVariant<ref<inkLinePattern>>(Reflection.GetClass(n"inkLinePattern").MakeInstance());
        if !IsDefined(w) {
            if !this.loggedNoWidget {
                this.loggedNoWidget = true;
                NMLog.Info("gps|line widget unavailable");
            }
            return null;
        }
        let st = this.style;
        let k = this.K();
        w.SetAnchor(inkEAnchor.TopLeft);
        w.SetInteractive(false);
        w.textureAtlas = st.atlas;
        w.texturePart = st.part;
        w.SetSize(new Vector2(st.size.X * k, st.size.Y * k * widthMul));
        w.spacing = st.spacing * k;
        w.looseSpacing = st.looseSpacing * k;
        w.rotateWithSegment = st.rotate;
        w.SetTintColor(color);
        w.SetOpacity(opacity);
        w.Reparent(parent);
        return w;
    }

    // World-space routes from the latest reading; an empty array clears that route.
    public func SetRoutes(questPts: array<Vector2>, questColor: HDRColor, trackedPts: array<Vector2>) {
        this.Assign(this.quest, questPts);
        this.Assign(this.tracked, trackedPts);
        let c = this.quest.color;
        if c.Red != questColor.Red || c.Green != questColor.Green || c.Blue != questColor.Blue {
            this.quest.color = questColor;
            if IsDefined(this.quest.core) { this.quest.core.SetTintColor(questColor); }
            if IsDefined(this.quest.glow) { this.quest.glow.SetTintColor(questColor); }
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
        this.Flow(this.tracked, pitch);
        this.Flow(this.quest, pitch);
    }

    // Trim the passed part (world metres), project, simplify at 1 px, and hand the points to the line widgets.
    private func Project(l: ref<NMRouteLine>, cam: ref<NMCamera>, px: Float, py: Float, force: Bool) {
        if !force && !l.dirty { return; }
        l.dirty = false;
        ArrayClear(l.screen);
        l.total = 0.0;
        if ArraySize(l.world) >= 2 {
            let proj: array<Vector2>;
            l.cursor = Max(NMRouteGeom.Closest(l.world, px, py, l.cursor), 0);
            for w in NMRouteGeom.TrimAt(l.world, px, py, l.cursor) {
                ArrayPush(proj, cam.WorldToMap(w.X, w.Y));
            }
            l.screen = NMRouteGeom.Simplify(proj, 1.0);
            l.total = NMRouteGeom.Length(l.screen);
        }
        this.SetVertices(l.core, l.screen);
        this.SetVertices(l.glow, l.screen);
    }

    private func SetVertices(w: ref<inkLinePattern>, pts: array<Vector2>) {
        if !IsDefined(w) { return; }
        let none: array<inkLineVertex>;
        w.vertexList = none;
        for p in pts { w.AddVertex(p); }
        w.SetVisible(ArraySize(pts) >= 2);
    }

    // Elements sit at fixed distances back from the destination (pitch - phase + k * pitch), so the pattern is pinned
    // to the road while V moves, and the phase moves it toward the destination.
    private func Flow(l: ref<NMRouteLine>, pitch: Float) {
        let off = NMRouteLayer.Wrap(l.total + this.phase, pitch);
        if IsDefined(l.core) { l.core.startOffset = off; }
        if IsDefined(l.glow) { l.glow.startOffset = off; }
    }
}
