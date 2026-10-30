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
        this.InputCases();
        this.LayoutCases();
        this.TileCases();
        this.RendererCases();
        this.PickCases();
        this.TooltipCases();
        this.VersionCases();
        NMHoloTests.Run(this);
        NMVanillaTests.Run(this);
        NMGpsTests.Run(this);
        NMHudTests.Run(this);
        NMFastTravelTests.Run(this);
        NMPhotoTests.Run(this);
        NMPerfTests.Run(this);
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
        let cam = NMCamera.Create(1880.0, 1480.0, b, NightMapSystem.MinMpp(), NightMapSystem.MaxMpp());
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
        this.Check("camera.zoom_clamp", zin == 0.1 && cam.mpp == 16.0, this.F(zin) + "/" + this.F(cam.mpp));
        this.Check("camera.closer_than_tiles", NightMapSystem.MinMpp() == 0.1 && NightMapSystem.OpenMpp() == NMTileManifest.LevelMpp(0),
            this.F(NightMapSystem.MinMpp()) + " open " + this.F(NightMapSystem.OpenMpp()));
        this.Check("photo.thumb_zoom", NMItemRenderer.ThumbZoom(16.0) == 1.0 && NMItemRenderer.ThumbZoom(0.5) == 1.0
            && this.Near(NMItemRenderer.ThumbZoom(0.25), 2.0, 0.001) && this.Near(NMItemRenderer.ThumbZoom(0.1), 5.0, 0.001),
            this.F(NMItemRenderer.ThumbZoom(0.25)) + " " + this.F(NMItemRenderer.ThumbZoom(0.1)));
        this.Check("camera.limits_follow_manifest", NightMapSystem.MaxMpp() == NMTileManifest.LevelMpp(NMTileManifest.LevelCount() - 1),
            this.F(NightMapSystem.MinMpp()) + "/" + this.F(NightMapSystem.MaxMpp()));
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
            let occErr = NMPerfTests.OccErr(L);
            if NotEquals(occErr, "") { return occErr; }
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

    private func InputCases() {
        let s = new NightMapSettings();
        // Mod Settings applies the user's saved bindings to class defaults, so pin every key the test relies on.
        s.keyToggle = EInputKey.IK_Backslash;
        s.keyPanUp = EInputKey.IK_NumPad8;
        s.keyPanDown = EInputKey.IK_NumPad2;
        s.keyPanLeft = EInputKey.IK_NumPad4;
        s.keyPanRight = EInputKey.IK_NumPad6;
        s.keyZoomIn = EInputKey.IK_NumPlus;
        s.keyZoomOut = EInputKey.IK_NumMinus;
        s.keyRecenter = EInputKey.IK_NumPad5;
        s.keyAct = EInputKey.IK_NumPad0;
        let inp = new NMInput();
        let press = EInputAction.IACT_Press;
        let release = EInputAction.IACT_Release;
        this.Check("input.toggle", inp.Handle(s, EInputKey.IK_Backslash, press, false, false, false, false) && inp.toggle, "");
        inp.toggle = false;
        inp.Handle(s, EInputKey.IK_Backslash, press, false, true, false, false);
        this.Check("input.ctrl_toggle_is_selftest", inp.debugSelfTest && !inp.toggle, "");
        // Hold to show: press opens, release closes, and a toggle key's release still does nothing.
        let hs = new NightMapSettings();
        hs.keyToggle = EInputKey.IK_Backslash;
        let rel = EInputAction.IACT_Release;
        let hi = new NMInput();
        hi.Handle(hs, EInputKey.IK_Backslash, press, false, false, false, true);
        hi.toggle = false;
        hi.Handle(hs, EInputKey.IK_Backslash, rel, false, false, false, true);
        this.Check("input.toggle_ignores_release", !hi.toggle, "");
        hs.holdToShow = true;
        hi.Handle(hs, EInputKey.IK_Backslash, press, false, false, false, false);
        let holdOpens = hi.toggle;
        hi.toggle = false;
        hi.Handle(hs, EInputKey.IK_Backslash, press, false, false, false, true);
        let heldStaysOpen = !hi.toggle;
        hi.Handle(hs, EInputKey.IK_Backslash, rel, false, false, false, true);
        let releaseCloses = hi.toggle;
        hi.toggle = false;
        hi.Handle(hs, EInputKey.IK_Backslash, rel, false, false, false, false);
        let releaseClosedIgnored = !hi.toggle;
        this.Check("input.hold_to_show", holdOpens && heldStaysOpen && releaseCloses && releaseClosedIgnored,
            ToString(holdOpens) + ToString(heldStaysOpen) + ToString(releaseCloses) + ToString(releaseClosedIgnored));
        this.Check("input.hold_hint", StrContains(NMInput.HintText(hs, "ALL", "TELEPORT"), "RELEASE") && !StrContains(NMInput.HintText(s, "ALL", "TELEPORT"), "RELEASE"), "");
        this.Check("input.ignored_when_closed", !inp.Handle(s, EInputKey.IK_NumPad8, press, false, false, false, false), "");
        let usedArrow = inp.Handle(s, EInputKey.IK_Up, press, false, false, false, true);
        let v0 = inp.PanVector();
        this.Check("input.arrows_never_pan", !usedArrow && v0.X == 0.0 && v0.Y == 0.0 && inp.arrowSeen, "");
        inp.Handle(s, EInputKey.IK_NumPad8, press, false, false, false, true);
        let v1 = inp.PanVector();
        inp.Handle(s, EInputKey.IK_NumPad8, release, false, false, false, true);
        let v2 = inp.PanVector();
        this.Check("input.numpad8_pans_up", v1.X == 0.0 && v1.Y == -1.0 && v2.Y == 0.0, this.F(v1.Y));
        inp.Handle(s, EInputKey.IK_NumPad9, press, false, false, false, true);
        let v3 = inp.PanVector();
        inp.ResetHeld();
        this.Check("input.numpad9_diagonal", this.Near(v3.X, 0.7071, 0.001) && this.Near(v3.Y, -0.7071, 0.001), this.F(v3.X) + "," + this.F(v3.Y));
        inp.Handle(s, EInputKey.IK_Backslash, press, true, true, false, false);
        inp.Handle(s, EInputKey.IK_Backslash, press, true, false, false, false);
        inp.Handle(s, EInputKey.IK_Backslash, press, false, false, true, false);
        this.Check("input.debug_chords", inp.debugLayer && inp.debugPerf && inp.debugCalib && !inp.toggle, "");
        inp.Handle(s, EInputKey.IK_NumPlus, press, false, false, false, true);
        this.Check("input.zoom_held", inp.zoomIn && !inp.zoomOut, "");
        this.Check("input.key_names", Equals(NMInput.KeyName(EInputKey.IK_NumPad8), "NUM 8") && Equals(NMInput.KeyName(EInputKey.IK_Backslash), "\\")
            && Equals(NMInput.KeyName(EInputKey.IK_NumPlus), "NUM +")
            && Equals(NMInput.KeyName(EInputKey.IK_SingleQuote), "'"), NMInput.KeyName(EInputKey.IK_NumPad8));
    }

    private func LayoutCases() {
        let sizes: array<Vector2> = [new Vector2(3840.0, 2160.0), new Vector2(5120.0, 2160.0), new Vector2(2560.0, 1600.0), new Vector2(1920.0, 1080.0)];
        let ok = true;
        let detail = "";
        for sz in sizes {
            let l = NMPanelLayout.Compute(sz.X, sz.Y);
            let inside = l.x >= 0.0 && l.y >= 0.0 && l.x + l.w <= sz.X + 0.01 && l.y + l.h <= sz.Y + 0.01;
            let parts = l.mapW > 0.0 && l.mapH > 0.0 && this.Near(l.mapW, l.w, 0.001);
            if !inside || !parts {
                ok = false;
                detail += this.F(sz.X) + "x" + this.F(sz.Y) + " ";
            }
        }
        this.Check("layout.fits_all_aspects", ok, detail);
        let full = NMPanelLayout.Compute(3840.0, 2160.0);
        this.Check("layout.full_width_map", full.mapW == full.w, this.F(full.mapW) + "/" + this.F(full.w));
        this.Check("layout.ninety_percent_wide", this.Near(full.w, 3840.0 * 0.9, 0.5), this.F(full.w));
        this.Check("layout.sidebar_quarter", this.Near(full.sideW, full.mapW * 0.25, 0.5) && this.Near(full.viewW, full.mapW - full.sideW, 0.5),
            this.F(full.sideW) + " " + this.F(full.viewW));
    }

    private func TileCases() {
        if !NMTileManifest.Available() {
            this.Check("tiles.manifest_available", false, "Generated/TileManifest.reds is the stub; run the tile build");
            return;
        }
        let n = NMTileManifest.LevelCount();
        this.Check("tiles.six_levels_four_sets", n == 6 && NMTileManifest.SetCount() == 4, ToString(n) + "/" + ToString(NMTileManifest.SetCount()));
        let ascending = true;
        let i = 1;
        while i < n {
            if NMTileManifest.LevelMpp(i) <= NMTileManifest.LevelMpp(i - 1) { ascending = false; }
            i += 1;
        }
        this.Check("tiles.levels_ascending", n >= 1 && ascending, ToString(n));
        this.Check("tiles.zoom_limits", this.Near(NMTileManifest.LevelMpp(0), 0.5, 0.0001) && this.Near(NMTileManifest.LevelMpp(n - 1), 16.0, 0.0001), "");
        // PickLevel is downscale-only: the coarsest level with m/px <= camera m/px, clamped to the finest.
        let pickOk = true;
        let pickDetail = "";
        let l = 0;
        while l < n {
            let m = NMTileManifest.LevelMpp(l);
            let hi = l + 1 < n ? NMTileManifest.LevelMpp(l + 1) : m * 8.0;
            if NMTileLayer.PickLevel(m) != l || NMTileLayer.PickLevel(m * 1.5) != l || NMTileLayer.PickLevel(hi * 0.999) != l {
                pickOk = false;
                pickDetail += "L" + ToString(l) + "=" + ToString(NMTileLayer.PickLevel(m)) + "," + ToString(NMTileLayer.PickLevel(m * 1.5)) + "," + ToString(NMTileLayer.PickLevel(hi * 0.999)) + " ";
            }
            l += 1;
        }
        this.Check("tiles.pick_level_downscale_only", pickOk && NMTileLayer.PickLevel(0.1) == 0 && NMTileLayer.PickLevel(1000.0) == n - 1, pickDetail);
        this.Check("tiles.ui_atlas_in_depot", GameInstance.GetResourceDepot().ResourceExists(NMTheme.UiAtlas()), "nightmap\\ui\\ui.inkatlas not found: archive not installed?");
        // Crossfade ramp: linear, clamped, symmetric.
        let dur = NMTileLayer.FadeMs();
        this.Check("tiles.fade_ramp", this.Near(NMTileLayer.FadeStep(0.0, dur * 0.5, dur, true), 0.5, 0.0001)
            && this.Near(NMTileLayer.FadeStep(1.0, dur * 0.25, dur, false), 0.75, 0.0001)
            && NMTileLayer.FadeStep(0.9, dur * 3.0, dur, true) == 1.0 && NMTileLayer.FadeStep(0.1, dur * 3.0, dur, false) == 0.0
            && NMTileLayer.FadeStep(0.3, 0.0, dur, true) == 0.3 && dur > 100.0 && dur < 250.0, this.F(dur));
        // Outgoing opacity keeps the combined coverage constant: 1 - (1 - under) * (1 - op * a) == op, from op down to 0.
        let fadeOk = true;
        let fa = 0.0;
        while fa < 0.999 {
            let under = NMTileLayer.UnderOpacity(0.9, fa);
            if !this.Near(1.0 - (1.0 - under) * (1.0 - 0.9 * fa), 0.9, 0.001) { fadeOk = false; }
            fa += 0.1;
        }
        this.Check("tiles.fade_no_dim", fadeOk && this.Near(NMTileLayer.UnderOpacity(0.9, 0.0), 0.9, 0.0001) && NMTileLayer.UnderOpacity(0.9, 1.0) == 0.0, "");
        // SetTiles lookup: every listed tile is found, the first unlisted index of each level is not.
        let canvas = new inkCanvas();   // detached: widgets exist but are never drawn
        let hitsOk = true;
        let missOk = true;
        let emptyDetail = "";
        let counts = "";
        let s = 0;
        while s < NMTileManifest.SetCount() {
            let layer = NMTileLayer.Create(canvas, s, 0);
            let lv = 0;
            while lv < n {
                let tiles: array<Int32> = NMTileManifest.SetTiles(s, lv);
                let nx = NMTileManifest.LevelNx(lv);
                let total = nx * NMTileManifest.LevelNy(lv);
                let sorted = true;
                let prev = -1;
                for key in tiles {
                    if key <= prev { sorted = false; }
                    prev = key;
                    if !layer.Has(lv, key % nx, key / nx) { hitsOk = false; }
                }
                if !sorted { hitsOk = false; }
                let probe = 0;
                while probe < total && probe < ArraySize(tiles) && tiles[probe] == probe {
                    probe += 1;
                }
                if probe < total && layer.Has(lv, probe % nx, probe / nx) { missOk = false; }
                if layer.Has(lv, -1, 0) || layer.Has(lv, nx, 0) { missOk = false; }
                // glow is baked only at L2.. (mpp >= 2): empty at L0/L1 by design, checked in HoloCases
                if ArraySize(tiles) == 0 && !(Equals(NMTileManifest.SetName(s), "glow") && lv < 2) { emptyDetail += NMTileManifest.SetName(s) + ".L" + ToString(lv) + " "; }
                counts += ToString(ArraySize(tiles)) + (lv + 1 < n ? "," : ";");
                lv += 1;
            }
            s += 1;
        }
        // Update state machine on a detached layer: fade start, swap-back, third level, release after the fade.
        let cb = NMRect.Create(NMTileManifest.WorldMinX(), NMTileManifest.WorldMinY(), NMTileManifest.WorldMaxX(), NMTileManifest.WorldMaxY());
        let cam = NMCamera.Create(1880.0, 1480.0, cb, NightMapSystem.MinMpp(), NightMapSystem.MaxMpp());
        cam.SetCenter(-1800.0, 150.0);
        let sl = NMTileLayer.Create(canvas, NMHoloTests.SetIndex("road"), 0);
        sl.skipLoadWait = true;
        cam.SetMpp(1.0);
        sl.Update(cam, 16.0);
        let st1 = sl.CurrentLevel() == 1 && sl.PreviousLevel() == -1;
        cam.SetMpp(2.0);
        sl.Update(cam, 16.0);
        let st2 = sl.CurrentLevel() == 2 && sl.PreviousLevel() == 1;
        sl.Update(cam, 16.0);   // the frame of a level change does not fade yet
        // Short step: after the swap the returning level is at ~0.95, so another 16 ms step would reach 1 and release the outgoing level.
        cam.SetMpp(1.0);
        sl.Update(cam, 1.0);
        let st3 = sl.CurrentLevel() == 1 && sl.PreviousLevel() == 2;
        cam.SetMpp(8.0);
        sl.Update(cam, 16.0);
        let st4 = sl.CurrentLevel() == 4 && sl.PreviousLevel() == 1;
        sl.Update(cam, NMTileLayer.FadeMs() * 2.0);
        let st5 = sl.CurrentLevel() == 4 && sl.PreviousLevel() == -1;
        // Tiles that have not loaded: the incoming level waits, and the outgoing one stays until it can fade in.
        let wl = NMTileLayer.Create(canvas, NMHoloTests.SetIndex("road"), 0);
        wl.skipLoadWait = true;
        cam.SetMpp(1.0);
        wl.Update(cam, 16.0);
        wl.skipLoadWait = false;
        wl.holdLoads = true;
        cam.SetMpp(2.0);
        wl.Update(cam, 16.0);
        wl.Update(cam, 16.0);
        wl.Update(cam, 16.0);
        this.Check("tiles.fade_waits_for_tiles", wl.CurrentLevel() == 2 && wl.PreviousLevel() == 1 && wl.Alpha() == 0.0 && wl.Waiting() > 0,
            ToString(wl.CurrentLevel()) + " " + ToString(wl.PreviousLevel()) + " " + this.F(wl.Alpha()) + " " + ToString(wl.Waiting()));
        cam.SetMpp(4.0);
        wl.Update(cam, 16.0);
        this.Check("tiles.unshown_level_dropped", wl.CurrentLevel() == 3 && wl.PreviousLevel() == 1,
            ToString(wl.CurrentLevel()) + " " + ToString(wl.PreviousLevel()));
        wl.Update(cam, NMTileLayer.LoadTimeoutMs());
        wl.Update(cam, NMTileLayer.FadeMs() * 2.0);
        this.Check("tiles.load_timeout_gives_up", wl.CurrentLevel() == 3 && wl.Waiting() == 0 && wl.PreviousLevel() == -1,
            ToString(wl.Waiting()) + " " + ToString(wl.PreviousLevel()));
        this.Check("tiles.layer_state_machine", st1 && st2 && st3 && st4 && st5, ToString(st1) + ToString(st2) + ToString(st3) + ToString(st4) + ToString(st5));
        this.Check("tiles.settiles_lookup_hits", hitsOk, "");
        this.Check("tiles.settiles_lookup_misses", missOk, "");
        NMLog.Info("TEST|INFO|tiles.set_level_counts|" + counts);
        this.Check("tiles.no_empty_set_levels", Equals(emptyDetail, ""), emptyDetail);
        // Read through locals: field access on a call temporary reads 0 in redscript.
        let roadTint: HDRColor = NMTheme.TileTint("road", 0);
        let roadOp: Float = NMTheme.TileOpacity("road");
        let outlineOp: Float = NMTheme.TileOpacity("outline");
        this.Check("tiles.theme_defaults", this.Near(roadOp, 0.55, 0.0001) && this.Near(outlineOp, 0.9, 0.0001) && this.Near(roadTint.Red, 0.118, 0.001),
            ToString(roadOp) + "," + ToString(outlineOp) + "," + ToString(roadTint.Red));
    }

    private func RendererCases() {
        let api = NightMap.Create();
        api.SetWorld(NMTileManifest.WorldMinX(), NMTileManifest.WorldMinY(), NMTileManifest.WorldMaxX(), NMTileManifest.WorldMaxY());
        NMDebugLayer.Fill(api, 3000);
        let canvas = new inkCanvas();   // detached: widgets exist but are never drawn
        let r = NMItemRenderer.Create(api, canvas, 1.0);
        let bounds = NMRect.Create(NMTileManifest.WorldMinX(), NMTileManifest.WorldMinY(), NMTileManifest.WorldMaxX(), NMTileManifest.WorldMaxY());
        let cam = NMCamera.Create(1880.0, 1480.0, bounds, 0.5, 16.0);
        let ok = true;
        let detail = "";
        let mpps: array<Float> = [0.6, 2.0, 6.0, 16.0];
        for m in mpps {
            cam.SetMpp(m);
            r.Update(cam, 1880.0, 1480.0);
            if r.chipsUsed > NMTheme.ChipBudget() || r.clustersUsed > NMTheme.ClusterBudget() {
                ok = false;
                detail += "mpp " + this.F(m) + ": chips " + ToString(r.chipsUsed) + " clusters " + ToString(r.clustersUsed) + "; ";
            }
            if ArraySize(r.candX) != r.chipsUsed + r.clustersUsed {
                ok = false;
                detail += "candidates mismatch at mpp " + this.F(m) + "; ";
            }
        }
        this.Check("renderer.budgets", ok, detail);
        // Whole city in view at 16 m/unit: every item is drawn exactly once, as a chip or inside a cluster.
        cam.SetCenter((bounds.minX + bounds.maxX) * 0.5, (bounds.minY + bounds.maxY) * 0.5);
        cam.SetMpp(16.0);
        r.Update(cam, 1880.0, 1480.0);
        let total = r.chipsUsed;
        let k = 0;
        while k < r.clustersUsed {
            total += r.clTotal[k];
            k += 1;
        }
        this.Check("renderer.conservation_overview", total == 3000, ToString(total) + " of 3000 (chips " + ToString(r.chipsUsed) + ")");
        this.Check("renderer.idle_skips_relayout", !r.Update(cam, 1880.0, 1480.0), "");
        let L = api.GetLayer(NMDebugLayer.Id());
        L.SetVisible(false);
        r.Update(cam, 1880.0, 1480.0);
        this.Check("renderer.hidden_layer_draws_nothing", r.chipsUsed == 0 && r.clustersUsed == 0, ToString(r.chipsUsed) + "/" + ToString(r.clustersUsed));
    }

    private func VersionCases() {
        this.Check("version.normalise.plain", Equals(NightMapSystem.Normalise("2.31"), "2.31"), "");
        this.Check("version.normalise.v_prefix", Equals(NightMapSystem.Normalise("v2.31"), "2.31"), "");
        this.Check("version.normalise.dotted_patch", Equals(NightMapSystem.Normalise("2.3.1"), "2.31"), "");
        this.Check("version.normalise.suffix", Equals(NightMapSystem.Normalise("2.31 (build 12345)"), "2.31"), "");
        this.Check("version.normalise.leading_space", Equals(NightMapSystem.Normalise(" 2.31"), "2.31"), "");
        this.Check("version.normalise.garbage_unknown", Equals(NightMapSystem.Normalise("unknown"), ""), "");
    }

    private func TooltipCases() {
        let p = NMTooltip.Place(1000.0, 500.0, 620.0, 200.0, 3000.0, 1500.0, 1.0);
        this.Check("tooltip.place_right", this.Near(p.X, 1060.0, 0.01) && this.Near(p.Y, 400.0, 0.01), this.F(p.X) + "," + this.F(p.Y));
        let f = NMTooltip.Place(2800.0, 500.0, 620.0, 200.0, 3000.0, 1500.0, 1.0);
        this.Check("tooltip.flip_left_near_edge", this.Near(f.X, 2800.0 - 60.0 - 620.0, 0.01), this.F(f.X));
        let top = NMTooltip.Place(1000.0, 20.0, 620.0, 200.0, 3000.0, 1500.0, 1.0);
        let bot = NMTooltip.Place(1000.0, 1490.0, 620.0, 200.0, 3000.0, 1500.0, 1.0);
        this.Check("tooltip.clamp_vertical", this.Near(top.Y, 0.0, 0.01) && this.Near(bot.Y, 1300.0, 0.01), this.F(top.Y) + "/" + this.F(bot.Y));
        let canvas = new inkCanvas();   // detached: widgets exist but are never drawn
        let dk = NMTooltip.CreateDocked(canvas, 40.0, 60.0, 900.0, 1.0);
        dk.Reposition(1500.0, 700.0);
        let dockedAt = dk.Origin();   // bind to a local: a field of a call temporary reads garbage in-game
        this.Check("tooltip.docked_stays", this.Near(dockedAt.X, 40.0, 0.01) && this.Near(dockedAt.Y, 60.0, 0.01) && this.Near(dk.CurrentWidth(), 900.0, 0.01),
            this.F(dockedAt.X) + "," + this.F(dockedAt.Y));
        let t = NMTooltip.Create(canvas, 3000.0, 1500.0, 1.0);
        this.Check("tooltip.hidden_when_nothing_selected", !t.IsShown(), "");
        let d = NightMapDetails.Create("cat", "A very long title that must be truncated with an ellipsis");
        let i = 0;
        while i < 6 {
            d.AddRow("Key" + ToString(i), "value");
            i += 1;
        }
        d.AddAction("NUM 0", "Track quest");
        d.AddAction("NUM 1", "Other");
        t.ShowDetails(d, NMTheme.Cyan());
        this.Check("tooltip.max_three_rows", t.IsShown() && t.RowsShown() == 3, ToString(t.RowsShown()));
        t.Hide();
        this.Check("tooltip.hides_again", !t.IsShown(), "");
        this.Check("tooltip.truncate", Equals(NMTooltip.Truncate("abcdef", 4), "abc…") && Equals(NMTooltip.Truncate("abc", 4), "abc"), "");
    }

    private func PickCases() {
        let xs: array<Float> = [100.0, 130.0, 300.0];
        let ys: array<Float> = [100.0, 100.0, 100.0];
        let kinds: array<Int32> = [0, 0, 1];
        let layers: array<Int32> = [0, 0, -1];
        let items: array<Int32> = [5, 6, -1];
        let noReach: array<Float>;
        this.Check("pick.nearest", NMCrosshair.Pick(xs, ys, noReach, kinds, layers, items, 114.0, 100.0, 50.0, -1, -1, -1) == 0, "");
        this.Check("pick.sticky_within_4px", NMCrosshair.Pick(xs, ys, noReach, kinds, layers, items, 116.0, 100.0, 50.0, 0, 0, 5) == 0, "");
        this.Check("pick.switches_beyond_4px", NMCrosshair.Pick(xs, ys, noReach, kinds, layers, items, 124.0, 100.0, 50.0, 0, 0, 5) == 1, "");
        this.Check("pick.removed_selection_falls_back", NMCrosshair.Pick(xs, ys, noReach, kinds, layers, items, 116.0, 100.0, 50.0, 0, 0, 7) == 1, "");
        this.Check("pick.none_in_radius", NMCrosshair.Pick(xs, ys, noReach, kinds, layers, items, 1000.0, 1000.0, 50.0, -1, -1, -1) == -1, "");
        // A photo pin's reach: its centre is far from the tip, and the candidate is still picked from there.
        let reach: array<Float>;
        for x in xs { ArrayPush(reach, 200.0); }
        this.Check("pick.reach_widens", NMCrosshair.Pick(xs, ys, noReach, kinds, layers, items, 1000.0, 1000.0, 50.0, -1, -1, -1) == -1
            && NMCrosshair.Pick(xs, ys, reach, kinds, layers, items, xs[0], ys[0] + 240.0, 50.0, -1, -1, -1) == 0, "");
        this.Check("pick.cluster", NMCrosshair.Pick(xs, ys, noReach, kinds, layers, items, 290.0, 100.0, 50.0, 1, -1, -1) == 2, "");
        // clusters are identified by key (item slot), not position: stays selected after a pan of 3 units, drops on a different key
        let cItems: array<Int32> = [5, 6, 200010003];
        this.Check("pick.cluster_sticky_by_key", NMCrosshair.Pick(xs, ys, noReach, kinds, layers, cItems, 292.0, 100.0, 50.0, 1, -1, 200010003) == 2, "");
        this.Check("pick.cluster_other_key_no_stick", NMCrosshair.Pick(xs, ys, noReach, kinds, layers, cItems, 292.0, 100.0, 50.0, 1, -1, 200010004) == 2, "");
        let empty: array<Float>;
        let emptyI: array<Int32>;
        this.Check("pick.empty_candidates", NMCrosshair.Pick(empty, empty, empty, emptyI, emptyI, emptyI, 0.0, 0.0, 50.0, 0, 0, 5) == -1, "");
    }
}
