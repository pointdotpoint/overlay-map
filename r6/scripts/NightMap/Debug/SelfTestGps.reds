module NightMap

// Self-test groups for the GPS route layer. Called from NMSelfTest.Run().
public abstract class NMGpsTests {
    public static func Run(t: ref<NMSelfTest>) {
        NMGpsTests.MathCases(t);
    }

    // Absolute minimap point for world point w: the forward transform of FINDINGS.md (test-only inverse of ToWorld).
    public static func Forward(w: Vector2, px: Float, py: Float, camYaw: Float, s: Float) -> Vector2 {
        let dx = w.X - px;
        let dy = -(w.Y - py);   // flipY
        let r = Deg2Rad(camYaw);
        let rx = dx * CosF(r) - dy * SinF(r);
        let ry = dx * SinF(r) + dy * CosF(r);
        return new Vector2(s * py + s * rx, s * px + s * ry);
    }

    private static func RoundTrip(t: ref<NMSelfTest>, name: String, camYaw: Float, s: Float) {
        let px = -957.2;
        let py = -806.1;
        let v0 = NMGpsTests.Forward(new Vector2(px, py), px, py, camYaw, s);
        let a = new Vector2(-1624.3, -386.8);
        let b = new Vector2(-953.8, -783.6);
        let ra = NMGps.ToWorld(NMGpsTests.Forward(a, px, py, camYaw, s), v0, px, py, camYaw, s);
        let rb = NMGps.ToWorld(NMGpsTests.Forward(b, px, py, camYaw, s), v0, px, py, camYaw, s);
        let ok = t.Near(ra.X, a.X, 0.01) && t.Near(ra.Y, a.Y, 0.01) && t.Near(rb.X, b.X, 0.01) && t.Near(rb.Y, b.Y, 0.01);
        t.Check(name, ok, t.F(ra.X) + "," + t.F(ra.Y) + " / " + t.F(rb.X) + "," + t.F(rb.Y));
    }

    private static func MathCases(t: ref<NMSelfTest>) {
        NMGpsTests.RoundTrip(t, "gps.toWorld_yaw_0", 0.0, 3.18);
        NMGpsTests.RoundTrip(t, "gps.toWorld_yaw_90", 90.0, 3.18);
        NMGpsTests.RoundTrip(t, "gps.toWorld_yaw_m90", -90.0, 3.18);
        NMGpsTests.RoundTrip(t, "gps.toWorld_yaw_180", 180.0, 3.18);
        NMGpsTests.RoundTrip(t, "gps.toWorld_scale_0p8", 37.5, 0.8);
        NMGpsTests.RoundTrip(t, "gps.toWorld_scale_3p18", 37.5, 3.18);

        // Session 1 sample: quest route end vs its mappin (-995.7, -710.9).
        let w = NMGps.ToWorld(new Vector2(-2877.3, -3129.7), new Vector2(-2563.3, -3047.8), -957.8, -805.6, -53.6, 3.182);
        let d = SqrtF((w.X + 995.7) * (w.X + 995.7) + (w.Y + 710.9) * (w.Y + 710.9));
        t.Check("gps.toWorld_spike_sample", d <= 3.0, t.F(w.X) + "," + t.F(w.Y) + " d=" + t.F(d));

        let px = -957.2;
        let py = -806.1;
        let sc = NMGps.Scale(NMGpsTests.Forward(new Vector2(px, py), px, py, 0.0, 3.18), px, py);
        t.Check("gps.scale_matches", t.Near(sc, 3.18, 0.001), t.F(sc));
        t.Check("gps.scale_near_origin", NMGps.Scale(new Vector2(10.0, 10.0), 20.0, -30.0) == -1.0, "");

        t.Check("gps.cameraYaw_north", t.Near(NMGps.CameraYaw(new Vector4(0.0, 1.0, 0.0, 0.0)), 0.0, 0.01), "");
        t.Check("gps.cameraYaw_west", t.Near(NMGps.CameraYaw(new Vector4(-1.0, 0.0, 0.0, 0.0)), 90.0, 0.01), "");

        let v0 = new Vector2(3.18 * py, 3.18 * px);
        let near = new Vector2(px + 3.0, py);
        t.Check("gps.reject_ok", Equals(NMGps.Reject(v0, px, py, 3.18, near), ""), NMGps.Reject(v0, px, py, 3.18, near));
        t.Check("gps.reject_scale", Equals(NMGps.Reject(v0, px, py, 12.0, near), "scale_range"), NMGps.Reject(v0, px, py, 12.0, near));
        let skew = new Vector2(3.18 * py * 1.08, 3.18 * px);
        t.Check("gps.reject_axis", Equals(NMGps.Reject(skew, px, py, 3.18, near), "axis_mismatch"), NMGps.Reject(skew, px, py, 3.18, near));
        let far = new Vector2(px + 20.0, py);
        t.Check("gps.reject_first_far", Equals(NMGps.Reject(v0, px, py, 3.18, far), "first_far"), NMGps.Reject(v0, px, py, 3.18, far));
    }
}
