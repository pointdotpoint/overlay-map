module NightMap

// Self-test group for the declutter (screen-space collision culling of markers). Called from NMSelfTest.Run().
// Two markers collide when their centres are closer than DeclutterOverlap x (rA + rB); the later one in placement
// order (tier, priority, nearest-first) is skipped unless it is an Always-tier item or the current selection.
public abstract class NMDeclutterTests {
    private static func W() -> Float { return 1880.0; }
    private static func H() -> Float { return 1480.0; }

    private static func Api() -> ref<NightMap> {
        let api = NightMap.Create();
        api.SetWorld(-6000.0, -4600.0, 4600.0, 7400.0);
        return api;
    }

    private static func Cam(mpp: Float) -> ref<NMCamera> {
        let cam = NMCamera.Create(NMDeclutterTests.W(), NMDeclutterTests.H(), NMRect.Create(-6000.0, -4600.0, 4600.0, 7400.0), 0.5, 16.0);
        cam.SetCenter(0.0, 0.0);
        cam.SetMpp(mpp);
        return cam;
    }

    private static func Layer(api: ref<NightMap>, id: CName, priority: Int32, tier: NightMapTier) -> ref<NightMapLayer> {
        let L = api.CreateLayer(id, "Declutter", priority);
        L.SetTier(tier);
        L.SetCategory(n"test.dc", "DC", NMTheme.Cyan());
        return L;
    }

    private static func At(L: ref<NightMapLayer>, x: Float, y: Float) -> Int32 {
        return L.Add(NightMapItem.Create(new Vector4(x, y, 0.0, 1.0), n"test.dc", NMTheme.UiAtlas(), n"icon_dot"));
    }

    private static func Placed(r: ref<NMItemRenderer>, L: ref<NightMapLayer>, id: Int32) -> Bool {
        let k = 0;
        while k < ArraySize(r.candItem) {
            if r.candLayer[k] == L.index && r.candItem[k] == id { return true; }
            k += 1;
        }
        return false;
    }

    private static func Info(r: ref<NMItemRenderer>) -> String {
        return "placed " + ToString(ArraySize(r.candX)) + " chips " + ToString(r.chipsUsed) + " culled " + ToString(r.culled);
    }

