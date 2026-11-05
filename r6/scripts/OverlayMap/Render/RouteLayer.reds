module OverlayMap

// One route on the map: cached world polyline, its smoothed screen polyline and its dash pools.
public class NMRouteLine {
    public let world: array<Vector2>;
    public let screen: array<Vector2>;
    public let cum: array<Float>;          // cumulative screen length at each screen point
    public let color: HDRColor;
    public let tintDirty: Bool;
    public let dirty: Bool;                // world changed since the last projection
    public let cursor: Int32;              // last matched world segment (the trim search starts here)
    // The world route simplified at one map pixel (in metres): kept indices, valid for simpleTol. A pan reuses them;
    // a zoom filters the per-point importance again (one Douglas-Peucker run per route, its most expensive step).
    public let imp: array<Float>;
    public let impOk: Bool;
    public let simpleIdx: array<Int32>;
    public let simpleTol: Float;
    public let simpleOk: Bool;
    public let canvas: ref<inkCanvas>;
    public let glowCanvas: ref<inkCanvas>;   // empty; kept so the core canvas stays child 1
    public let coreCanvas: ref<inkCanvas>;
    public let dashCore: array<ref<inkImage>>;
    public let used: Int32;                // dashes shown in the last layout
}

// The look of the HUD minimap's GPS path widget (an inkLinePattern of unrotated `pathCircle` dots), copied so
// OverlayMap's routes read like the minimap's. Sizes are in minimap units; NMRouteLayer scales them to the map.
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

// GPS routes as a thin solid line, like the vanilla map: the screen route is rounded off (corner cutting), then
// short overlapping pieces are laid along it every PieceStep() back from the destination, so the line stays pinned to
// the road while V moves. Pooled images of the atlas's holo_line part, whose alpha fades to 0 at its top and bottom
// rows, so texture filtering antialiases the rotated edges (plain rectangles alias). No glow: overlapping translucent
// pieces would band. At most
// DashCap() for both routes; the waypoint route claims the cap first and is drawn over the quest route. Projection
// and layout rerun only when the camera, the player or a route changed.
public class NMRouteLayer {
    private let root: ref<inkCanvas>;
    private let s: Float;
    private let style: ref<NMRouteStyle>;
    private let quest: ref<NMRouteLine>;
    private let tracked: ref<NMRouteLine>;
    private let camRev: Int32;
    private let lastPx: Float;
    private let lastPy: Float;
    private let shown: Int32;
    private let simplifyRuns: Int32;
    private let importanceRuns: Int32;
    // Perf suite only (profile on): the last Update's stage times and sizes.
    public let profile: Bool;
    public let projMs: Float;
    public let layoutMs: Float;
    public let placeMs: Float;    // widget calls, part of layoutMs
    public let trimMs: Float;     // projMs stages: trim (closest + copy), WorldToMap, Simplify, Smooth + lengths
    public let mapMs: Float;
    public let simpMs: Float;
    public let smoothMs: Float;
    public let iters: Int32;      // pieces stepped along the route, on screen or not
    public let worldPts: Int32;
    public let screenPts: Int32;

    public static func DashCap() -> Int32 { return 500; }       // pieces, shared by both routes; the waypoint route first
    public static func LineWidth() -> Float { return 10.0; }    // line width, 4K units (before the UI scale)
    public static func PieceLen() -> Float { return 3.0; }      // piece length, times the width
    public static func PieceStep() -> Float { return 2.5; }     // piece spacing, times the width; < PieceLen so they overlap
    public static func Feather() -> Float { return 16.0 / 12.0; } // holo_line is half opaque over 12 of its 16 rows
    public static func ClipMargin() -> Float { return 64.0; }
    public static func WaypointColor() -> HDRColor { return new HDRColor(1.0, 1.0, 1.0, 1.0); }

