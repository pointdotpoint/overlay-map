module OverlayMap

public abstract class NMVanillaText {
    // Mappin and journal strings arrive as "LocKey#NNN"; resolve those, pass anything else through.
    public static func Loc(s: String) -> String {
        if StrBeginsWith(s, "LocKey#") {
            return GetLocalizedText(s);
        }
        return s;
    }

    // Localized type label, e.g. "Drop Point" (UI-MappinTypes-*).
    public static func LabelOf(v: gamedataMappinVariant) -> String {
        let key = MappinUIUtils.MappinToString(v);
        let s = GetLocalizedTextByKey(key);
        return StrLen(s) > 0 ? s : ToString(v);
    }

    // The building of a home or for-rent pin, by the game's own area name ("Northside Apartment"); "" when the pin is
    // not near a residence (NMResidences). The pins carry no name of their own.
    public static func HomeId(x: Float, y: Float) -> String {
        let best = "";
        let bestD = NMVanillaText.HomeReach() * NMVanillaText.HomeReach();
        let i = 0;
        while i < NMResidences.Count() {
            let p = NMResidences.Door(i);
            let dx = x - p.X;
            let dy = y - p.Y;
            let d = dx * dx + dy * dy;
            if d < bestD {
                bestD = d;
                best = NMResidences.AreaId(i);
            }
            i += 1;
        }
        return best;
    }

    public static func HomeReach() -> Float { return 100.0; }

    public static func HomeName(x: Float, y: Float) -> String {
        return NMAreaIndex.DistrictName(NMVanillaText.HomeId(x, y));
    }

    // Fast-travel point name, else the mappin's display name, else the type label.
    public static func Title(m: ref<IMappin>, v: gamedataMappinVariant) -> String {
        if IsDefined(m) {
            let ft = m as FastTravelMappin;
            if IsDefined(ft) {
                let pd = ft.GetPointData();
                if IsDefined(pd) {
                    let n = NMVanillaText.Loc(pd.GetPointDisplayName());
                    if StrLen(n) > 0 { return n; }
                }
            }
            let dn = NMVanillaText.Loc(m.GetDisplayName());
            if StrLen(dn) > 0 { return dn; }
        }
        return NMVanillaText.LabelOf(v);
    }

    // A vehicle marker's car or bike, by its in-game name (as the vanilla world map tooltip shows it); else "".
    public static func VehicleName(m: ref<IMappin>) -> String {
        let vm = m as VehicleMappin;
        if !IsDefined(vm) { return ""; }
        let veh = vm.GetVehicle();
        return IsDefined(veh) ? veh.GetDisplayName() : "";
    }

    public static func District(m: ref<IMappin>) -> String {
        let ft = m as FastTravelMappin;
        if IsDefined(ft) {
            let pd = ft.GetPointData();
            if IsDefined(pd) { return NMVanillaText.Loc(pd.GetDistrictDisplayName()); }
        }
        return "";
    }
}
