module OverlayMap

// In-game assertions. Run with Ctrl + toggle key (Debug setting on). Output: [OverlayMap] TEST|PASS|... lines
// and a final TEST|SUMMARY|passed=N|failed=M line in CET's gamelog.log.
public class NMSelfTest {
    private let passed: Int32;
    private let failed: Int32;
    private let failedNames: String;

    public func Run() {
        this.passed = 0;
        this.failed = 0;
        this.failedNames = "";
        NMLog.Info("TEST|START");
        this.MathCases();
        this.CameraCases();
        this.GridCases();
        this.ApiCases();
        this.InputCases();
        this.PadCases();
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
        NMTeleportTests.Run(this);
        NMPhotoTests.Run(this);
        NMCollectTests.Run(this);
        NMTierTests.Run(this);
        NMDeclutterTests.Run(this);
        NMPerfTests.Run(this);
        NMCornerTests.Run(this);
        NMPaletteTests.Run(this);
        NMParityTests.Run(this);
        NMWaypointTests.Run(this);
        NMAreaTests.Run(this);
        NMLog.Info("TEST|SUMMARY|passed=" + ToString(this.passed) + "|failed=" + ToString(this.failed));
    }

    public func Check(name: String, ok: Bool, detail: String) {
        if ok {
            this.passed += 1;
            NMLog.Info("TEST|PASS|" + name);
        } else {
            this.failed += 1;
            this.failedNames += (StrLen(this.failedNames) > 0 ? "," : "") + name;
            NMLog.Info("TEST|FAIL|" + name + "|" + detail);
        }
    }

    public func Summary() -> String {
        return "passed=" + ToString(this.passed) + "|failed=" + ToString(this.failed) + "|fails=" + this.failedNames;
    }

    public static func ChildIndex(parent: ref<inkCompoundWidget>, name: CName) -> Int32 {
        let n = parent.GetNumChildren();
        let i = 0;
        while i < n {
            if Equals(parent.GetWidgetByIndex(i).GetName(), name) {
                return i;
            }
            i += 1;
        }
        return -1;
    }

    // A widget's top-left in panel space: its translations summed up to the panel root.
    public static func PanelPos(w: wref<inkWidget>) -> Vector2 {
        let x = 0.0;
        let y = 0.0;
        let cur = w;
        while IsDefined(cur) && NotEquals(cur.GetName(), n"OverlayMapPanel") {
            let t = cur.GetTranslation();
            x += t.X;
            y += t.Y;
            cur = cur.GetParentWidget();
        }
        return new Vector2(x, y);
    }

    public static func HasAncestor(w: wref<inkWidget>, name: CName) -> Bool {
        let cur: wref<inkWidget> = w.GetParentWidget();
        while IsDefined(cur) {
            if Equals(cur.GetName(), name) { return true; }
            cur = cur.GetParentWidget();
        }
        return false;
    }