    public static func Create(parent: ref<inkCanvas>, scale: Float, effects: Bool) -> ref<NMRouteLayer> {
        let L = new NMRouteLayer();
        L.s = scale;
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
    public func SimplifyRuns() -> Int32 { return this.simplifyRuns; }
    public func ImportanceRuns() -> Int32 { return this.importanceRuns; }
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
            l.simpleOk = false;
            l.impOk = false;
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
        if this.profile { this.projMs = 0.0; this.layoutMs = 0.0; this.placeMs = 0.0; this.iters = 0; this.trimMs = 0.0; this.mapMs = 0.0; this.simpMs = 0.0; this.smoothMs = 0.0; }
        if !reproject && !this.tracked.dirty && !this.quest.dirty && !this.tracked.tintDirty && !this.quest.tintDirty { return; }
        let t0 = this.profile ? NMClock.NowMs() : 0.0;
        this.Project(this.tracked, cam, px, py, reproject);
        this.Project(this.quest, cam, px, py, reproject);
        let t1 = this.profile ? NMClock.NowMs() : 0.0;
        let budget = NMRouteLayer.DashCap();
        this.Layout(this.tracked, mapW, mapH, budget);
        budget -= this.tracked.used;
        this.Layout(this.quest, mapW, mapH, budget);
        this.shown = this.tracked.used + this.quest.used;
        if this.profile {
            this.projMs = t1 - t0;
            this.layoutMs = NMClock.NowMs() - t1;
            this.worldPts = ArraySize(this.tracked.world) + ArraySize(this.quest.world);
            this.screenPts = ArraySize(this.tracked.screen) + ArraySize(this.quest.screen);
        }
    }

    private func W() -> Float { return NMRouteLayer.LineWidth() * this.s; }
    private func Step() -> Float { return NMRouteLayer.PieceStep() * this.W(); }

    // Trim the passed part (world metres), simplify at 1 px (cached per route and zoom), project, round the corners and
    // cache cumulative lengths. The trimmed line is [V, V on the cursor segment, the kept points after that segment]:
    // simplifying the whole route instead of the trimmed one moves the line at most ~2 px near V.
    private func Project(l: ref<NMRouteLine>, cam: ref<NMCamera>, px: Float, py: Float, force: Bool) {
        if !force && !l.dirty { return; }
        l.dirty = false;
        ArrayClear(l.screen);
        ArrayClear(l.cum);
        let n = ArraySize(l.world);
        if n < 2 { return; }
        let t0 = this.profile ? NMClock.NowMs() : 0.0;
        l.cursor = Max(NMRouteGeom.Closest(l.world, px, py, l.cursor), 0);
        let seg = l.cursor;
        let t1 = this.profile ? NMClock.NowMs() : 0.0;
        let tol = NMRouteLayer.PixelMetres(cam);
        if !l.simpleOk || AbsF(tol - l.simpleTol) > tol * 0.0001 {
            if !l.impOk {
                l.imp = NMRouteGeom.Importance(l.world);
                l.impOk = true;
                this.importanceRuns += 1;
            }
            l.simpleIdx = NMRouteGeom.KeepIdx(l.imp, tol);
            l.simpleTol = tol;
            l.simpleOk = true;
            this.simplifyRuns += 1;
        }
        let t2 = this.profile ? NMClock.NowMs() : 0.0;
        let p = new Vector2(px, py);
        let q = NMRouteGeom.Project(p, l.world[seg], l.world[seg + 1]);
        let proj: array<Vector2>;
        ArrayPush(proj, cam.WorldToMap(p.X, p.Y));
        ArrayPush(proj, cam.WorldToMap(q.X, q.Y));
        for k in l.simpleIdx {
            if k > seg {
                let w = l.world[k];
                ArrayPush(proj, cam.WorldToMap(w.X, w.Y));
            }
        }
        let t3 = this.profile ? NMClock.NowMs() : 0.0;
        l.screen = NMRouteLayer.Smooth(proj, 2);
        let acc = 0.0;
        let i = 0;
        while i < ArraySize(l.screen) {
            if i > 0 { acc += SqrtF(NMRouteGeom.Dist2(l.screen[i - 1], l.screen[i])); }
            ArrayPush(l.cum, acc);
            i += 1;
        }
        if this.profile {
            this.trimMs += t1 - t0;
            this.simpMs += t2 - t1;
            this.mapMs += t3 - t2;
            this.smoothMs += NMClock.NowMs() - t3;
        }
    }

