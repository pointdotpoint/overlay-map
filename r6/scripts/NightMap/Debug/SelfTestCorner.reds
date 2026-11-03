module NightMap

// Corner minimap: settings, layout, the corner view, modes.
public abstract class NMCornerTests {
    public static func Run(t: ref<NMSelfTest>) {
        NMCornerTests.Settings(t);
        NMCornerTests.Layout(t);
        NMCornerTests.Probe(t);
        NMCornerTests.View(t);
        NMCornerTests.Modes(t);
    }

    private static func Settings(t: ref<NMSelfTest>) {
        // Shelved 2026-11-03: even a save with "Replace vanilla minimap" on gets no corner and an untouched open map.
        let on = new NightMapSettings();
        on.replaceMinimap = true;
        t.Check("corner.shelved", NMCornerHost.Shelved() && !NMCornerHost.Enabled(on) && !NMCornerHost.Enabled(null), "");
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

    public static func Box() -> ref<NMRect> { return NMRect.Create(3300.0, 100.0, 3700.0, 500.0); }

    private static func BuildStyle(host: ref<inkCanvas>, style: NightMapCornerStyle) -> ref<NMCorner> {
        let s = new NightMapSettings();
        s.cornerStyle = style;
        let cfg = NMCornerConfig.From(s);
        let l = NMCornerLayout.Compute(NMCornerTests.Box(), style, 1.0, 1.0, 3840.0, 2160.0);
        return NMCorner.Build(host, l, cfg, NightMap.Create(), 0.4);
    }

    private static func View(t: ref<NMSelfTest>) {
        let host = new inkCanvas();
        host.SetSize(new Vector2(3840.0, 2160.0));
        let circle = NMCornerTests.BuildStyle(host, NightMapCornerStyle.Circle);
        let square = NMCornerTests.BuildStyle(host, NightMapCornerStyle.Square);
        let strip = NMCornerTests.BuildStyle(host, NightMapCornerStyle.SquareStrip);
        t.Check("corner.style_widgets",
            circle.HasMask() && !circle.HasStrip() && circle.HasRing() && !circle.HasBrackets()
            && !square.HasMask() && !square.HasStrip() && square.HasBrackets()
            && strip.HasStrip() && strip.HasBrackets()
            && Equals(strip.Root().GetName(), n"NightMapCorner"), "");
        // Markers and routes slide with the camera between relayouts (corner perf: relayout was 1.1 ms a moving frame).
        t.Check("corner.relayout_trigger", !NMCorner.NeedsRelayout(10.0, 10.0, 5, false, 40.0, 20)
            && NMCorner.NeedsRelayout(41.0, 0.0, 5, false, 40.0, 20) && NMCorner.NeedsRelayout(0.0, -41.0, 5, false, 40.0, 20)
            && NMCorner.NeedsRelayout(0.0, 0.0, 20, false, 40.0, 20) && NMCorner.NeedsRelayout(0.0, 0.0, 1, true, 40.0, 20), "");
        t.Check("corner.strip_text", Equals(NMCorner.DistanceText(320.0), "320 M") && Equals(NMCorner.DistanceText(1440.0), "1.4 KM")
            && Equals(NMCorner.DistanceText(-1.0), "") && Equals(NMCorner.DistanceText(14.0), "10 M"), NMCorner.DistanceText(320.0));
        let a = NMCornerConfig.From(new NightMapSettings());
        let b = NMCornerConfig.From(new NightMapSettings());
        let s2 = new NightMapSettings();
        s2.cornerStyle = NightMapCornerStyle.Circle;
        t.Check("corner.config_same", a.Same(b) && !a.Same(NMCornerConfig.From(s2)), "");
        t.Check("corner.never_rotates", strip.MapRotation() == 0.0, "");
        strip.SetMpp(1.7);
        t.Check("corner.set_mpp", strip.Mpp() == 1.7, "");
        strip.Destroy();
        t.Check("corner.destroy_removes", NMSelfTest.ChildIndex(host, n"NightMapCorner") >= 0
            && !IsDefined(strip.Root().GetParentWidget()), "");
        circle.Destroy();
        square.Destroy();
    }

    // A host on a fake 3840x2160 window whose fake minimap sits at 3300,100 400x400.
    private static func FakeWindow() -> ref<inkCanvas> {
        let w = new inkCanvas();
        w.SetSize(new Vector2(3840.0, 2160.0));
        let root = NMCornerTests.FakeMinimap(w);
        root.SetTranslation(new Vector2(3300.0, 100.0));
        return w;
    }

    // Off-HUD test widgets get no layout pass, so the probe is given the box the fake minimap would measure.
    private static func FakeProbe(w: ref<inkCanvas>) -> ref<NMMinimapProbe> {
        return NMMinimapProbe.ForWidgetBox(w, w.GetWidgetByIndex(0), NMRect.Create(0.0, 0.0, 400.0, 400.0));
    }

    private static func On() -> ref<NightMapSettings> {
        let s = new NightMapSettings();
        s.replaceMinimap = true;
        return s;
    }

    private static func Modes(t: ref<NMSelfTest>) {
        let api = NightMap.Create();
        // Off: nothing happens.
        let w0 = NMCornerTests.FakeWindow();
        let h0 = new NMCornerHost();
        let r0 = h0.Sync(new NightMapSettings(), w0, NMCornerTests.FakeProbe(w0), api);
        t.Check("corner.off_means_today", r0 == 0 && !h0.Active() && NMSelfTest.ChildIndex(w0, n"NightMapCorner") < 0
            && (w0.GetWidgetByIndex(0) as inkCompoundWidget).GetWidgetByIndex(0).GetOpacity() == 0.8, "");

        // Zoom hand-over through expand / collapse.
        let w1 = NMCornerTests.FakeWindow();
        let h1 = new NMCornerHost();
        let created = h1.Sync(NMCornerTests.On(), w1, NMCornerTests.FakeProbe(w1), api) == 1;
        let start = h1.Expanding();
        let hidden = !h1.corner.IsShown();
        h1.Collapsed(1.7);
        // The corner lives inside the vanilla minimap's root (its position and visibility follow the game's) and is
        // never faded with the vanilla children.
        let mini1 = w1.GetWidgetByIndex(0) as inkCompoundWidget;
        let ci = NMSelfTest.ChildIndex(mini1, n"NightMapCorner");
        h1.probe.Fade();
        t.Check("corner.lives_in_minimap_root", ci >= 0 && NMSelfTest.ChildIndex(w1, n"NightMapCorner") < 0
            && mini1.GetWidgetByIndex(ci).GetOpacity() == 1.0 && mini1.GetWidgetByIndex(0).GetOpacity() == 0.0, ToString(ci));
        t.Check("corner.zoom_handover", created && start == 0.0 && hidden && h1.corner.IsShown() && h1.corner.Mpp() == 1.7
            && h1.Expanding() == 1.7, "");
        h1.Collapsed(0.0);
        t.Check("corner.collapse_without_zoom_keeps_it", h1.corner.Mpp() == 1.7, "");

        // Option switched off: corner gone, vanilla opacity back.
        let w2 = NMCornerTests.FakeWindow();
        let mini = w2.GetWidgetByIndex(0) as inkCompoundWidget;
        let h2 = new NMCornerHost();
        h2.Sync(NMCornerTests.On(), w2, NMCornerTests.FakeProbe(w2), api);
        let fadedNow = mini.GetWidgetByIndex(0).GetOpacity() == 0.0;
        let r2 = h2.Sync(new NightMapSettings(), w2, NMCornerTests.FakeProbe(w2), api);
        t.Check("corner.option_off_restores_vanilla", fadedNow && r2 == 2 && !h2.Active()
            && NMSelfTest.ChildIndex(mini, n"NightMapCorner") < 0 && mini.GetWidgetByIndex(0).GetOpacity() == 0.8, "");

        // Session teardown.
        let w3 = NMCornerTests.FakeWindow();
        let mini3 = w3.GetWidgetByIndex(0) as inkCompoundWidget;
        let h3 = new NMCornerHost();
        h3.Sync(NMCornerTests.On(), w3, NMCornerTests.FakeProbe(w3), api);
        h3.Detach();
        t.Check("corner.detach_restores", !h3.Active() && NMSelfTest.ChildIndex(mini3, n"NightMapCorner") < 0
            && mini3.GetWidgetByIndex(0).GetOpacity() == 0.8, "");

        // A settings change rebuilds; an unchanged poll does nothing.
        let w4 = NMCornerTests.FakeWindow();
        let h4 = new NMCornerHost();
        let s4 = NMCornerTests.On();
        h4.Sync(s4, w4, NMCornerTests.FakeProbe(w4), api);
        let same = h4.Sync(s4, w4, NMCornerTests.FakeProbe(w4), api);
        s4.cornerStyle = NightMapCornerStyle.Circle;
        let rebuilt = h4.Sync(s4, w4, NMCornerTests.FakeProbe(w4), api);
        t.Check("corner.settings_change_rebuilds", same == 0 && rebuilt == 3 && h4.corner.HasMask(), "");

        // A rebuild that can't measure the box gives the vanilla minimap back (review: it stayed faded).
        let w7 = NMCornerTests.FakeWindow();
        let mini7 = w7.GetWidgetByIndex(0) as inkCompoundWidget;
        let h7 = new NMCornerHost();
        let s7 = NMCornerTests.On();
        let p7 = NMCornerTests.FakeProbe(w7);
        h7.Sync(s7, w7, p7, api);
        p7.SetBoxForTest(null);
        s7.cornerStyle = NightMapCornerStyle.Square;
        let r7 = h7.Sync(s7, w7, p7, api);
        t.Check("corner.failed_rebuild_restores", r7 == 2 && !h7.Active() && !IsDefined(h7.probe)
            && mini7.GetWidgetByIndex(0).GetOpacity() == 0.8, ToString(r7));

        // A box bigger than a third of the window is not the minimap: no corner.
        let w8 = NMCornerTests.FakeWindow();
        let h8 = new NMCornerHost();
        let big = NMMinimapProbe.ForWidgetBox(w8, w8.GetWidgetByIndex(0), NMRect.Create(0.0, 0.0, 3840.0, 2160.0));   // a full-screen root
        t.Check("corner.box_too_big_rejected", h8.Sync(NMCornerTests.On(), w8, big, api) == 0 && !h8.Active()
            && (w8.GetWidgetByIndex(0) as inkCompoundWidget).GetWidgetByIndex(0).GetOpacity() == 0.8, "");

        // No minimap yet: nothing drawn, retried later.
        let h5 = new NMCornerHost();
        t.Check("corner.waits_for_minimap", h5.Sync(NMCornerTests.On(), new inkCanvas(), null, api) == 0 && !h5.Active(), "");

        // Hide HUD while open: the hider fades the corner with the rest and gives it back; the vanilla stays at 0.
        let w6 = NMCornerTests.FakeWindow();
        let mini6 = w6.GetWidgetByIndex(0) as inkCompoundWidget;
        let h6 = new NMCornerHost();
        h6.Sync(NMCornerTests.On(), w6, NMCornerTests.FakeProbe(w6), api);
        let panel = new inkCanvas();
        panel.Reparent(w6);
        h6.Expanding();
        let hider = NMHudHider.Hide(w6, panel);
        hider.Restore();
        h6.Collapsed(0.5);
        t.Check("corner.hudhider_roundtrip", mini6.GetWidgetByIndex(0).GetOpacity() == 0.0 && h6.corner.Root().GetOpacity() == 1.0
            && h6.corner.IsShown(), "");
        h1.Detach();
        h4.Detach();
        h6.Detach();
    }
}
