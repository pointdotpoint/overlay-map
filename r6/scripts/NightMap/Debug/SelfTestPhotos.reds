module NightMap

// NMSelfTest.Run(). Photo pins: line storage, grouping (Task 2).
public abstract class NMPhotoTests {
    public static func Run(t: ref<NMSelfTest>) {
        NMPhotoTests.Store(t);
        NMPhotoTests.Groups(t);
        NMPhotoTests.Link(t);
        NMPhotoTests.Layer(t);
        NMPhotoTests.Drawer(t);
    }

    private static func Drawer(t: ref<NMSelfTest>) {
        t.Check("photo.shift_target", NMPhotoDrawer.ShiftTarget(true, 1600.0) == 400.0 && NMPhotoDrawer.ShiftTarget(false, 1600.0) == 0.0, "");
        let half = NMPhotoDrawer.EaseShift(0.0, 400.0, 75.0);
        t.Check("photo.shift_ease", half >= 150.0 && half <= 250.0 && NMPhotoDrawer.EaseShift(0.0, 400.0, 150.0) == 400.0
            && NMPhotoDrawer.EaseShift(400.0, 0.0, 1000.0) == 0.0, ToString(half));

        let xs: array<Float>;
        let ys: array<Float>;
        let kinds: array<Int32>;
        let layers: array<Int32>;
        let items: array<Int32>;
        ArrayPush(xs, 100.0); ArrayPush(ys, 100.0); ArrayPush(kinds, 0); ArrayPush(layers, 0); ArrayPush(items, 1);
        ArrayPush(xs, 500.0); ArrayPush(ys, 100.0); ArrayPush(kinds, 0); ArrayPush(layers, 0); ArrayPush(items, 2);
        t.Check("photo.pick_shifted", NMCrosshair.Pick(xs, ys, kinds, layers, items, 500.0 - 400.0, 100.0, 50.0, -1, -1, -1) == 0, "");

        let cam = NMCamera.Create(1600.0, 900.0, NMRect.Create(-5000.0, -5000.0, 5000.0, 5000.0), 0.5, 16.0);
        cam.follow = true;
        NMPhotoDrawer.OnOpen(cam);
        t.Check("photo.drawer_stops_follow", !cam.follow, "");

        t.Check("photo.date_from_path", Equals(NMPhotoDrawer.DateFromPath("C:\\users\\steamuser\\Pictures\\Cyberpunk 2077\\photomode_28102026_110520.png"), "28 OCT 2026 · 11:05")
            && Equals(NMPhotoDrawer.DateFromPath("collage_column.png"), ""), NMPhotoDrawer.DateFromPath("photomode_28102026_110520.png"));
    }

    private static func Layer(t: ref<NMSelfTest>) {
        let pos = new Vector4(100.0, 200.0, 10.0, 1.0);
        let it = NightMapItem.Shot(pos, n"Photos", 42u);
        t.Check("photo.item_shot", it.shotHash == 42u && !it.hasAtlas, "");

        let api = NightMap.Create();
        let L = api.CreateLayer(n"Test.Photos", "Photos", 10);
        let a = L.Add(NightMapItem.Shot(pos, n"Photos", 1u));
        let b = L.Add(NightMapItem.Shot(new Vector4(300.0, 200.0, 10.0, 1.0), n"Photos", 2u));
        let k1 = NMItemRenderer.IconKeyFor(L, a);
        let k2 = NMItemRenderer.IconKeyFor(L, b);
        L.Update(a, NightMapItem.Shot(pos, n"Photos", 3u));
        t.Check("photo.icon_key_changes", Equals(k1, "shot:1") && Equals(k2, "shot:2") && Equals(NMItemRenderer.IconKeyFor(L, a), "shot:3"),
            k1 + " " + k2 + " " + NMItemRenderer.IconKeyFor(L, a));

        let spots: array<ref<NMPhotoSpot>>;
        ArrayPush(spots, NMPhotoTests.Spot(11u, 0.0, 0.0, 1ul));
        ArrayPush(spots, NMPhotoTests.Spot(12u, 2.0, 1.0, 3ul));
        ArrayPush(spots, NMPhotoTests.Spot(13u, 1.0, 2.0, 2ul));
        ArrayPush(spots, NMPhotoTests.Spot(14u, 500.0, 0.0, 4ul));
        let ph = new NMPhotos();
        ph.SetSpotsForTest(spots, NMPhotoTests.AllExist(4));
        let api2 = NightMap.Create();
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
        t.Check("photo.group_edge", ArraySize(NMPhotoGroups.Newest(a, NMPhotoTests.AllExist(2), r)) == 1
            && ArraySize(NMPhotoGroups.Newest(b, NMPhotoTests.AllExist(2), r)) == 2, "");

        let gone = NMPhotoTests.AllExist(3);
        gone[1] = false;   // the newest (created 3) was deleted
        let del = NMPhotoGroups.Newest(near, gone, r);
        t.Check("photo.group_deleted_newest", ArraySize(del) == 1 && del[0] == 2, ArraySize(del) > 0 ? ToString(del[0]) : "empty");

        let none: array<Bool>;
        ArrayPush(none, false);
        ArrayPush(none, false);
        ArrayPush(none, false);
        t.Check("photo.group_all_deleted", ArraySize(NMPhotoGroups.Newest(near, none, r)) == 0, "");
    }
}
