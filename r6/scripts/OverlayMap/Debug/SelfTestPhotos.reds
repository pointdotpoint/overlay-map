module OverlayMap

// NMSelfTest.Run(). Photo pins: line storage, grouping (Task 2).
public abstract class NMPhotoTests {
    public static func Run(t: ref<NMSelfTest>) {
        NMPhotoTests.Store(t);
        NMPhotoTests.Groups(t);
        NMPhotoTests.Link(t);
        NMPhotoTests.Layer(t);
        NMPhotoTests.Drawer(t);
        NMPhotoTests.Teleport(t);
        NMPhotoTests.Review(t);
        NMPhotoTests.Reticle(t);
    }

    // The focus reticle: four corner brackets that lock around the focused marker, and a plus on the focus point.
    private static func Reticle(t: ref<NMSelfTest>) {
        let r = NMReticle.Corners(100.0, 200.0, 80.0, 60.0, 20.0, 4.0);
        let inside = ArraySize(r) == 8;
        for q in r {   // (centre x, centre y, w, h)
            inside = inside && q.X - q.Z * 0.5 >= 59.99 && q.X + q.Z * 0.5 <= 140.01 && q.Y - q.W * 0.5 >= 169.99 && q.Y + q.W * 0.5 <= 230.01;
        }
        t.Check("reticle.corners_inside_box", inside, ToString(ArraySize(r)));
        t.Check("reticle.corner_touches", AbsF(r[0].X - r[0].Z * 0.5 - 60.0) < 0.01 && AbsF(r[0].Y - r[0].W * 0.5 - 170.0) < 0.01, "");
        let half = NMReticle.Ease(0.0, 100.0, 60.0);
        t.Check("reticle.ease", half > 30.0 && half < 70.0 && NMReticle.Ease(0.0, 100.0, NMReticle.EaseMs()) == 100.0, ToString(half));
        let idle = NMReticle.BoxFor(false, false, 1.0, 1.0);
        let chip = NMReticle.BoxFor(true, false, 1.0, 1.0);
        let photo = NMReticle.BoxFor(true, true, 1.0, 1.0);
        t.Check("reticle.box_sizes", idle.X > chip.X && photo.X > photo.Y && photo.X > NMItemRenderer.ThumbW(), "");
    }

