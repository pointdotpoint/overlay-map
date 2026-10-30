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

    // Screen Y of every placed waypoint-route piece centre (core canvas children up to DashesUsed).
    private static func DashYs(L: ref<NMRouteLayer>) -> array<Float> {
        let out: array<Float>;
        let line = L.Root().GetWidget(NMGpsTests.ChildIndex(L.Root(), n"tracked")) as inkCompoundWidget;
        let core = line.GetWidget(1) as inkCompoundWidget;   // children: glow canvas, core canvas
        let i = 0;
        while i < L.DashesUsed(true) {
            let at = core.GetWidget(i).GetTranslation();   // bind to a local: see NMPerfTests.GrowScale
            ArrayPush(out, at.Y);
            i += 1;
        }
        return out;
    }

    private static func TopDashY(L: ref<NMRouteLayer>) -> Float {
        let best = 100000.0;
        for y in NMGpsTests.DashYs(L) { best = MinF(best, y); }
        return best;
    }

    // Largest distance between neighbouring piece centres (sorted).
    private static func MaxGap(ys: array<Float>) -> Float {
        let v = ys;
        let i = 1;
        while i < ArraySize(v) {
            let j = i;
            while j > 0 && v[j - 1] > v[j] { let tmp = v[j]; v[j] = v[j - 1]; v[j - 1] = tmp; j -= 1; }
            i += 1;
        }
        let m = 0.0;
        i = 1;
        while i < ArraySize(v) { m = MaxF(m, v[i] - v[i - 1]); i += 1; }
        return m;
    }

    private static func MaxTurn(p: array<Vector2>) -> Float {
        let m = 0.0;
        let i = 1;
        while i < ArraySize(p) - 1 {
            let a1 = AtanF(p[i].Y - p[i - 1].Y, p[i].X - p[i - 1].X);
            let a2 = AtanF(p[i + 1].Y - p[i].Y, p[i + 1].X - p[i].X);
            let d = AbsF(Rad2Deg(a2 - a1));
            if d > 180.0 { d = 360.0 - d; }
            m = MaxF(m, d);
            i += 1;
        }
        return m;
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

        // Straight 100 m route north, 1 m/px, V at its start.
        let north: array<Vector2>;
        ArrayPush(north, new Vector2(0.0, 0.0));
        ArrayPush(north, new Vector2(0.0, 100.0));
        let cam = NMCamera.Create(400.0, 400.0, NMRect.Create(-1000.0, -1000.0, 1000.0, 1000.0), 0.25, 64.0);
        cam.SetCenter(0.0, 50.0);
        cam.SetMpp(1.0);

        // A thin solid line like the vanilla map: overlapping pieces along the smoothed screen route, end to end.
        let P = NMRouteLayer.Create(new inkCanvas(), 1.0, false);
        P.SetRoutes(none, yellow, north);
        cam.SetMpp(0.25);   // 100 m -> 400 px, destination at the top (y 0), V at the bottom (y 400)
        cam.SetCenter(0.0, 50.0);
        P.Update(cam, 0.0, 0.0, 0.0, 400.0, 400.0);
        let len = NMRouteLayer.PieceLen() * NMRouteLayer.LineWidth();
        let ys = NMGpsTests.DashYs(P);
        let top = 100000.0;
        let bottom = -100000.0;
        for y in ys { top = MinF(top, y); bottom = MaxF(bottom, y); }
        t.Check("route.line_ends", ArraySize(ys) > 0 && t.Near(top - len * 0.5, 0.0, 1.0) && t.Near(bottom + len * 0.5, 400.0, 1.0),
            t.F(top - len * 0.5) + " .. " + t.F(bottom + len * 0.5));
        t.Check("route.line_no_gaps", NMGpsTests.MaxGap(ys) <= len - 0.5, t.F(NMGpsTests.MaxGap(ys)) + " len " + t.F(len));
        t.Check("route.thin", NMRouteLayer.LineWidth() <= 12.0 && NMRouteLayer.PieceStep() < NMRouteLayer.PieceLen(), "");

        // Pinned to the road: V moving 5 m along the route leaves the piece at the destination where it was.
        let y0 = NMGpsTests.TopDashY(P);
        P.Update(cam, 0.0, 5.0, 0.0, 400.0, 400.0);
        let y1 = NMGpsTests.TopDashY(P);
        t.Check("route.pinned", y0 < 1000.0 && t.Near(y0, y1, 0.5), t.F(y0) + " -> " + t.F(y1));

        // Time alone moves nothing: a solid line has no flow.
        P.Update(cam, 0.0, 5.0, 100.0, 400.0, 400.0);
        t.Check("route.static", t.Near(NMGpsTests.TopDashY(P), y1, 0.01), t.F(NMGpsTests.TopDashY(P)));

        // Corners are rounded before dashes are placed: a 90 degree turn becomes several gentle ones.
        let ell: array<Vector2>;
        ArrayPush(ell, new Vector2(0.0, 0.0));
        ArrayPush(ell, new Vector2(0.0, 100.0));
        ArrayPush(ell, new Vector2(100.0, 100.0));
        let sm = NMRouteLayer.Smooth(ell, 2);
        t.Check("route.smooth_corner", NMGpsTests.MaxTurn(sm) <= 46.0 && sm[0].X == 0.0 && sm[0].Y == 0.0
            && sm[ArraySize(sm) - 1].X == 100.0, t.F(NMGpsTests.MaxTurn(sm)));

        // A route entirely off screen draws nothing.
        let far: array<Vector2>;
        ArrayPush(far, new Vector2(900.0, 900.0));
        ArrayPush(far, new Vector2(950.0, 900.0));
        P.SetRoutes(none, yellow, far);
        P.Update(cam, 900.0, 900.0, 0.0, 400.0, 400.0);
        t.Check("route.clipped", P.DashesShown() == 0, ToString(P.DashesShown()));

        // A very long route on a huge view is capped.
        let long: array<Vector2>;
        ArrayPush(long, new Vector2(0.0, 0.0));
        ArrayPush(long, new Vector2(10000.0, 0.0));
        let camL = NMCamera.Create(40000.0, 40000.0, NMRect.Create(-20000.0, -20000.0, 20000.0, 20000.0), 0.25, 64.0);
        camL.SetCenter(5000.0, 0.0);
        camL.SetMpp(0.25);
        L.SetRoutes(long, yellow, long);
        L.Update(camL, 0.0, 0.0, 16.0, 40000.0, 40000.0);
        t.Check("route.dash_cap", L.DashesShown() == NMRouteLayer.DashCap(), ToString(L.DashesShown()));

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
        // A perf run closed mid-suite must not leave the routes off for the session (OnClosing clears the override).
        if IsDefined(sys) {
            let was = sys.RoutesOn();
            sys.SetRoutesEnabled(false);
            sys.ClearPerfOverrides();
            t.Check("gps.routes_override_cleared", sys.RoutesOn(), "");
            sys.SetRoutesEnabled(was);
        }
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

        // The 30 m window starts at the cursor (last matched segment), so a V far along the route is never pulled back.
        t.Check("geom.closest_from_start", NMRouteGeom.Closest(r, 0.0, 12.0, 0) == 1, ToString(NMRouteGeom.Closest(r, 0.0, 12.0, 0)));
        t.Check("geom.closest_from_cursor", NMRouteGeom.Closest(r, 38.0, 31.0, 3) == 3, ToString(NMRouteGeom.Closest(r, 38.0, 31.0, 3)));
        let e = NMRouteGeom.TrimAt(r, 38.0, 31.0, 3);
        t.Check("geom.trim_cursor", ArraySize(e) == 3 && NMGpsTests.Same(e[1], 38.0, 30.0) && NMGpsTests.Same(e[2], 40.0, 30.0), NMGpsTests.Dump(e));

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
        t.Check("gps.reject_ok", Equals(NMGps.Reject(v0, px, py, 3.18), ""), NMGps.Reject(v0, px, py, 3.18));
        t.Check("gps.reject_scale", Equals(NMGps.Reject(v0, px, py, 12.0), "scale_range"), NMGps.Reject(v0, px, py, 12.0));
        let skew = new Vector2(3.18 * py * 1.08, 3.18 * px);
        t.Check("gps.reject_axis", Equals(NMGps.Reject(skew, px, py, 3.18), "axis_mismatch"), NMGps.Reject(skew, px, py, 3.18));
        // The player's own vertex decodes 20 m away from the player (a stale reading): the axis ratios still agree.
        let stale = new Vector2(3.18 * py, 3.18 * (px + 20.0));
        t.Check("gps.reject_first_far", Equals(NMGps.Reject(stale, px, py, 3.18), "first_far"), NMGps.Reject(stale, px, py, 3.18));
        let mirrored = new Vector2(-3.18 * py, -3.18 * px);
        t.Check("gps.reject_mirrored", Equals(NMGps.Reject(mirrored, px, py, 3.18), "first_far"), NMGps.Reject(mirrored, px, py, 3.18));
    }
}
