module OverlayMap

// The corner minimap: a persistent, north-up OverlayMap in the vanilla minimap's box. Its own camera, tile stack, marker
// renderer, route layer and V marker, all reading the shared OverlayMap API. Never takes input.
public class NMCorner {
    public let layout: ref<NMCornerLayout>;
    public let cfg: ref<NMCornerConfig>;
    private let root: ref<inkCanvas>;
    private let mapArea: ref<inkCompoundWidget>;
    private let mapContent: ref<inkCanvas>;
    public let tiles: ref<inkCanvas>;
    public let routesCanvas: ref<inkCanvas>;
    public let shapes: ref<inkCanvas>;       // cones and areas (minimap parity), between routes and markers
    public let items: ref<inkCanvas>;
    public let overlay: ref<inkCanvas>;
    public let frame: ref<inkCanvas>;        // outside the clip: ring / brackets, zone label
    private let mask: ref<inkMask>;
    private let ringCount: Int32;
    private let bracketCount: Int32;
    private let stripBg: ref<inkRectangle>;
    private let zoneScrim: ref<inkRectangle>;
    private let zoneText: ref<inkText>;
    private let zoneKey: String;
    private let stripLeft: ref<inkText>;
    private let stripRight: ref<inkText>;
    private let stripLeftText: String;
    private let stripRightText: String;
    public let camera: ref<NMCamera>;
    public let layers: ref<NMLayerStack>;
    public let renderer: ref<NMItemRenderer>;
    public let routes: ref<NMRouteLayer>;
    private let marker: ref<NMPlayerMarker>;
    public let mirrorLayer: ref<NMShapeLayer>;
    private let panelLayout: ref<NMPanelLayout>;
    private let shown: Bool;
    // Markers and routes are laid out against layCam and their canvases slide by the live camera's offset in between:
    // north-up at a fixed zoom, a slide is exact, and the relayout (1.1 ms a moving frame) runs a few times a second.
    private let layCam: ref<NMCamera>;
    private let layFrames: Int32;
    private let layMpp: Float;
    public let msTiles: Float;    // last Update's split (profiling: NMCornerPerf)
    public let msRoutes: Float;
    public let msItems: Float;

    public static func DefaultMpp() -> Float { return 0.4; }
    public static func RimInset() -> Float { return 22.0; }       // 4K units: clamped markers sit this far inside the rim
    public static func RingInset() -> Float { return 3.0; }       // 4K units between stacked rings
    public static func BracketScale() -> Float { return 0.45; }   // of NMTheme.BracketSize(), at frame thickness 1
    public static func StripFont() -> Float { return 30.0; }      // 4K units, at text size 1
    public static func StripPad() -> Float { return 14.0; }       // 4K units
    public static func RelayoutPx() -> Float { return 40.0; }     // 4K units of slide before markers are laid out again
    public static func RelayoutFrames() -> Int32 { return 20; }

    public static func NeedsRelayout(dx: Float, dy: Float, frames: Int32, mppChanged: Bool, limitPx: Float, maxFrames: Int32) -> Bool {
        return mppChanged || frames >= maxFrames || AbsF(dx) > limitPx || AbsF(dy) > limitPx;
    }

