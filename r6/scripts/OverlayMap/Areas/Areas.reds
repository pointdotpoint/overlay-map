module OverlayMap

// One named area outline from NMAreaData (tools/areas/gen.py). Custom areas carry their own name; game areas only
// their Districts.* key, named through TweakDB so the name follows the game language.
public class NMArea {
    public let key: String;
    public let name: String;
    public let parent: String;
    public let desc: String;
    public let minX: Float;
    public let minY: Float;
    public let maxX: Float;
    public let maxY: Float;
    public let xs: array<Float>;
    public let ys: array<Float>;
}

// "Which area contains (x, y)": areas are kept in data order (smallest first), so the first hit is the smallest.
public class NMAreaIndex {
    private let areas: array<ref<NMArea>>;
    private let titles: array<String>;
    private let titled: array<Bool>;

    public static func Parse(chunks: array<String>) -> ref<NMAreaIndex> {
        let idx = new NMAreaIndex();
        for chunk in chunks {
            for e in StrSplit(chunk, ";", false) {
                let a = NMAreaIndex.ParseEntry(e);
                if IsDefined(a) {
                    ArrayPush(idx.areas, a);
                    ArrayPush(idx.titles, "");
                    ArrayPush(idx.titled, false);
                }
            }
        }
        return idx;
    }

    // gen.py writes an empty field as "~": the game's StrSplit may drop empty fields.
    private static func Field(s: String) -> String {
        return Equals(s, "~") ? "" : s;
    }

    // key|name|parent|desc|x1,y1,...; null when malformed or under 3 points.
    private static func ParseEntry(e: String) -> ref<NMArea> {
        let f = StrSplit(e, "|", false);
        if ArraySize(f) < 5 {
            return null;
        }
        let c = StrSplit(f[4], ",", false);
        let n = ArraySize(c) / 2;
        if n < 3 {
            return null;
        }
        let a = new NMArea();
        a.key = f[0];
        a.name = NMAreaIndex.Field(f[1]);
        a.parent = NMAreaIndex.Field(f[2]);
        a.desc = NMAreaIndex.Field(f[3]);
        let i = 0;
        while i < n {
            let x = StringToFloat(c[2 * i]);
            let y = StringToFloat(c[2 * i + 1]);
            ArrayPush(a.xs, x);
            ArrayPush(a.ys, y);
            if i == 0 || x < a.minX { a.minX = x; }
            if i == 0 || x > a.maxX { a.maxX = x; }
            if i == 0 || y < a.minY { a.minY = y; }
            if i == 0 || y > a.maxY { a.maxY = y; }
            i += 1;
        }
        return a;
    }

    public static func Load() -> ref<NMAreaIndex> {
        let chunks: array<String>;
        let k = 0;
        while k < NMAreaData.Chunks() {
            ArrayPush(chunks, NMAreaData.Chunk(k));
            k += 1;
        }
        let idx = NMAreaIndex.Parse(chunks);
        NMLog.Info("areas|loaded|" + ToString(idx.Count()) + "|of|" + ToString(NMAreaData.Count()));
        return idx;
    }

    public func Count() -> Int32 {
        return ArraySize(this.areas);
    }

    // The first area (smallest) that contains the point and has a name; -1 if none.
    public func At(x: Float, y: Float) -> Int32 {
        let i = 0;
        let n = ArraySize(this.areas);
        while i < n {
            if NMAreaIndex.Contains(this.areas[i], x, y) && StrLen(this.Title(i)) > 0 {
                return i;
            }
            i += 1;
        }
        return -1;
    }

    // A game venue at the point (a bar, shop or clinic with its own area, like "Red Dirt"): the smallest game area
    // that contains it and spans at most VenueSpan() metres; -1 if none. Custom areas and districts never count.
    public func VenueAt(x: Float, y: Float) -> Int32 {
        let i = 0;
        let n = ArraySize(this.areas);
        while i < n {
            let a = this.areas[i];
            if StrLen(a.name) == 0 && MaxF(a.maxX - a.minX, a.maxY - a.minY) <= NMAreaIndex.VenueSpan()
                && NMAreaIndex.Contains(a, x, y) && StrLen(this.Title(i)) > 0 {
                return i;
            }
            i += 1;
        }
        return -1;
    }

    public static func VenueSpan() -> Float { return 120.0; }

    public func Title(i: Int32) -> String {
        if i < 0 || i >= ArraySize(this.areas) {
            return "";
        }
        if !this.titled[i] {
            let a = this.areas[i];
            this.titles[i] = StrLen(a.name) > 0 ? a.name : NMAreaIndex.DistrictName(a.key);
            this.titled[i] = true;
        }
        return this.titles[i];
    }

    // The parent chain, top first, upper case: "BADLANDS · RED PEAKS". A game area walks up from its own record;
    // a custom area starts at (and includes) its parent record.
    public func Label(i: Int32) -> String {
        if i < 0 || i >= ArraySize(this.areas) {
            return "";
        }
        let a = this.areas[i];
        let rec: wref<District_Record>;
        if StrLen(a.name) > 0 {
            if StrLen(a.parent) == 0 {
                return "";
            }
            rec = TweakDBInterface.GetDistrictRecord(TDBID.Create(a.parent));
        } else {
            let own = TweakDBInterface.GetDistrictRecord(TDBID.Create(a.key));
            rec = IsDefined(own) ? own.ParentDistrict() : null;
        }
        let names: array<String>;
        let guard = 0;
        while IsDefined(rec) && guard < 8 {
            let s = GetLocalizedText(rec.LocalizedName());
            if StrLen(s) > 0 {
                ArrayInsert(names, 0, StrUpper(s));
            }
            rec = rec.ParentDistrict();
            guard += 1;
        }
        let out = "";
        for s in names {
            out += (StrLen(out) > 0 ? " · " : "") + s;
        }
        return out;
    }

    public func Key(i: Int32) -> String {
        return i >= 0 && i < ArraySize(this.areas) ? this.areas[i].key : "";
    }

    public func Desc(i: Int32) -> String {
        return i >= 0 && i < ArraySize(this.areas) ? this.areas[i].desc : "";
    }

    // Bounding box, then even-odd: concave outlines and either winding hit-test the same.
    public static func Contains(a: ref<NMArea>, x: Float, y: Float) -> Bool {
        if x < a.minX || x > a.maxX || y < a.minY || y > a.maxY {
            return false;
        }
        let inside = false;
        let n = ArraySize(a.xs);
        let j = n - 1;
        let i = 0;
        while i < n {
            let yi = a.ys[i];
            let yj = a.ys[j];
            if ((yi > y && yj <= y) || (yj > y && yi <= y)) && x < (a.xs[j] - a.xs[i]) * (y - yi) / (yj - yi) + a.xs[i] {
                inside = !inside;
            }
            j = i;
            i += 1;
        }
        return inside;
    }

    public static func DistrictName(id: String) -> String {
        if StrLen(id) == 0 {
            return "";
        }
        let rec = TweakDBInterface.GetDistrictRecord(TDBID.Create(id));
        return IsDefined(rec) ? GetLocalizedText(rec.LocalizedName()) : "";
    }
}
