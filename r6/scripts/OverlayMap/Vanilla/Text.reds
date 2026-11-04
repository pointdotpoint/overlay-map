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

    public static func District(m: ref<IMappin>) -> String {
        let ft = m as FastTravelMappin;
        if IsDefined(ft) {
            let pd = ft.GetPointData();
            if IsDefined(pd) { return NMVanillaText.Loc(pd.GetDistrictDisplayName()); }
        }
        return "";
    }
}
