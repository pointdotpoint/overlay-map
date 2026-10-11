module NightMap

// In-game assertions. Run with Ctrl + toggle key (Debug setting on). Output: [NightMap] TEST|PASS|... lines
// and a final TEST|SUMMARY|passed=N|failed=M line in CET's gamelog.log.
public class NMSelfTest {
    private let passed: Int32;
    private let failed: Int32;

    public func Run() {
        this.passed = 0;
        this.failed = 0;
        NMLog.Info("TEST|START");
        this.MathCases();
        this.CameraCases();
        this.GridCases();
        this.ApiCases();
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
        cam.EaseTo(0.0, 0.0, 8.0, 250.0);
        cam.Tick(50.0);
        cam.ZoomBy(2.0);
        let zoomed = cam.mpp;
        cam.Tick(16.0);
        this.Check("camera.zoom_cancels_ease", !cam.IsEasing() && cam.mpp == zoomed, this.F(cam.mpp) + "/" + this.F(zoomed));
        cam.SetMpp(4.0);
        let v = cam.VisibleRect(0.0);
        this.Check("camera.visible_rect", this.Near(v.maxX - v.minX, 1880.0 * 4.0, 0.1) && this.Near(v.maxY - v.minY, 1480.0 * 4.0, 0.1), "");
    }

    // Deterministic pseudo-random world coordinate in [-11000, 11000).
    private func Coord(i: Int32, mul: Int32) -> Float {
        return Cast<Float>((i * mul) % 22000 - 11000);
    }

    // Brute-force check of every pyramid level against the alive items.
    private func GridConsistent(L: ref<NightMapLayer>) -> String {
        let level = 0;
        while level < 3 {
            let base = NMGrid.Base(level);
            let n = NMGrid.Side(level) * NMGrid.Side(level);
            let cntB: array<Int32>;
            let sxB: array<Float>;
            let syB: array<Float>;
            let tB: array<Int32>;
            ArrayResize(cntB, n);
            ArrayResize(sxB, n);
            ArrayResize(syB, n);
            ArrayResize(tB, n * NMGrid.MaxCats());
            let total = 0;
            let id = 0;
            while id < ArraySize(L.alive) {
                if L.alive[id] {
                    let c = NMGrid.CellIndex(level, L.px[id], L.py[id]);
                    if L.cellOf[id * 3 + level] != c { return "cellOf mismatch id=" + ToString(id) + " level=" + ToString(level); }
                    cntB[c - base] += 1;
                    sxB[c - base] += L.px[id];
                    syB[c - base] += L.py[id];
                    tB[(c - base) * NMGrid.MaxCats() + L.cat[id]] += 1;
                    // the item must be reachable from its cell's list head
                    let walk = L.head[c];
                    let found = false;
                    while walk >= 0 && !found {
                        if walk == id { found = true; }
                        walk = L.nextIn[walk * 3 + level];
                    }
                    if !found { return "id " + ToString(id) + " not linked at level " + ToString(level); }
                }
                id += 1;
            }
            let k = 0;
            while k < n {
                if L.cnt[base + k] != cntB[k] { return "count mismatch level=" + ToString(level) + " cell=" + ToString(k); }
                if AbsF(L.sumX[base + k] - sxB[k]) > 0.5 { return "sumX mismatch level=" + ToString(level) + " cell=" + ToString(k); }
                if AbsF(L.sumY[base + k] - syB[k]) > 0.5 { return "sumY mismatch level=" + ToString(level) + " cell=" + ToString(k); }
                let t = 0;
                while t < NMGrid.MaxCats() {
                    if L.tally[(base + k) * NMGrid.MaxCats() + t] != tB[k * NMGrid.MaxCats() + t] { return "tally mismatch level=" + ToString(level) + " cell=" + ToString(k) + " cat=" + ToString(t); }
                    t += 1;
                }
                // list integrity: alive nodes only, right cell, prev links, length == cnt, cycle-capped
                let node = L.head[base + k];
                let prev = -1;
                let steps = 0;
                while node >= 0 && steps <= L.cnt[base + k] {
                    if !L.IsAlive(node) { return "dead node " + ToString(node) + " linked level=" + ToString(level) + " cell=" + ToString(k); }
                    if L.cellOf[node * 3 + level] != base + k { return "list cell mismatch id=" + ToString(node) + " level=" + ToString(level); }
                    if L.prevIn[node * 3 + level] != prev { return "prevIn mismatch id=" + ToString(node) + " level=" + ToString(level); }
                    prev = node;
                    node = L.nextIn[node * 3 + level];
                    steps += 1;
                }
                if steps != L.cnt[base + k] || node >= 0 { return "list length/cycle level=" + ToString(level) + " cell=" + ToString(k) + " steps=" + ToString(steps); }
                total += L.cnt[base + k];
                k += 1;
            }
            if total != L.count { return "total " + ToString(total) + " != count " + ToString(L.count); }
            level += 1;
        }
        return "";
    }

