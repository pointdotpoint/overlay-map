module NightMap

// Self-test group for collectible pins (spec 2026-10-31-nightmap-collectibles-design.md). Called from NMSelfTest.Run().
public abstract class NMCollectTests {
    public static func Run(t: ref<NMSelfTest>) {
        NMCollectTests.ParseCases(t);
        NMCollectTests.DataCases(t);
        NMCollectTests.GameCases(t);
        NMCollectTests.SyncCases(t);
        NMCollectTests.StrikeCases(t);
    }

    private static func TestApi() -> ref<NightMap> {
        let api = NightMap.Create();
        api.SetWorld(NMTileManifest.WorldMinX(), NMTileManifest.WorldMinY(), NMTileManifest.WorldMaxX(), NMTileManifest.WorldMaxY());
        return api;
    }

    private static func ParseCases(t: ref<NMSelfTest>) {
        let s = NMCollect.Parse("S,1.50,-2.00,3.25,Items.a;T,4.00,5.00,6.00,mq033_x+mq033_y;Q,1,2,3,Items.b;W,1,2");
        t.Check("collect.parse_count", ArraySize(s) == 2, ToString(ArraySize(s)));
        t.Check("collect.parse_fields", ArraySize(s) == 2 && s[0].cat == 0 && t.Near(s[0].pos.X, 1.5, 0.001)
            && t.Near(s[0].pos.Y, -2.0, 0.001) && t.Near(s[0].pos.Z, 3.25, 0.001) && Equals(s[0].ref, "Items.a")
            && s[1].cat == NMCollectCats.Tarot() && Equals(s[1].ref, "mq033_x+mq033_y"), "");
        t.Check("collect.parse_empty", ArraySize(NMCollect.Parse("")) == 0, "");
        t.Check("collect.layer_ids", NMCollect.IsCollectLayer(NMCollectCats.LayerId(2)) && !NMCollect.IsCollectLayer(n"Vanilla.Quest"), "");
        t.Check("collect.teleport_exact", NMTeleport.ExactLayer(n"Collect.Shard") && NMTeleport.ExactLayer(n"Collect.Tarot"), "");
    }

    // The generated data: every entry parses, every category has spots, all inside the map.
    private static func DataCases(t: ref<NMSelfTest>) {
        let c = new NMCollect();
        c.EnsureSpots();
        t.Check("collect.data_count", ArraySize(c.spots) == NMCollectData.Count(), ToString(ArraySize(c.spots)) + "/" + ToString(NMCollectData.Count()));
        let per: array<Int32>;
        let k = 0;
        while k < NMCollectCats.Count() { ArrayPush(per, 0); k += 1; }
        let outside = 0;
        for s in c.spots {
            per[s.cat] += 1;
            if !NMTeleport.InBounds(s.pos.X, s.pos.Y) { outside += 1; }
        }
        let empty = 0;
        for n in per { if n == 0 { empty += 1; } }
        t.Check("collect.data_categories", empty == 0, ToString(per[0]) + "," + ToString(per[1]) + "," + ToString(per[2]) + ","
            + ToString(per[3]) + "," + ToString(per[4]) + "," + ToString(per[5]));
        t.Check("collect.data_in_map", outside == 0, ToString(outside));
    }

    // Against the live game: item records and journal entries resolve, and names come back.
    private static func GameCases(t: ref<NMSelfTest>) {
        let gi = GetGameInstance();
        let c = new NMCollect();
        c.Refresh(gi, new inkHashMap());
        let noRecord = 0;
        let noName = 0;
        let firstBad = "";
        for s in c.spots {
            if s.cat != NMCollectCats.Tarot() && !IsDefined(TweakDBInterface.GetItemRecord(s.item)) {
                noRecord += 1;
                if Equals(firstBad, "") { firstBad = s.ref; }
            }
            if Equals(c.Title(s), s.ref) { noName += 1; }
        }
        t.Check("collect.records_resolve", noRecord == 0, ToString(noRecord) + " " + firstBad);
        t.Check("collect.names_resolve", noName * 50 <= ArraySize(c.spots), ToString(noName) + "/" + ToString(ArraySize(c.spots)));
        t.Check("collect.state_read", c.collectedN >= 0 && c.collectedN <= ArraySize(c.spots), ToString(c.collectedN));
        let d = c.Details(0);
        t.Check("collect.details", IsDefined(d) && StrLen(d.title) > 0, IsDefined(d) ? d.title : "none");
    }

    private static func FirstOf(c: ref<NMCollect>, cat: Int32) -> Int32 {
        let i = 0;
        while i < ArraySize(c.spots) {
            if c.spots[i].cat == cat { return i; }
            i += 1;
        }
        return -1;
    }