    public static func Build(window: wref<inkCompoundWidget>, layout: ref<NMCornerLayout>, cfg: ref<NMCornerConfig>, api: ref<OverlayMap>, mpp: Float) -> ref<NMCorner> {
        let c = new NMCorner();
        c.layout = layout;
        c.cfg = cfg;
        let s = layout.scale;
        let th = cfg.theme;
        c.root = NMUi.Canvas(window, layout.x, layout.y, layout.w, layout.h);
        c.root.SetName(n"OverlayMapCorner");
        c.root.SetInteractive(false);

        // Map area, clipped: a square scroll-area mask (as NMPanel), or a disc mask before the content (Circle).
        if layout.round {
            let disc = NMUi.HoloImage(c.root, n"holo_disc", layout.mapX, layout.mapY, layout.mapW, layout.mapH,
                NMTheme.HoloBackground(th), cfg.opacity, inkBrushTileType.NoTile);
            disc.SetName(n"CornerFill");
            let holder = NMUi.Canvas(c.root, layout.mapX, layout.mapY, layout.mapW, layout.mapH);
            holder.SetName(n"CornerMapView");
            c.mask = new inkMask();
            c.mask.SetAnchor(inkEAnchor.TopLeft);
            c.mask.SetSize(new Vector2(layout.mapW, layout.mapH));
            c.mask.SetTextureAtlas(NMTheme.HoloAtlas());
            c.mask.texturePart = n"holo_disc";
            c.mask.SetDataSource(inkMaskDataSource.TextureAtlas);
            c.mask.SetName(n"CornerMask");
            c.mask.Reparent(holder);
            c.mapArea = holder;
        } else {
            NMUi.Rect(c.root, layout.mapX, layout.mapY, layout.mapW, layout.mapH, NMTheme.HoloBackground(th), cfg.opacity);
            let area = new inkScrollArea();
            area.SetAnchor(inkEAnchor.TopLeft);
            area.SetTranslation(new Vector2(layout.mapX, layout.mapY));
            area.SetSize(new Vector2(layout.mapW, layout.mapH));
            area.SetConstrainContentPosition(false);
            area.SetUseInternalMask(true);
            area.SetInteractive(false);
            area.SetName(n"CornerMapView");
            area.Reparent(c.root);
            c.mapArea = area;
        }
        c.mapContent = new inkCanvas();
        c.mapContent.SetSize(new Vector2(layout.mapW, layout.mapH));
        c.mapContent.SetInteractive(false);
        c.mapContent.Reparent(c.mapArea);
        c.tiles = NMUi.Canvas(c.mapContent, 0.0, 0.0, layout.mapW, layout.mapH);
        c.routesCanvas = NMUi.Canvas(c.mapContent, 0.0, 0.0, layout.mapW, layout.mapH);
        c.shapes = NMUi.Canvas(c.mapContent, 0.0, 0.0, layout.mapW, layout.mapH);
        c.items = NMUi.Canvas(c.mapContent, 0.0, 0.0, layout.mapW, layout.mapH);
        c.items.SetName(n"Items");
        c.overlay = NMUi.Canvas(c.mapContent, 0.0, 0.0, layout.mapW, layout.mapH);
        c.frame = NMUi.Canvas(c.root, 0.0, 0.0, layout.w, layout.h);
        c.frame.SetName(n"CornerFrame");
        c.BuildFrame();
        if layout.stripH > 0.0 {
            c.BuildStrip();
        }
        c.BuildZoneLabel();

        let bounds = NMRect.Create(NMTileManifest.WorldMinX(), NMTileManifest.WorldMinY(), NMTileManifest.WorldMaxX(), NMTileManifest.WorldMaxY());
        c.camera = NMCamera.Create(layout.mapW, layout.mapH, bounds, OverlayMapSystem.MinMpp(), OverlayMapSystem.MaxMpp());
        c.camera.SetMpp(mpp > 0.0 ? mpp : NMCorner.DefaultMpp());
        c.camera.follow = true;
        c.layCam = NMCamera.Create(layout.mapW, layout.mapH, bounds, OverlayMapSystem.MinMpp(), OverlayMapSystem.MaxMpp());
        c.layFrames = 1000;
        c.panelLayout = layout.AsPanelLayout();
        c.layers = NMLayerStack.Create(c.tiles, th, cfg.effects);
        c.renderer = NMItemRenderer.Create(api, c.items, s * cfg.markerSize);
        c.routes = NMRouteLayer.Create(c.routesCanvas, s, cfg.effects);
        c.marker = NMPlayerMarker.Create(c.overlay, s * cfg.markerSize, false, th);
        c.mirrorLayer = NMShapeLayer.Create(c.shapes, cfg.markerSize);
        c.mirrorLayer.SetRim(layout.round, NMCorner.RimInset() * s, s);
        c.shown = true;
        return c;
    }

