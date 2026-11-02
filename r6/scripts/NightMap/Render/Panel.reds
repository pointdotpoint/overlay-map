module NightMap

// Centered hologram panel: full-width clipped map area, hint bar at the bottom.
public class NMPanelLayout {
    public let winW: Float;
    public let winH: Float;
    public let scale: Float;
    public let x: Float;
    public let y: Float;
    public let w: Float;
    public let h: Float;
    public let mapW: Float;
    public let mapH: Float;
    public let hintH: Float;
    public let sideW: Float;   // the always-visible sidebar on the right of the map area (25% of mapW)
    public let viewW: Float;   // map visible left of the sidebar

    // expandedScale: NightMapSettings.expandedScale (0.7-1.0), multiplying the panel's share of the window.
    public static func Compute(winW: Float, winH: Float, opt expandedScale: Float) -> ref<NMPanelLayout> {
        let k = expandedScale > 0.0 ? expandedScale : 1.0;
        let l = new NMPanelLayout();
        l.winW = winW;
        l.winH = winH;
        l.scale = MinF(winW / 3840.0, winH / 2160.0);
        l.w = winW * 0.90 * k;
        l.h = winH * 0.711 * k;
        l.x = (winW - l.w) * 0.5;
        l.y = (winH - l.h) * 0.5;
        l.hintH = NMTheme.HintHeight() * l.scale;
        l.mapW = l.w;
        l.mapH = l.h - l.hintH;
        l.sideW = l.mapW * 0.25;
        l.viewW = l.mapW - l.sideW;
        return l;
    }
}

public class NMPanel {
    public let layout: ref<NMPanelLayout>;
    public let root: ref<inkCanvas>;
    public let mapContent: ref<inkCanvas>;
    public let tiles: ref<inkCanvas>;
    public let routes: ref<inkCanvas>;
    public let shapes: ref<inkCanvas>;   // mirrored vanilla minimap markers (enemies, cones, devices)
    public let items: ref<inkCanvas>;
    public let overlay: ref<inkCanvas>;
    public let districtTitle: ref<inkText>;   // top-left header: the district
    public let districtSub: ref<inkText>;     // under it: the filter view, hidden on ALL
    public let headerScrim: ref<inkImage>;    // soft dark backing behind the title, over the markers
    public let warning: ref<inkText>;
    public let questTitle: ref<inkText>;
    public let questObjective: ref<inkText>;
    public let scaleBar: ref<inkRectangle>;
    public let scaleTickL: ref<inkRectangle>;
    public let scaleTickR: ref<inkRectangle>;
    public let scaleLabel: ref<inkText>;
    public let hintBar: ref<NMHintBar>;
    public let holo: ref<NMHolo>;
    public let sidebar: ref<inkCanvas>;       // right of the view, outside the map clip: card (drawer) and tracking block
    public let tracking: ref<inkCanvas>;      // the tracking block, pinned to the sidebar's bottom; hidden with no quest
    public let questDiamond: ref<inkRectangle>;