    public static func Run(t: ref<NMSelfTest>) {
        let w = NMDeclutterTests.W();
        let h = NMDeclutterTests.H();
        t.Check("declutter.token", t.Near(NMTheme.DeclutterOverlap(), 0.75, 0.0001), t.F(NMTheme.DeclutterOverlap()));

        // 1. Two Minor items of one layer on the same spot: one is drawn, the other skipped without a slot.
        let api = NMDeclutterTests.Api();
        let L = NMDeclutterTests.Layer(api, n"test.dc.overlap", 5, NightMapTier.Minor);
        NMDeclutterTests.At(L, 0.0, 0.0);
        NMDeclutterTests.At(L, 0.0, 0.0);
        let r = NMItemRenderer.Create(api, new inkCanvas(), 1.0);
        r.Update(NMDeclutterTests.Cam(2.0), w, h);
        t.Check("declutter.overlap_skipped", ArraySize(r.candX) == 1 && r.chipsUsed == 1 && r.culled == 1, NMDeclutterTests.Info(r));

        // 2. A Minor (higher priority) and a Major item on the same spot: the tier wins, the Minor one is culled.
        let api2 = NMDeclutterTests.Api();
        let mi = NMDeclutterTests.Layer(api2, n"test.dc.minor", 50, NightMapTier.Minor);
        let ma = NMDeclutterTests.Layer(api2, n"test.dc.major", 1, NightMapTier.Major);
        let miId = NMDeclutterTests.At(mi, 0.0, 0.0);
        let maId = NMDeclutterTests.At(ma, 0.0, 0.0);
        let r2 = NMItemRenderer.Create(api2, new inkCanvas(), 1.0);
        r2.Update(NMDeclutterTests.Cam(2.0), w, h);
        t.Check("declutter.major_wins", NMDeclutterTests.Placed(r2, ma, maId) && !NMDeclutterTests.Placed(r2, mi, miId) && r2.culled == 1 && r2.chipsUsed == 1,
            NMDeclutterTests.Info(r2));

        // 3. Two items three radii apart on screen (hex chips at full scale: r = ChipSize / 2) are both drawn.
        let api3 = NMDeclutterTests.Api();
        let L3 = NMDeclutterTests.Layer(api3, n"test.dc.spaced", 5, NightMapTier.Minor);
        let mpp3 = 2.0;
        let gap = 3.0 * NMTheme.ChipSize() * 0.5 * mpp3;   // metres
        NMDeclutterTests.At(L3, 0.0, 0.0);
        NMDeclutterTests.At(L3, gap, 0.0);
        let r3 = NMItemRenderer.Create(api3, new inkCanvas(), 1.0);
        r3.Update(NMDeclutterTests.Cam(mpp3), w, h);
        t.Check("declutter.spaced_both", ArraySize(r3.candX) == 2 && r3.culled == 0, NMDeclutterTests.Info(r3));

        // 4. Always items are never culled (two of them on one spot both stay) and take space: the Major one under
        // them is culled even though its layer has the higher priority.
        let api4 = NMDeclutterTests.Api();
        let al = NMDeclutterTests.Layer(api4, n"test.dc.always", 1, NightMapTier.Always);
        let mj = NMDeclutterTests.Layer(api4, n"test.dc.major4", 90, NightMapTier.Major);
        let a0 = NMDeclutterTests.At(al, 0.0, 0.0);
        let a1 = NMDeclutterTests.At(al, 0.0, 0.0);
        let mjId = NMDeclutterTests.At(mj, 0.0, 0.0);
        let r4 = NMItemRenderer.Create(api4, new inkCanvas(), 1.0);
        r4.Update(NMDeclutterTests.Cam(2.0), w, h);
        t.Check("declutter.always_never_culled", NMDeclutterTests.Placed(r4, al, a0) && NMDeclutterTests.Placed(r4, al, a1) && !NMDeclutterTests.Placed(r4, mj, mjId)
            && r4.culled == 1, NMDeclutterTests.Info(r4));

        // 5. The selected item is never culled while selected: select a Minor pin, then a Major item appears on the
        // same spot. The selection is placed first and keeps its space (the Major item is culled); once the selection
        // is dropped, the next relayout goes by tier again and culls the Minor pin.
        let api5 = NMDeclutterTests.Api();
        let s5 = NMDeclutterTests.Layer(api5, n"test.dc.sel", 5, NightMapTier.Minor);
        s5.SetPinStyle(NightMapPinStyle.Icon);
        let sId = NMDeclutterTests.At(s5, 0.0, 0.0);
        let r5 = NMItemRenderer.Create(api5, new inkCanvas(), 1.0);
        let c5 = NMCrosshair.Create();
        let cam5 = NMDeclutterTests.Cam(2.0);
        r5.Update(cam5, w, h);
        c5.Update(r5, w, h, 1.0, 0.0);
        r5.ApplySelection(c5.sel, c5.selKind, 16.0);
        let picked = c5.selKind == 0 && c5.selLayer == s5.index && c5.selItem == sId;
        let m5 = NMDeclutterTests.Layer(api5, n"test.dc.selmajor", 1, NightMapTier.Major);
        let m5Id = NMDeclutterTests.At(m5, 0.0, 0.0);
        let relaid = r5.Update(cam5, w, h);
        let kept = NMDeclutterTests.Placed(r5, s5, sId) && !NMDeclutterTests.Placed(r5, m5, m5Id) && r5.culled == 1;
        c5.Update(r5, w, h, 1.0, 0.0);
        r5.ApplySelection(c5.sel, c5.selKind, 16.0);
        let still = c5.selLayer == s5.index && c5.selItem == sId;
        r5.ApplySelection(-1, -1, 16.0);
        r5.Invalidate();
        r5.Update(cam5, w, h);
        let dropped = !NMDeclutterTests.Placed(r5, s5, sId) && NMDeclutterTests.Placed(r5, m5, m5Id) && r5.culled == 1;
        t.Check("declutter.selected_kept", picked && relaid && kept && still && dropped,
            ToString(picked) + ToString(relaid) + ToString(kept) + ToString(still) + ToString(dropped) + " " + NMDeclutterTests.Info(r5));

        // 6. Two Minor items 40 m apart: one pile at mpp 3.5, separate at mpp 0.5.
        let api6 = NMDeclutterTests.Api();
        let L6 = NMDeclutterTests.Layer(api6, n"test.dc.zoom", 5, NightMapTier.Minor);
        NMDeclutterTests.At(L6, -20.0, 0.0);
        NMDeclutterTests.At(L6, 20.0, 0.0);
        let r6 = NMItemRenderer.Create(api6, new inkCanvas(), 1.0);
        let cam6 = NMDeclutterTests.Cam(3.5);
        r6.Update(cam6, w, h);
        let far = ArraySize(r6.candX) == 1 && r6.culled == 1;
        let farInfo = NMDeclutterTests.Info(r6);
        cam6.SetMpp(0.5);
        r6.Update(cam6, w, h);
        t.Check("declutter.zoom_separates", far && ArraySize(r6.candX) == 2 && r6.culled == 0, farInfo + " / " + NMDeclutterTests.Info(r6));

        // 7. Invariant over a dense layer (the spatial hash finds every neighbour): no two drawn hex chips at full
        // scale are closer than DeclutterOverlap x 2r, and every culled item cost no slot.
        let api7 = NMDeclutterTests.Api();
        let L7 = NMDeclutterTests.Layer(api7, n"test.dc.dense", 5, NightMapTier.Minor);
        let i = 0;
        while i < 1500 {
            NMDeclutterTests.At(L7, Cast<Float>((i * 7919) % 3000) - 1500.0, Cast<Float>((i * 104729) % 2400) - 1200.0);
            i += 1;
        }
        let r7 = NMItemRenderer.Create(api7, new inkCanvas(), 1.0);
        r7.Update(NMDeclutterTests.Cam(2.0), w, h);
        let minD = 2.0 * NMTheme.DeclutterOverlap() * NMTheme.ChipSize() * 0.5;
        let close = 0;
        let a = 0;
        while a < ArraySize(r7.candX) {
            let b = a + 1;
            while b < ArraySize(r7.candX) {
                let dx = r7.candX[a] - r7.candX[b];
                let dy = r7.candY[a] - r7.candY[b];
                if dx * dx + dy * dy < minD * minD - 0.01 { close += 1; }
                b += 1;
            }
            a += 1;
        }
        t.Check("declutter.no_pair_overlaps", close == 0 && r7.culled > 0 && ArraySize(r7.candX) > 0 && r7.chipsUsed == ArraySize(r7.candX),
            "close " + ToString(close) + " " + NMDeclutterTests.Info(r7));

        // 8. Work bounds: a pile of 500 items on one spot stops after the cell's miss cap, and piles in 600 cells
        // stop testing at CullCap culls.
        let api8 = NMDeclutterTests.Api();
        let L8 = NMDeclutterTests.Layer(api8, n"test.dc.pile", 5, NightMapTier.Minor);
        i = 0;
        while i < 500 {
            NMDeclutterTests.At(L8, 10.0, 10.0);
            i += 1;
        }
        let r8 = NMItemRenderer.Create(api8, new inkCanvas(), 1.0);
        r8.Update(NMDeclutterTests.Cam(4.0), w, h);
        let pileOk = ArraySize(r8.candX) == 1 && r8.culled >= 1 && r8.culled <= 8;
        let pileInfo = NMDeclutterTests.Info(r8);
        let api9 = NMDeclutterTests.Api();
        let L9 = NMDeclutterTests.Layer(api9, n"test.dc.piles", 5, NightMapTier.Major);   // at mpp 16 neighbouring cells collide
        i = 0;
        while i < 600 * 6 {
            let c = i / 6;   // 6 items in each of 600 level-0 cells, 30 x 20 cells around the centre
            NMDeclutterTests.At(L9, Cast<Float>(c % 30 - 15) * 250.0 + 125.0, Cast<Float>(c / 30 - 10) * 250.0 + 125.0);
            i += 1;
        }
        let r9 = NMItemRenderer.Create(api9, new inkCanvas(), 1.0);
        r9.Update(NMDeclutterTests.Cam(16.0), w, h);
        t.Check("declutter.work_bounded", pileOk && r9.culled == NMItemRenderer.CullCap() && ArraySize(r9.candX) > 0 && ArraySize(r9.candX) < 300,
            pileInfo + " / piles " + NMDeclutterTests.Info(r9));

        // 9. A tarot collectible and the vanilla tarot marker sit on one spot; the collectible (name, collected
        // state) must win the declutter, so its layer outranks the vanilla tarot layer. Other collectibles stay below
        // every vanilla layer.
        let vapi = NMDeclutterTests.Api();
        let v = NMVanilla.Create(vapi, GetGameInstance());
        let empty: array<ref<IMappin>>;
        v.PollFrom(empty, 0ul);
        let vt = -1;
        let vTier = -1;
        let ci = 0;
        while ci < v.catalog.Count() {
            if Equals(v.catalog.TypeOf(ci), gamedataWorldMapFilter.TarotFilter) {
                let vl = v.LayerForSlot(ci);
                if IsDefined(vl) {
                    vt = vl.priority;
                    vTier = vl.tier;
                }
            }
            ci += 1;
        }
        let capi = NMDeclutterTests.Api();
        let col = new NMCollect();
        col.Sync(capi, 0, null);
        let ctl = capi.GetLayer(NMCollectCats.LayerId(NMCollectCats.Tarot()));
        let tp = ctl.priority;
        let sp = capi.GetLayer(NMCollectCats.LayerId(NMCollectCats.Shard())).priority;
        let api10 = NMDeclutterTests.Api();
        let van = NMDeclutterTests.Layer(api10, n"test.dc.vtarot", vt, IntEnum<NightMapTier>(Max(vTier, 0)));
        van.SetPinStyle(NightMapPinStyle.Icon);
        let tar = NMDeclutterTests.Layer(api10, n"test.dc.ctarot", tp, IntEnum<NightMapTier>(ctl.tier));
        let vId = NMDeclutterTests.At(van, 0.0, 0.0);
        let tId = NMDeclutterTests.At(tar, 4.0, 0.0);
        let rc = NMItemRenderer.Create(api10, new inkCanvas(), 1.0);
        rc.Update(NMDeclutterTests.Cam(0.5), w, h);
        t.Check("declutter.collect_tarot_wins", vt > 0 && vTier >= 0 && tp > vt && sp < 50 && NMDeclutterTests.Placed(rc, tar, tId) && !NMDeclutterTests.Placed(rc, van, vId),
            "vanilla " + ToString(vt) + " tier " + ToString(vTier) + " tarot " + ToString(tp) + " tier " + ToString(ctl.tier) + " shard " + ToString(sp) + " " + NMDeclutterTests.Info(rc));

        // 10. The selection survives a saturated relayout: higher-priority piles spend the cull cap before the
        // selected item's low-priority layer is reached, and it must still be placed (it is placed first).
        let api11 = NMDeclutterTests.Api();
        let sel = NMDeclutterTests.Layer(api11, n"test.dc.capsel", 1, NightMapTier.Major);
        let selId = NMDeclutterTests.At(sel, 0.0, 0.0);
        let r11 = NMItemRenderer.Create(api11, new inkCanvas(), 1.0);
        let c11 = NMCrosshair.Create();
        let cam11 = NMDeclutterTests.Cam(16.0);
        r11.Update(cam11, w, h);
        c11.Update(r11, w, h, 1.0, 0.0);
        r11.ApplySelection(c11.sel, c11.selKind, 16.0);
        let picked11 = c11.selKind == 0 && c11.selLayer == sel.index && c11.selItem == selId;
        let piles = NMDeclutterTests.Layer(api11, n"test.dc.cappiles", 90, NightMapTier.Major);
        i = 0;
        while i < 600 * 6 {
            let pc = i / 6;
            NMDeclutterTests.At(piles, Cast<Float>(pc % 30 - 15) * 250.0 + 125.0, Cast<Float>(pc / 30 - 10) * 250.0 + 125.0);
            i += 1;
        }
        r11.Update(cam11, w, h);
        let kept11 = NMDeclutterTests.Placed(r11, sel, selId);
        let capped = r11.culled == NMItemRenderer.CullCap();
        c11.Update(r11, w, h, 1.0, 0.0);
        r11.ApplySelection(c11.sel, c11.selKind, 16.0);
        let still11 = c11.selLayer == sel.index && c11.selItem == selId;
        t.Check("declutter.selected_survives_cap", picked11 && capped && kept11 && still11,
            ToString(picked11) + ToString(capped) + ToString(kept11) + ToString(still11) + " " + NMDeclutterTests.Info(r11));
        NMDeclutterTests.Cost();
    }