    // Final review fixes.
    private static func Review(t: ref<NMSelfTest>) {
        // Loading twice gives the same pins (the plugin reads the file afresh each time).
        let la = NMPhotoStore.Load();
        let lb = NMPhotoStore.Load();
        t.Check("photo.store_reload", ArraySize(la) == ArraySize(lb), ToString(ArraySize(la)) + "/" + ToString(ArraySize(lb)));

        // Thumbnails are cached by shot hash, one load in flight, off-screen wants dropped.
        let p = NMThumbPlan.Create(2);
        p.BeginLayout();
        let w0 = p.Want(5u);
        p.EndLayout();
        let r0 = p.NextRequest();
        let s5 = p.SlotOf(5u);
        p.Loaded(5u, true);
        p.BeginLayout();
        let again = p.Want(5u);
        p.EndLayout();
        t.Check("photo.thumb_keyed", w0 == -1 && r0 == 5u && s5 >= 0 && again == s5 && p.IsReady(s5) && p.NextRequest() == 0u,
            ToString(w0) + " " + ToString(r0) + " " + ToString(again));

        let q = NMThumbPlan.Create(2);
        q.BeginLayout();
        q.Want(1u);
        q.Want(2u);
        q.EndLayout();
        let a1 = q.NextRequest();
        let busy = q.NextRequest();
        q.Loaded(1u, true);
        t.Check("photo.thumb_one_in_flight", a1 == 1u && busy == 0u && q.NextRequest() == 2u, "");

        let d = NMThumbPlan.Create(2);
        d.BeginLayout();
        d.Want(1u);
        d.Want(2u);
        d.EndLayout();
        d.NextRequest();
        d.BeginLayout();
        d.Want(3u);
        d.EndLayout();
        d.Loaded(1u, true);
        t.Check("photo.thumb_drop_offscreen", d.NextRequest() == 3u && d.SlotOf(2u) < 0, "");

        let e = NMThumbPlan.Create(2);
        e.BeginLayout(); e.Want(1u); e.Want(2u); e.EndLayout();
        e.NextRequest(); e.Loaded(1u, true);
        e.NextRequest(); e.Loaded(2u, true);
        e.BeginLayout(); e.Want(3u); e.EndLayout();
        t.Check("photo.thumb_evict", e.NextRequest() == 3u && (e.SlotOf(1u) < 0 || e.SlotOf(2u) < 0), "");

        // A late image from the previous pin never shows under the next pin's details.
        let dr = NMPhotoDrawer.CreateDetached();
        dr.Show(NMPhotoTests.Spot(21u, 0.0, 0.0, 1ul), "1 M", "", "NUM .", null);
        let la = dr.LastListener();
        dr.Show(NMPhotoTests.Spot(22u, 0.0, 0.0, 2ul), "1 M", "", "NUM .", null);
        la.OnLoaded(new Vector2(2560.0, 1440.0), 0);
        t.Check("photo.drawer_stale_image", !dr.ImageShown(), "");

        // A session without a baseline never claims shots (it would claim every older screenshot).
        let nb0 = new NMPhotoSession();
        t.Check("photo.no_baseline_claims_nothing", !NMPhotoLink.CanClaim(nb0), "");
        nb0.hasBaseline = true;
        t.Check("photo.baseline_claims", NMPhotoLink.CanClaim(nb0), "");

        // A load that finds no file reports no skipped lines left over from an earlier parse.
        let bad: array<String>;
        ArrayPush(bad, "garbage");
        NMPhotoStore.Parse(bad);
        NMPhotoStore.Load();
        t.Check("photo.load_resets_skipped", NMPhotoStore.Skipped() == 0, ToString(NMPhotoStore.Skipped()));

        // A session stays open 10 s after photo mode closes (shots finish writing ~5 s after capture).
        t.Check("photo.session_window", !NMPhotoLink.SessionDone(1000.0, 10999.0) && NMPhotoLink.SessionDone(1000.0, 11000.0), "");

        // The drawer shift is a screen offset of the camera, not a pan.
        let cam = NMCamera.Create(1600.0, 900.0, NMRect.Create(-5000.0, -5000.0, 5000.0, 5000.0), 0.5, 16.0);
        cam.SetCenter(4999.0, 0.0);
        cam.SetScreenShift(400.0);
        let c = cam.WorldToMap(cam.cx, cam.cy);
        let back = cam.MapToWorld(300.0, 200.0);
        let fwd = cam.WorldToMap(back.X, back.Y);
        t.Check("photo.camera_offset", AbsF(c.X - 400.0) < 0.01 && AbsF(fwd.X - 300.0) < 0.01 && AbsF(fwd.Y - 200.0) < 0.01 && cam.cx == 4999.0,
            ToString(c.X));

        // Closing the map mid-suite never leaves seeded perf spots behind.
        let sys = OverlayMapSystem.Get(GetGameInstance());
        if IsDefined(sys) {
            sys.Photos().SeedForPerf(3);
            sys.ClearPerfOverrides();
            t.Check("photo.perf_seed_cleared", !sys.Photos().IsPerfSeeded(), "");
        }
    }

    private static func Teleport(t: ref<NMSelfTest>) {
        // Refusal(isPhoto, inVehicle, playerReady)
        t.Check("photo.tp_ok", Equals(NMPhotoTeleport.Refusal(true, false, true), ""), "");
        t.Check("photo.tp_vehicle", Equals(NMPhotoTeleport.Refusal(true, true, true), "in vehicle"), "");
        t.Check("photo.tp_not_photo", Equals(NMPhotoTeleport.Refusal(false, false, true), "not a photo"), "");
        t.Check("photo.tp_not_ready_first", Equals(NMPhotoTeleport.Refusal(false, true, false), "not ready"), "");
        let s = new OverlayMapSettings();
        s.teleportEnabled = true;
        t.Check("photo.hint_teleport", StrContains(NMInput.HintText(s, "ALL", "TELEPORT"), "TELEPORT")
            && !StrContains(NMInput.HintText(s, "ALL", "TELEPORT"), "FAST TRAVEL"), "");
    }

