module NightMap

// Self-tests for the renderer's cost work (occupied-cell lists, shared ring order). Called from NMSelfTest.Run().
// The old per-cell scan is kept reachable through NMItemRenderer.forceScan and is the reference behaviour.
public class NMRendSnap {
    public let chips: Int32;
    public let clusters: Int32;
    public let candX: array<Float>;
    public let candY: array<Float>;
    public let candKind: array<Int32>;
    public let candLayer: array<Int32>;
    public let candItem: array<Int32>;
    public let candSlot: array<Int32>;
    public let clWx: array<Float>;
    public let clWy: array<Float>;
    public let clTotal: array<Int32>;
    public let clKey: array<Int32>;
    public let clCats: array<Int32>;
    public let clCatCount: array<Int32>;

    public static func Take(r: ref<NMItemRenderer>) -> ref<NMRendSnap> {
        let s = new NMRendSnap();
        s.chips = r.chipsUsed;
        s.clusters = r.clustersUsed;
        s.candX = r.candX;
        s.candY = r.candY;
        s.candKind = r.candKind;
        s.candLayer = r.candLayer;
        s.candItem = r.candItem;
        s.candSlot = r.candSlot;
        let i = 0;
        while i < r.clustersUsed {
            ArrayPush(s.clWx, r.clWx[i]);
            ArrayPush(s.clWy, r.clWy[i]);
            ArrayPush(s.clTotal, r.clTotal[i]);
            ArrayPush(s.clKey, r.clKey[i]);
            let k = 0;
            while k < 6 {
                ArrayPush(s.clCats, r.clCats[i * 6 + k]);
                ArrayPush(s.clCatCount, r.clCatCount[i * 6 + k]);
                k += 1;
            }
            i += 1;
        }
        return s;
    }

    // "" when identical (exact float equality), else the first difference.
    public static func Diff(a: ref<NMRendSnap>, b: ref<NMRendSnap>) -> String {
        if a.chips != b.chips || a.clusters != b.clusters {
            return "counts " + ToString(a.chips) + "/" + ToString(a.clusters) + " vs " + ToString(b.chips) + "/" + ToString(b.clusters);
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
        i = 0;
        while i < a.clusters {
            if a.clWx[i] != b.clWx[i] || a.clWy[i] != b.clWy[i] || a.clTotal[i] != b.clTotal[i] || a.clKey[i] != b.clKey[i] {
                return "cluster " + ToString(i);
            }
            let k = 0;
            while k < 6 {
                if a.clCats[i * 6 + k] != b.clCats[i * 6 + k] || a.clCatCount[i * 6 + k] != b.clCatCount[i * 6 + k] {
                    return "cluster cats " + ToString(i);
                }
                k += 1;
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
    // occupied-list path must give exactly the scan path's output (counts, positions, keys, categories).
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
        let canvas = new inkCanvas();
        let r = NMItemRenderer.Create(api, canvas, 1.0);
        let bounds = NMRect.Create(minX, minY, NMTileManifest.WorldMaxX(), NMTileManifest.WorldMaxY());
        let cam = NMCamera.Create(1880.0, 1480.0, bounds, 0.5, 16.0);
        let mpps: array<Float> = [0.6, 1.2, 2.0, 5.1, 5.3, 8.0, 16.0];
        let cx: array<Float> = [(bounds.minX + bounds.maxX) * 0.5, minX + 5000.0, minX + 3200.0];
        let cy: array<Float> = [(bounds.minY + bounds.maxY) * 0.5, minY + 5000.0, minY + 5000.0];
        let bad = "";
        let runs = 0;
        let sawCluster = false;
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
                if ref0.clusters > 0 { sawCluster = true; }
                if ref0.chips > 0 { sawChip = true; }
                runs += 1;
            }
            c += 1;
        }
        t.Check("perf.occ_identical_to_scan", Equals(bad, "") && runs == 21, bad);
        t.Check("perf.equivalence_exercised", sawCluster && sawChip && dbg.count == 3000, "");
        // Conservation with the sparse path: at 16 m/unit every alive item of every layer is drawn once.
        cam.SetCenter((bounds.minX + bounds.maxX) * 0.5, (bounds.minY + bounds.maxY) * 0.5);
        cam.SetMpp(16.0);
        r.Invalidate();
        r.Update(cam, 1880.0, 1480.0);
        let total = r.chipsUsed;
        let k = 0;
        while k < r.clustersUsed {
            total += r.clTotal[k];
            k += 1;
        }
        t.Check("perf.conservation_all_layers", total == dbg.count + sp.count + sp2.count, ToString(total) + " of " + ToString(dbg.count + sp.count + sp2.count));
    }
}