    private func BuildFrame() {
        let l = this.layout;
        let s = l.scale;
        let th = this.cfg.theme;
        let hi = NMTheme.HoloHighlight(th);
        if l.round {
            this.ringCount = Max(1, Min(3, RoundF(this.cfg.frame)));
            let i = 0;
            while i < this.ringCount {
                let inset = Cast<Float>(i) * NMCorner.RingInset() * s;
                let ring = NMUi.HoloImage(this.frame, n"holo_ring", l.mapX + inset, l.mapY + inset, l.mapW - 2.0 * inset, l.mapH - 2.0 * inset,
                    hi, i == 0 ? 0.9 : 0.5, inkBrushTileType.NoTile);
                ring.SetName(n"CornerRing");
                i += 1;
            }
            let north = NMUi.Text(this.frame, NMTheme.BodyFont(), n"Bold", Cast<Int32>(26.0 * s * this.cfg.textSize), NMTheme.HeaderTitle(th));
            north.SetText("N");
            north.SetAnchorPoint(new Vector2(0.5, 0.0));
            north.SetTranslation(new Vector2(l.mapX + l.mapW * 0.5, l.mapY + 6.0 * s));
            return;
        }
        let t = 2.0 * s * this.cfg.frame;
        NMUi.Rect(this.frame, 0.0, 0.0, l.w, t, hi, 0.35);
        NMUi.Rect(this.frame, 0.0, l.h - t, l.w, t, hi, 0.35);
        NMUi.Rect(this.frame, 0.0, 0.0, t, l.h, hi, 0.35);
        NMUi.Rect(this.frame, l.w - t, 0.0, t, l.h, hi, 0.35);
        let bc = NMTheme.BracketColor(th, this.cfg.effects);
        let b = NMTheme.BracketSize() * NMCorner.BracketScale() * s * this.cfg.frame;
        NMUi.Image(this.frame, n"bracket_tl", 0.0, 0.0, b, bc, false);
        NMUi.Image(this.frame, n"bracket_tr", l.w - b, 0.0, b, bc, false);
        NMUi.Image(this.frame, n"bracket_bl", 0.0, l.h - b, b, bc, false);
        NMUi.Image(this.frame, n"bracket_br", l.w - b, l.h - b, b, bc, false);
        this.bracketCount = 4;
    }

    private func BuildStrip() {
        let l = this.layout;
        let s = l.scale;
        let th = this.cfg.theme;
        let y = l.mapY + l.mapH;
        this.stripBg = NMUi.Rect(this.frame, 0.0, y, l.w, l.stripH, NMTheme.PanelBg(), MaxF(this.cfg.opacity, 0.6));
        this.stripBg.SetName(n"CornerStrip");
        let size = Cast<Int32>(NMCorner.StripFont() * s * this.cfg.textSize);
        let pad = NMCorner.StripPad() * s;
        this.stripLeft = NMUi.Text(this.frame, NMTheme.BodyFont(), n"Medium", size, NMTheme.Text());
        this.stripLeft.SetAnchorPoint(new Vector2(0.0, 0.5));
        this.stripLeft.SetTranslation(new Vector2(pad, y + l.stripH * 0.5));
        this.stripRight = NMUi.Text(this.frame, NMTheme.BodyFont(), n"Medium", size, NMTheme.Yellow());
        this.stripRight.SetAnchorPoint(new Vector2(1.0, 0.5));
        this.stripRight.SetTranslation(new Vector2(l.w - pad, y + l.stripH * 0.5));
        this.stripLeftText = "\n";
        this.stripRightText = "\n";
    }

