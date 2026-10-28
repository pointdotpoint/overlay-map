module NightMap

// NMSelfTest.Run(). Photo pins: line storage, grouping (Task 2).
public abstract class NMPhotoTests {
    public static func Run(t: ref<NMSelfTest>) {
        NMPhotoTests.Store(t);
        NMPhotoTests.Groups(t);
        NMPhotoTests.Link(t);
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
        let r = NMPhotoStore.FromLine(NMPhotoStore.ToLine(s));
        t.Check("photo.line_roundtrip", IsDefined(r) && r.hash == s.hash && Equals(r.path, s.path) && r.created == s.created
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