    // Visible text widgets with text under w (w included), skipping hidden subtrees and the subtree named skip.
    public static func VisibleTexts(w: wref<inkWidget>, skip: CName) -> Int32 {
        if !IsDefined(w) || !w.IsVisible() || Equals(w.GetName(), skip) { return 0; }
        let t = w as inkText;
        if IsDefined(t) { return StrLen(t.GetText()) > 0 ? 1 : 0; }
        let c = w as inkCompoundWidget;
        if !IsDefined(c) { return 0; }
        let n = 0;
        let i = 0;
        while i < c.GetNumChildren() {
            n += NMSelfTest.VisibleTexts(c.GetWidgetByIndex(i), skip);
            i += 1;
        }
        return n;
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
        let cam = NMCamera.Create(1880.0, 1480.0, b, OverlayMapSystem.MinMpp(), OverlayMapSystem.MaxMpp());
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
        this.Check("camera.closer_than_tiles", OverlayMapSystem.MinMpp() == 0.1 && OverlayMapSystem.OpenMpp() == NMTileManifest.LevelMpp(0),
            this.F(OverlayMapSystem.MinMpp()) + " open " + this.F(OverlayMapSystem.OpenMpp()));
        this.Check("photo.thumb_zoom", NMItemRenderer.ThumbZoom(16.0) == 1.0 && NMItemRenderer.ThumbZoom(0.5) == 1.0
            && this.Near(NMItemRenderer.ThumbZoom(0.25), 2.0, 0.001) && this.Near(NMItemRenderer.ThumbZoom(0.1), 5.0, 0.001),
            this.F(NMItemRenderer.ThumbZoom(0.25)) + " " + this.F(NMItemRenderer.ThumbZoom(0.1)));
        this.Check("camera.limits_follow_manifest", OverlayMapSystem.MaxMpp() == NMTileManifest.LevelMpp(NMTileManifest.LevelCount() - 1),
            this.F(OverlayMapSystem.MinMpp()) + "/" + this.F(OverlayMapSystem.MaxMpp()));
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
    private func GridConsistent(L: ref<OverlayMapLayer>) -> String {
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
        let api = OverlayMap.Create();
        let L = api.CreateLayer(n"test.grid", "Grid test", 10);
        L.SetCategory(n"test.a", "A", NMTheme.Cyan());
        L.SetCategory(n"test.b", "B", NMTheme.Pink());
        let ids: array<Int32>;
        let i = 0;
        while i < 500 {
            let cat = i % 2 == 0 ? n"test.a" : n"test.b";
            ArrayPush(ids, L.Add(OverlayMapItem.Create(new Vector4(this.Coord(i, 7919), this.Coord(i, 104729), 0.0, 1.0), cat, r"base\\x.inkatlas", n"p")));
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
        let reused = L.Add(OverlayMapItem.Create(new Vector4(0.0, 0.0, 0.0, 1.0), n"test.a", r"base\\x.inkatlas", n"p"));
        this.Check("grid.id_recycled", reused >= 100 && reused < 200, ToString(reused));
        this.Check("grid.remove_twice_false", !L.Remove(ids[150]) && !L.Move(ids[150], new Vector4(0.0, 0.0, 0.0, 1.0)), "");
        // edges of the grid extent (world bounds default to the whole grid)
        let lo = L.Add(OverlayMapItem.Create(new Vector4(-12000.0, -12000.0, 0.0, 1.0), n"test.a", r"base\\x.inkatlas", n"p"));
        let hi = L.Add(OverlayMapItem.Create(new Vector4(11999.0, 11999.0, 0.0, 1.0), n"test.a", r"base\\x.inkatlas", n"p"));
        let out = L.Add(OverlayMapItem.Create(new Vector4(12000.0, 0.0, 0.0, 1.0), n"test.a", r"base\\x.inkatlas", n"p"));
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
        let first = L.Add(OverlayMapItem.Create(new Vector4(100.0, 200.0, 0.0, 1.0), n"test.b", r"base\\x.inkatlas", n"p"));
        err = this.GridConsistent(L);
        this.Check("grid.add_after_clear", first == 0 && L.count == 1 && Equals(err, ""), ToString(first) + " " + err);
    }

    private func ApiCases() {
        let api = OverlayMap.Create();
        api.SetWorld(-6000.0, -4600.0, 4600.0, 7400.0);
        let L = api.CreateLayer(n"test.api", "API test", 5);
        this.Check("api.create_layer_idempotent", api.CreateLayer(n"test.api", "again", 1) == L && ArraySize(api.layers) == 1, "");
        let inside = L.Add(OverlayMapItem.Create(new Vector4(5500.0, 0.0, 0.0, 1.0), n"x", r"base\\x.inkatlas", n"p"));
        let outside = L.Add(OverlayMapItem.Create(new Vector4(5700.0, 0.0, 0.0, 1.0), n"x", r"base\\x.inkatlas", n"p"));
        this.Check("api.world_bounds_plus_1km", inside >= 0 && outside == -1, ToString(inside) + "/" + ToString(outside));
        let i = 0;
        while i < 10 {
            L.Add(OverlayMapItem.Create(new Vector4(0.0, 0.0, 0.0, 1.0), StringToName("cat" + ToString(i)), r"base\\x.inkatlas", n"p"));
            i += 1;
        }
        this.Check("api.category_overflow_to_other", ArraySize(L.catNames) == NMGrid.MaxCats() && Equals(L.catNames[NMGrid.MaxCats() - 1], n"other"),
            ToString(ArraySize(L.catNames)));
        let g = api.CategoryIndex(n"x");
        this.Check("api.global_category", g >= 0 && Equals(api.catNames[g], n"x"), ToString(g));
        let rev = api.revision;
        L.SetOpacity(0.5);
        this.Check("api.revision_bumps", api.revision > rev && L.opacity == 0.5, "");
        let d = OverlayMapDetails.Create("GIG", "TITLE").AddRow("a", "1").AddRow("b", "2").AddRow("c", "3").AddRow("d", "4")
            .AddRow("e", "5").AddRow("f", "6").AddRow("g", "7").AddAction("K", "one").AddAction("K", "two").AddAction("K", "three").AddAction("K", "four");
        this.Check("api.details_caps", ArraySize(d.rowKeys) == 6 && ArraySize(d.actionKeys) == 3, "");
        api.RemoveLayer(n"test.api");
        this.Check("api.remove_layer", ArraySize(api.layers) == 0 && !IsDefined(api.GetLayer(n"test.api")), "");
    }

    private func InputCases() {
        let s = new OverlayMapSettings();
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
        let hs = new OverlayMapSettings();
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
        this.TakeKeysCases();
        this.HintCases();
    }

    // Every key the hint copy names, pinned (Mod Settings applies the user's saved bindings to class defaults).
    public static func HintSettings(holdToShow: Bool) -> ref<OverlayMapSettings> {
        let s = new OverlayMapSettings();
        s.keyToggle = EInputKey.IK_Backslash;
        s.keyPanUp = EInputKey.IK_NumPad8;
        s.keyPanDown = EInputKey.IK_NumPad2;
        s.keyPanLeft = EInputKey.IK_NumPad4;
        s.keyPanRight = EInputKey.IK_NumPad6;
        s.keyZoomIn = EInputKey.IK_NumPlus;
        s.keyZoomOut = EInputKey.IK_NumMinus;
        s.keyRecenter = EInputKey.IK_NumPad5;
        s.keyAct = EInputKey.IK_NumPad0;
        s.keyFilter = EInputKey.IK_NumSlash;
        s.keyTeleport = EInputKey.IK_NumPeriod;
        s.keyMapPanUp = EInputKey.IK_W;
        s.keyMapPanDown = EInputKey.IK_S;
        s.keyMapPanLeft = EInputKey.IK_A;
        s.keyMapPanRight = EInputKey.IK_D;
        s.keyMapRecenter = EInputKey.IK_Space;
        s.keyMapAct = EInputKey.IK_F;
        s.keyMapWaypoint = EInputKey.IK_E;
        s.keyMapFilter = EInputKey.IK_R;
        s.keyMapTeleport = EInputKey.IK_T;
        s.teleportEnabled = true;
        s.holdToShow = holdToShow;
        return s;
    }

    // Any-keyboard set: only while the map holds the keyboard (V stopped) do WASD, arrows and the wheel drive it.
    private func TakeKeysCases() {
        let s = NMSelfTest.HintSettings(false);
        let press = EInputAction.IACT_Press;
        let release = EInputAction.IACT_Release;
        let free = new NMInput();
        let usedW = free.Handle(s, EInputKey.IK_W, press, false, false, false, true);
        free.Handle(s, EInputKey.IK_MouseWheelUp, press, false, false, false, true);
        let fv = free.PanVector();
        free.Axis(EInputKey.IK_MouseZ, 1.0, true);
        this.Check("keys.wasd_ignored_while_v_moves", !usedW && fv.X == 0.0 && fv.Y == 0.0 && free.wheel == 0, ToString(free.wheel));
        let k = new NMInput();
        k.takesKeys = true;
        k.Handle(s, EInputKey.IK_W, press, false, false, false, true);
        let up = k.PanVector();
        k.Handle(s, EInputKey.IK_W, release, false, false, false, true);
        k.Handle(s, EInputKey.IK_D, press, false, false, false, true);
        let right = k.PanVector();
        k.ResetHeld();
        this.Check("keys.wasd_pans", up.X == 0.0 && up.Y == -1.0 && right.X == 1.0 && right.Y == 0.0, this.F(up.Y) + "," + this.F(right.X));
        let usedArrow = k.Handle(s, EInputKey.IK_Left, press, false, false, false, true);
        let left = k.PanVector();
        k.ResetHeld();
        this.Check("keys.arrows_pan_when_taken", usedArrow && left.X == -1.0 && !k.arrowSeen, this.F(left.X));
        k.Handle(s, EInputKey.IK_MouseWheelUp, press, false, false, false, true);
        k.Handle(s, EInputKey.IK_MouseWheelUp, press, false, false, false, true);
        k.Handle(s, EInputKey.IK_MouseWheelDown, press, false, false, false, true);
        k.Handle(s, EInputKey.IK_MouseWheelUp, release, false, false, false, true);
        this.Check("keys.wheel_counts_notches", k.wheel == 1, ToString(k.wheel));
        k.wheel = 0;
        let usedZ = k.Axis(EInputKey.IK_MouseZ, -1.0, true);
        k.Axis(EInputKey.IK_MouseZ, -1.0, true);
        k.Axis(EInputKey.IK_MouseZ, 1.0, true);
        let otherAxis = k.Axis(EInputKey.IK_MouseX, 5.0, true);
        let closedZ = k.Axis(EInputKey.IK_MouseZ, 1.0, false);
        this.Check("keys.wheel_axis", usedZ && !otherAxis && !closedZ && k.wheel == -1, ToString(k.wheel));
        k.wheel = 0;
        k.Handle(s, EInputKey.IK_Space, press, false, false, false, true);
        k.Handle(s, EInputKey.IK_F, press, false, false, false, true);
        k.Handle(s, EInputKey.IK_R, press, false, false, false, true);
        k.Handle(s, EInputKey.IK_T, press, false, false, false, true);
        let usedE = k.Handle(s, EInputKey.IK_E, press, false, false, false, true);
        this.Check("keys.actions", k.recenter && k.act && k.filter && k.teleport && usedE && k.waypoint, "");
        let freeE = new NMInput();
        this.Check("keys.e_ignored_while_v_moves", !freeE.Handle(s, EInputKey.IK_E, press, false, false, false, true), "");
        k.ResetHeld();
        k.Handle(s, EInputKey.IK_NumPad8, press, false, false, false, true);
        let np = k.PanVector();
        k.ResetHeld();
        this.Check("keys.numpad_still_works", np.Y == -1.0 && k.wheel == 0, this.F(np.Y));
        let closed = new NMInput();
        closed.takesKeys = true;
        this.Check("keys.ignored_when_closed", !closed.Handle(s, EInputKey.IK_W, press, false, false, false, false), "");
        let h = NMHints.Join(NMInput.TakeHints(s, "ALL", "TELEPORT"));
        let want = "W/A/S/D PAN   ·   WHEEL ZOOM   ·   SPACE FOLLOW   ·   F ACT   ·   T TELEPORT   ·   R FILTER: ALL   ·   \\ CLOSE";
        this.Check("keys.hints", Equals(h, want), h);
        // Wheel notches ease the zoom; notches during an ease stack on its target.
        let cam = NMCamera.Create(1880.0, 1480.0, NMRect.Create(-6000.0, -4600.0, 4600.0, 7400.0), 0.5, 16.0);
        cam.SetMpp(4.0);
        cam.ZoomSteps(1, 150.0);
        cam.ZoomSteps(1, 150.0);
        cam.Tick(200.0);
        let twoIn = cam.mpp;
        cam.ZoomSteps(-40, 150.0);
        cam.Tick(200.0);
        this.Check("keys.wheel_zoom_steps", this.Near(twoIn, 4.0 / (NMCamera.WheelStep() * NMCamera.WheelStep()), 0.001) && cam.mpp == 16.0,
            this.F(twoIn) + " " + this.F(cam.mpp));
    }

    private static func LastLabel(h: array<NMHint>) -> String {
        return ArraySize(h) > 0 ? h[ArraySize(h) - 1].label : "";
    }

    // Keycap hint bar (Task 10): the entries reproduce the old single-line copy exactly, CLOSE stays last.
    private func HintCases() {
        let s = NMSelfTest.HintSettings(false);
        let hs = NMSelfTest.HintSettings(true);
        // The old NMInput.HintText / NMPad.HintText strings, captured before the bar replaced them.
        let kb = "NUM 8/NUM 4/NUM 6/NUM 2 PAN   ·   NUM + NUM - ZOOM   ·   NUM 5 FOLLOW   ·   NUM 0 ACT   ·   NUM . TELEPORT   ·   NUM / FILTER: ALL   ·   \\ CLOSE";
        let kbHold = "NUM 8/NUM 4/NUM 6/NUM 2 PAN   ·   NUM + NUM - ZOOM   ·   NUM 5 FOLLOW   ·   NUM 0 ACT   ·   NUM . FAST TRAVEL   ·   NUM / FILTER: SERVICES   ·   RELEASE \\ CLOSE";
        let pad = "LS PAN   ·   LT/RT ZOOM   ·   R3 FOLLOW   ·   A ACT   ·   X TELEPORT   ·   Y FILTER: ALL   ·   B CLOSE";
        let padHold = "LS PAN   ·   LT/RT ZOOM   ·   R3 FOLLOW   ·   A ACT   ·   X FAST TRAVEL   ·   Y FILTER: JOBS   ·   RELEASE VIEW CLOSE";
        let padNoTp = "LS PAN   ·   LT/RT ZOOM   ·   R3 FOLLOW   ·   A ACT   ·   Y FILTER: ALL   ·   B CLOSE";
        let j0 = NMHints.Join(NMInput.Hints(s, "ALL", "TELEPORT"));
        let j1 = NMHints.Join(NMInput.Hints(hs, "SERVICES", "FAST TRAVEL"));
        this.Check("hint.join_matches_legacy", Equals(j0, kb) && Equals(NMInput.HintText(s, "ALL", "TELEPORT"), kb)
            && Equals(j1, kbHold) && Equals(NMInput.HintText(hs, "SERVICES", "FAST TRAVEL"), kbHold), j0 + " | " + j1);
        let p0 = NMHints.Join(NMPad.Hints("ALL", "TELEPORT", true, false));
        let p1 = NMHints.Join(NMPad.Hints("JOBS", "FAST TRAVEL", true, true));
        let p2 = NMHints.Join(NMPad.Hints("ALL", "TELEPORT", false, false));
        this.Check("hint.join_matches_legacy_pad", Equals(p0, pad) && Equals(NMPad.HintText("ALL", "TELEPORT", true, false), pad)
            && Equals(p1, padHold) && Equals(NMPad.HintText("JOBS", "FAST TRAVEL", true, true), padHold) && Equals(p2, padNoTp),
            p0 + " | " + p1 + " | " + p2);
        // CLOSE is the last entry in every variant: keyboard, Hold to show, pad, pass-through and the NumLock notice.
        let kbH = NMInput.Hints(s, "ALL", "TELEPORT");
        let pass = NMPad.PassThroughHints(NMInput.Hints(hs, "ALL", "TELEPORT"));
        let numlock = NMInput.NumLockHints(kbH);
        let lasts = NMSelfTest.LastLabel(kbH) + "|" + NMSelfTest.LastLabel(NMInput.Hints(hs, "ALL", "TELEPORT")) + "|"
            + NMSelfTest.LastLabel(NMPad.Hints("ALL", "TELEPORT", true, true)) + "|" + NMSelfTest.LastLabel(pass) + "|" + NMSelfTest.LastLabel(numlock);
        this.Check("hint.close_last", Equals(lasts, "CLOSE|CLOSE|CLOSE|CLOSE|CLOSE")
            && ArraySize(pass) > 0 && Equals(pass[ArraySize(pass) - 1].key, "VIEW") && Equals(pass[ArraySize(pass) - 1].pre, "HOLD"), lasts);
        let n = ArraySize(numlock);
        this.Check("hint.numlock_plain", n == ArraySize(kbH) + 1 && n >= 2 && Equals(numlock[n - 2].key, "")
            && StrContains(numlock[n - 2].label, "NUMLOCK"), ToString(n));
        // Short key names only when every map key is on the numpad; a custom non-numpad bind shows every key in full.
        let short = NMHints.Short(kbH);
        let w = NMSelfTest.HintSettings(false);
        w.keyPanUp = EInputKey.IK_W;
        let full = NMHints.Short(NMInput.Hints(w, "ALL", "TELEPORT"));
        let shortOk = ArraySize(short) >= 3 && Equals(short[0].key, "8 4 6 2") && Equals(short[1].key, "+ -") && Equals(short[2].key, "5");
        let fullOk = ArraySize(full) >= 3 && Equals(full[0].key, "W/NUM 4/NUM 6/NUM 2") && Equals(full[2].key, "NUM 5");
        let padShort = NMHints.Short(NMPad.Hints("ALL", "TELEPORT", true, false));
        let padOk = ArraySize(padShort) > 1 ? Equals(padShort[1].key, "LT/RT") : false;
        this.Check("hint.short_numpad", shortOk && fullOk && padOk,
            (ArraySize(short) > 0 ? short[0].key : "-") + " / " + (ArraySize(full) > 0 ? full[0].key : "-"));
    }

    private func PadCases() {
        let A = EInputKey.IK_Pad_A_CROSS;
        let B = EInputKey.IK_Pad_B_CIRCLE;
        let X = EInputKey.IK_Pad_X_SQUARE;
        let Y = EInputKey.IK_Pad_Y_TRIANGLE;
        let VIEW = EInputKey.IK_Pad_Back_Select;
        let press = EInputAction.IACT_Press;
        let release = EInputAction.IACT_Release;
        this.Check("pad.is_pad", NMPad.IsPad(A) && NMPad.IsPad(EInputKey.IK_Pad_RightAxisY) && NMPad.IsPad(VIEW)
            && !NMPad.IsPad(EInputKey.IK_NumPad8) && !NMPad.IsPad(EInputKey.IK_Escape), "");
        // Open: a tap does nothing; a hold opens once, at 500 ms.
        let p = new NMPad();
        p.Button(VIEW, press, 1000.0, false, false, false, false, true);
        p.Button(VIEW, release, 1200.0, false, false, false, false, true);
        this.Check("pad.view_tap_no_open", !p.PollHold(1600.0, false, false, false) && !p.Waiting() && p.tap, "");
        p.tap = false;
        p.Button(VIEW, press, 2000.0, false, false, false, false, true);
        let early = p.PollHold(2499.0, false, false, false);
        let at = p.PollHold(2500.0, false, false, false);
        let again = p.PollHold(2600.0, false, false, false);
        this.Check("pad.view_hold_opens", !early && at && !again && p.Waiting() && !p.HoldPending(), ToString(early) + ToString(at) + ToString(again));
        p.Button(VIEW, release, 2700.0, true, true, true, false, true);
        this.Check("pad.view_release_after_open_keeps_open", !p.close && !p.Waiting() && !p.tap, "");
        // While the map owns the pad: buttons map to actions, and View or B close.
        p.Button(A, press, 3000.0, true, true, true, false, true);
        p.Button(X, press, 3000.0, true, true, true, false, true);
        p.Button(Y, press, 3000.0, true, true, true, false, true);
        p.Button(EInputKey.IK_Pad_RightThumb, press, 3000.0, true, true, true, false, true);
        this.Check("pad.buttons", p.act && p.teleport && p.filter && p.recenter && !p.close && p.lastWasPad, "");
        p.Reset();
        p.Button(A, release, 3000.0, true, true, true, false, true);
        this.Check("pad.release_is_not_a_press", !p.act, "");
        p.Button(B, press, 3000.0, true, true, true, false, true);
        this.Check("pad.b_closes", p.close, "");
        p.Reset();
        p.Button(VIEW, press, 3100.0, true, true, true, false, true);
        this.Check("pad.view_closes_when_open", p.close, "");
        // Map opened with the keyboard: the pad does nothing on it.
        let k = new NMPad();
        let used = k.Button(A, press, 0.0, true, false, false, false, true);
        k.Button(B, press, 0.0, true, false, false, false, true);
        k.Button(VIEW, press, 0.0, true, false, false, false, true);
        k.Axis(EInputKey.IK_Pad_LeftAxisX, 1.0);
        this.Check("pad.keyboard_open_ignores_pad", !used && !k.act && !k.close && !k.PollHold(9999.0, true, false, false) && !k.lastWasPad, "");
        // Off: nothing at all.
        let off = new NMPad();
        off.Button(VIEW, press, 0.0, false, false, false, false, false);
        this.Check("pad.disabled_ignores_all", !off.PollHold(9999.0, false, false, false) && !off.Waiting(), "");
        // Hold to show: open after the hold, close on release.
        let h = new NMPad();
        h.Button(VIEW, press, 0.0, false, false, false, true, true);
        let hOpen = h.PollHold(500.0, false, false, false);
        h.Button(VIEW, release, 900.0, true, true, true, true, true);
        this.Check("pad.hold_to_show_release_closes", hOpen && h.close, "");
        // Car pass-through: opened from the pad but not owning it; holding View again closes.
        let c = new NMPad();
        c.Button(A, press, 0.0, true, true, false, false, true);
        c.Button(VIEW, press, 100.0, true, true, false, false, true);
        let cEarly = c.PollHold(400.0, true, true, false);
        let cClose = c.PollHold(600.0, true, true, false);
        this.Check("pad.car_pass_through", !c.act && !c.close && !cEarly && cClose, ToString(cEarly) + ToString(cClose));
        // Sticks: deadzone, full tilt, diagonals stay within the unit circle; screen Y is down.
        let s = new NMPad();
        s.Axis(EInputKey.IK_Pad_LeftAxisX, 0.15);
        s.Axis(EInputKey.IK_Pad_LeftAxisY, 0.1);
        let dz = s.PanVector();
        this.Check("pad.deadzone", dz.X == 0.0 && dz.Y == 0.0, this.F(dz.X));
        s.Axis(EInputKey.IK_Pad_LeftAxisX, 1.0);
        s.Axis(EInputKey.IK_Pad_LeftAxisY, 0.0);
        let full = s.PanVector();
        this.Check("pad.full_tilt", this.Near(full.X, 1.0, 0.001) && full.Y == 0.0, this.F(full.X));
        s.Axis(EInputKey.IK_Pad_LeftAxisX, 0.0);
        s.Axis(EInputKey.IK_Pad_LeftAxisY, 1.0);
        let up = s.PanVector();
        this.Check("pad.stick_up_pans_north", this.Near(up.Y, -1.0, 0.001), this.F(up.Y));
        s.Axis(EInputKey.IK_Pad_LeftAxisX, 0.9);
        s.Axis(EInputKey.IK_Pad_LeftAxisY, 0.9);
        let dg = s.PanVector();
        this.Check("pad.diag_unit", SqrtF(dg.X * dg.X + dg.Y * dg.Y) <= 1.0001 && dg.X > 0.6, this.F(dg.X) + "," + this.F(dg.Y));
        s.Axis(EInputKey.IK_Pad_LeftAxisX, 0.6);
        s.Axis(EInputKey.IK_Pad_LeftAxisY, 0.0);
        let half = s.PanVector();
        this.Check("pad.small_tilt_is_slow", half.X > 0.0 && half.X < 0.4, this.F(half.X));
        // Triggers: RT in, LT out, both cancel; a press without analog values counts as full.
        let t = new NMPad();
        t.Axis(EInputKey.IK_Pad_RightTrigger, 1.0);
        let zin = t.ZoomRate();
        t.Axis(EInputKey.IK_Pad_LeftTrigger, 1.0);
        let zboth = t.ZoomRate();
        t.Axis(EInputKey.IK_Pad_RightTrigger, 0.05);
        let zout = t.ZoomRate();
        let tb = new NMPad();
        tb.Button(EInputKey.IK_Pad_RightTrigger, press, 0.0, true, true, true, false, true);
        let zbtn = tb.ZoomRate();
        tb.Button(EInputKey.IK_Pad_RightTrigger, release, 0.0, true, true, true, false, true);
        this.Check("pad.zoom_rate", this.Near(zin, 1.0, 0.001) && zboth == 0.0 && this.Near(zout, -1.0, 0.001) && this.Near(zbtn, 1.0, 0.001) && tb.ZoomRate() == 0.0,
            this.F(zin) + "," + this.F(zboth) + "," + this.F(zout) + "," + this.F(zbtn));
        t.Reset();
        let r0 = t.PanVector();
        this.Check("pad.reset_clears_axes", t.ZoomRate() == 0.0 && r0.X == 0.0 && r0.Y == 0.0, "");
        // Held buttons: counted by press and release, axes excluded, repeated presses counted once.
        let hc = new NMPad();
        hc.Button(B, press, 0.0, true, true, true, false, true);
        hc.Button(B, press, 0.0, true, true, true, false, true);
        hc.Button(VIEW, press, 0.0, true, true, true, true, true);
        hc.Button(EInputKey.IK_Pad_LeftAxisX, press, 0.0, true, true, true, false, true);
        let two = hc.HeldCount();
        hc.Button(B, release, 0.0, false, false, false, false, true);
        let one = hc.HeldCount();
        hc.Button(VIEW, release, 0.0, false, false, false, true, true);
        this.Check("pad.is_held", !hc.IsHeld(B) && !hc.IsHeld(VIEW), "");
        this.Check("pad.held_count", two == 2 && one == 1 && hc.HeldCount() == 0, IntToString(two) + "," + IntToString(one));
        // After opening: a stick or trigger still held from gameplay doesn't move the map until let go once.
        let g = new NMPad();
        g.Axis(EInputKey.IK_Pad_LeftAxisY, 1.0);
        g.Axis(EInputKey.IK_Pad_RightTrigger, 1.0);
        g.ClearAxes();
        g.Axis(EInputKey.IK_Pad_LeftAxisY, 1.0);
        g.Axis(EInputKey.IK_Pad_RightTrigger, 1.0);
        let gHeld = g.PanVector();
        let zHeld = g.ZoomRate();
        g.Axis(EInputKey.IK_Pad_LeftAxisY, 0.0);
        g.Axis(EInputKey.IK_Pad_RightTrigger, 0.0);
        g.Axis(EInputKey.IK_Pad_LeftAxisY, 1.0);
        g.Axis(EInputKey.IK_Pad_RightTrigger, 1.0);
        let gAfter = g.PanVector();
        let rest = new NMPad();
        rest.ClearAxes();
        rest.Axis(EInputKey.IK_Pad_RightTrigger, 1.0);
        rest.Axis(EInputKey.IK_Pad_LeftAxisX, 1.0);
        let restPan = rest.PanVector();
        this.Check("pad.no_gate_when_at_rest", this.Near(rest.ZoomRate(), 1.0, 0.001) && this.Near(restPan.X, 1.0, 0.001), this.F(rest.ZoomRate()));
        this.Check("pad.gate_after_open", gHeld.Y == 0.0 && zHeld == 0.0 && this.Near(gAfter.Y, -1.0, 0.001) && this.Near(g.ZoomRate(), 1.0, 0.001),
            this.F(gHeld.Y) + "," + this.F(zHeld) + "," + this.F(gAfter.Y));
        // Hint copy.
        this.Check("pad.hint_text", Equals(NMPad.HintText("ALL", "TELEPORT", true, false),
            "LS PAN   ·   LT/RT ZOOM   ·   R3 FOLLOW   ·   A ACT   ·   X TELEPORT   ·   Y FILTER: ALL   ·   B CLOSE"), NMPad.HintText("ALL", "TELEPORT", true, false));
        this.Check("pad.hint_variants", StrContains(NMPad.HintText("JOBS", "FAST TRAVEL", true, true), "RELEASE VIEW CLOSE")
            && !StrContains(NMPad.HintText("ALL", "TELEPORT", false, false), "X "), "");
        this.HintBarCases();
    }

    // The keycap bar at 1920x1080 with the longest set: a pad-opened pass-through map with Hold to show, teleport, the
    // SERVICES filter and the NumLock notice. Nothing is dropped, nothing overflows, CLOSE sits flush right.
    private func HintBarCases() {
        let l = NMPanelLayout.Compute(1920.0, 1080.0);
        let longest = NMInput.NumLockHints(NMPad.PassThroughHints(NMInput.Hints(NMSelfTest.HintSettings(true), "SERVICES", "FAST TRAVEL")));
        let bar = NMHintBar.Create(new inkCanvas(), 0.0, l.mapH, l.w, l.hintH, l.scale, 0);
        bar.Set(longest);
        let right = l.w - NMHintBar.Margin() * l.scale;
        this.Check("hint.bar_fits_1080p", ArraySize(longest) == 9 && bar.Shown() == ArraySize(longest) && bar.LaidOutWidth() > 0.0
            && bar.LaidOutWidth() <= l.w && this.Near(bar.LastRight(), right, 0.5),
            ToString(ArraySize(longest)) + "/" + ToString(bar.Shown()) + " " + this.F(bar.LaidOutWidth()) + "/" + this.F(l.w) + " last " + this.F(bar.LastRight()));
        bar.Set(NMInput.NumLockHints(NMPad.PassThroughHints(NMInput.Hints(NMSelfTest.HintSettings(true), "SERVICES", "FAST TRAVEL"))));
        let same = bar.Rebuilds();
        bar.Set(NMPad.Hints("ALL", "TELEPORT", true, false));
        this.Check("hint.bar_rebuilds_on_change", same == 1 && bar.Rebuilds() == 2, ToString(same) + "/" + ToString(bar.Rebuilds()));
        // Too narrow (custom long binds would do the same): entries go from the left, CLOSE never does.
        let narrow = NMHintBar.Create(new inkCanvas(), 0.0, 0.0, 1200.0 * l.scale, l.hintH, l.scale, 0);
        narrow.Set(longest);
        let kept = narrow.Kept();
        let k = ArraySize(kept);
        this.Check("hint.bar_drops_from_left", k >= 1 && k < ArraySize(longest) && narrow.Shown() == k && narrow.LaidOutWidth() <= 1200.0 * l.scale
            && Equals(kept[k - 1].pre, "HOLD") && Equals(kept[k - 1].label, "CLOSE") && !Equals(kept[0].label, "PAN"),
            ToString(k) + " " + this.F(narrow.LaidOutWidth()));
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
        // Frame (spec 6): district title top-left, scale bar inside the view (its longest bar, right tick included).
        let fsizes: array<Vector2> = [new Vector2(3840.0, 2160.0), new Vector2(1920.0, 1080.0)];
        let titleOk = true;
        let barOk = true;
        let zOk = true;
        let clipOk = true;
        let trackOk = true;
        let fdetail = "";
        for sz in fsizes {
            let fl = NMPanelLayout.Compute(sz.X, sz.Y);
            let panel = NMPanel.Build(new inkCanvas(), fl, NMTheme.DefaultPanelOpacity(), 0, false);
            let tp = panel.districtTitle.GetTranslation();
            let onRoot = Equals(panel.districtTitle.GetParentWidget().GetName(), n"OverlayMapPanel");   // translation in panel space
            if !onRoot || tp.X > fl.viewW * 0.1 || tp.Y > fl.mapH * 0.1 {
                titleOk = false;
                fdetail += "title root=" + ToString(onRoot) + " " + this.F(tp.X) + "," + this.F(tp.Y) + " ";
            }
            panel.SetScaleBar(NMPanel.ScaleBarMax(fl.scale));   // the longest bar UpdateScale can draw
            let right = panel.scaleTickR.GetTranslation().X + panel.scaleTickR.GetWidth();
            if right > fl.viewW {
                barOk = false;
                fdetail += "bar " + this.F(right) + "/" + this.F(fl.viewW) + " ";
            }
            // Z-order: the header and scale bar come after the map viewport under the panel root (so above every
            // marker, route and photo pin), and the scrim comes after the routes and items inside the viewport.
            let view = NMSelfTest.ChildIndex(panel.root, n"MapView");
            let names: array<CName> = [n"DistrictTitle", n"DistrictSub", n"ScaleBar", n"ScaleLabel"];
            for nm in names {
                let i = NMSelfTest.ChildIndex(panel.root, nm);
                if view < 0 || i <= view {
                    zOk = false;
                    fdetail += "z " + NameToString(nm) + "=" + ToString(i) + " view=" + ToString(view) + " ";
                }
            }
            let scrim = NMSelfTest.ChildIndex(panel.mapContent, n"HeaderScrim");
            let items = NMSelfTest.ChildIndex(panel.mapContent, n"Items");
            if items < 0 || scrim <= items {
                zOk = false;
                fdetail += "scrim=" + ToString(scrim) + " items=" + ToString(items) + " ";
            }
            // Sidebar (spec 6): the viewport clips at the view's right edge (nothing on the map draws under the
            // sidebar), and the sidebar comes after the viewport under the panel root, outside the clip.
            let side = NMSelfTest.ChildIndex(panel.root, n"Sidebar");
            let clipW = view >= 0 ? panel.root.GetWidgetByIndex(view).GetWidth() : -1.0;
            if view < 0 || side <= view || !this.Near(clipW, fl.viewW, 0.5) {
                clipOk = false;
                fdetail += "clip " + this.F(clipW) + "/" + this.F(fl.viewW) + " side=" + ToString(side) + " ";
            }
            // The tracked quest sits in the sidebar, in its bottom 30 %.
            let qp = NMSelfTest.PanelPos(panel.questTitle);
            if !NMSelfTest.HasAncestor(panel.questTitle, n"Sidebar") || qp.X < fl.viewW || qp.Y <= fl.mapH * 0.7 {
                trackOk = false;
                fdetail += "quest " + this.F(qp.X) + "," + this.F(qp.Y) + " ";
            }
            panel.Destroy();
        }
        this.Check("layout.header_above_markers", zOk, fdetail);
        this.Check("layout.district_top_left", titleOk, fdetail);
        this.Check("layout.scale_bar_in_view", barOk, fdetail);
        this.Check("layout.map_clipped_to_view", clipOk, fdetail);
        this.Check("layout.tracking_bottom", trackOk, fdetail);
        this.Check("settings.panel_opacity_migrates", this.Near(NMTheme.MigratePanelOpacity(0.45), 0.5, 0.0001)
            && this.Near(NMTheme.MigratePanelOpacity(0.6), 0.6, 0.0001) && this.Near(NMTheme.MigratePanelOpacity(0.92), 0.92, 0.0001)
            && this.Near(NMTheme.MigratePanelOpacity(0.449), 0.449, 0.0001) && this.Near(NMTheme.MigratePanelOpacity(0.451), 0.451, 0.0001),
            this.F(NMTheme.MigratePanelOpacity(0.45)) + " " + this.F(NMTheme.MigratePanelOpacity(0.6)) + " " + this.F(NMTheme.MigratePanelOpacity(0.449)) + " " + this.F(NMTheme.MigratePanelOpacity(0.451)));
    }

    private func TileCases() {
        if !NMTileManifest.Available() {
            this.Check("tiles.manifest_available", false, "Generated/TileManifest.reds is the stub; run the tile build");
            return;
        }
        let n = NMTileManifest.LevelCount();
        this.Check("tiles.six_levels", n == 6, ToString(n));
        this.Check("tiles.five_sets_order", NMTileManifest.SetCount() == 5 && Equals(NMTileManifest.SetName(3), "road") && Equals(NMTileManifest.SetName(4), "metro"),
            ToString(NMTileManifest.SetCount()));
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
        this.Check("tiles.ui_atlas_in_depot", GameInstance.GetResourceDepot().ResourceExists(NMTheme.UiAtlas()), "overlaymap\\ui\\ui.inkatlas not found: archive not installed?");
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
        let cam = NMCamera.Create(1880.0, 1480.0, cb, OverlayMapSystem.MinMpp(), OverlayMapSystem.MaxMpp());
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
        this.Check("tiles.theme_defaults", this.Near(roadOp, 0.90, 0.0001) && this.Near(outlineOp, 0.40, 0.0001) && this.Near(roadTint.Red, 0.363, 0.001),
            ToString(roadOp) + "," + ToString(outlineOp) + "," + ToString(roadTint.Red));
    }

    private func RendererCases() {
        let api = OverlayMap.Create();
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
            if r.chipsUsed > NMTheme.ChipBudget() {
                ok = false;
                detail += "mpp " + this.F(m) + ": chips " + ToString(r.chipsUsed) + "; ";
            }
            if ArraySize(r.candX) != r.chipsUsed {
                ok = false;
                detail += "candidates mismatch at mpp " + this.F(m) + "; ";
            }
        }
        this.Check("renderer.budgets", ok, detail);
        // Whole city in view at 16 m/unit: the Minor debug layer is hidden; promoted to Major it fills the budget
        // and no item is drawn twice.
        cam.SetCenter((bounds.minX + bounds.maxX) * 0.5, (bounds.minY + bounds.maxY) * 0.5);
        cam.SetMpp(16.0);
        r.noDeclutter = true;   // the budget fill, not the overlap skipping (NMDeclutterTests)
        r.Update(cam, 1880.0, 1480.0);
        let minorChips = r.chipsUsed;
        let L = api.GetLayer(NMDebugLayer.Id());
        L.SetTier(OverlayMapTier.Major);
        r.Update(cam, 1880.0, 1480.0);
        let seen: array<Bool>;
        ArrayResize(seen, ArraySize(L.alive));
        let dup = 0;
        for item in r.candItem {
            if seen[item] { dup += 1; }
            seen[item] = true;
        }
        this.Check("renderer.overview_tiers", minorChips == 0 && r.chipsUsed == NMTheme.ChipBudget() && dup == 0,
            "minor " + ToString(minorChips) + " major " + ToString(r.chipsUsed) + " dup " + ToString(dup));
        this.Check("renderer.idle_skips_relayout", !r.Update(cam, 1880.0, 1480.0), "");
        L.SetVisible(false);
        r.Update(cam, 1880.0, 1480.0);
        this.Check("renderer.hidden_layer_draws_nothing", r.chipsUsed == 0 && ArraySize(r.candX) == 0, ToString(r.chipsUsed) + "/" + ToString(ArraySize(r.candX)));
        // Placed as OverlayMapSystem places them: nothing lands under the sidebar (past the view plus the cull margin).
        L.SetVisible(true);
        let pl = NMPanelLayout.Compute(3840.0, 2160.0);
        let pc = NMCamera.Create(pl.mapW, pl.mapH, bounds, 0.5, 16.0);
        pc.SetScreenShift(NMPhotoDrawer.FocusShift(pl));
        pc.SetMpp(1.0);   // close enough that the chip budget does not run out before the view's edges
        let pr = NMItemRenderer.Create(api, new inkCanvas(), pl.scale);
        pr.noDeclutter = true;
        pr.UpdateFor(pc, pl);
        let maxX = -100000.0;
        for x in pr.candX { maxX = MaxF(maxX, x); }
        let n = ArraySize(pr.candX);
        // Control: culled to the whole map area instead, some items do land under the sidebar.
        pr.Invalidate();
        pr.Update(pc, pl.mapW, pl.mapH);
        let ctrlX = -100000.0;
        for x in pr.candX { ctrlX = MaxF(ctrlX, x); }
        let edge = pl.viewW + NMItemRenderer.CullMargin(pl.scale);
        this.Check("renderer.culls_to_view", n > 0 && maxX <= edge && ctrlX > edge,
            ToString(n) + " max " + this.F(maxX) + " control " + this.F(ctrlX) + " edge " + this.F(edge));
    }

    private func VersionCases() {
        this.Check("version.normalise.plain", Equals(OverlayMapSystem.Normalise("2.31"), "2.31"), "");
        this.Check("version.normalise.v_prefix", Equals(OverlayMapSystem.Normalise("v2.31"), "2.31"), "");
        this.Check("version.normalise.dotted_patch", Equals(OverlayMapSystem.Normalise("2.3.1"), "2.31"), "");
        this.Check("version.normalise.suffix", Equals(OverlayMapSystem.Normalise("2.31 (build 12345)"), "2.31"), "");
        this.Check("version.normalise.leading_space", Equals(OverlayMapSystem.Normalise(" 2.31"), "2.31"), "");
        this.Check("version.normalise.garbage_unknown", Equals(OverlayMapSystem.Normalise("unknown"), ""), "");
        this.Check("version.normalise.one_digit_minor", Equals(OverlayMapSystem.Normalise("2.5"), "2.5"), OverlayMapSystem.Normalise("2.5"));
        this.Check("version.normalise.differs", NotEquals(OverlayMapSystem.Normalise("2.5"), OverlayMapSystem.Normalise("2.31")), "");
        let w = OverlayMapSystem.VersionWarning("2.5", "2.31");
        this.Check("version.warning_for_players", StrContains(w, "2.5") && StrContains(w, "2.31") && !StrContains(w, "rebuild") && !StrContains(w, "tools"), w);
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
        let d = OverlayMapDetails.Create("cat", "A very long title that must be truncated with an ellipsis");
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

        // Sidebar card (spec 6) at the 4K sidebar width: a long description wraps to at most three lines.
        let cw = 784.0;
        let card = NMTooltip.CreateDocked(canvas, 40.0, 40.0, cw, 1.0);
        card.ShowDetails(OverlayMapDetails.Create("Gig", "Shoot to Thrill").AddRow("Distance", "640 M"), NMTheme.Cyan());
        let h0 = card.Height();
        let bare = !card.DescriptionShown();
        let desc = "Wakako wants a shipment intercepted before it reaches the checkpoint. The convoy leaves Japantown at dusk; "
            + "stop it before the bridge, keep the cargo intact and bring the driver back alive for questioning.";   // ~200
        card.ShowDetails(OverlayMapDetails.Create("Gig", "Shoot to Thrill").WithDescription(desc).AddRow("Distance", "640 M"), NMTheme.Cyan());
        let h1 = card.Height();
        let grow = h1 - h0;
        this.Check("tooltip.shows_description", bare && card.DescriptionShown() && grow > 0.0
            && grow <= 3.0 * NMTooltip.DescLineH() + NMTooltip.DescGap() + 0.01 && StrLen(card.DescriptionText()) < StrLen(desc),
            "len " + ToString(StrLen(desc)) + " grow " + this.F(grow) + " shown " + ToString(card.DescriptionShown()) + " text " + ToString(StrLen(card.DescriptionText())));
        let three = OverlayMapDetails.Create("Gig", "Shoot to Thrill").AddAction("NUM 0", "Track").AddAction("NUM .", "Fast travel").AddAction("NUM 1", "Third");
        card.ShowDetails(three, NMTheme.Cyan());
        this.Check("tooltip.two_actions", card.KeycapsShown() == 2, ToString(card.KeycapsShown()));
        this.Check("tooltip.keycap_width", NMUi.Keycap(new inkCanvas(), "NUM 0", "TRACK") > NMUi.Keycap(new inkCanvas(), "0", "TRACK"), "");

        // No selection: the sidebar shows no text but the tracking block (no "POINT AT A MARKER"), also after a card hid.
        let fl = NMPanelLayout.Compute(3840.0, 2160.0);
        let panel = NMPanel.Build(new inkCanvas(), fl, NMTheme.DefaultPanelOpacity(), 0, false);
        let dr = NMPhotoDrawer.Create(panel.sidebar, fl, 0);
        let side = NMTooltip.CreateDocked(dr.Root(), 40.0, 40.0, fl.sideW - 80.0, fl.scale);
        let blank0 = NMSelfTest.VisibleTexts(panel.sidebar, n"Tracking");
        side.ShowDetails(three, NMTheme.Cyan());
        let shownTexts = NMSelfTest.VisibleTexts(panel.sidebar, n"Tracking");
        side.Hide();
        let blank1 = NMSelfTest.VisibleTexts(panel.sidebar, n"Tracking");
        this.Check("tooltip.empty_state_blank", blank0 == 0 && blank1 == 0 && shownTexts > 0,
            ToString(blank0) + "/" + ToString(shownTexts) + "/" + ToString(blank1));
        panel.Destroy();
    }

    private func PickCases() {
        let xs: array<Float> = [100.0, 130.0, 300.0];
        let ys: array<Float> = [100.0, 100.0, 100.0];
        let kinds: array<Int32> = [0, 0, 0];
        let layers: array<Int32> = [0, 0, 1];
        let items: array<Int32> = [5, 6, 9];
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
        // Every candidate is an item (kind 0), identified by layer + item. A lone item is picked away from the others;
        // the selected item is kept within 4 units of the nearest one, but only the same item on the same layer.
        this.Check("pick.lone_item", NMCrosshair.Pick(xs, ys, noReach, kinds, layers, items, 290.0, 100.0, 50.0, 0, 0, 5) == 2, "");
        this.Check("pick.sticky_by_identity", NMCrosshair.Pick(xs, ys, noReach, kinds, layers, items, 114.5, 100.0, 50.0, 0, 0, 6) == 1, "");
        this.Check("pick.other_layer_no_stick", NMCrosshair.Pick(xs, ys, noReach, kinds, layers, items, 114.5, 100.0, 50.0, 0, 1, 6) == 0, "");
        let empty: array<Float>;
        let emptyI: array<Int32>;
        this.Check("pick.empty_candidates", NMCrosshair.Pick(empty, empty, empty, emptyI, emptyI, emptyI, 0.0, 0.0, 50.0, 0, 0, 5) == -1, "");
        // The focus point is the map area's centre (mapW: the camera's width) less the sidebar shift, which lands on the
        // middle of the view the renderer culls to. Passing viewW there would move it half a sidebar left of the reticle.
        let l4 = NMPanelLayout.Compute(3840.0, 2160.0);
        let l1 = NMPanelLayout.Compute(1920.0, 1080.0);
        let f4 = NMCrosshair.FocusX(l4.mapW, NMPhotoDrawer.FocusShift(l4));
        let f1 = NMCrosshair.FocusX(l1.mapW, NMPhotoDrawer.FocusShift(l1));
        this.Check("pick.focus_mid_view", this.Near(f4, l4.viewW * 0.5, 0.01) && this.Near(f1, l1.viewW * 0.5, 0.01)
            && f4 + NMTheme.SelectRadius() * l4.scale < l4.viewW, this.F(f4) + "/" + this.F(l4.viewW) + " " + this.F(f1) + "/" + this.F(l1.viewW));
    }
}
