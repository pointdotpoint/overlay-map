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
        let assigned = q.tier == 1 && ft.tier == 1 && v.pinned.tier == 0 && gigs.tier == 2;
        v.ApplyFilters(1, s);
        let on = gigs.promoted && gigs.EffectiveTier() == 1;
        v.ApplyFilters(0, s);
        t.Check("tier.vanilla_assignment", assigned && on && !gigs.promoted, ToString(q.tier) + ToString(ft.tier) + ToString(gigs.tier));
    }
}
