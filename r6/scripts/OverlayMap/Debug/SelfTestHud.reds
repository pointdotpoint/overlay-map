module OverlayMap

// Self-test group for hiding the HUD while the map is open. Called from NMSelfTest.Run(). Detached widgets only.
public abstract class NMHudTests {
    public static func Run(t: ref<NMSelfTest>) {
        let host = new inkCanvas();
        let a = NMUi.Canvas(host, 0.0, 0.0, 10.0, 10.0);
        let b = NMUi.Canvas(host, 0.0, 0.0, 10.0, 10.0);
        b.SetOpacity(0.5);
        let panel = NMUi.Canvas(host, 0.0, 0.0, 10.0, 10.0);
        let h = NMHudHider.Hide(host, panel);
        t.Check("hud.hides_others", a.GetOpacity() == 0.0 && b.GetOpacity() == 0.0, t.F(a.GetOpacity()) + " " + t.F(b.GetOpacity()));
        t.Check("hud.keeps_panel", panel.GetOpacity() == 1.0 && panel.IsVisible(), t.F(panel.GetOpacity()));

        // A HUD widget added, or faded back in by its own controller, while the map is open.
        let c = NMUi.Canvas(host, 0.0, 0.0, 10.0, 10.0);
        c.SetOpacity(0.8);
        a.SetOpacity(1.0);
        h.Refresh();
        t.Check("hud.refresh", a.GetOpacity() == 0.0 && c.GetOpacity() == 0.0, t.F(a.GetOpacity()) + " " + t.F(c.GetOpacity()));

        h.Restore();
        t.Check("hud.restore", t.Near(a.GetOpacity(), 1.0, 0.001) && t.Near(b.GetOpacity(), 0.5, 0.001) && t.Near(c.GetOpacity(), 0.8, 0.001),
            t.F(a.GetOpacity()) + " " + t.F(b.GetOpacity()) + " " + t.F(c.GetOpacity()));
        t.Check("hud.restore_keeps_panel", panel.GetOpacity() == 1.0, t.F(panel.GetOpacity()));
    }
}
