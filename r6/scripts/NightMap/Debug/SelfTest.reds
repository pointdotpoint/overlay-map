module NightMap

// In-game assertions. Run with Ctrl + toggle key (Debug setting on). Output: [NightMap] TEST|PASS|... lines
// and a final TEST|SUMMARY|passed=N|failed=M line in CET's gamelog.log.
public class NMSelfTest {
    private let passed: Int32;
    private let failed: Int32;

    public func Run() {
        NMLog.Info("TEST|START");
        this.MathCases();
        this.CameraCases();
        NMLog.Info("TEST|SUMMARY|passed=" + ToString(this.passed) + "|failed=" + ToString(this.failed));
    }

    public func Check(name: String, ok: Bool, detail: String) {
        if ok {
            this.passed += 1;
            NMLog.Info("TEST|PASS|" + name);
        } else {
            this.failed += 1;
            NMLog.Info("TEST|FAIL|" + name + "|" + detail);
        }
    }

    public func Near(a: Float, b: Float, eps: Float) -> Bool {
        return AbsF(a - b) <= eps;
    }

    public func F(v: Float) -> String {
        return FloatToStringPrec(v, 3);
    }

    private func MathCases() {
        let a = AtanF(1.0, 0.0);
        this.Check("math.atan_order", this.Near(a, 1.5707963, 0.001), "AtanF(1,0)=" + this.F(a) + " (expected pi/2: AtanF(y,x))");
        this.Check("math.heading_north", this.Near(NMMath.HeadingDeg(0.0, 1.0), 0.0, 0.01), this.F(NMMath.HeadingDeg(0.0, 1.0)));
        this.Check("math.heading_east", this.Near(NMMath.HeadingDeg(1.0, 0.0), 90.0, 0.01), this.F(NMMath.HeadingDeg(1.0, 0.0)));
        this.Check("math.nice_length", NMMath.NiceLength(730.0) == 500.0 && NMMath.NiceLength(5.0) == 10.0, this.F(NMMath.NiceLength(730.0)));
        this.Check("math.format_meters", Equals(NMMath.FormatMeters(2000.0), "2 KM") && Equals(NMMath.FormatMeters(500.0), "500 M"),
            NMMath.FormatMeters(2000.0) + " / " + NMMath.FormatMeters(500.0));
        let r = NMRect.Create(0.0, 0.0, 10.0, 10.0);
        this.Check("math.rect_contains", r.Contains(10.0, 0.0) && !r.Contains(10.1, 0.0) && !r.Contains(5.0, -0.1), "");
    }

    private func CameraCases() {
        let b = NMRect.Create(-6000.0, -4600.0, 4600.0, 7400.0);
        let cam = NMCamera.Create(1880.0, 1480.0, b, 0.5, 16.0);
        cam.SetCenter(100.0, 200.0);
        let c = cam.WorldToMap(100.0, 200.0);
        this.Check("camera.center_maps_to_view_center", this.Near(c.X, 940.0, 0.01) && this.Near(c.Y, 740.0, 0.01), this.F(c.X) + "," + this.F(c.Y));
        let north = cam.WorldToMap(100.0, 300.0);
        this.Check("camera.north_up", north.Y < c.Y && this.Near(north.X, c.X, 0.01), this.F(north.Y));
        let ok = true;
        let mpps: array<Float> = [0.5, 2.0, 16.0];
        for m in mpps {
            cam.SetMpp(m);
            let p = cam.WorldToMap(-1234.5, 987.25);
            let w = cam.MapToWorld(p.X, p.Y);
            if !this.Near(w.X, -1234.5, 0.01) || !this.Near(w.Y, 987.25, 0.01) { ok = false; }
        }
        this.Check("camera.roundtrip", ok, "");
        cam.ZoomBy(100000.0);
        let zin = cam.mpp;
        cam.ZoomBy(0.000001);
        this.Check("camera.zoom_clamp", zin == 0.5 && cam.mpp == 16.0, this.F(zin) + "/" + this.F(cam.mpp));
        cam.SetCenter(99999.0, -99999.0);
        this.Check("camera.bounds_clamp", cam.cx == 4600.0 && cam.cy == -4600.0, this.F(cam.cx) + "," + this.F(cam.cy));
        cam.SetCenter(0.0, 0.0);
        cam.SetMpp(2.0);
        cam.follow = true;
        let rev = cam.revision;
        cam.PanPixels(10.0, 0.0);
        this.Check("camera.pan_disables_follow", !cam.follow && this.Near(cam.cx, 20.0, 0.01) && cam.revision > rev, this.F(cam.cx));
        cam.EaseTo(-500.0, 300.0, 4.0, 250.0);
        cam.Tick(100.0);
        let mid = cam.IsEasing();
        cam.Tick(200.0);
        this.Check("camera.ease_reaches_target", mid && !cam.IsEasing() && this.Near(cam.cx, -500.0, 0.01) && this.Near(cam.cy, 300.0, 0.01) && this.Near(cam.mpp, 4.0, 0.001),
            this.F(cam.cx) + "," + this.F(cam.cy) + "," + this.F(cam.mpp));
        let v = cam.VisibleRect(0.0);
        this.Check("camera.visible_rect", this.Near(v.maxX - v.minX, 1880.0 * 4.0, 0.1) && this.Near(v.maxY - v.minY, 1480.0 * 4.0, 0.1), "");
    }
}
