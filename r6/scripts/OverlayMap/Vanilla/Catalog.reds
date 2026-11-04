module OverlayMap

// The vanilla world map's custom filter list (TweakDB WorldMap.WorldMapCustomFiltersList, 12 entries in 2.31):
// one OverlayMap layer per filter, plus index Count() = "Other" for map variants no filter lists.
public class NMVanillaCatalog {
    public let types: array<gamedataWorldMapFilter>;
    public let names: array<String>;
    public let firstVariant: array<gamedataMappinVariant>;
    private let filterOfVariant: array<Int32>;   // index = EnumInt(variant); value = filter index (Count() = Other)
    private let layerIds: array<CName>;           // per index incl. Other
    private let categoryNames: array<CName>;
    // Per-variant style cache (index = EnumInt(variant)): the TweakDB / MappinUIUtils lookups run once per variant.
    private let partCache: array<CName>;
    private let colorCache: array<HDRColor>;
    private let styleSet: array<Bool>;

    public static func Build() -> ref<NMVanillaCatalog> {
        let c = new NMVanillaCatalog();
        let rec = TweakDBInterface.GetWorldMapFiltersListRecord(t"WorldMap.WorldMapCustomFiltersList");
        if !IsDefined(rec) {
            NMLog.Error("vanilla|catalog|WorldMapCustomFiltersList missing; all markers go to Other");
            c.Finish();
            return c;
        }
        let n = rec.GetListCount();
        let vsize = EnumInt(gamedataMappinVariant.Count) + 1;
        ArrayResize(c.filterOfVariant, vsize);
        let z = 0;
        while z < vsize {
            c.filterOfVariant[z] = -1;
            z += 1;
        }
        let i = 0;
        while i < n {
            let g = rec.GetListItem(i);
            if IsDefined(g) {
                let ft = g.FilterType();
                let idx = ArraySize(c.types);
                ArrayPush(c.types, IsDefined(ft) ? ft.Type() : gamedataWorldMapFilter.CustomFilter);
                ArrayPush(c.names, GetLocalizedTextByKey(g.FilterName()));
                let first = gamedataMappinVariant.Invalid;
                let m = g.GetMappinsCount();
                let k = 0;
                while k < m {
                    let mv = g.GetMappinsItem(k);
                    if IsDefined(mv) {
                        let v = mv.Type();
                        if k == 0 { first = v; }
                        let vi = EnumInt(v);
                        if vi >= 0 && vi < vsize && c.filterOfVariant[vi] < 0 {
                            c.filterOfVariant[vi] = idx;   // first filter in TweakDB order wins
                        }
                    }
                    k += 1;
                }
                ArrayPush(c.firstVariant, first);
            }
            i += 1;
        }
        c.Finish();
        return c;
    }

    // Unlisted variants -> Other index; per-index CName caches (incl. Other).
    private func Finish() {
        let other = ArraySize(this.types);
        let z = 0;
        while z < ArraySize(this.filterOfVariant) {
            if this.filterOfVariant[z] < 0 { this.filterOfVariant[z] = other; }
            z += 1;
        }
        let i = 0;
        while i <= other {
            if i == other {
                ArrayPush(this.layerIds, n"Vanilla.Other");
                ArrayPush(this.categoryNames, n"vanilla.other");
            } else {
                ArrayPush(this.layerIds, StringToName("Vanilla." + ToString(this.types[i])));
                ArrayPush(this.categoryNames, StringToName("vanilla." + ToString(this.types[i])));
            }
            i += 1;
        }
    }

    public func Count() -> Int32 { return ArraySize(this.types); }

    private func StyleSlot(v: gamedataMappinVariant) -> Int32 {
        let vi = EnumInt(v);
        if vi < 0 || vi > EnumInt(gamedataMappinVariant.Count) { return -1; }
        if ArraySize(this.styleSet) == 0 {
            let n = EnumInt(gamedataMappinVariant.Count) + 1;
            ArrayResize(this.partCache, n);
            ArrayResize(this.colorCache, n);
            ArrayResize(this.styleSet, n);
        }
        if !this.styleSet[vi] {
            this.partCache[vi] = NMVanillaStyle.PartOf(v);
            this.colorCache[vi] = NMVanillaStyle.Color(v, gamedataMappinPhase.DefaultPhase);
            this.styleSet[vi] = true;
        }
        return vi;
    }

    // NMVanillaStyle.PartOf / .Color memoised per variant (the phase only matters for Completed, handled here).
    public func PartFor(v: gamedataMappinVariant) -> CName {
        let i = this.StyleSlot(v);
        return i >= 0 ? this.partCache[i] : NMVanillaStyle.PartOf(v);
    }

    public func ColorFor(v: gamedataMappinVariant, phase: gamedataMappinPhase) -> HDRColor {
        if Equals(phase, gamedataMappinPhase.CompletedPhase) { return NMVanillaStyle.Color(v, phase); }
        let i = this.StyleSlot(v);
        return i >= 0 ? this.colorCache[i] : NMVanillaStyle.Color(v, phase);
    }

    public func IsOther(i: Int32) -> Bool { return i >= ArraySize(this.types); }

    // First filter (TweakDB order) listing v, else Count() (Other).
    public func FilterIndexOf(v: gamedataMappinVariant) -> Int32 {
        let key = EnumInt(v);
        if key >= 0 && key < ArraySize(this.filterOfVariant) {
            return this.filterOfVariant[key];
        }
        return ArraySize(this.types);
    }

    public func TypeOf(i: Int32) -> gamedataWorldMapFilter {
        return this.IsOther(i) ? gamedataWorldMapFilter.NoFilter : this.types[i];
    }

    public func LayerId(i: Int32) -> CName {
        return i >= 0 && i < ArraySize(this.layerIds) ? this.layerIds[i] : n"Vanilla.Other";
    }

    public func CategoryName(i: Int32) -> CName {
        return i >= 0 && i < ArraySize(this.categoryNames) ? this.categoryNames[i] : n"vanilla.other";
    }

    public func DisplayName(i: Int32) -> String {
        if this.IsOther(i) { return "Other"; }
        let s = this.names[i];
        return StrLen(s) > 0 ? s : ToString(this.types[i]);
    }

    // Draw and declutter priority (higher on top, placed first within a tier): jobs above services, as the vanilla
    // map layers them. NCPD Scanner (the Story filter: hustles, gang watch, stashes) is the exception: the most
    // numerous ambient vanilla category, it goes below services and tarot but above the collectibles (40, over 1,600
    // shards), so at mid zoom services win the space and NCPD fills the gaps (Task 11 tuning). Each Minor layer has its
    // own declutter evaluation slice, so this order decides who wins a spot, not who gets evaluated at all.
    public func Priority(i: Int32) -> Int32 {
        let t = this.TypeOf(i);
        if Equals(t, gamedataWorldMapFilter.Quest) { return 90; }
        if Equals(t, gamedataWorldMapFilter.Gigs) { return 85; }
        if Equals(t, gamedataWorldMapFilter.PsychoFilter) { return 84; }
        if Equals(t, gamedataWorldMapFilter.Story) { return 45; }
        if Equals(t, gamedataWorldMapFilter.FastTravel) { return 70; }
        if Equals(t, gamedataWorldMapFilter.TarotFilter) { return 55; }
        if this.IsOther(i) { return 50; }
        return 60;
    }
}
