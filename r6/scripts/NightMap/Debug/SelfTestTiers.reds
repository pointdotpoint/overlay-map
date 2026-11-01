module NightMap

// Self-test group for marker tiers (spec 2026-11-01 visual overhaul, section 7). Called from NMSelfTest.Run().
public abstract class NMTierTests {
    public static func Run(t: ref<NMSelfTest>) {
        t.Check("tier.minor_fades", NMTiers.Fade(2, 4.0) == 1.0 && t.Near(NMTiers.Fade(2, 5.0), 0.5, 0.001) && NMTiers.Fade(2, 6.0) == 0.0, "");
        t.Check("tier.major_stays", NMTiers.Fade(1, 16.0) == 1.0, "");
        t.Check("tier.always_at_max", NMTiers.Fade(0, NightMapSystem.MaxMpp()) == 1.0 && NMTiers.Scale(0, 16.0) == 1.0, "");
        t.Check("tier.scale_shrinks", NMTiers.Scale(2, 2.0) == 1.0 && t.Near(NMTiers.Scale(2, 8.0), 0.7, 0.01) && t.Near(NMTiers.Scale(1, 4.0), 0.85, 0.01), "");
        let api = NMVanillaTests.TestApi();
        let a = api.CreateLayer(n"Tier.A", "A", 10);
        let m = api.CreateLayer(n"Tier.M", "M", 11);
        a.SetTier(NightMapTier.Always);
        m.SetPromoted(true);
        t.Check("tier.promoted_effective", m.EffectiveTier() == 1 && a.EffectiveTier() == 0 && m.tier == 2, "");
        let amb = api.CreateLayer(n"Tier.Amb", "Amb", 12);
        amb.SetAmbient(true);
        let ambOk = NMTiers.LayerFade(amb, 2.5) == 1.0 && t.Near(NMTiers.LayerFade(amb, 3.25), 0.5, 0.001) && NMTiers.LayerFade(amb, 4.0) == 0.0
            && NMTiers.LayerFade(a, 16.0) == 1.0;
        amb.SetPromoted(true);
        ambOk = ambOk && NMTiers.LayerFade(amb, 16.0) == 1.0;   // promoted by a filter: Major, the ambient fade no longer applies
        t.Check("tier.ambient_fades_early", ambOk, t.F(NMTiers.LayerFade(amb, 3.25)));
        let rev = api.revision;
        m.SetPromoted(false);
        m.SetPromoted(true);
        t.Check("tier.filter_promotes_now", api.revision > rev, "");
        let s = new NightMapSettings();
        let v = NMVanilla.Create(api, GetGameInstance());
        let empty: array<ref<IMappin>>;
        v.PollFrom(empty, 0ul);
        let q = v.LayerForSlot(v.catalog.FilterIndexOf(gamedataMappinVariant.DefaultQuestVariant));
        let ft = v.LayerForSlot(v.catalog.FilterIndexOf(gamedataMappinVariant.FastTravelVariant));
        let gigs = v.LayerForSlot(v.catalog.FilterIndexOf(gamedataMappinVariant.RetrievingVariant));
        let ncpd = v.LayerForSlot(v.catalog.FilterIndexOf(gamedataMappinVariant.GangWatchVariant));
        let assigned = q.tier == 1 && ft.tier == 1 && v.pinned.tier == 0 && gigs.tier == 2 && ncpd.tier == 2 && ncpd.ambient && !gigs.ambient && !ft.ambient;
        v.ApplyFilters(1, s);
        let on = gigs.promoted && gigs.EffectiveTier() == 1;
        v.ApplyFilters(0, s);
        t.Check("tier.vanilla_assignment", assigned && on && !gigs.promoted, ToString(q.tier) + ToString(ft.tier) + ToString(gigs.tier));
        NMTierTests.RenderCases(t);
    }

    // ---- the renderer: no clusters, tiers scale and fade instead (spec section 7) ----

    private static func Cam() -> ref<NMCamera> {
        let cam = NMCamera.Create(1880.0, 1480.0, NMRect.Create(-6000.0, -4600.0, 4600.0, 7400.0), 0.5, 16.0);
        cam.SetCenter(0.0, 0.0);
        return cam;
    }

