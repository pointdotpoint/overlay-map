module OverlayMap

// Quick views (NUM /) x per-category Mod Settings toggles. View 0 = all; Other and TAROT appear only in view 0.
// Deviation from spec 8 (controller ruling): the views follow the vanilla quick lists in filters.txt, so JOBS has no
// Story/NCPD Scanner; those stay reachable in ALL. Residences show in every view (AlwaysShown).
public abstract class NMVanillaFilters {
    public static func ViewCount() -> Int32 { return 3; }

    public static func ViewName(view: Int32) -> String {
        if view == 1 { return "JOBS"; }
        if view == 2 { return "SERVICES"; }
        return "ALL";
    }

    // Residences (V's homes, and those for rent): in every view, never faded by zoom nor hidden by the declutter.
    // Their Mod Settings toggles still apply. Your Apartments also carries V's vehicles: few, so they come along.
    public static func AlwaysShown(t: gamedataWorldMapFilter, isOther: Bool) -> Bool {
        return !isOther && (Equals(t, gamedataWorldMapFilter.ApartmentToPurchaseFilter) || Equals(t, gamedataWorldMapFilter.CommonFilter));
    }

    public static func InView(view: Int32, t: gamedataWorldMapFilter, isOther: Bool) -> Bool {
        if view == 0 { return true; }
        if isOther { return false; }
        if NMVanillaFilters.AlwaysShown(t, isOther) { return true; }
        if view == 1 {
            return Equals(t, gamedataWorldMapFilter.Quest) || Equals(t, gamedataWorldMapFilter.Gigs)
                || Equals(t, gamedataWorldMapFilter.PsychoFilter);
        }
        return Equals(t, gamedataWorldMapFilter.RipperdocFilter) || Equals(t, gamedataWorldMapFilter.VendorFilter)
            || Equals(t, gamedataWorldMapFilter.AutofixerFilter) || Equals(t, gamedataWorldMapFilter.DropPoint)
            || Equals(t, gamedataWorldMapFilter.FastTravel) || Equals(t, gamedataWorldMapFilter.CommonFilter);
    }

    public static func Enabled(s: ref<OverlayMapSettings>, t: gamedataWorldMapFilter) -> Bool {
        if !IsDefined(s) { return true; }
        if Equals(t, gamedataWorldMapFilter.Quest) { return s.filterJobs; }
        if Equals(t, gamedataWorldMapFilter.Gigs) { return s.filterGigs; }
        if Equals(t, gamedataWorldMapFilter.PsychoFilter) { return s.filterPsycho; }
        if Equals(t, gamedataWorldMapFilter.Story) { return s.filterNcpd; }
        if Equals(t, gamedataWorldMapFilter.FastTravel) { return s.filterFastTravel; }
        if Equals(t, gamedataWorldMapFilter.RipperdocFilter) { return s.filterRipperdoc; }
        if Equals(t, gamedataWorldMapFilter.VendorFilter) { return s.filterVendor; }
        if Equals(t, gamedataWorldMapFilter.AutofixerFilter) { return s.filterAutofixer; }
        if Equals(t, gamedataWorldMapFilter.DropPoint) { return s.filterDropPoint; }
        if Equals(t, gamedataWorldMapFilter.ApartmentToPurchaseFilter) { return s.filterApartmentRent; }
        if Equals(t, gamedataWorldMapFilter.TarotFilter) { return s.filterTarot; }
        if Equals(t, gamedataWorldMapFilter.CommonFilter) { return s.filterYourProperty; }
        return true;
    }

    public static func Visible(view: Int32, s: ref<OverlayMapSettings>, t: gamedataWorldMapFilter, isOther: Bool) -> Bool {
        return NMVanillaFilters.InView(view, t, isOther) && (isOther || NMVanillaFilters.Enabled(s, t));
    }
}
