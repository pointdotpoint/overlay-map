module NightMap

// Self-tests for the renderer's cost work (occupied-cell lists, shared ring order). Called from NMSelfTest.Run().
// The full ring-order cell scan is kept reachable through NMItemRenderer.forceScan and is the reference behaviour.
public class NMRendSnap {
    public let chips: Int32;
    public let candX: array<Float>;
    public let candY: array<Float>;
    public let candKind: array<Int32>;
    public let candLayer: array<Int32>;
    public let candItem: array<Int32>;
    public let candSlot: array<Int32>;

    public static func Take(r: ref<NMItemRenderer>) -> ref<NMRendSnap> {
        let s = new NMRendSnap();
        s.chips = r.chipsUsed;
        s.candX = r.candX;
        s.candY = r.candY;
        s.candKind = r.candKind;
        s.candLayer = r.candLayer;
        s.candItem = r.candItem;
        s.candSlot = r.candSlot;
        return s;
    }

    // "" when identical (exact float equality), else the first difference.
    public static func Diff(a: ref<NMRendSnap>, b: ref<NMRendSnap>) -> String {
        if a.chips != b.chips {
            return "counts " + ToString(a.chips) + " vs " + ToString(b.chips);
        }
        let n = ArraySize(a.candX);
        let i = 0;
        while i < n {
            if a.candX[i] != b.candX[i] || a.candY[i] != b.candY[i] || a.candKind[i] != b.candKind[i]
                || a.candLayer[i] != b.candLayer[i] || a.candItem[i] != b.candItem[i] || a.candSlot[i] != b.candSlot[i] {
                return "cand " + ToString(i);
            }
            i += 1;
        }
        return "";
    }
}

public abstract class NMPerfTests {
    public static func Run(t: ref<NMSelfTest>) {
        NMPerfTests.OccupiedCases(t);
        NMPerfTests.EquivalenceCases(t);
        NMPerfTests.GrowReuseCases(t);
        NMPerfTests.PhotoSlotReuseCases(t);
        NMPerfTests.ImageCacheCases(t);
    }

    // The occupied lists must equal the set of non-empty cells after any add/move/update/remove sequence.
    public static func OccErr(L: ref<NightMapLayer>) -> String {
        let level = 0;
        while level < 3 {
            let base = NMGrid.Base(level);
            let cells = NMGrid.Side(level) * NMGrid.Side(level);
            let nonEmpty = 0;
            let k = 0;
            while k < cells {
                if L.cnt[base + k] > 0 {
                    nonEmpty += 1;
                    let p = L.occPos[base + k];
                    if p < 0 || p >= L.occN[level] || L.occ[base + p] != base + k { return "occPos wrong level=" + ToString(level) + " cell=" + ToString(k); }
                } else if L.occPos[base + k] != -1 {
                    return "empty cell listed level=" + ToString(level) + " cell=" + ToString(k);
                }
                k += 1;
            }
            let so = 1;
            while so < L.occN[level] {
                if L.occ[base + so - 1] >= L.occ[base + so] { return "occ not sorted level=" + ToString(level) + " at " + ToString(so); }
                so += 1;
            }
            if nonEmpty != L.occN[level] { return "occN " + ToString(L.occN[level]) + " != non-empty " + ToString(nonEmpty) + " level=" + ToString(level); }
            level += 1;
        }
        return "";
    }

