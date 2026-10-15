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

    public static func Compute(winW: Float, winH: Float) -> ref<NMPanelLayout> {
        let l = new NMPanelLayout();
        l.winW = winW;
        l.winH = winH;
        l.scale = MinF(winW / 3840.0, winH / 2160.0);
        l.w = winW * 0.70;
        l.h = winH * 0.711;
        if l.w > l.h * 1.75 {
            l.w = l.h * 1.75;   // keep the approved 1120x640 proportions on ultra-wide screens
        }
        l.x = (winW - l.w) * 0.5;
        l.y = (winH - l.h) * 0.5;
        l.hintH = NMTheme.HintHeight() * l.scale;
        l.mapW = l.w;
        l.mapH = l.h - l.hintH;
        return l;
    }
}

public class NMPanel {
    public let layout: ref<NMPanelLayout>;
    public let root: ref<inkCanvas>;
    public let mapContent: ref<inkCanvas>;
    public let tiles: ref<inkCanvas>;
    public let items: ref<inkCanvas>;
    public let overlay: ref<inkCanvas>;
    public let subtitle: ref<inkText>;
    public let warning: ref<inkText>;
    public let questTitle: ref<inkText>;
    public let questObjective: ref<inkText>;
    public let scaleBar: ref<inkRectangle>;
    public let scaleLabel: ref<inkText>;
    public let hints: ref<inkText>;
    public let holo: ref<NMHolo>;

    // green / effects: NightMapSettings.greenHologram / hologramEffects, passed in so the layout stays testable.
    public static func Build(window: wref<inkCompoundWidget>, layout: ref<NMPanelLayout>, opacity: Float, green: Bool, effects: Bool) -> ref<NMPanel> {
        let p = new NMPanel();
        p.layout = layout;
        let s = layout.scale;
        p.root = NMUi.Canvas(window, layout.x, layout.y, layout.w, layout.h);
        p.root.SetName(n"NightMapPanel");
        p.holo = NMHolo.Create(effects, green, layout.mapW, layout.mapH, s);
        // One background layer per region (the panel fill only under the hint bar): stacking the panel fill under the map
        // fill would compound the opacity (0.45 over 0.45 reads as 0.70) and the world would not show through.
        NMUi.Rect(p.root, 0.0, layout.mapH, layout.w, layout.hintH, NMTheme.PanelBg(), opacity);
        NMUi.Rect(p.root, 0.0, 0.0, layout.mapW, layout.mapH, NMTheme.HoloBackground(green), opacity);

        // Clipped viewport (inkScrollArea's internal mask), same pattern as Codeware's text input viewport.
        let area = new inkScrollArea();
        area.SetAnchor(inkEAnchor.TopLeft);
        area.SetSize(new Vector2(layout.mapW, layout.mapH));
        area.SetConstrainContentPosition(false);
        area.SetUseInternalMask(true);
        area.SetInteractive(false);
        area.Reparent(p.root);
        p.mapContent = new inkCanvas();
        p.mapContent.SetSize(new Vector2(layout.mapW, layout.mapH));
        p.mapContent.SetInteractive(false);
        p.mapContent.Reparent(area);
        p.holo.AddGrid(p.mapContent);                                                      // under the glow
        p.tiles = NMUi.Canvas(p.mapContent, 0.0, 0.0, layout.mapW, layout.mapH);
        p.holo.AddScan(p.mapContent);                                                      // over the tiles, under the markers
        p.items = NMUi.Canvas(p.mapContent, 0.0, 0.0, layout.mapW, layout.mapH);
        p.holo.AddBar(p.mapContent);                                                       // over the markers, under the player arrow
        p.overlay = NMUi.Canvas(p.mapContent, 0.0, 0.0, layout.mapW, layout.mapH);

        // Hint bar.
        NMUi.Rect(p.root, 0.0, layout.mapH, layout.w, layout.hintH, NMTheme.CardBg(), 0.6);
        p.hints = NMUi.Text(p.root, NMTheme.BodyFont(), n"Medium", Cast<Int32>(34.0 * s), NMTheme.HoloHighlight(green));
        p.hints.SetTranslation(new Vector2(58.0 * s, layout.mapH + 34.0 * s));

        // Header over the map area.
        p.subtitle = NMUi.Text(p.root, NMTheme.BodyFont(), n"Medium", Cast<Int32>(34.0 * s), NMTheme.HoloHighlight(green));
        p.subtitle.SetTranslation(new Vector2(67.0 * s, 46.0 * s));
        p.questTitle = NMUi.Text(p.root, NMTheme.BodyFont(), n"Bold", Cast<Int32>(34.0 * s), NMTheme.VanillaStateColor(n"Quest"));
        p.questTitle.SetTranslation(new Vector2(67.0 * s, 100.0 * s));
        p.questTitle.SetVisible(false);
        p.questObjective = NMUi.Text(p.root, NMTheme.BodyFont(), n"Medium", Cast<Int32>(30.0 * s), NMTheme.Text());
        p.questObjective.SetTranslation(new Vector2(67.0 * s, 146.0 * s));
        p.questObjective.SetWrappingAtPosition(layout.mapW * 0.6);   // two lines at most (see NMQuestHeader.Clip)
        p.questObjective.SetVisible(false);
        p.warning = NMUi.Text(p.root, NMTheme.BodyFont(), n"Medium", Cast<Int32>(32.0 * s), NMTheme.Pink());
        p.warning.SetTranslation(new Vector2(67.0 * s, 240.0 * s));
        p.warning.SetVisible(false);

        // Scale bar (top-right of the map area).
        p.scaleBar = NMUi.Rect(p.root, layout.mapW - 400.0 * s, 96.0 * s, 336.0 * s, 5.0 * s, NMTheme.Text(), 1.0);
        p.scaleLabel = NMUi.Text(p.root, NMTheme.BodyFont(), n"Medium", Cast<Int32>(32.0 * s), NMTheme.Text());
        p.scaleLabel.SetTranslation(new Vector2(layout.mapW - 300.0 * s, 108.0 * s));

        // Frame outline, edge glow and glowing corner brackets (brightened with HDR gain when effects are on).
        let t = 2.0 * s;
        let hi = NMTheme.HoloHighlight(green);
        NMUi.Rect(p.root, 0.0, 0.0, layout.w, t, hi, 0.35);
        NMUi.Rect(p.root, 0.0, layout.h - t, layout.w, t, hi, 0.35);
        NMUi.Rect(p.root, 0.0, 0.0, t, layout.h, hi, 0.35);
        NMUi.Rect(p.root, layout.w - t, 0.0, t, layout.h, hi, 0.35);
        p.holo.AddEdges(p.root, layout.w, layout.h);
        let bc = NMTheme.BracketColor(green, effects);
        let b = NMTheme.BracketSize() * s;
        NMUi.Image(p.root, n"bracket_tl", 0.0, 0.0, b, bc, false);
        NMUi.Image(p.root, n"bracket_tr", layout.w - b, 0.0, b, bc, false);
        NMUi.Image(p.root, n"bracket_bl", 0.0, layout.h - b, b, bc, false);
        NMUi.Image(p.root, n"bracket_br", layout.w - b, layout.h - b, b, bc, false);
        p.holo.Play(p.mapContent);
        return p;
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