    // theme / effects: NMTheme.ThemeIndex(NightMapSettings.holoColor) / hologramEffects, passed in so the layout stays testable.
    public static func Build(window: wref<inkCompoundWidget>, layout: ref<NMPanelLayout>, opacity: Float, theme: Int32, effects: Bool) -> ref<NMPanel> {
        let p = new NMPanel();
        p.layout = layout;
        let s = layout.scale;
        p.root = NMUi.Canvas(window, layout.x, layout.y, layout.w, layout.h);
        p.root.SetName(n"NightMapPanel");
        p.holo = NMHolo.Create(effects, theme, layout.mapW, layout.mapH, s);
        // One background layer per region (the panel fill only under the hint bar): stacking the panel fill under the map
        // fill would compound the opacity (0.45 over 0.45 reads as 0.70) and a low setting would not show the world through.
        NMUi.Rect(p.root, 0.0, layout.mapH, layout.w, layout.hintH, NMTheme.PanelBg(), opacity);
        NMUi.Rect(p.root, 0.0, 0.0, layout.mapW, layout.mapH, NMTheme.HoloBackground(theme), opacity);

        // Clipped viewport (inkScrollArea's internal mask), same pattern as Codeware's text input viewport. It clips at
        // the view's right edge: the map content is mapW wide (the camera centres on the map area), but nothing of it
        // draws under the sidebar.
        let area = new inkScrollArea();
        area.SetAnchor(inkEAnchor.TopLeft);
        area.SetSize(new Vector2(layout.viewW, layout.mapH));
        area.SetConstrainContentPosition(false);
        area.SetUseInternalMask(true);
        area.SetInteractive(false);
        area.SetName(n"MapView");
        area.Reparent(p.root);
        p.mapContent = new inkCanvas();
        p.mapContent.SetSize(new Vector2(layout.mapW, layout.mapH));
        p.mapContent.SetInteractive(false);
        p.mapContent.Reparent(area);
        p.holo.AddGrid(p.mapContent);                                                      // under the glow
        p.tiles = NMUi.Canvas(p.mapContent, 0.0, 0.0, layout.mapW, layout.mapH);
        p.holo.AddVignette(p.mapContent);                                                  // over the tiles, under the routes
        p.holo.AddNoise(p.mapContent);                                                     // over the tiles, under the markers
        p.routes = NMUi.Canvas(p.mapContent, 0.0, 0.0, layout.mapW, layout.mapH);           // GPS routes, under the markers
        p.shapes = NMUi.Canvas(p.mapContent, 0.0, 0.0, layout.mapW, layout.mapH);
        p.items = NMUi.Canvas(p.mapContent, 0.0, 0.0, layout.mapW, layout.mapH);
        p.items.SetName(n"Items");
        // Soft dark scrim behind the district title (over the routes, markers and photo pins, under the player arrow),
        // clipped by the viewport. It is part of the frame, so it stays with effects off.
        p.headerScrim = NMUi.HoloImage(p.mapContent, n"holo_halo", -540.0 * s, -240.0 * s, 2000.0 * s, 760.0 * s,
            NMTheme.HoloBackground(theme), NMTheme.HeaderScrimOpacity(), inkBrushTileType.NoTile);
        p.headerScrim.SetName(n"HeaderScrim");
        p.holo.AddScan(p.mapContent);                                                      // over the markers, under the overlay
        p.holo.AddBar(p.mapContent);                                                       // over the markers, under the player arrow
        p.overlay = NMUi.Canvas(p.mapContent, 0.0, 0.0, layout.mapW, layout.mapH);

        NMPanel.BuildSidebar(p, opacity, theme);

        // Hint bar.
        NMUi.Rect(p.root, 0.0, layout.mapH, layout.w, layout.hintH, NMTheme.CardBg(), 0.6);
        p.hintBar = NMHintBar.Create(p.root, 0.0, layout.mapH, layout.w, layout.hintH, s, theme);

        // Top-left header: the district as a large letter-spaced title, the filter view under it in the accent colour.
        p.districtTitle = NMUi.Text(p.root, NMTheme.BodyFont(), n"Bold", Cast<Int32>(68.0 * s), NMTheme.HeaderTitle(theme));
        p.districtTitle.SetTranslation(new Vector2(88.0 * s, 80.0 * s));
        p.districtTitle.SetTracking(Cast<Int32>(8.0 * s));
        p.districtTitle.SetName(n"DistrictTitle");
        p.districtSub = NMUi.Text(p.root, NMTheme.BodyFont(), n"Medium", Cast<Int32>(32.0 * s), NMTheme.HoloAccent(theme));
        p.districtSub.SetTranslation(new Vector2(90.0 * s, 164.0 * s));
        p.districtSub.SetTracking(Cast<Int32>(6.0 * s));
        p.districtSub.SetVisible(false);
        p.districtSub.SetName(n"DistrictSub");

        p.warning = NMUi.Text(p.root, NMTheme.BodyFont(), n"Medium", Cast<Int32>(32.0 * s), NMTheme.Pink());
        p.warning.SetTranslation(new Vector2(67.0 * s, 240.0 * s));
        p.warning.SetVisible(false);

        // Scale bar (top-right of the view): a thin bar with end ticks, the label centred under it (SetScaleBar).
        let bx = layout.viewW - 500.0 * s;
        let bt = NMPanel.ScaleBarThickness(s);
        p.scaleBar = NMUi.Rect(p.root, bx, 96.0 * s, NMPanel.ScaleBarMax(s), bt, NMTheme.Text(), 1.0);
        p.scaleTickL = NMUi.Rect(p.root, bx, 96.0 * s, bt, 20.0 * s, NMTheme.Text(), 1.0);
        p.scaleTickR = NMUi.Rect(p.root, bx + NMPanel.ScaleBarMax(s) - bt, 96.0 * s, bt, 20.0 * s, NMTheme.Text(), 1.0);
        p.scaleLabel = NMUi.Text(p.root, NMTheme.BodyFont(), n"Medium", Cast<Int32>(30.0 * s), NMTheme.Text());
        p.scaleLabel.SetAnchorPoint(new Vector2(0.5, 0.0));
        p.scaleLabel.SetTracking(Cast<Int32>(4.0 * s));
        p.scaleBar.SetName(n"ScaleBar");
        p.scaleLabel.SetName(n"ScaleLabel");
        p.SetScaleBar(NMPanel.ScaleBarMax(s));

        // Frame outline, edge glow and glowing corner brackets (brightened with HDR gain when effects are on).
        let t = 2.0 * s;
        let hi = NMTheme.HoloHighlight(theme);
        NMUi.Rect(p.root, 0.0, 0.0, layout.w, t, hi, 0.35);
        NMUi.Rect(p.root, 0.0, layout.h - t, layout.w, t, hi, 0.35);
        NMUi.Rect(p.root, 0.0, 0.0, t, layout.h, hi, 0.35);
        NMUi.Rect(p.root, layout.w - t, 0.0, t, layout.h, hi, 0.35);
        p.holo.AddEdges(p.root, layout.w, layout.h);
        let bc = NMTheme.BracketColor(theme, effects);
        let b = NMTheme.BracketSize() * s;
        NMUi.Image(p.root, n"bracket_tl", 0.0, 0.0, b, bc, false);
        NMUi.Image(p.root, n"bracket_tr", layout.w - b, 0.0, b, bc, false);
        NMUi.Image(p.root, n"bracket_bl", 0.0, layout.h - b, b, bc, false);
        NMUi.Image(p.root, n"bracket_br", layout.w - b, layout.h - b, b, bc, false);
        p.holo.Play(p.mapContent);
        return p;
    }