    private static func OccupiedCases(t: ref<NMSelfTest>) {
        let api = NightMap.Create();
        api.SetWorld(-6000.0, -4600.0, 4600.0, 7400.0);
        let L = api.CreateLayer(n"test.occ", "Occ", 3);
        L.SetCategory(n"test.a", "A", NMTheme.Cyan());
        let ids: array<Int32>;
        let i = 0;
        while i < 200 {
            ArrayPush(ids, L.Add(NightMapItem.Create(new Vector4(Cast<Float>((i * 797) % 9000 - 4500), Cast<Float>((i * 1291) % 9000 - 3000), 0.0, 1.0), n"test.a", r"x\\y.inkatlas", n"p")));
            i += 1;
        }
        let err = NMPerfTests.OccErr(L);
        t.Check("occ.after_add", Equals(err, "") && L.occN[0] > 0, err);
        i = 0;
        while i < 200 {
            if i % 3 == 0 {
                L.Move(ids[i], new Vector4(Cast<Float>((i * 313) % 9000 - 4500), Cast<Float>((i * 71) % 9000 - 3000), 0.0, 1.0));
            } else if i % 3 == 1 {
                L.Remove(ids[i]);
            } else {
                L.Update(ids[i], NightMapItem.Create(new Vector4(Cast<Float>((i * 53) % 9000 - 4500), Cast<Float>((i * 97) % 9000 - 3000), 0.0, 1.0), n"test.a", r"x\\y.inkatlas", n"p"));
            }
            i += 1;
        }
        err = NMPerfTests.OccErr(L);
        t.Check("occ.after_move_update_remove", Equals(err, ""), err);
        i = 0;
        while i < 200 {
            L.Remove(ids[i]);
            i += 1;
        }
        t.Check("occ.empty_after_remove_all", Equals(NMPerfTests.OccErr(L), "") && L.occN[0] == 0 && L.occN[1] == 0 && L.occN[2] == 0, ToString(L.occN[0]));
        L.Add(NightMapItem.Create(new Vector4(10.0, 10.0, 0.0, 1.0), n"test.a", r"x\\y.inkatlas", n"p"));
        L.Clear();
        t.Check("occ.after_clear", Equals(NMPerfTests.OccErr(L), "") && L.occN[0] == 0, "");
        L.Add(NightMapItem.Create(new Vector4(10.0, 10.0, 0.0, 1.0), n"test.a", r"x\\y.inkatlas", n"p"));
        t.Check("occ.add_after_clear", Equals(NMPerfTests.OccErr(L), "") && L.occN[0] == 1, "");
    }

