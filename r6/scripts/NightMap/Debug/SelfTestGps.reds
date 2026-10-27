module NightMap

// Self-test groups for the GPS route layer. Called from NMSelfTest.Run().
public abstract class NMGpsTests {
    public static func Run(t: ref<NMSelfTest>) {
        NMGpsTests.MathCases(t);
        NMGpsTests.GeomCases(t);
        NMGpsTests.LiveCases(t);
        NMGpsTests.RouteCases(t);
    }

    private static func ChildIndex(root: ref<inkCompoundWidget>, name: CName) -> Int32 {
        let i = 0;
        while i < root.GetNumChildren() {
            if Equals(root.GetWidget(i).GetName(), name) { return i; }
            i += 1;
        }
        return -1;
    }

    private static func RouteCases(t: ref<NMSelfTest>) {
        let yellow = NMTheme.VanillaStateColor(n"Quest");
        let none: array<Vector2>;
        let L = NMRouteLayer.Create(new inkCanvas(), 1.0, true);
        L.SetRoutes(NMGpsTests.Route(), yellow, none);
        t.Check("route.has_route", L.HasRoute(), "");
        L.SetRoutes(NMGpsTests.Route(), yellow, NMGpsTests.Route());
        L.SetRoutes(none, yellow, none);
        t.Check("route.clear_on_empty", !L.HasRoute(), "");

        // 10 km straight route on a 20000 px view at 0.5 m/px: about 830 dashes wanted, capped.
        let long: array<Vector2>;
        ArrayPush(long, new Vector2(0.0, 0.0));
        ArrayPush(long, new Vector2(10000.0, 0.0));
        let cam = NMCamera.Create(20000.0, 20000.0, NMRect.Create(-20000.0, -20000.0, 20000.0, 20000.0), 0.25, 64.0);
        cam.SetCenter(5000.0, 0.0);
        cam.SetMpp(0.5);
        L.SetRoutes(long, yellow, long);
        L.Update(cam, 0.0, 0.0, 16.0, 20000.0, 20000.0);
        t.Check("route.dash_cap", L.DashesShown() > 0 && L.DashesShown() <= NMRouteLayer.DashCap(), ToString(L.DashesShown()));

        let qi = NMGpsTests.ChildIndex(L.Root(), n"quest");
        let ti = NMGpsTests.ChildIndex(L.Root(), n"tracked");
        t.Check("route.order", qi >= 0 && ti > qi, ToString(qi) + " " + ToString(ti));
    }

    private static func LiveCases(t: ref<NMSelfTest>) {
        let gi = GetGameInstance();
        let sys = NightMapSystem.Get(gi);
        let r = IsDefined(sys) ? sys.Gps().Read(GetPlayer(gi)) : null;
        let ok = IsDefined(r) && (ArraySize(r.quest) == 0 || ArraySize(r.quest) >= 2) && (ArraySize(r.tracked) == 0 || ArraySize(r.tracked) >= 2);
        t.Check("gps.read_safe", ok, IsDefined(r) ? "quest " + ToString(ArraySize(r.quest)) + " tracked " + ToString(ArraySize(r.tracked)) : "null");
    }

    // [(0,0), (0,10), (0,20), (0,30), (40,30)]: 70 m, a corner at (0,30).
    private static func Route() -> array<Vector2> {
        let r: array<Vector2>;
        ArrayPush(r, new Vector2(0.0, 0.0));
        ArrayPush(r, new Vector2(0.0, 10.0));
        ArrayPush(r, new Vector2(0.0, 20.0));
        ArrayPush(r, new Vector2(0.0, 30.0));
        ArrayPush(r, new Vector2(40.0, 30.0));
        return r;
    }

    private static func Same(a: Vector2, x: Float, y: Float) -> Bool {
        return AbsF(a.X - x) <= 0.001 && AbsF(a.Y - y) <= 0.001;
    }