    // The vanilla minimap's zone line (zone text, autodrive, courier timer) along the top of the map area, inside the box.
    private func BuildZoneLabel() {
        let l = this.layout;
        let s = l.scale;
        let h = NMCorner.StripFont() * s * this.cfg.textSize * 1.4;
        let top = l.round ? l.mapY + l.mapH * 0.18 : l.mapY + 4.0 * s * this.cfg.frame;
        this.zoneScrim = NMUi.Rect(this.frame, l.mapX + l.mapW * 0.15, top, l.mapW * 0.7, h, NMTheme.PanelBg(), 0.7);
        this.zoneScrim.SetName(n"CornerZoneScrim");
        this.zoneScrim.SetVisible(false);
        this.zoneText = NMUi.Text(this.frame, NMTheme.BodyFont(), n"Semi-Bold", Cast<Int32>(NMCorner.StripFont() * s * this.cfg.textSize), NMTheme.Text());
        this.zoneText.SetAnchorPoint(new Vector2(0.5, 0.5));
        this.zoneText.SetTranslation(new Vector2(l.mapX + l.mapW * 0.5, top + h * 0.5));
        this.zoneText.SetVisible(false);
        this.zoneKey = "\n";
    }

    public func ZoneLabelRect() -> ref<NMRect> {
        let p = this.zoneScrim.GetTranslation();
        let z = this.zoneScrim.GetSize();
        return NMRect.Create(p.X, p.Y, p.X + z.X, p.Y + z.Y);
    }

    public static func ZoneText(z: ref<NMZoneInfo>) -> String {
        let parts: array<String>;
        if StrLen(z.label) > 0 { ArrayPush(parts, StrUpper(z.label)); }
        if z.autodrive { ArrayPush(parts, "AUTODRIVE"); }
        if StrLen(z.timer) > 0 { ArrayPush(parts, z.timer); }
        let out = "";
        let i = 0;
        while i < ArraySize(parts) {
            if i > 0 { out += "  ·  "; }
            out += parts[i];
            i += 1;
        }
        return out;
    }

    // Frame tint for the vanilla vignette state: white (no change) when safe or public, the route yellow when
    // restricted (vanilla "Default"), the enemy red when hostile or in combat.
    public static func ZoneTint(state: CName) -> HDRColor {
        if Equals(state, n"Dangerous") || Equals(state, n"Combat") {
            return NMTheme.Pick(NMColorRole.Enemy, new HDRColor(1.0, 0.33, 0.33, 1.0));
        }
        if Equals(state, n"Default") { return NMTheme.Yellow(); }
        return new HDRColor(1.0, 1.0, 1.0, 1.0);
    }

    public func SetZone(z: ref<NMZoneInfo>) {
        if !IsDefined(z) { return; }
        let key = z.Key();
        if Equals(key, this.zoneKey) { return; }
        this.zoneKey = key;
        let text = NMCorner.ZoneText(z);
        let on = StrLen(text) > 0;
        this.zoneText.SetText(text);
        this.zoneText.SetVisible(on);
        this.zoneScrim.SetVisible(on);
        this.frame.SetTintColor(NMCorner.ZoneTint(z.state));
    }

    // "320 M" (10 m steps) below 1 km, "1.4 KM" above, "" when nothing is tracked (m < 0).
    public static func DistanceText(m: Float) -> String {
        if m < 0.0 { return ""; }
        if m < 1000.0 {
            return IntToString(Max(10, RoundF(m / 10.0) * 10)) + " M";
        }
        return FloatToStringPrec(m / 1000.0, 1) + " KM";
    }