    // Relayout cost with and without the declutter over the perf suite's biggest item layer (logged, not checked:
    // timings need the precise clock and vary with the machine).
    private static func Cost() {
        if !NMClock.Precise() { return; }
        let api = NightMap.Create();
        api.SetWorld(NMTileManifest.WorldMinX(), NMTileManifest.WorldMinY(), NMTileManifest.WorldMaxX(), NMTileManifest.WorldMaxY());
        let L = NMDebugLayer.Fill(api, 50000);
        let r = NMItemRenderer.Create(api, new inkCanvas(), 1.0);
        let bounds = NMRect.Create(NMTileManifest.WorldMinX(), NMTileManifest.WorldMinY(), NMTileManifest.WorldMaxX(), NMTileManifest.WorldMaxY());
        let cam = NMCamera.Create(1880.0, 1480.0, bounds, 0.5, 16.0);
        cam.SetCenter(L.px[0], L.py[0]);   // inside a neighbourhood cluster: the densest view
        let mpps: array<Float> = [0.5, 1.0, 2.0, 4.0, 5.5];
        let line = "";
        for m in mpps {
            cam.SetMpp(m);
            let pass = 0;
            while pass < 2 {
                r.noDeclutter = pass == 0;
                let t0 = NMClock.NowMs();
                let n = 0;
                while n < 5 {
                    r.Invalidate();
                    r.Update(cam, 1880.0, 1480.0);
                    n += 1;
                }
                let ms = (NMClock.NowMs() - t0) / 5.0;
                line += (pass == 0 ? " mpp " + FloatToStringPrec(m, 1) + " off " : " on ") + FloatToStringPrec(ms, 2) + "ms/" + ToString(r.chipsUsed)
                    + (pass == 1 ? " culled " + ToString(r.culled) : "");
                pass += 1;
            }
        }
        NMLog.Info("TEST|INFO|declutter.cost|50000 debug items:" + line);
    }
}