    // Several layers (dense Debug content plus sparse icon layers, one mutated), several zooms and centres: the
    // occupied-list path must give exactly the full ring scan's output (counts, positions, items, slots, order).
    private static func EquivalenceCases(t: ref<NMSelfTest>) {
        let api = NightMap.Create();
        api.SetWorld(NMTileManifest.WorldMinX(), NMTileManifest.WorldMinY(), NMTileManifest.WorldMaxX(), NMTileManifest.WorldMaxY());
        let dbg = NMDebugLayer.Fill(api, 3000);
        let minX = NMTileManifest.WorldMinX();
        let minY = NMTileManifest.WorldMinY();
        let spanX = NMTileManifest.WorldMaxX() - minX;
        let spanY = NMTileManifest.WorldMaxY() - minY;
        let sp = api.CreateLayer(n"test.sparse1", "Sparse 1", 40);
        sp.SetPinStyle(NightMapPinStyle.Icon);
        sp.SetCategory(n"test.s1a", "S1A", NMTheme.Yellow());
        sp.SetCategory(n"test.s1b", "S1B", NMTheme.Pink());
        let sp2 = api.CreateLayer(n"test.sparse2", "Sparse 2", 30);
        sp2.SetCategory(n"test.s2a", "S2A", NMTheme.Cyan());
        sp2.SetTier(NightMapTier.Major);   // the only layer left at the far zooms
        let ids: array<Int32>;
        let i = 0;
        while i < 120 {
            let fx = Cast<Float>((i * 7919) % 1000) / 1000.0;
            let fy = Cast<Float>((i * 104729) % 1000) / 1000.0;
            let pos = new Vector4(minX + 1000.0 + fx * (spanX - 2000.0), minY + 1000.0 + fy * (spanY - 2000.0), 0.0, 1.0);
            if i % 2 == 0 {
                ArrayPush(ids, sp.Add(NightMapItem.Create(pos, i % 4 == 0 ? n"test.s1a" : n"test.s1b", NMTheme.UiAtlas(), n"icon_dot")));
            } else {
                sp2.Add(NightMapItem.Create(pos, n"test.s2a", NMTheme.UiAtlas(), n"icon_dot"));
            }
            i += 1;
        }
        i = 0;
        while i < ArraySize(ids) {
            if i % 5 == 0 {
                sp.Remove(ids[i]);
            } else if i % 5 == 1 {
                sp.Move(ids[i], new Vector4(minX + 3000.0 + Cast<Float>(i) * 40.0, minY + 5000.0, 0.0, 1.0));
            }
            i += 1;
        }
        // A wide layer (the formerly capped case): 400 items on a lattice over the whole city, one per few cells.
        let wide = api.CreateLayer(n"test.wide", "Wide", 20);
        wide.SetPinStyle(NightMapPinStyle.Icon);
        wide.SetCategory(n"test.w", "W", NMTheme.Pink());
        i = 0;
        while i < 400 {
            // A 20 x 20 lattice: each item in its own level-0 cell while the spacing exceeds a cell.
            let wx = minX + 1000.0 + Cast<Float>(i % 20) / 20.0 * (spanX - 2000.0) + Cast<Float>(i % 7) * 13.0;
            let wy = minY + 1000.0 + Cast<Float>(i / 20) / 20.0 * (spanY - 2000.0);
            wide.Add(NightMapItem.Create(new Vector4(wx, wy, 0.0, 1.0), n"test.w", NMTheme.UiAtlas(), n"icon_dot"));
            i += 1;
        }
        let canvas = new inkCanvas();
        let r = NMItemRenderer.Create(api, canvas, 1.0);
        let bounds = NMRect.Create(minX, minY, NMTileManifest.WorldMaxX(), NMTileManifest.WorldMaxY());
        let cam = NMCamera.Create(1880.0, 1480.0, bounds, 0.5, 16.0);
        let mpps: array<Float> = [0.6, 1.2, 2.0, 5.1, 5.3, 8.0, 16.0];
        let cx: array<Float> = [(bounds.minX + bounds.maxX) * 0.5, minX + 5000.0, minX + 3200.0];
        let cy: array<Float> = [(bounds.minY + bounds.maxY) * 0.5, minY + 5000.0, minY + 5000.0];
        let bad = "";
        let runs = 0;
        let sawCapped = false;
        let sawFar = false;
        let sawChip = false;
        let c = 0;
        while c < 3 {
            for m in mpps {
                cam.SetCenter(cx[c], cy[c]);
                cam.SetMpp(m);
                r.forceScan = true;
                r.Invalidate();
                r.Update(cam, 1880.0, 1480.0);
                let ref0 = NMRendSnap.Take(r);
                r.forceScan = false;
                r.Invalidate();
                r.Update(cam, 1880.0, 1480.0);
                let got = NMRendSnap.Take(r);
                let d = NMRendSnap.Diff(ref0, got);
                if NotEquals(d, "") {
                    bad += "c" + ToString(c) + " mpp " + FloatToStringPrec(m, 1) + ": " + d + "; ";
                }
                if ref0.chips >= NMTheme.ChipBudget() { sawCapped = true; }
                if m >= 8.0 && ref0.chips > 0 && ref0.chips < NMTheme.ChipBudget() { sawFar = true; }
                if ref0.chips > 0 { sawChip = true; }
                runs += 1;
            }
            c += 1;
        }
        t.Check("perf.occ_identical_to_scan", Equals(bad, "") && runs == 21, bad);
        t.Check("perf.equivalence_exercised", sawCapped && sawFar && sawChip && dbg.count == 3000, ToString(sawCapped) + ToString(sawFar) + ToString(sawChip));
        // The wide layer must really have > 150 occupied level-0 cells (the old 64 cap's territory) over the city.
        t.Check("perf.wide_layer_exceeds_old_cap", wide.occN[0] > 150 && Equals(NMPerfTests.OccErr(wide), ""), ToString(wide.occN[0]));
        // Far zoom costs less than it draws: at 16 m/unit the Minor layers (3,000 debug items among them) are skipped
        // whole, and every Major item is placed once.
        cam.SetCenter((bounds.minX + bounds.maxX) * 0.5, (bounds.minY + bounds.maxY) * 0.5);
        cam.SetMpp(16.0);
        r.Invalidate();
        r.Update(cam, 1880.0, 1480.0);
        let others = 0;
        for li in r.candLayer {
            if li != sp2.index { others += 1; }
        }
        t.Check("perf.far_zoom_major_only", r.chipsUsed == sp2.count && others == 0, ToString(r.chipsUsed) + " of " + ToString(sp2.count) + ", others " + ToString(others));
    }

    // ---- selection grow vs slot reuse (renderer slots are reassigned in placement order) ----

