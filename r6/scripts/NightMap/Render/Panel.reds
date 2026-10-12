module NightMap

// Centered hologram panel: map area (left 70%, clipped), docked card (right 30%), hint bar at the bottom.
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
    public let cardW: Float;
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
        l.mapW = l.w * 0.70;
        l.cardW = l.w - l.mapW;
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
    public let card: ref<inkCanvas>;
    public let title: ref<inkText>;
    public let subtitle: ref<inkText>;
    public let warning: ref<inkText>;
    public let scaleBar: ref<inkRectangle>;
    public let scaleLabel: ref<inkText>;
    public let hints: ref<inkText>;

    public static func Build(window: wref<inkCompoundWidget>, layout: ref<NMPanelLayout>, opacity: Float) -> ref<NMPanel> {
        let p = new NMPanel();
        p.layout = layout;
        let s = layout.scale;
        p.root = NMUi.Canvas(window, layout.x, layout.y, layout.w, layout.h);
        p.root.SetName(n"NightMapPanel");
        NMUi.Rect(p.root, 0.0, 0.0, layout.w, layout.h, NMTheme.PanelBg(), opacity);

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
        p.tiles = NMUi.Canvas(p.mapContent, 0.0, 0.0, layout.mapW, layout.mapH);
        p.items = NMUi.Canvas(p.mapContent, 0.0, 0.0, layout.mapW, layout.mapH);
        p.overlay = NMUi.Canvas(p.mapContent, 0.0, 0.0, layout.mapW, layout.mapH);

        // Card column and divider.
        NMUi.Rect(p.root, layout.mapW, 0.0, layout.cardW, layout.mapH, NMTheme.CardBg(), NMTheme.CardOpacity());
        NMUi.Rect(p.root, layout.mapW, 0.0, 2.0 * s, layout.mapH, NMTheme.Cyan(), 0.35);
        p.card = NMUi.Canvas(p.root, layout.mapW, 0.0, layout.cardW, layout.mapH);

        // Hint bar.
        NMUi.Rect(p.root, 0.0, layout.mapH, layout.w, layout.hintH, NMTheme.CardBg(), 0.6);
        p.hints = NMUi.Text(p.root, NMTheme.BodyFont(), n"Medium", Cast<Int32>(34.0 * s), NMTheme.Cyan());
        p.hints.SetTranslation(new Vector2(58.0 * s, layout.mapH + 34.0 * s));

        // Header over the map area.
        p.title = NMUi.Text(p.root, NMTheme.HeadingFont(), n"Bold", Cast<Int32>(62.0 * s), NMTheme.Text());
        p.title.SetText("NIGHT CITY");
        p.title.SetTranslation(new Vector2(67.0 * s, 46.0 * s));
        p.subtitle = NMUi.Text(p.root, NMTheme.BodyFont(), n"Medium", Cast<Int32>(34.0 * s), NMTheme.Cyan());
        p.subtitle.SetTranslation(new Vector2(67.0 * s, 128.0 * s));
        p.warning = NMUi.Text(p.root, NMTheme.BodyFont(), n"Medium", Cast<Int32>(32.0 * s), NMTheme.Pink());
        p.warning.SetTranslation(new Vector2(67.0 * s, 176.0 * s));
        p.warning.SetVisible(false);

        // Scale bar (top-right of the map area).
        p.scaleBar = NMUi.Rect(p.root, layout.mapW - 400.0 * s, 96.0 * s, 336.0 * s, 5.0 * s, NMTheme.Text(), 1.0);
        p.scaleLabel = NMUi.Text(p.root, NMTheme.BodyFont(), n"Medium", Cast<Int32>(32.0 * s), NMTheme.Text());
        p.scaleLabel.SetTranslation(new Vector2(layout.mapW - 300.0 * s, 108.0 * s));

        // Frame outline and glowing corner brackets.
        let t = 2.0 * s;
        NMUi.Rect(p.root, 0.0, 0.0, layout.w, t, NMTheme.Cyan(), 0.35);
        NMUi.Rect(p.root, 0.0, layout.h - t, layout.w, t, NMTheme.Cyan(), 0.35);
        NMUi.Rect(p.root, 0.0, 0.0, t, layout.h, NMTheme.Cyan(), 0.35);
        NMUi.Rect(p.root, layout.w - t, 0.0, t, layout.h, NMTheme.Cyan(), 0.35);
        let b = NMTheme.BracketSize() * s;
        NMUi.Image(p.root, n"bracket_tl", 0.0, 0.0, b, NMTheme.Cyan(), false);
        NMUi.Image(p.root, n"bracket_tr", layout.w - b, 0.0, b, NMTheme.Cyan(), false);
        NMUi.Image(p.root, n"bracket_bl", 0.0, layout.h - b, b, NMTheme.Cyan(), false);
        NMUi.Image(p.root, n"bracket_br", layout.w - b, layout.h - b, b, NMTheme.Cyan(), false);
        return p;
    }

    public func Destroy() {
        if IsDefined(this.root) {
            let parent = this.root.GetParentWidget() as inkCompoundWidget;
            if IsDefined(parent) {
                parent.RemoveChild(this.root);
            }
        }
    }
}