    // Chebyshev ring of the item's level-0 cell around the camera's cell: the renderer's nearest-first order.
    private static func Ring(L: ref<NightMapLayer>, id: Int32, cam: ref<NMCamera>) -> Int32 {
        let cs = NMGrid.CellSize(0);
        let dx = FloorF((L.px[id] - NMGrid.OriginX()) / cs) - FloorF((cam.cx - NMGrid.OriginX()) / cs);
        let dy = FloorF((L.py[id] - NMGrid.OriginY()) / cs) - FloorF((cam.cy - NMGrid.OriginY()) / cs);
        return Max(Max(dx, -dx), Max(dy, -dy));
    }

    private static func ScaleOf(w: ref<inkImage>) -> Float {
        let v = w.GetScale();   // bind to a local: a field of a call temporary reads garbage in-game
        return v.X;
    }

    private static func OneItem(api: ref<NightMap>, id: CName, icon: Bool) -> ref<NightMapLayer> {
        let L = api.CreateLayer(id, "One", 5);
        if icon { L.SetPinStyle(NightMapPinStyle.Icon); }
        L.SetCategory(n"test.one", "One", NMTheme.Cyan());
        L.Add(NightMapItem.Create(new Vector4(0.0, 0.0, 0.0, 1.0), n"test.one", NMTheme.UiAtlas(), n"icon_dot"));
        return L;
    }