    private static func Drawer(t: ref<NMSelfTest>) {
        // The focus point is the centre of the map area left of the always-visible sidebar.
        let l = NMPanelLayout.Compute(3840.0, 2160.0);
        t.Check("photo.focus_shift", AbsF(NMPhotoDrawer.FocusShift(l) - l.sideW * 0.5) < 0.01, ToString(NMPhotoDrawer.FocusShift(l)));
        // Snap: letting go of the pan keys eases the focused marker under the focus point.
        t.Check("snap.on_release", NMInput.SnapOnRelease(true, false, true), "");
        t.Check("snap.not_while_panning", !NMInput.SnapOnRelease(true, true, true), "");
        t.Check("snap.needs_selection", !NMInput.SnapOnRelease(true, false, false), "");
        t.Check("snap.only_after_pan", !NMInput.SnapOnRelease(false, false, true), "");
        t.Check("photo.thumb_bigger", NMItemRenderer.ThumbW() == 108.0 && AbsF(NMItemRenderer.ThumbH() - 61.5) < 0.01, "");

        let xs: array<Float>;
        let ys: array<Float>;
        let kinds: array<Int32>;
        let layers: array<Int32>;
        let items: array<Int32>;
        ArrayPush(xs, 100.0); ArrayPush(ys, 100.0); ArrayPush(kinds, 0); ArrayPush(layers, 0); ArrayPush(items, 1);
        ArrayPush(xs, 500.0); ArrayPush(ys, 100.0); ArrayPush(kinds, 0); ArrayPush(layers, 0); ArrayPush(items, 2);
        let noReach: array<Float>;
        t.Check("photo.pick_shifted", NMCrosshair.Pick(xs, ys, noReach, kinds, layers, items, 500.0 - 400.0, 100.0, 50.0, -1, -1, -1) == 0, "");


        t.Check("photo.date_from_path", Equals(NMPhotoDrawer.DateFromPath("C:\\users\\steamuser\\Pictures\\Cyberpunk 2077\\photomode_28102026_110520.png"), "28 OCT 2026 · 11:05")
            && Equals(NMPhotoDrawer.DateFromPath("collage_column.png"), ""), NMPhotoDrawer.DateFromPath("photomode_28102026_110520.png"));
    }

    private static func Layer(t: ref<NMSelfTest>) {
        let pos = new Vector4(100.0, 200.0, 10.0, 1.0);
        let it = OverlayMapItem.Shot(pos, n"Photos", 42u);
        t.Check("photo.item_shot", it.shotHash == 42u && !it.hasAtlas, "");

        let api = OverlayMap.Create();
        let L = api.CreateLayer(n"Test.Photos", "Photos", 10);
        let a = L.Add(OverlayMapItem.Shot(pos, n"Photos", 1u));
        let b = L.Add(OverlayMapItem.Shot(new Vector4(300.0, 200.0, 10.0, 1.0), n"Photos", 2u));
        let k1 = NMItemRenderer.IconKeyFor(L, a);
        let k2 = NMItemRenderer.IconKeyFor(L, b);
        L.Update(a, OverlayMapItem.Shot(pos, n"Photos", 3u));
        t.Check("photo.icon_key_changes", Equals(k1, "shot:1") && Equals(k2, "shot:2") && Equals(NMItemRenderer.IconKeyFor(L, a), "shot:3"),
            k1 + " " + k2 + " " + NMItemRenderer.IconKeyFor(L, a));

        let spots: array<ref<NMPhotoSpot>>;
        ArrayPush(spots, NMPhotoTests.Spot(11u, 0.0, 0.0, 1ul));
        ArrayPush(spots, NMPhotoTests.Spot(12u, 2.0, 1.0, 3ul));
        ArrayPush(spots, NMPhotoTests.Spot(13u, 1.0, 2.0, 2ul));
        ArrayPush(spots, NMPhotoTests.Spot(14u, 500.0, 0.0, 4ul));
        let ph = new NMPhotos();
        ph.SetSpotsForTest(spots, NMPhotoTests.AllExist(4));
        let api2 = OverlayMap.Create();
        ph.SyncLayer(api2, true);
        let PL = api2.GetLayer(NMPhotos.LayerId());
        let alive = 0;
        let hasNewest = false;
        let i = 0;
        while IsDefined(PL) && i < ArraySize(PL.alive) {
            if PL.alive[i] {
                alive += 1;
                if PL.shot[i] == 12u && ph.SpotOf(i).hash == 12u { hasNewest = true; }
            }
            i += 1;
        }
        t.Check("photo.sync_newest", alive == 2 && hasNewest, ToString(alive) + " alive");

        t.Check("photo.thumb_cap", NMPhotos.ThumbCap() == 24 && NMPhotos.ThumbAllowed(23, 24) && !NMPhotos.ThumbAllowed(24, 24), "");
    }

