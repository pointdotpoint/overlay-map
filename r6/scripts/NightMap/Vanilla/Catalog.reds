module NightMap

// The vanilla world map's custom filter list (TweakDB WorldMap.WorldMapCustomFiltersList, 12 entries in 2.31):
// one NightMap layer per filter, plus index Count() = "Other" for map variants no filter lists.
public class NMVanillaCatalog {
    public let types: array<gamedataWorldMapFilter>;
    public let names: array<String>;
    public let firstVariant: array<gamedataMappinVariant>;
    private let memberVariant: array<Int32>;   // flattened (variant, filter index) pairs
    private let memberFilter: array<Int32>;

    public static func Build() -> ref<NMVanillaCatalog> {
        let c = new NMVanillaCatalog();
        let rec = TweakDBInterface.GetWorldMapFiltersListRecord(t"WorldMap.WorldMapCustomFiltersList");
        if !IsDefined(rec) {
            NMLog.Error("vanilla|catalog|WorldMapCustomFiltersList missing; all markers go to Other");
            return c;
        }
        let n = rec.GetListCount();
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
                        ArrayPush(c.memberVariant, EnumInt(v));
                        ArrayPush(c.memberFilter, idx);
                    }
                    k += 1;
                }
                ArrayPush(c.firstVariant, first);
            }
            i += 1;
        }
        return c;
    }

    public func Count() -> Int32 { return ArraySize(this.types); }

    public func IsOther(i: Int32) -> Bool { return i >= ArraySize(this.types); }

    // First filter (TweakDB order) listing v, else Count() (Other).
    public func FilterIndexOf(v: gamedataMappinVariant) -> Int32 {
        let key = EnumInt(v);
        let i = 0;
        let n = ArraySize(this.memberVariant);
        while i < n {
            if this.memberVariant[i] == key {
                return this.memberFilter[i];
            }
            i += 1;
        }
        return ArraySize(this.types);
    }

    public func TypeOf(i: Int32) -> gamedataWorldMapFilter {
        return this.IsOther(i) ? gamedataWorldMapFilter.NoFilter : this.types[i];
    }

    public func LayerId(i: Int32) -> CName {
        return this.IsOther(i) ? n"Vanilla.Other" : StringToName("Vanilla." + ToString(this.types[i]));
    }

    public func CategoryName(i: Int32) -> CName {
        return this.IsOther(i) ? n"vanilla.other" : StringToName("vanilla." + ToString(this.types[i]));
    }

    public func DisplayName(i: Int32) -> String {
        if this.IsOther(i) { return "Other"; }
        let s = this.names[i];
        return StrLen(s) > 0 ? s : ToString(this.types[i]);
    }

    // Draw priority (higher on top): jobs above services, as the vanilla map layers them.
    public func Priority(i: Int32) -> Int32 {
        let t = this.TypeOf(i);
        if Equals(t, gamedataWorldMapFilter.Quest) { return 90; }
        if Equals(t, gamedataWorldMapFilter.Gigs) { return 85; }
        if Equals(t, gamedataWorldMapFilter.PsychoFilter) { return 84; }
        if Equals(t, gamedataWorldMapFilter.Story) { return 80; }
        if Equals(t, gamedataWorldMapFilter.FastTravel) { return 70; }
        if Equals(t, gamedataWorldMapFilter.TarotFilter) { return 55; }
        if this.IsOther(i) { return 50; }
        return 60;
    }
}
