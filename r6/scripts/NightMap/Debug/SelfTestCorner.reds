module NightMap

// Corner minimap: settings, layout, the corner view, modes.
public abstract class NMCornerTests {
    public static func Run(t: ref<NMSelfTest>) {
        NMCornerTests.Settings(t);
        NMCornerTests.Layout(t);
        NMCornerTests.Probe(t);
    }

    private static func Settings(t: ref<NMSelfTest>) {
        let s = new NightMapSettings();
        t.Check("corner.settings_defaults",
            !s.replaceMinimap && Equals(s.cornerStyle, NightMapCornerStyle.SquareStrip)
            && s.cornerScale == 1.0 && s.cornerMarkerSize == 1.0 && s.cornerTextSize == 1.0
            && s.cornerFrameThickness == 1.0 && s.cornerOpacity == 0.92
            && s.cornerEnemies && s.cornerPolice && s.expandedScale == 1.0 && !s.followHudPainter, "");
    }

    private static func Layout(t: ref<NMSelfTest>) {
        let box = NMRect.Create(3300.0, 100.0, 3700.0, 500.0);
        let a = NMCornerLayout.Compute(box, NightMapCornerStyle.SquareStrip, 1.0, 1.0, 3840.0, 2160.0);
        t.Check("corner.layout_strip_inside_box", IsDefined(a) && a.y + a.h == 500.0 && a.mapH == 400.0 - 44.0 && a.stripH == 44.0,
            IsDefined(a) ? FloatToStringPrec(a.mapH, 1) : "null");
        let b = NMCornerLayout.Compute(box, NightMapCornerStyle.Square, 1.5, 1.0, 3840.0, 2160.0);
        t.Check("corner.layout_scale_top_right", IsDefined(b) && b.x + b.w == 3700.0 && b.y == 100.0 && b.w == 600.0 && b.stripH == 0.0, "");
        let c = NMCornerLayout.Compute(NMRect.Create(0.0, 0.0, 400.0, 360.0), NightMapCornerStyle.Circle, 1.0, 1.0, 3840.0, 2160.0);
        t.Check("corner.layout_circle_square_bounds", IsDefined(c) && c.mapW == 360.0 && c.mapH == 360.0 && c.round && c.mapX == 40.0, "");
        t.Check("corner.no_box_no_draw", !IsDefined(NMCornerLayout.Compute(null, NightMapCornerStyle.Square, 1.0, 1.0, 3840.0, 2160.0))
            && !IsDefined(NMCornerLayout.Compute(NMRect.Create(0.0, 0.0, 4.0, 4.0), NightMapCornerStyle.Square, 1.0, 1.0, 3840.0, 2160.0)), "");
        let pl = a.AsPanelLayout();
        t.Check("corner.as_panel_layout", pl.viewW == a.mapW && pl.mapH == a.mapH && pl.sideW == 0.0, "");
    }

    // A fake minimap: root canvas with two children at 0.8 and 1.0.
    public static func FakeMinimap(parent: ref<inkCompoundWidget>) -> ref<inkCanvas> {
        let root = new inkCanvas();
        root.SetName(n"NMFakeMinimap");
        root.SetSize(new Vector2(400.0, 400.0));
        root.Reparent(parent);
        let a = new inkCanvas();
        a.SetOpacity(0.8);
        a.Reparent(root);
        let b = new inkCanvas();
        b.Reparent(root);
        return root;
    }

    private static func Probe(t: ref<NMSelfTest>) {
        let host = new inkCanvas();
        let root = NMCornerTests.FakeMinimap(host);
        let p = NMMinimapProbe.ForWidget(host, root);
        p.Fade();
        let faded = root.GetWidgetByIndex(0).GetOpacity() == 0.0 && root.GetWidgetByIndex(1).GetOpacity() == 0.0 && root.GetOpacity() == 1.0;
        root.GetWidgetByIndex(1).SetOpacity(1.0);   // a HUD animation fades it back in
        p.Fade();
        let refaded = root.GetWidgetByIndex(1).GetOpacity() == 0.0;
        p.Restore();
        t.Check("corner.probe_fade_restore", faded && refaded && root.GetWidgetByIndex(0).GetOpacity() == 0.8
            && root.GetWidgetByIndex(1).GetOpacity() == 1.0 && p.FadedCount() == 0, "");
        root.SetVisible(false);
        t.Check("corner.probe_follows_game_hide", !p.ShownByGame(), "");
    }
}
