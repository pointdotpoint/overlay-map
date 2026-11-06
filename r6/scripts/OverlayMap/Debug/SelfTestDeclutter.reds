module OverlayMap

// Self-test group for the declutter (screen-space collision culling of markers). Called from NMSelfTest.Run().
// Two markers collide when their centres are closer than DeclutterOverlap x (rA + rB); the later one in placement
// order (tier, priority, nearest-first) is skipped unless it is an Always-tier item or the current selection.
public abstract class NMDeclutterTests {
    private static func W() -> Float { return 1880.0; }
    private static func H() -> Float { return 1480.0; }

    private static func Api() -> ref<OverlayMap> {
        let api = OverlayMap.Create();
        api.SetWorld(-6000.0, -4600.0, 4600.0, 7400.0);
        return api;
    }

    private static func Cam(mpp: Float) -> ref<NMCamera> {
        let cam = NMCamera.Create(NMDeclutterTests.W(), NMDeclutterTests.H(), NMRect.Create(-6000.0, -4600.0, 4600.0, 7400.0), 0.5, 16.0);
        cam.SetCenter(0.0, 0.0);
        cam.SetMpp(mpp);
        return cam;
    }

    private static func Layer(api: ref<OverlayMap>, id: CName, priority: Int32, tier: OverlayMapTier) -> ref<OverlayMapLayer> {
        let L = api.CreateLayer(id, "Declutter", priority);
        L.SetTier(tier);
        L.SetCategory(n"test.dc", "DC", NMTheme.Cyan());
        return L;
    }

    private static func At(L: ref<OverlayMapLayer>, x: Float, y: Float) -> Int32 {
        return L.Add(OverlayMapItem.Create(new Vector4(x, y, 0.0, 1.0), n"test.dc", NMTheme.UiAtlas(), n"icon_dot"));
    }