    // Metres per map pixel at this zoom: Douglas-Peucker is unchanged by the camera's move and uniform scale, so
    // simplifying the world route at this tolerance keeps the same points as simplifying the projected one at 1 px.
    public static func PixelMetres(cam: ref<NMCamera>) -> Float {
        let a = cam.WorldToMap(0.0, 0.0);
        let b = cam.WorldToMap(1.0, 0.0);
        let d = SqrtF(NMRouteGeom.Dist2(a, b));
        return d > 0.0 ? 1.0 / d : 1.0;
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

    // Pieces end every Step() back from the destination (so they stay pinned to it); the first piece starts at V.
    // Clipped to the map area plus a margin; at most `budget`.
    private func Layout(l: ref<NMRouteLine>, mapW: Float, mapH: Float, budget: Int32) {
        let n = ArraySize(l.screen);
        let used = 0;
        if n >= 2 && budget > 0 {
            let total = l.cum[n - 1];
            let len = NMRouteLayer.PieceLen() * this.W();
            let step = this.Step();
            let m = NMRouteLayer.ClipMargin() * this.s;
            let e = total - Cast<Float>(FloorF(total / step)) * step;   // the piece end nearest V, in [0, step)
            if e <= 0.0 { e += step; }
            let seg = 0;
            while e <= total + 0.01 && used < budget {
                let st = MaxF(e - len, 0.0);
                let en = MinF(MaxF(e, st + len), total);   // the first piece keeps its full length from V
                seg = this.SegAt(l, st, seg);
                let a = this.At(l, st, seg);
                let b = this.At(l, en, this.SegAt(l, en, seg));
                if MaxF(a.X, b.X) >= -m && MinF(a.X, b.X) <= mapW + m && MaxF(a.Y, b.Y) >= -m && MinF(a.Y, b.Y) <= mapH + m {
                    let tp = this.profile ? NMClock.NowMs() : 0.0;
                    this.PlacePiece(l, used, a, b);
                    if this.profile { this.placeMs += NMClock.NowMs() - tp; }
                    used += 1;
                }
                if this.profile { this.iters += 1; }
                e += step;
            }
        }
        let k = used;
        while k < l.used {
            l.dashCore[k].SetVisible(false);
            k += 1;
        }
        if l.tintDirty {
            l.tintDirty = false;
            for r in l.dashCore { r.SetTintColor(l.color); }
        }
        l.used = used;
    }

    private func PlacePiece(l: ref<NMRouteLine>, i: Int32, a: Vector2, b: Vector2) {
        if i >= ArraySize(l.dashCore) {
            ArrayPush(l.dashCore, this.Bar(l.coreCanvas, l.color, 1.0));
        }
        let c = l.dashCore[i];
        c.SetTranslation(new Vector2((a.X + b.X) * 0.5, (a.Y + b.Y) * 0.5));
        c.SetSize(new Vector2(SqrtF(NMRouteGeom.Dist2(a, b)), this.W() * NMRouteLayer.Feather()));
        c.SetRotation(Rad2Deg(AtanF(b.Y - a.Y, b.X - a.X)));
        c.SetVisible(true);
    }

    private func Bar(parent: ref<inkCanvas>, color: HDRColor, opacity: Float) -> ref<inkImage> {
        let r = new inkImage();
        r.SetAtlasResource(NMTheme.HoloAtlas());
        r.SetTexturePart(n"holo_line");
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