    private static func Dump(pts: array<Vector2>) -> String {
        let s = ToString(ArraySize(pts)) + ":";
        for p in pts {
            s += " " + FloatToStringPrec(p.X, 1) + "," + FloatToStringPrec(p.Y, 1);
        }
        return s;
    }

    private static func GeomCases(t: ref<NMSelfTest>) {
        let r = NMGpsTests.Route();
        let same = NMGpsTests.Route();
        t.Check("geom.changed_same", !NMRouteGeom.Changed(r, same), "");
        let end04 = NMGpsTests.Route();
        end04[4] = new Vector2(40.4, 30.0);
        t.Check("geom.changed_end_0p4", !NMRouteGeom.Changed(r, end04), "");
        let end06 = NMGpsTests.Route();
        end06[4] = new Vector2(40.6, 30.0);
        t.Check("geom.changed_end_0p6", NMRouteGeom.Changed(r, end06), "");
        let shorter = NMGpsTests.Route();
        ArrayPop(shorter);
        t.Check("geom.changed_count", NMRouteGeom.Changed(r, shorter), "");

        let a = NMRouteGeom.Trim(r, 0.0, 0.0);
        t.Check("geom.trim_at_start", ArraySize(a) == 6 && NMGpsTests.Same(a[0], 0.0, 0.0) && NMGpsTests.Same(a[1], 0.0, 0.0)
            && NMGpsTests.Same(a[2], 0.0, 10.0), NMGpsTests.Dump(a));
        let b = NMRouteGeom.Trim(r, 0.0, 12.0);
        t.Check("geom.trim_12m", ArraySize(b) == 5 && NMGpsTests.Same(b[0], 0.0, 12.0) && NMGpsTests.Same(b[1], 0.0, 12.0)
            && NMGpsTests.Same(b[2], 0.0, 20.0) && NMGpsTests.Same(b[3], 0.0, 30.0) && NMGpsTests.Same(b[4], 40.0, 30.0), NMGpsTests.Dump(b));
        let c = NMRouteGeom.Trim(r, 20.0, 12.0);
        t.Check("geom.trim_off_route", ArraySize(c) >= 3 && NMGpsTests.Same(c[0], 20.0, 12.0) && NMGpsTests.Same(c[1], 0.0, 12.0)
            && NMGpsTests.Same(c[2], 0.0, 20.0), NMGpsTests.Dump(c));
        let d = NMRouteGeom.Trim(r, 40.0, 30.0);
        t.Check("geom.trim_window", ArraySize(d) >= 2 && NMGpsTests.Same(d[1], 0.0, 30.0), NMGpsTests.Dump(d));

        let bent: array<Vector2>;
        ArrayPush(bent, new Vector2(0.0, 0.0));
        ArrayPush(bent, new Vector2(0.0, 5.0));
        ArrayPush(bent, new Vector2(0.0, 10.0));
        ArrayPush(bent, new Vector2(10.0, 10.0));
        let sb = NMRouteGeom.Simplify(bent, 1.0);
        t.Check("geom.simplify_keeps_corner", ArraySize(sb) == 3 && NMGpsTests.Same(sb[0], 0.0, 0.0) && NMGpsTests.Same(sb[1], 0.0, 10.0)
            && NMGpsTests.Same(sb[2], 10.0, 10.0), NMGpsTests.Dump(sb));
        let two: array<Vector2>;
        ArrayPush(two, new Vector2(1.0, 2.0));
        ArrayPush(two, new Vector2(3.0, 4.0));
        let s2 = NMRouteGeom.Simplify(two, 1.0);
        t.Check("geom.simplify_keeps_ends", ArraySize(s2) == 2 && NMGpsTests.Same(s2[0], 1.0, 2.0) && NMGpsTests.Same(s2[1], 3.0, 4.0), NMGpsTests.Dump(s2));

        t.Check("geom.length", t.Near(NMRouteGeom.Length(r), 70.0, 0.001), t.F(NMRouteGeom.Length(r)));
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