    private static func GrowScale(r: ref<NMItemRenderer>, slot: Int32) -> Float {
        let v = r.chipBg[slot].GetScale();   // bind to a local: a field of a call temporary reads garbage in-game
        return v.X;
    }

    // Two icon pins, A at the camera centre (first placed, so the top slot) and B 300 m east. A is selected and
    // fully grown. Returns the renderer; ids and the layer come back through out-style fields on the arguments.
    private static func GrowSetup(out api: ref<NightMap>, out cam: ref<NMCamera>, out L: ref<NightMapLayer>, out ids: array<Int32>) -> ref<NMItemRenderer> {
        api = NightMap.Create();
        api.SetWorld(-6000.0, -4600.0, 4600.0, 7400.0);
        L = api.CreateLayer(n"test.grow", "Grow", 5);
        L.SetPinStyle(NightMapPinStyle.Icon);
        L.SetCategory(n"test.g", "G", NMTheme.Cyan());
        ArrayClear(ids);
        ArrayPush(ids, L.Add(NightMapItem.Create(new Vector4(100.0, 100.0, 0.0, 1.0), n"test.g", NMTheme.UiAtlas(), n"icon_dot")));
        ArrayPush(ids, L.Add(NightMapItem.Create(new Vector4(400.0, 100.0, 0.0, 1.0), n"test.g", NMTheme.UiAtlas(), n"icon_dot")));
        let canvas = new inkCanvas();
        let r = NMItemRenderer.Create(api, canvas, 1.0);
        cam = NMCamera.Create(1880.0, 1480.0, NMRect.Create(-6000.0, -4600.0, 4600.0, 7400.0), 0.5, 16.0);
        cam.SetCenter(100.0, 100.0);
        cam.SetMpp(0.6);
        r.Update(cam, 1880.0, 1480.0);
        r.ApplySelection(0, 0, 10000.0);   // candidate 0 is A; one big dt completes the grow
        return r;
    }

    // A slot goes from a photo pin to a normal marker: both of its widgets must come back, or the marker is placed
    // but invisible (seen as markers vanishing at random while panning, since slots are handed out in placement order).
    private static func PhotoSlotReuseCases(t: ref<NMSelfTest>) {
        let api: ref<NightMap>;
        let cam: ref<NMCamera>;
        let L: ref<NightMapLayer>;
        let ids: array<Int32>;
        let top = NMTheme.ChipBudget() - 1;
        let r = NMPerfTests.GrowSetup(api, cam, L, ids);
        let photo = NightMapItem.Create(new Vector4(100.0, 100.0, 0.0, 1.0), n"test.g", NMTheme.UiAtlas(), n"icon_dot");
        photo.shotHash = 5u;
        L.Update(ids[0], photo);
        r.Update(cam, 1880.0, 1480.0);
        L.Update(ids[0], NightMapItem.Create(new Vector4(100.0, 100.0, 0.0, 1.0), n"test.g", NMTheme.UiAtlas(), n"icon_dot"));
        r.Update(cam, 1880.0, 1480.0);
        t.Check("chip.visible_after_photo_slot", r.candSlot[0] == top && r.chipIcon[top].IsVisible() && r.chipBg[top].IsVisible(),
            "slot " + ToString(r.candSlot[0]) + " icon " + ToString(r.chipIcon[top].IsVisible()) + " bg " + ToString(r.chipBg[top].IsVisible()));
    }