    // Layers: built per category; a seen item is struck and faded; hidden outside the ALL view; collected ones drop
    // out when "Show collected" is off.
    private static func SyncCases(t: ref<NMSelfTest>) {
        let api = NMCollectTests.TestApi();
        let c = new NMCollect();
        c.Refresh(GetGameInstance(), new inkHashMap());
        let ws = NMCollectTests.FirstOf(c, 2);
        let seen = new inkHashMap();
        seen.Insert(TDBID.ToNumber(c.spots[ws].item), c);
        c.Refresh(GetGameInstance(), seen);
        c.Sync(api, 0, null);
        let total = 0;
        let k = 0;
        while k < NMCollectCats.Count() {
            let L = api.GetLayer(NMCollectCats.LayerId(k));
            if IsDefined(L) { total += L.count; }
            k += 1;
        }
        t.Check("collect.sync_all", total == ArraySize(c.spots), ToString(total) + "/" + ToString(ArraySize(c.spots)));
        let W = api.GetLayer(NMCollectCats.LayerId(2));
        let struck = 0;
        let faded = true;
        let i = 0;
        while i < ArraySize(W.alive) {
            if W.alive[i] && W.struck[i] {
                struck += 1;
                faded = faded && t.Near(W.alpha[i], NMCollect.CollectedOpacity(), 0.001);
            }
            i += 1;
        }
        t.Check("collect.seen_struck", c.spots[ws].collected && struck >= 1 && faded, ToString(struck));
        t.Check("collect.icon_style", W.pinStyle == 1 && W.visible, "");
        let full = W.count;
        c.Sync(api, 1, null);
        t.Check("collect.view_hides", !W.visible, "");
        let s = new NightMapSettings();
        s.collectShowCollected = false;
        s.collectShards = false;
        c.Sync(api, 0, s);
        let W2 = api.GetLayer(NMCollectCats.LayerId(2));
        let S2 = api.GetLayer(NMCollectCats.LayerId(0));
        t.Check("collect.hide_collected", W2.count == full - struck && !S2.visible, ToString(W2.count) + "/" + ToString(full));
        s.collectShowCollected = true;
        c.Sync(api, 0, s);
        t.Check("collect.show_collected_again", W2.count == full, ToString(W2.count));
    }

    // The renderer draws the scratch over a struck item's icon, the same size, and none over the others.
    private static func StrikeCases(t: ref<NMSelfTest>) {
        let api = NMCollectTests.TestApi();
        let L = api.CreateLayer(n"Collect.Test", "Test", 40);
        L.SetPinStyle(NightMapPinStyle.Icon);
        let a = L.Add(NightMapItem.Create(new Vector4(-1800.0, 150.0, 0.0, 1.0), n"t", NMTheme.UiAtlas(), n"icon_c_shard").WithStruck(true).WithOpacity(0.5));
        let b = L.Add(NightMapItem.Create(new Vector4(-1780.0, 150.0, 0.0, 1.0), n"t", NMTheme.UiAtlas(), n"icon_c_tarot"));
        let canvas = new inkCanvas();
        let r = NMItemRenderer.Create(api, canvas, 1.0);
        let cam = NMCamera.Create(1880.0, 1480.0, NMRect.Create(-6000.0, -4600.0, 4600.0, 7400.0), 0.5, 16.0);
        cam.SetCenter(-1800.0, 150.0);
        cam.SetMpp(0.5);
        r.Update(cam, 1880.0, 1480.0);
        let sa = NMCollectTests.SlotOf(r, L.index, a);
        let sb = NMCollectTests.SlotOf(r, L.index, b);
        t.Check("collect.strike_placed", sa >= 0 && sb >= 0 && r.strikeOn[sa] && !r.strikeOn[sb], ToString(sa) + "," + ToString(sb));
        if sa >= 0 && r.strikeOn[sa] {
            let ss = r.chipStrike[sa].GetSize();
            let is = r.chipIcon[sa].GetSize();
            t.Check("collect.strike_matches_icon", t.Near(ss.X, is.X, 0.01) && t.Near(r.chipStrike[sa].GetOpacity(), r.chipIcon[sa].GetOpacity(), 0.001)
                && t.Near(r.chipAlpha[sa], 0.25, 0.001), t.F(ss.X) + " " + t.F(r.chipAlpha[sa]));
        }
        // Unstrike: the scratch goes away on the next layout.
        L.Update(a, NightMapItem.Create(new Vector4(-1800.0, 150.0, 0.0, 1.0), n"t", NMTheme.UiAtlas(), n"icon_c_shard"));
        r.Update(cam, 1880.0, 1480.0);
        let sa2 = NMCollectTests.SlotOf(r, L.index, a);
        t.Check("collect.strike_cleared", sa2 >= 0 && !r.strikeOn[sa2], ToString(sa2));
    }

    private static func SlotOf(r: ref<NMItemRenderer>, li: Int32, id: Int32) -> Int32 {
        let i = 0;
        while i < ArraySize(r.candItem) {
            if r.candKind[i] == 0 && r.candLayer[i] == li && r.candItem[i] == id { return r.candSlot[i]; }
            i += 1;
        }
        return -1;
    }
}
