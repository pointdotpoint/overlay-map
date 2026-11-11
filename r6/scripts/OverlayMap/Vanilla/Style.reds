module OverlayMap

// Variant/phase -> vanilla look and rules. Mirrors worldMap.script (BaseWorldMapMappinController) and mappinUtils.script.
public abstract class NMVanillaStyle {
    public static func StateOf(v: gamedataMappinVariant, phase: gamedataMappinPhase) -> CName {
        if Equals(phase, gamedataMappinPhase.CompletedPhase) { return n"QuestComplete"; }
        if Equals(v, gamedataMappinVariant.Zzz17_NCARTVariant) { return n"FastTravelMetro"; }
        if Equals(v, gamedataMappinVariant.Zzz16_RelicDeviceBasicVariant) { return n"Relic"; }
        let g = MappinUtils.GetMappinsGroup(v);
        if !IsDefined(g) { return n"Quest"; }
        let st = g.WidgetState();
        return Equals(st, n"") || Equals(st, n"None") ? n"Quest" : st;
    }

    public static func Color(v: gamedataMappinVariant, phase: gamedataMappinPhase) -> HDRColor {
        return NMTheme.VanillaStateColor(NMVanillaStyle.StateOf(v, phase));
    }

    // Icon part in NMTheme.MappinAtlas(). Parts the game names but does not ship fall back to a close match.
    public static func PartOf(v: gamedataMappinVariant) -> CName {
        let p = MappinUIUtils.MappinToTexturePart(v);
        if Equals(p, n"relic_dataterm") { return n"relic_access_point"; }
        if Equals(p, n"failed_crossing") { return n"dogtown_gate"; }
        if Equals(p, n"PhoneCall") { return n"quest"; }
        if Equals(p, n"invalid") || Equals(p, n"") || Equals(p, n"None") { return n"quest"; }
        return p;
    }

    // Vanilla CanQuestTrackMappin: Quest/SecondaryQuest groups, except racing (worldMap.script:1638-1660).
    // The caller must also check that the mappin's journal entry resolves.
    public static func CanQuestTrack(v: gamedataMappinVariant) -> Bool {
        if Equals(v, gamedataMappinVariant.Zzz18_RacingVariant) { return false; }
        let g = MappinUtils.GetMappinsGroup(v);
        if !IsDefined(g) { return false; }
        let name = g.GroupName();
        return Equals(name, n"Quest") || Equals(name, n"SecondaryQuest");
    }

    // V's own apartments (H10 and every bought one). Drawn emphasised, and a teleport lands at the pin, out of the car.
    public static func IsHome(v: gamedataMappinVariant) -> Bool {
        return Equals(v, gamedataMappinVariant.ApartmentVariant);
    }

    // A residence: V's own, or one for rent.
    public static func IsResidence(v: gamedataMappinVariant) -> Bool {
        return NMVanillaStyle.IsHome(v) || Equals(v, gamedataMappinVariant.Zzz05_ApartmentToPurchaseVariant);
    }

    // A shop or service pin (ServicePoint*Variant: food, guns, clothes, ripperdoc, drop point, ...).
    public static func IsService(v: gamedataMappinVariant) -> Bool {
        return StrContains(ToString(v), "ServicePoint");
    }

    public static func CompletedOpacity() -> Float { return 0.7; }   // MappinUIGlobalProfile.CompletedPOIOpacity
}