    private static func U32(a: Int32, b: Int32, c: Int32) -> array<Uint32> {
        let r: array<Uint32>;
        ArrayPush(r, Cast<Uint32>(a));
        ArrayPush(r, Cast<Uint32>(b));
        ArrayPush(r, Cast<Uint32>(c));
        return r;
    }

    private static func IdxStr(r: array<Int32>) -> String {
        let s = "[";
        for i in r { s += ToString(i) + ","; }
        return s + "]";
    }

    private static func Link(t: ref<NMSelfTest>) {
        let hashes = NMPhotoTests.U32(5, 7, 9);
        let created: array<Uint64>;
        ArrayPush(created, 90ul);
        ArrayPush(created, 101ul);
        ArrayPush(created, 105ul);
        let none: array<Uint32>;
        let r1 = NMPhotoLink.NewSince(hashes, created, 100ul, none);
        t.Check("photo.link_session", ArraySize(r1) == 2 && r1[0] == 1 && r1[1] == 2, NMPhotoTests.IdxStr(r1));

        let known: array<Uint32>;
        ArrayPush(known, 9u);
        let r2 = NMPhotoLink.NewSince(hashes, created, 100ul, known);
        t.Check("photo.link_skips_known", ArraySize(r2) == 1 && r2[0] == 1, NMPhotoTests.IdxStr(r2));

        let h5: array<Uint32>;
        let c5: array<Uint64>;
        ArrayPush(h5, 1u); ArrayPush(c5, 103ul);
        ArrayPush(h5, 2u); ArrayPush(c5, 101ul);
        ArrayPush(h5, 3u); ArrayPush(c5, 105ul);
        ArrayPush(h5, 4u); ArrayPush(c5, 102ul);
        ArrayPush(h5, 6u); ArrayPush(c5, 104ul);
        let r3 = NMPhotoLink.NewSince(h5, c5, 100ul, none);
        t.Check("photo.link_burst", ArraySize(r3) == 5 && r3[0] == 1 && r3[1] == 3 && r3[2] == 0 && r3[3] == 4 && r3[4] == 2,
            NMPhotoTests.IdxStr(r3));

        t.Check("photo.link_none", ArraySize(NMPhotoLink.NewSince(hashes, created, 105ul, none)) == 0, "");

        let b: array<Uint64>;
        ArrayPush(b, 3ul);
        ArrayPush(b, 9ul);
        ArrayPush(b, 4ul);
        let empty: array<Uint64>;
        t.Check("photo.baseline", NMPhotoLink.Baseline(b) == 9ul && NMPhotoLink.Baseline(empty) == 0ul, "");
    }

    private static func Spot(hash: Uint32, x: Float, y: Float, created: Uint64) -> ref<NMPhotoSpot> {
        return NMPhotoSpot.Create(hash, "photomode_" + ToString(hash) + ".png", new Vector4(x, y, 12.5, 1.0), 90.0, created);
    }