    public static func ScaleBarMax(scale: Float) -> Float { return 336.0 * scale; }
    public static func ScaleBarThickness(scale: Float) -> Float { return 4.0 * scale; }   // 2 px at 1080p

    // Screen areas the markers keep clear of (NMItemRenderer.SetReserved): the district title with its sub line, and
    // the scale bar with its label, each padded. Text sizes come from ink once laid out, else an estimate.
    public func HeaderRects() -> array<ref<NMRect>> {
        let s = this.layout.scale;
        let pad = NMTheme.HeaderPad() * s;
        let rects: array<ref<NMRect>>;
        let tp = this.districtTitle.GetTranslation();
        let ts = NMPanel.TextSize(this.districtTitle);
        let w = ts.X;
        let bottom = tp.Y + ts.Y;
        if this.districtSub.IsVisible() {
            let sp = this.districtSub.GetTranslation();
            let ss = NMPanel.TextSize(this.districtSub);
            w = MaxF(w, sp.X - tp.X + ss.X);
            bottom = sp.Y + ss.Y;
        }
        if w > 0.0 {
            ArrayPush(rects, NMRect.Create(tp.X - pad, tp.Y - pad, tp.X + w + pad, bottom + pad));
        }
        let b = this.scaleBar.GetTranslation();
        let lp = this.scaleLabel.GetTranslation();   // the label's top centre
        let ls = NMPanel.TextSize(this.scaleLabel);
        ArrayPush(rects, NMRect.Create(MinF(b.X, lp.X - ls.X * 0.5) - pad, b.Y - pad,
            MaxF(b.X + NMPanel.ScaleBarMax(s), lp.X + ls.X * 0.5) + pad, lp.Y + ls.Y + pad));
        return rects;
    }

    // A text widget's laid-out size; before ink lays it out, a conservative estimate from its length and font size.
    private static func TextSize(t: ref<inkText>) -> Vector2 {
        let d = t.GetDesiredSize();
        if d.X > 0.0 && d.Y > 0.0 {
            return d;
        }
        let size = Cast<Float>(t.GetFontSize());
        let n = Cast<Float>(StrLen(t.GetText()));
        return new Vector2(n * (size * 0.6 + Cast<Float>(t.GetTracking())), size * 1.2);
    }