    private static func Placed(r: ref<NMItemRenderer>, L: ref<OverlayMapLayer>, id: Int32) -> Bool {
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
        t.Check("declutter.token", t.Near(NMTheme.DeclutterOverlap(), 1.0, 0.0001), t.F(NMTheme.DeclutterOverlap()));

        // 1. Two Minor items of one layer on the same spot: one is drawn, the other skipped without a slot.
        let api = NMDeclutterTests.Api();
        let L = NMDeclutterTests.Layer(api, n"test.dc.overlap", 5, OverlayMapTier.Minor);
        NMDeclutterTests.At(L, 0.0, 0.0);
        NMDeclutterTests.At(L, 0.0, 0.0);
        let r = NMItemRenderer.Create(api, new inkCanvas(), 1.0);
        r.Update(NMDeclutterTests.Cam(2.0), w, h);
        t.Check("declutter.overlap_skipped", ArraySize(r.candX) == 1 && r.chipsUsed == 1 && r.culled == 1, NMDeclutterTests.Info(r));

        // 2. A Minor (higher priority) and a Major item on the same spot: the tier wins, the Minor one is culled.
        let api2 = NMDeclutterTests.Api();
        let mi = NMDeclutterTests.Layer(api2, n"test.dc.minor", 50, OverlayMapTier.Minor);
        let ma = NMDeclutterTests.Layer(api2, n"test.dc.major", 1, OverlayMapTier.Major);
        let miId = NMDeclutterTests.At(mi, 0.0, 0.0);
        let maId = NMDeclutterTests.At(ma, 0.0, 0.0);
        let r2 = NMItemRenderer.Create(api2, new inkCanvas(), 1.0);
        r2.Update(NMDeclutterTests.Cam(2.0), w, h);
        t.Check("declutter.major_wins", NMDeclutterTests.Placed(r2, ma, maId) && !NMDeclutterTests.Placed(r2, mi, miId) && r2.culled == 1 && r2.chipsUsed == 1,
            NMDeclutterTests.Info(r2));

        // 3. Two items three radii apart on screen (hex chips at full scale: r = ChipSize / 2) are both drawn.
        let api3 = NMDeclutterTests.Api();
        let L3 = NMDeclutterTests.Layer(api3, n"test.dc.spaced", 5, OverlayMapTier.Minor);
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
        let al = NMDeclutterTests.Layer(api4, n"test.dc.always", 1, OverlayMapTier.Always);
        let mj = NMDeclutterTests.Layer(api4, n"test.dc.major4", 90, OverlayMapTier.Major);
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
        let s5 = NMDeclutterTests.Layer(api5, n"test.dc.sel", 5, OverlayMapTier.Minor);
        s5.SetPinStyle(OverlayMapPinStyle.Icon);
        let sId = NMDeclutterTests.At(s5, 0.0, 0.0);
        let r5 = NMItemRenderer.Create(api5, new inkCanvas(), 1.0);
        let c5 = NMCrosshair.Create();
        let cam5 = NMDeclutterTests.Cam(2.0);
        r5.Update(cam5, w, h);
        c5.Update(r5, w, h, 1.0, 0.0);
        r5.ApplySelection(c5.sel, c5.selKind, 16.0);
        let picked = c5.selKind == 0 && c5.selLayer == s5.index && c5.selItem == sId;
        let m5 = NMDeclutterTests.Layer(api5, n"test.dc.selmajor", 1, OverlayMapTier.Major);
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
        let L6 = NMDeclutterTests.Layer(api6, n"test.dc.zoom", 5, OverlayMapTier.Minor);
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
        let L7 = NMDeclutterTests.Layer(api7, n"test.dc.dense", 5, OverlayMapTier.Minor);
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
        // stop testing at CullCap culls (a Major layer has only the relayout's bound).
        let api8 = NMDeclutterTests.Api();
        let L8 = NMDeclutterTests.Layer(api8, n"test.dc.pile", 5, OverlayMapTier.Minor);
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
        let L9 = NMDeclutterTests.Layer(api9, n"test.dc.piles", 5, OverlayMapTier.Major);   // at mpp 16 neighbouring cells collide
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
        let van = NMDeclutterTests.Layer(api10, n"test.dc.vtarot", vt, IntEnum<OverlayMapTier>(Max(vTier, 0)));
        van.SetPinStyle(OverlayMapPinStyle.Icon);
        let tar = NMDeclutterTests.Layer(api10, n"test.dc.ctarot", tp, IntEnum<OverlayMapTier>(ctl.tier));
        let vId = NMDeclutterTests.At(van, 0.0, 0.0);
        let tId = NMDeclutterTests.At(tar, 4.0, 0.0);
        let rc = NMItemRenderer.Create(api10, new inkCanvas(), 1.0);
        rc.Update(NMDeclutterTests.Cam(0.5), w, h);
        t.Check("declutter.collect_tarot_wins", vt > 0 && vTier >= 0 && tp > vt && sp < 50 && NMDeclutterTests.Placed(rc, tar, tId) && !NMDeclutterTests.Placed(rc, van, vId),
            "vanilla " + ToString(vt) + " tier " + ToString(vTier) + " tarot " + ToString(tp) + " tier " + ToString(ctl.tier) + " shard " + ToString(sp) + " " + NMDeclutterTests.Info(rc));

        // 10. The selection survives a saturated relayout: higher-priority piles spend the cull cap before the
        // selected item's low-priority layer is reached, and it must still be placed (it is placed first).
        let api11 = NMDeclutterTests.Api();
        let sel = NMDeclutterTests.Layer(api11, n"test.dc.capsel", 1, OverlayMapTier.Major);
        let selId = NMDeclutterTests.At(sel, 0.0, 0.0);
        let r11 = NMItemRenderer.Create(api11, new inkCanvas(), 1.0);
        let c11 = NMCrosshair.Create();
        let cam11 = NMDeclutterTests.Cam(16.0);
        r11.Update(cam11, w, h);
        c11.Update(r11, w, h, 1.0, 0.0);
        r11.ApplySelection(c11.sel, c11.selKind, 16.0);
        let picked11 = c11.selKind == 0 && c11.selLayer == sel.index && c11.selItem == selId;
        let piles = NMDeclutterTests.Layer(api11, n"test.dc.cappiles", 90, OverlayMapTier.Major);
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

        // 11. A Minor layer's cull cap is its own: a dense high-priority Minor layer that spends its LayerCullCap culls
        // doesn't starve a later, lower-priority one, whose lone item away from the piles is still placed.
        let api13 = NMDeclutterTests.Api();
        let dense = NMDeclutterTests.Layer(api13, n"test.dc.densefirst", 90, OverlayMapTier.Minor);
        i = 0;
        while i < 300 * 12 {
            let dc = i / 12;   // 12 items in each of 300 cells, the left half of the 30 x 20 block
            NMDeclutterTests.At(dense, Cast<Float>(dc % 15 - 15) * 250.0 + 125.0, Cast<Float>(dc / 15 - 10) * 250.0 + 125.0);
            i += 1;
        }
        let lone = NMDeclutterTests.Layer(api13, n"test.dc.lonelater", 5, OverlayMapTier.Minor);
        let loneId = NMDeclutterTests.At(lone, 3000.0, 0.0);
        let r13 = NMItemRenderer.Create(api13, new inkCanvas(), 1.0);
        r13.Update(NMDeclutterTests.Cam(4.0), w, h);
        t.Check("declutter.cap_per_layer", r13.culled == NMItemRenderer.LayerCullCap()
            && NMDeclutterTests.Placed(r13, lone, loneId), NMDeclutterTests.Info(r13));

        // 11b. Major culls don't eat the Minor slices: a Major layer spends its CullCap, two dense Minor layers their
        // LayerCullCap each, and a last, lowest-priority Minor layer is still walked and places its lone item.
        let api14 = NMDeclutterTests.Api();
        let maj = NMDeclutterTests.Layer(api14, n"test.dc.majpiles", 90, OverlayMapTier.Major);
        let minA = NMDeclutterTests.Layer(api14, n"test.dc.minA", 60, OverlayMapTier.Minor);
        let minB = NMDeclutterTests.Layer(api14, n"test.dc.minB", 50, OverlayMapTier.Minor);
        let minC = NMDeclutterTests.Layer(api14, n"test.dc.minC", 5, OverlayMapTier.Minor);
        i = 0;
        while i < 200 * 6 {
            let mc = i / 6;   // 6 items in each of 200 cells: x -3750..-1250 m, 20 rows
            NMDeclutterTests.At(maj, Cast<Float>(mc % 10 - 15) * 250.0 + 125.0, Cast<Float>(mc / 10 - 10) * 250.0 + 125.0);
            i += 1;
        }
        i = 0;
        while i < 60 * 6 {
            let ac = i / 6;   // 60 cells each: A at x -1000..-250 m, B at x 0..750 m
            NMDeclutterTests.At(minA, Cast<Float>(ac % 3 - 4) * 250.0 + 125.0, Cast<Float>(ac / 3 - 10) * 250.0 + 125.0);
            NMDeclutterTests.At(minB, Cast<Float>(ac % 3) * 250.0 + 125.0, Cast<Float>(ac / 3 - 10) * 250.0 + 125.0);
            i += 1;
        }
        let lastId = NMDeclutterTests.At(minC, 3000.0, 0.0);
        let r14 = NMItemRenderer.Create(api14, new inkCanvas(), 1.0);
        r14.Update(NMDeclutterTests.Cam(4.0), w, h);
        t.Check("declutter.minor_slices_after_major", r14.culled == NMItemRenderer.CullCap() + 2 * NMItemRenderer.LayerCullCap()
            && r14.capStops == 3 && NMDeclutterTests.Placed(r14, minC, lastId), "stops " + ToString(r14.capStops) + " " + NMDeclutterTests.Info(r14));

        // 11c. A filter-promoted big layer (1,657 items, like the shards, promoted to Major) still fills mid zoom: the
        // Major cap stops it only after a screenful of markers.
        let api15 = NMDeclutterTests.Api();
        let big = NMDeclutterTests.Layer(api15, n"test.dc.bigpromoted", 40, OverlayMapTier.Minor);
        big.SetPromoted(true);
        i = 0;
        while i < 1657 {
            NMDeclutterTests.At(big, -6000.0 + Cast<Float>((i * 7919) % 10600), -4600.0 + Cast<Float>((i * 104729) % 12000));
            i += 1;
        }
        let r15 = NMItemRenderer.Create(api15, new inkCanvas(), 1.0);
        r15.Update(NMDeclutterTests.Cam(4.0), w, h);
        t.Check("declutter.promoted_big_layer_fills", ArraySize(r15.candX) >= 60 && r15.culled <= NMItemRenderer.CullCap(), NMDeclutterTests.Info(r15));

        // 12. The header is reserved: a pile of Minor and Major items inside the panel's padded title rect is culled,
        // an Always item there stays, and an item just outside the rect is placed. Rects come from a real panel
        // (scale 1, so map units are 4K units) with a district name set.
        let layout12 = NMPanelLayout.Compute(3840.0, 2160.0);
        let panel12 = NMPanel.Build(new inkCanvas(), layout12, NMTheme.DefaultPanelOpacity(), 0, false);
        panel12.districtTitle.SetText("VISTA DEL REY");
        let rects = panel12.HeaderRects();
        panel12.Destroy();
        let q = rects[0];
        let padOk = ArraySize(rects) == 2 && t.Near(q.minX, 88.0 - NMTheme.HeaderPad(), 0.5) && t.Near(q.minY, 80.0 - NMTheme.HeaderPad(), 0.5)
            && q.maxX > 88.0 + 300.0 && rects[1].maxX <= layout12.viewW;
        let api12 = NMDeclutterTests.Api();
        let mi12 = NMDeclutterTests.Layer(api12, n"test.dc.resminor", 50, OverlayMapTier.Minor);
        let ma12 = NMDeclutterTests.Layer(api12, n"test.dc.resmajor", 40, OverlayMapTier.Major);
        let al12 = NMDeclutterTests.Layer(api12, n"test.dc.resalways", 1, OverlayMapTier.Always);
        let cam12 = NMDeclutterTests.Cam(2.0);
        let cy = (q.minY + q.maxY) * 0.5;
        let xs: array<Float> = [q.minX + 4.0, q.minX + 120.0, (q.minX + q.maxX) * 0.5, q.maxX - 120.0, q.maxX - 4.0];
        for x in xs {
            let wp = cam12.MapToWorld(x, cy);
            NMDeclutterTests.At(mi12, wp.X, wp.Y);
            NMDeclutterTests.At(ma12, wp.X, wp.Y);
        }
        let ac = cam12.MapToWorld(q.minX + 300.0, cy);
        let aId = NMDeclutterTests.At(al12, ac.X, ac.Y);
        let out = cam12.MapToWorld(q.maxX + NMTheme.ChipSize() * 0.5 + 4.0, cy);   // its circle clears the rect
        let outId = NMDeclutterTests.At(mi12, out.X, out.Y);
        let r12 = NMItemRenderer.Create(api12, new inkCanvas(), 1.0);
        r12.SetReserved(rects);
        r12.Update(cam12, w, h);
        let anyIn = false;
        let k = 0;
        while k < ArraySize(xs) {   // ids 0..4 of both layers are the pile; the Minor layer's id 5 is the outside one
            if NMDeclutterTests.Placed(r12, mi12, k) || NMDeclutterTests.Placed(r12, ma12, k) { anyIn = true; }
            k += 1;
        }
        t.Check("declutter.header_reserved", padOk && !anyIn && NMDeclutterTests.Placed(r12, al12, aId) && NMDeclutterTests.Placed(r12, mi12, outId),
            ToString(padOk) + ToString(anyIn) + " rect " + t.F(q.minX) + "," + t.F(q.minY) + "-" + t.F(q.maxX) + "," + t.F(q.maxY) + " " + NMDeclutterTests.Info(r12));

        // 13. Panning never drops a pin that stays in view (the shards bug, 2026-11-02). A pile of 70 at (-100, 0) spends
        // the layer's whole cull slice in its own cell, and a lone item sits at (100, 50), 400 px away at mpp 0.5. With
        // the view centre in the lone item's cell, the ring walk places it before the pile; 20 m west, the centre is in
        // the pile's cell, the pile runs first and the slice ends before the lone item. Persistence keeps it placed.
        let api13 = NMDeclutterTests.Api();
        let pan = NMDeclutterTests.Layer(api13, n"test.dc.pan", 40, NightMapTier.Minor);
        i = 0;
        while i < 70 {
            NMDeclutterTests.At(pan, -100.0, 0.0);
            i += 1;
        }
        let lone = NMDeclutterTests.At(pan, 100.0, 50.0);
        let cam13 = NMDeclutterTests.Cam(0.5);
        let r13p = NMItemRenderer.Create(api13, new inkCanvas(), 1.0);
        cam13.SetCenter(10.0, 25.0);
        r13p.Update(cam13, w, h);
        let firstIn = NMDeclutterTests.Placed(r13p, pan, lone);
        cam13.SetCenter(-10.0, 25.0);
        r13p.Update(cam13, w, h);
        t.Check("declutter.pan_keeps_placed", firstIn && NMDeclutterTests.Placed(r13p, pan, lone),
            ToString(firstIn) + " " + NMDeclutterTests.Info(r13p));
        // A fresh renderer at the second view still walks from scratch: the pile's cell first, so the lone item is out.
        let r13f = NMItemRenderer.Create(api13, new inkCanvas(), 1.0);
        r13f.Update(cam13, w, h);
        t.Check("declutter.fresh_walk_unchanged", !NMDeclutterTests.Placed(r13f, pan, lone)
            && r13f.culled == NMItemRenderer.LayerCullCap(), NMDeclutterTests.Info(r13f));
        // Persistence keeps the layer order: a higher-priority marker added on the lone item's spot still wins.
        let over = NMDeclutterTests.Layer(api13, n"test.dc.panover", 90, NightMapTier.Major);
        NMDeclutterTests.At(over, 100.0, 50.0);
        r13p.Update(cam13, w, h);
        t.Check("declutter.persist_yields_to_higher", !NMDeclutterTests.Placed(r13p, pan, lone), NMDeclutterTests.Info(r13p));
        NMDeclutterTests.Cost();
    }

    // Relayout cost with and without the declutter over the perf suite's biggest item layer (logged, not checked:
    // timings need the precise clock and vary with the machine).
    private static func Cost() {
        if !NMClock.Precise() { return; }
        let api = OverlayMap.Create();
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