    // routes: null = unchanged since the last call (routes are read every 500 ms).
    public func Update(player: ref<GameObject>, dt: Float, routes: ref<NMGpsReading>, routeColor: HDRColor, routeStyle: ref<NMRouteStyle>,
                       routesOn: Bool, district: String, objectiveM: Float) {
        if !this.shown || !IsDefined(player) { return; }
        let l = this.layout;
        let p = player.GetWorldPosition();
        this.camera.SetCenter(p.X, p.Y);
        let t0 = NMClock.NowMs();
        this.layers.Update(this.camera, dt);
        let t1 = NMClock.NowMs();
        this.msTiles = t1 - t0;
        // Slide or relayout: where the layout camera's centre now sits in the live view.
        let at = this.camera.WorldToMap(this.layCam.cx, this.layCam.cy);
        let home = this.layCam.WorldToMap(this.layCam.cx, this.layCam.cy);
        let dx = at.X - home.X;
        let dy = at.Y - home.Y;
        this.layFrames += 1;
        if NMCorner.NeedsRelayout(dx, dy, this.layFrames, this.camera.mpp != this.layMpp, NMCorner.RelayoutPx() * l.scale, NMCorner.RelayoutFrames()) {
            this.layCam.SetMpp(this.camera.mpp);
            this.layCam.SetCenter(this.camera.cx, this.camera.cy);
            this.layMpp = this.camera.mpp;
            this.layFrames = 0;
            dx = 0.0;
            dy = 0.0;
        }
        let shift = new Vector2(dx, dy);
        this.items.SetTranslation(shift);
        this.routesCanvas.SetTranslation(shift);
        this.routes.SetVisible(routesOn);
        if routesOn {
            if !this.routes.HasStyle() && IsDefined(routeStyle) {
                this.routes.SetStyle(routeStyle);
            }
            if IsDefined(routes) {
                this.routes.SetRoutes(routes.quest, routeColor, routes.tracked);
            }
            this.routes.Update(this.layCam, p.X, p.Y, dt, l.mapW, l.mapH);
        }
        let t2 = NMClock.NowMs();
        this.msRoutes = t2 - t1;
        this.renderer.UpdateFor(this.layCam, this.panelLayout);
        this.msItems = NMClock.NowMs() - t2;
        this.marker.Update(this.camera, player, l.mapW, l.mapH);
        if IsDefined(this.stripLeft) {
            if NotEquals(district, this.stripLeftText) {
                this.stripLeftText = district;
                this.stripLeft.SetText(district);
            }
            let right = NMCorner.DistanceText(objectiveM);
            if NotEquals(right, this.stripRightText) {
                this.stripRightText = right;
                this.stripRight.SetText(right);
            }
        }
    }

    // Vanilla minimap markers (enemies and cones, devices, ...), after Update moved the camera.
    public func UpdateMirror(mirror: ref<NMMinimapMirror>, sMini: Float, camYaw: Float, skip: ref<NMVanillaDiff>) {
        if !this.shown { return; }
        this.mirrorLayer.Update(this.camera, mirror, this.layout.mapW, this.layout.mapH, this.cfg.enemies, this.cfg.police, sMini, camYaw, skip);
    }

    public func SetShown(on: Bool) {
        if Equals(on, this.shown) { return; }
        this.shown = on;
        this.root.SetVisible(on);
    }

    public func IsShown() -> Bool { return this.shown; }
    public func SetMpp(m: Float) { this.camera.SetMpp(m > 0.0 ? m : NMCorner.DefaultMpp()); }
    public func Mpp() -> Float { return this.camera.mpp; }
    public func Root() -> ref<inkCanvas> { return this.root; }
    public func MapRotation() -> Float { return this.mapContent.GetRotation(); }
    public func HasMask() -> Bool { return IsDefined(this.mask); }
    public func HasRing() -> Bool { return this.ringCount > 0; }
    public func HasBrackets() -> Bool { return this.bracketCount > 0; }
    public func HasStrip() -> Bool { return IsDefined(this.stripLeft); }

    public func Destroy() {
        if IsDefined(this.root) {
            let parent = this.root.GetParentWidget() as inkCompoundWidget;
            if IsDefined(parent) {
                parent.RemoveChild(this.root);
            }
        }
        this.layers = null;
        this.renderer = null;
        this.routes = null;
        this.marker = null;
        this.mirrorLayer = null;
    }
}