    // The bar keeps its left end; the right tick and the centred label follow its length.
    public func SetScaleBar(len: Float) {
        let s = this.layout.scale;
        let at = this.scaleBar.GetTranslation();
        let bt = NMPanel.ScaleBarThickness(s);
        this.scaleBar.SetSize(new Vector2(len, bt));
        this.scaleTickR.SetTranslation(new Vector2(at.X + len - bt, at.Y));
        this.scaleLabel.SetTranslation(new Vector2(at.X + len * 0.5, at.Y + 30.0 * s));
    }

    public static func SidebarPad() -> Float { return 40.0; }      // 4K units, the sidebar's inner margin
    public static func TrackingHeight() -> Float { return 300.0; }  // 4K units: divider, label, title, three objective lines

    // Sidebar (spec 6): glass over the panel fill, a bright 1.5 px left edge with a soft inner gradient, and the tracking
    // block pinned to the bottom. The marker card (NMPhotoDrawer and its docked NMTooltip) is added on open.
    private static func BuildSidebar(p: ref<NMPanel>, opacity: Float, theme: Int32) {
        let l = p.layout;
        let s = l.scale;
        let hi = NMTheme.HoloHighlight(theme);
        p.sidebar = NMUi.Canvas(p.root, l.viewW, 0.0, l.sideW, l.mapH);
        p.sidebar.SetName(n"Sidebar");
        NMUi.Rect(p.sidebar, 0.0, 0.0, l.sideW, l.mapH, NMTheme.SidebarBg(theme), NMTheme.SidebarOpacity(opacity));
        // The inner gradient reuses the holo_edge_l art but is part of the frame (spec 6), so hologramEffects does not gate it.
        NMUi.HoloImage(p.sidebar, n"holo_edge_l", 0.0, 0.0, 80.0 * s, l.mapH, hi, NMTheme.SidebarGradientOpacity(), inkBrushTileType.NoTile);
        NMUi.Rect(p.sidebar, 0.0, 0.0, 3.0 * s, l.mapH, hi, NMTheme.SidebarEdgeOpacity());

        let pad = NMPanel.SidebarPad() * s;
        let w = l.sideW - 2.0 * pad;
        let th = NMPanel.TrackingHeight() * s;
        p.tracking = NMUi.Canvas(p.sidebar, pad, l.mapH - th, w, th);
        p.tracking.SetName(n"Tracking");
        p.tracking.SetVisible(false);
        NMUi.Rect(p.tracking, 0.0, 0.0, w, 2.0 * s, hi, NMTheme.DividerOpacity());
        let label = NMUi.Text(p.tracking, NMTheme.BodyFont(), n"Medium", Cast<Int32>(28.0 * s), NMTheme.CardLabel(theme));
        label.SetTranslation(new Vector2(0.0, 24.0 * s));
        label.SetTracking(Cast<Int32>(4.0 * s));
        label.SetText("TRACKING");
        let quest = NMTheme.VanillaStateColor(n"Quest");
        p.questDiamond = NMUi.Rect(p.tracking, 11.0 * s, 98.0 * s, 16.0 * s, 16.0 * s, quest, 1.0);
        p.questDiamond.SetAnchorPoint(new Vector2(0.5, 0.5));
        p.questDiamond.SetRotation(45.0);
        p.questTitle = NMUi.Text(p.tracking, NMTheme.BodyFont(), n"Bold", Cast<Int32>(40.0 * s), quest);
        p.questTitle.SetTranslation(new Vector2(30.0 * s, 74.0 * s));
        p.questObjective = NMUi.Text(p.tracking, NMTheme.BodyFont(), n"Medium", Cast<Int32>(30.0 * s), NMTheme.Text());
        p.questObjective.SetTranslation(new Vector2(0.0, 134.0 * s));
        p.questObjective.SetWrappingAtPosition(w);   // the sidebar width; NMQuestHeader.Clip bounds the length
        p.questObjective.SetVisible(false);
    }

    // Characters of a quest title that fit the tracking block at its font size (NMTooltip.FitChars).
    public func QuestTitleChars() -> Int32 {
        let s = this.layout.scale;
        return NMTooltip.FitChars(this.layout.sideW - 2.0 * NMPanel.SidebarPad() * s - 30.0 * s, 40.0 * s, 0.0);
    }

    public func Destroy() {
        if IsDefined(this.holo) {
            this.holo.Stop();
        }
        if IsDefined(this.root) {
            let parent = this.root.GetParentWidget() as inkCompoundWidget;
            if IsDefined(parent) {
                parent.RemoveChild(this.root);
            }
        }
    }
}