    private static func RenderCases(t: ref<NMSelfTest>) {
        let w = 1880.0;
        let h = 1480.0;
        // 1. A Minor layer of 2,000 items: nothing at the whole-city zoom; at mpp 2 the budget, nearest rings first.
        let api = NMVanillaTests.TestApi();
        let L = api.CreateLayer(n"test.tier.minor", "Minor", 5);
        L.SetCategory(n"test.tm", "TM", NMTheme.Cyan());
        let i = 0;
        while i < 2000 {
            let x = Cast<Float>((i * 7919) % 4000) - 2000.0;
            let y = Cast<Float>((i * 104729) % 3000) - 1500.0;
            L.Add(NightMapItem.Create(new Vector4(x, y, 0.0, 1.0), n"test.tm", NMTheme.UiAtlas(), n"icon_dot"));
            i += 1;
        }
        let r = NMItemRenderer.Create(api, new inkCanvas(), 1.0);
        r.noDeclutter = true;   // placement order and budget only; NMDeclutterTests covers the overlap skipping
        let cam = NMTierTests.Cam();
        cam.SetMpp(16.0);
        r.Update(cam, w, h);
        let far = r.chipsUsed;
        let farCand = ArraySize(r.candX);
        cam.SetMpp(2.0);
        r.Update(cam, w, h);
        let placed: array<Bool>;
        ArrayResize(placed, ArraySize(L.alive));
        let maxRing = 0;
        let k = 0;
        while k < ArraySize(r.candItem) {
            placed[r.candItem[k]] = true;
            maxRing = Max(maxRing, NMTierTests.Ring(L, r.candItem[k], cam));
            k += 1;
        }
        let missed = 0;
        i = 0;
        while i < ArraySize(L.alive) {
            let p = cam.WorldToMap(L.px[i], L.py[i]);
            let inView = p.X >= 0.0 && p.X <= w && p.Y >= 0.0 && p.Y <= h;
            if L.alive[i] && !placed[i] && inView && NMTierTests.Ring(L, i, cam) < maxRing { missed += 1; }
            i += 1;
        }
        t.Check("render.no_clusters_far", far == 0 && farCand == 0 && r.chipsUsed == NMTheme.ChipBudget() && ArraySize(r.candX) == r.chipsUsed && missed == 0,
            "far " + ToString(far) + "/" + ToString(farCand) + " near " + ToString(r.chipsUsed) + " missed " + ToString(missed) + " ring " + ToString(maxRing));
        // 2. A Major layer of 40 items over the city: all placed at the whole-city zoom, at the Major scale.
        let api2 = NMVanillaTests.TestApi();
        let M = api2.CreateLayer(n"test.tier.major", "Major", 5);
        M.SetTier(NightMapTier.Major);
        M.SetCategory(n"test.tmj", "TMJ", NMTheme.Yellow());
        i = 0;
        while i < 40 {
            M.Add(NightMapItem.Create(new Vector4(-5000.0 + Cast<Float>(i % 8) * 1200.0, -4000.0 + Cast<Float>(i / 8) * 2000.0, 0.0, 1.0), n"test.tmj", NMTheme.UiAtlas(), n"icon_dot"));
            i += 1;
        }
        let r2 = NMItemRenderer.Create(api2, new inkCanvas(), 1.0);
        let cam2 = NMTierTests.Cam();
        cam2.SetMpp(16.0);
        r2.Update(cam2, w, h);
        let want = NMTiers.Scale(1, 16.0);
        let badScale = 0;
        k = 0;
        while k < ArraySize(r2.candSlot) {
            if !t.Near(NMTierTests.ScaleOf(r2.chipIcon[r2.candSlot[k]]), want, 0.001) || !t.Near(NMTierTests.ScaleOf(r2.chipBg[r2.candSlot[k]]), want, 0.001) { badScale += 1; }
            k += 1;
        }
        t.Check("render.major_far", r2.chipsUsed == 40 && badScale == 0 && want < 1.0,
            ToString(r2.chipsUsed) + " chips, " + ToString(badScale) + " off scale " + t.F(want));
        // 3. A fading Minor item stays a candidate (at its faded opacity) until it is fully hidden.
        let api3 = NMVanillaTests.TestApi();
        NMTierTests.OneItem(api3, n"test.tier.fade", false);
        let r3 = NMItemRenderer.Create(api3, new inkCanvas(), 1.0);
        let cam3 = NMTierTests.Cam();
        cam3.SetMpp(4.0);
        r3.Update(cam3, w, h);
        let top = NMTheme.ChipBudget() - 1;
        let base = r3.chipIcon[top].GetOpacity();
        cam3.SetMpp(6.5);
        r3.Update(cam3, w, h);
        let hidden = ArraySize(r3.candX) == 0 && r3.chipsUsed == 0;
        cam3.SetMpp(5.0);
        r3.Update(cam3, w, h);
        let half = r3.chipIcon[top].GetOpacity();
        t.Check("render.faded_not_candidate", hidden && ArraySize(r3.candX) == 1 && base > 0.0 && t.Near(half, 0.5 * base, 0.01),
            ToString(hidden) + " cands " + ToString(ArraySize(r3.candX)) + " " + t.F(half) + " of " + t.F(base));
        // 4. A selected Minor pin that fades out: the next frame drops the selection, its grow and the tooltip.
        let api4 = NMVanillaTests.TestApi();
        NMTierTests.OneItem(api4, n"test.tier.hover", true);
        let canvas = new inkCanvas();
        let r4 = NMItemRenderer.Create(api4, canvas, 1.0);
        let tip = NMTooltip.Create(canvas, w, h, 1.0);
        let c = NMCrosshair.Create();
        let cam4 = NMTierTests.Cam();
        cam4.SetMpp(3.0);
        r4.Update(cam4, w, h);
        c.Update(r4, w, h, 1.0, 0.0);
        r4.ApplySelection(c.sel, c.selKind, 10000.0);
        tip.ShowDetails(NightMapDetails.Create("One", "One"), NMTheme.Cyan());
        let selected = c.selKind == 0 && r4.growSlot == top && tip.IsShown();
        cam4.SetMpp(7.0);
        // One frame as NightMapSystem runs it: relayout, re-pick, and on a changed pick of nothing RefreshSidebar hides.
        let relaid = r4.Update(cam4, w, h);
        let changed = relaid && c.Update(r4, w, h, 1.0, 0.0);
        if changed && c.selKind < 0 { tip.Hide(); }
        r4.ApplySelection(c.sel, c.selKind, 16.0);
        t.Check("render.hover_clears_on_fade", selected && changed && c.sel == -1 && c.selKind == -1 && !tip.IsShown() && r4.growSlot == -1 && !r4.selChip.IsVisible(),
            ToString(selected) + ToString(changed) + " sel " + ToString(c.sel) + " grow " + ToString(r4.growSlot));
        // 5. The emphasis grow multiplies the tier scale, and dropping the selection returns to the tier scale (not 1).
        let api5 = NMVanillaTests.TestApi();
        NMTierTests.OneItem(api5, n"test.tier.grow", true);
        let r5 = NMItemRenderer.Create(api5, new inkCanvas(), 1.0);
        let cam5 = NMTierTests.Cam();
        cam5.SetMpp(4.0);
        r5.Update(cam5, w, h);
        let ks = NMTiers.Scale(2, 4.0);
        let idle = NMTierTests.ScaleOf(r5.chipIcon[top]);
        r5.ApplySelection(0, 0, 10000.0);
        let grown = NMTierTests.ScaleOf(r5.chipIcon[top]);
        r5.ApplySelection(-1, -1, 16.0);
        let back = NMTierTests.ScaleOf(r5.chipIcon[top]);
        t.Check("render.grow_composes_tier_scale", ks < 1.0 && t.Near(idle, ks, 0.001) && t.Near(grown, ks * NMTheme.VanillaEmphScale(), 0.001) && t.Near(back, ks, 0.001),
            t.F(idle) + " " + t.F(grown) + " " + t.F(back) + " k " + t.F(ks));
        // 6. A selected hex pin's rim and the reticle box shrink with the slot's tier scale.
        let api6 = NMVanillaTests.TestApi();
        NMTierTests.OneItem(api6, n"test.tier.rim", false);
        let r6 = NMItemRenderer.Create(api6, new inkCanvas(), 1.0);
        let c6 = NMCrosshair.Create();
        let cam6 = NMTierTests.Cam();
        cam6.SetMpp(4.0);
        r6.Update(cam6, w, h);
        c6.Update(r6, w, h, 1.0, 0.0);
        r6.ApplySelection(c6.sel, c6.selKind, 16.0);
        let rimK = NMTierTests.ScaleOf(r6.selChip);
        let candK = r6.CandScale(c6.sel);
        let rimSize: Vector2 = r6.selChip.GetSize();
        t.Check("render.sel_rim_tier_scale", c6.selKind == 0 && r6.selChip.IsVisible() && ks < 1.0 && t.Near(rimK, ks, 0.001) && t.Near(candK, ks, 0.001)
            && t.Near(rimSize.X, NMTheme.ChipSelSize(), 0.01) && t.Near(NMTheme.ChipSelSize(), 92.0, 0.001),
            t.F(rimK) + " cand " + t.F(candK) + " k " + t.F(ks));
        let full = NMReticle.BoxFor(true, false, 1.0, 1.0);
        let small = NMReticle.BoxFor(true, false, 1.0, ks);
        let idleBox = NMReticle.BoxFor(false, false, 1.0, ks);
        let photoBox = NMReticle.BoxFor(true, true, 1.0, ks);
        let photoFull = NMReticle.BoxFor(true, true, 1.0, 1.0);
        t.Check("reticle.box_tier_scale", t.Near(small.X, full.X * ks, 0.01) && t.Near(idleBox.X, 170.0, 0.01) && t.Near(photoBox.X, photoFull.X, 0.01),
            t.F(small.X) + "/" + t.F(full.X));
        // 7. Placement goes by tier before priority: a big high-priority Minor layer can't spend the budget first.
        let api7 = NMVanillaTests.TestApi();
        let mn = api7.CreateLayer(n"test.tier.bigminor", "BigMinor", 100);
        mn.SetCategory(n"test.bm", "BM", NMTheme.Cyan());
        i = 0;
        while i < NMTheme.ChipBudget() + 100 {
            let x = Cast<Float>((i * 7919) % 800) - 400.0;
            let y = Cast<Float>((i * 104729) % 600) - 300.0;
            mn.Add(NightMapItem.Create(new Vector4(x, y, 0.0, 1.0), n"test.bm", NMTheme.UiAtlas(), n"icon_dot"));
            i += 1;
        }
        let mj = api7.CreateLayer(n"test.tier.smallmajor", "SmallMajor", 1);
        mj.SetTier(NightMapTier.Major);
        mj.SetCategory(n"test.sm", "SM", NMTheme.Yellow());
        i = 0;
        while i < 10 {
            mj.Add(NightMapItem.Create(new Vector4(-300.0 + Cast<Float>(i) * 60.0, 200.0, 0.0, 1.0), n"test.sm", NMTheme.UiAtlas(), n"icon_dot"));
            i += 1;
        }
        let r7 = NMItemRenderer.Create(api7, new inkCanvas(), 1.0);
        r7.noDeclutter = true;   // the budget order, with the 400 Minor items packed far closer than a pin apart
        let cam7 = NMTierTests.Cam();
        cam7.SetMpp(1.0);
        r7.Update(cam7, w, h);
        let majors = 0;
        let minors = 0;
        k = 0;
        while k < ArraySize(r7.candLayer) {
            if r7.candLayer[k] == mj.index { majors += 1; }
            if r7.candLayer[k] == mn.index { minors += 1; }
            k += 1;
        }
        t.Check("render.major_before_minor_budget", majors == 10 && r7.chipsUsed == NMTheme.ChipBudget() && minors == NMTheme.ChipBudget() - 10,
            "major " + ToString(majors) + " minor " + ToString(minors) + " used " + ToString(r7.chipsUsed));
    }
}