    private func GridCases() {
        let api = NightMap.Create();
        let L = api.CreateLayer(n"test.grid", "Grid test", 10);
        L.SetCategory(n"test.a", "A", NMTheme.Cyan());
        L.SetCategory(n"test.b", "B", NMTheme.Pink());
        let ids: array<Int32>;
        let i = 0;
        while i < 500 {
            let cat = i % 2 == 0 ? n"test.a" : n"test.b";
            ArrayPush(ids, L.Add(NightMapItem.Create(new Vector4(this.Coord(i, 7919), this.Coord(i, 104729), 0.0, 1.0), cat, r"base\\x.inkatlas", n"p")));
            i += 1;
        }
        this.Check("grid.add_count", L.count == 500 && ids[499] == 499, ToString(L.count));
        let err = this.GridConsistent(L);
        this.Check("grid.consistent_after_add", Equals(err, ""), err);
        let tallyA = 0;
        let c = 0;
        while c < 36 {
            tallyA += L.tally[(NMGrid.Base(2) + c) * NMGrid.MaxCats() + 0];
            c += 1;
        }
        this.Check("grid.tally_level2", tallyA == 250, ToString(tallyA));
        i = 0;
        while i < 100 {
            L.Move(ids[i], new Vector4(this.Coord(i + 900, 31), this.Coord(i + 900, 17), 0.0, 1.0));
            i += 1;
        }
        err = this.GridConsistent(L);
        this.Check("grid.consistent_after_move", Equals(err, ""), err);
        i = 100;
        while i < 200 {
            L.Remove(ids[i]);
            i += 1;
        }
        err = this.GridConsistent(L);
        this.Check("grid.consistent_after_remove", Equals(err, "") && L.count == 400, err);
        let reused = L.Add(NightMapItem.Create(new Vector4(0.0, 0.0, 0.0, 1.0), n"test.a", r"base\\x.inkatlas", n"p"));
        this.Check("grid.id_recycled", reused >= 100 && reused < 200, ToString(reused));
        this.Check("grid.remove_twice_false", !L.Remove(ids[150]) && !L.Move(ids[150], new Vector4(0.0, 0.0, 0.0, 1.0)), "");
        // edges of the grid extent (world bounds default to the whole grid)
        let lo = L.Add(NightMapItem.Create(new Vector4(-12000.0, -12000.0, 0.0, 1.0), n"test.a", r"base\\x.inkatlas", n"p"));
        let hi = L.Add(NightMapItem.Create(new Vector4(11999.0, 11999.0, 0.0, 1.0), n"test.a", r"base\\x.inkatlas", n"p"));
        let out = L.Add(NightMapItem.Create(new Vector4(12000.0, 0.0, 0.0, 1.0), n"test.a", r"base\\x.inkatlas", n"p"));
        this.Check("grid.edges", lo >= 0 && hi >= 0 && out == -1, ToString(lo) + "/" + ToString(hi) + "/" + ToString(out));
        err = this.GridConsistent(L);
        this.Check("grid.consistent_at_edges", Equals(err, ""), err);
        L.Clear();
        let sum = 0;
        c = 0;
        while c < 36 {
            sum += L.cnt[NMGrid.Base(2) + c];
            c += 1;
        }
        this.Check("grid.clear", L.count == 0 && sum == 0, ToString(L.count));
        let first = L.Add(NightMapItem.Create(new Vector4(100.0, 200.0, 0.0, 1.0), n"test.b", r"base\\x.inkatlas", n"p"));
        err = this.GridConsistent(L);
        this.Check("grid.add_after_clear", first == 0 && L.count == 1 && Equals(err, ""), ToString(first) + " " + err);
    }

    private func ApiCases() {
        let api = NightMap.Create();
        api.SetWorld(-6000.0, -4600.0, 4600.0, 7400.0);
        let L = api.CreateLayer(n"test.api", "API test", 5);
        this.Check("api.create_layer_idempotent", api.CreateLayer(n"test.api", "again", 1) == L && ArraySize(api.layers) == 1, "");
        let inside = L.Add(NightMapItem.Create(new Vector4(5500.0, 0.0, 0.0, 1.0), n"x", r"base\\x.inkatlas", n"p"));
        let outside = L.Add(NightMapItem.Create(new Vector4(5700.0, 0.0, 0.0, 1.0), n"x", r"base\\x.inkatlas", n"p"));
        this.Check("api.world_bounds_plus_1km", inside >= 0 && outside == -1, ToString(inside) + "/" + ToString(outside));
        let i = 0;
        while i < 10 {
            L.Add(NightMapItem.Create(new Vector4(0.0, 0.0, 0.0, 1.0), StringToName("cat" + ToString(i)), r"base\\x.inkatlas", n"p"));
            i += 1;
        }
        this.Check("api.category_overflow_to_other", ArraySize(L.catNames) == NMGrid.MaxCats() && Equals(L.catNames[NMGrid.MaxCats() - 1], n"other"),
            ToString(ArraySize(L.catNames)));
        let g = api.CategoryIndex(n"x");
        this.Check("api.global_category", g >= 0 && Equals(api.catNames[g], n"x"), ToString(g));
        let rev = api.revision;
        L.SetOpacity(0.5);
        this.Check("api.revision_bumps", api.revision > rev && L.opacity == 0.5, "");
        let d = NightMapDetails.Create("GIG", "TITLE").AddRow("a", "1").AddRow("b", "2").AddRow("c", "3").AddRow("d", "4")
            .AddRow("e", "5").AddRow("f", "6").AddRow("g", "7").AddAction("K", "one").AddAction("K", "two").AddAction("K", "three").AddAction("K", "four");
        this.Check("api.details_caps", ArraySize(d.rowKeys) == 6 && ArraySize(d.actionKeys) == 3, "");
        api.RemoveLayer(n"test.api");
        this.Check("api.remove_layer", ArraySize(api.layers) == 0 && !IsDefined(api.GetLayer(n"test.api")), "");
    }
}