    private static func Store(t: ref<NMSelfTest>) {
        let s = NMPhotoSpot.Create(4000000000u, "C:\\Pictures\\photomode_27102026_225854.png",
            new Vector4(-1624.257, -387.004, 33.1, 1.0), -135.5, 133432000000000000ul);
        s.district = "WEST WIND ESTATE";
        let r = NMPhotoStore.FromLine(NMPhotoStore.ToLine(s));
        t.Check("photo.line_roundtrip", IsDefined(r) && r.hash == s.hash && Equals(r.path, s.path) && r.created == s.created && Equals(r.district, s.district)
            && AbsF(r.x - s.x) <= 0.01 && AbsF(r.y - s.y) <= 0.01 && AbsF(r.z - s.z) <= 0.01 && AbsF(r.yaw - s.yaw) <= 0.01,
            IsDefined(r) ? NMPhotoStore.ToLine(r) : "null");

        let good = NMPhotoStore.ToLine(NMPhotoTests.Spot(7u, 1.0, 2.0, 5ul));
        let lines: array<String>;
        ArrayPush(lines, good);
        ArrayPush(lines, "garbage");
        ArrayPush(lines, "1;2;3");
        ArrayPush(lines, good);
        let parsed = NMPhotoStore.Parse(lines);
        t.Check("photo.parse_skips_bad", ArraySize(parsed) == 2 && NMPhotoStore.Skipped() == 2,
            ToString(ArraySize(parsed)) + " parsed, " + ToString(NMPhotoStore.Skipped()) + " skipped");

        // Older versions wrote every spot without a line break: the whole file reads as one line.
        let glued: array<String>;
        ArrayPush(glued, NMPhotoStore.ToLine(NMPhotoTests.Spot(7u, 1.0, 2.0, 5ul)) + NMPhotoStore.ToLine(NMPhotoTests.Spot(8u, 3.0, 4.0, 6ul))
            + NMPhotoStore.ToLine(NMPhotoTests.Spot(9u, 5.0, 6.0, 7ul)));
        let unglued = NMPhotoStore.Parse(glued);
        t.Check("photo.parse_glued_spots", ArraySize(unglued) == 3 && NMPhotoStore.Skipped() == 0
            && unglued[0].hash == 7u && unglued[2].hash == 9u && Equals(unglued[1].path, "photomode_8.png"),
            ToString(ArraySize(unglued)) + " parsed, " + ToString(NMPhotoStore.Skipped()) + " skipped");

        let semi = NMPhotoSpot.Create(9u, "odd;name;photo.png", new Vector4(0.0, 0.0, 0.0, 1.0), 0.0, 1ul);
        let rs = NMPhotoStore.FromLine(NMPhotoStore.ToLine(semi));
        t.Check("photo.path_with_semicolon", IsDefined(rs) && Equals(rs.path, "odd;name;photo.png"), IsDefined(rs) ? rs.path : "null");
    }

    private static func AllExist(n: Int32) -> array<Bool> {
        let e: array<Bool>;
        let i = 0;
        while i < n { ArrayPush(e, true); i += 1; }
        return e;
    }

    private static func Groups(t: ref<NMSelfTest>) {
        let r = NMPhotoGroups.Radius();
        let near: array<ref<NMPhotoSpot>>;
        ArrayPush(near, NMPhotoTests.Spot(1u, 0.0, 0.0, 1ul));
        ArrayPush(near, NMPhotoTests.Spot(2u, 3.0, 1.0, 3ul));
        ArrayPush(near, NMPhotoTests.Spot(3u, 1.0, 2.0, 2ul));
        let one = NMPhotoGroups.Newest(near, NMPhotoTests.AllExist(3), r);
        t.Check("photo.group_one_place", ArraySize(one) == 1 && one[0] == 1, ToString(ArraySize(one)));

        let a: array<ref<NMPhotoSpot>>;
        ArrayPush(a, NMPhotoTests.Spot(1u, 0.0, 0.0, 1ul));
        ArrayPush(a, NMPhotoTests.Spot(2u, 9.9, 0.0, 2ul));
        let b: array<ref<NMPhotoSpot>>;
        ArrayPush(b, NMPhotoTests.Spot(1u, 0.0, 0.0, 1ul));
        ArrayPush(b, NMPhotoTests.Spot(2u, 10.1, 0.0, 2ul));
        let both = NMPhotoTests.AllExist(2);
        let groupsA = NMPhotoGroups.Newest(a, both, r);   // bind to locals: ArraySize of a call temporary misreads in-game
        let groupsB = NMPhotoGroups.Newest(b, both, r);
        let na = ArraySize(groupsA);
        let nb = ArraySize(groupsB);
        t.Check("photo.group_edge", na == 1 && nb == 2, "9.9 m -> " + ToString(na) + ", 10.1 m -> " + ToString(nb) + ", r " + ToString(r));

        let gone = NMPhotoTests.AllExist(3);
        gone[1] = false;   // the newest (created 3) was deleted
        let del = NMPhotoGroups.Newest(near, gone, r);
        t.Check("photo.group_deleted_newest", ArraySize(del) == 1 && del[0] == 2, ArraySize(del) > 0 ? ToString(del[0]) : "empty");

        let none: array<Bool>;
        ArrayPush(none, false);
        ArrayPush(none, false);
        ArrayPush(none, false);
        let all = NMPhotoGroups.Newest(near, none, r);
        t.Check("photo.group_all_deleted", ArraySize(all) == 0, ToString(ArraySize(all)) + " shown, exists " + ToString(ArraySize(none)));
    }
}