    private static func GrowReuseCases(t: ref<NMSelfTest>) {
        let api: ref<NightMap>;
        let cam: ref<NMCamera>;
        let L: ref<NightMapLayer>;
        let ids: array<Int32>;
        let top = NMTheme.ChipBudget() - 1;
        let r = NMPerfTests.GrowSetup(api, cam, L, ids);
        t.Check("grow.setup_grown", r.growSlot == top && r.growT == 1.0 && t.Near(NMPerfTests.GrowScale(r, top), NMTheme.VanillaEmphScale(), 0.001),
            ToString(r.growSlot) + " " + t.F(r.growT) + " " + t.F(NMPerfTests.GrowScale(r, top)));
        // 1. the selected item is removed and the slot is reused by the other pin
        L.Remove(ids[0]);
        r.Update(cam, 1880.0, 1480.0);
        t.Check("grow.reset_on_slot_reuse", r.growSlot == -1 && ArraySize(r.candSlot) == 1 && r.candSlot[0] == top && t.Near(NMPerfTests.GrowScale(r, top), 1.0, 0.0001),
            ToString(r.growSlot) + " " + t.F(NMPerfTests.GrowScale(r, top)));
        // 2. the layer is hidden: the grown slot is hidden and reset
        let r2 = NMPerfTests.GrowSetup(api, cam, L, ids);
        L.SetVisible(false);
        r2.Update(cam, 1880.0, 1480.0);
        t.Check("grow.reset_on_hide", r2.growSlot == -1 && r2.chipsUsed == 0 && t.Near(NMPerfTests.GrowScale(r2, top), 1.0, 0.0001), ToString(r2.growSlot) + " " + t.F(NMPerfTests.GrowScale(r2, top)));
        // 3. the pin turns emphasised in place (style flip on the same slot): the grow state is dropped
        let r3 = NMPerfTests.GrowSetup(api, cam, L, ids);
        L.Update(ids[0], NightMapItem.Create(new Vector4(100.0, 100.0, 0.0, 1.0), n"test.g", NMTheme.UiAtlas(), n"icon_dot").WithEmphasis(true));
        r3.Update(cam, 1880.0, 1480.0);
        t.Check("grow.reset_on_style_flip", r3.growSlot == -1 && r3.chipStyle[top] == 2, ToString(r3.growSlot) + " style " + ToString(r3.chipStyle[top]));
        // 0. a mid-selection update of the selected pin's opacity keeps it grown at full opacity (not dim at 1.3x)
        let r0 = NMPerfTests.GrowSetup(api, cam, L, ids);
        L.Update(ids[0], NightMapItem.Create(new Vector4(100.0, 100.0, 0.0, 1.0), n"test.g", NMTheme.UiAtlas(), n"icon_dot").WithOpacity(0.5));
        r0.Update(cam, 1880.0, 1480.0);
        let want = 0.5;   // base 0.5 * idle opacity, grown to base / idle
        t.Check("grow.keeps_opacity_on_update", r0.growSlot == top && t.Near(r0.chipIcon[top].GetOpacity(), want, 0.001) && t.Near(NMPerfTests.GrowScale(r0, top), NMTheme.VanillaEmphScale(), 0.001),
            t.F(r0.chipIcon[top].GetOpacity()) + " want " + t.F(want));
        // 4. the selected pin moves out of view: its slot is hidden and the grow dropped
        let r4 = NMPerfTests.GrowSetup(api, cam, L, ids);
        L.Move(ids[0], new Vector4(3000.0, 3000.0, 0.0, 1.0));
        r4.Update(cam, 1880.0, 1480.0);
        t.Check("grow.reset_on_cull", r4.growSlot == -1 && t.Near(NMPerfTests.GrowScale(r4, top), 1.0, 0.0001), ToString(r4.growSlot) + " " + t.F(NMPerfTests.GrowScale(r4, top)));
    }

    // Update keeps the resolved image while the image key is unchanged and drops it when the key changes.
    private static func ImageCacheCases(t: ref<NMSelfTest>) {
        let api = NightMap.Create();
        api.SetWorld(-6000.0, -4600.0, 4600.0, 7400.0);
        let L = api.CreateLayer(n"test.img", "Img", 5);
        L.SetCategory(n"test.i", "I", NMTheme.Cyan());
        let id = L.Add(NightMapItem.Image(new Vector4(0.0, 0.0, 0.0, 1.0), n"test.i", "photo/a"));
        L.imageResolved[id] = "resolved/a";
        L.Update(id, NightMapItem.Image(new Vector4(5.0, 5.0, 0.0, 1.0), n"test.i", "photo/a"));
        t.Check("update.keeps_resolved_image", Equals(L.imageResolved[id], "resolved/a"), L.imageResolved[id]);
        L.Update(id, NightMapItem.Image(new Vector4(5.0, 5.0, 0.0, 1.0), n"test.i", "photo/b"));
        t.Check("update.resets_resolved_on_new_image", Equals(L.imageResolved[id], "") && Equals(L.image[id], "photo/b"), L.imageResolved[id]);
    }
}
