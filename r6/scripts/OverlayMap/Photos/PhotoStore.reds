module OverlayMap

// One saved photo spot: where V stood when the shot was taken, and the game's hash for loading that shot.
public class NMPhotoSpot {
    public let hash: Uint32;
    public let path: String;
    public let x: Float;
    public let y: Float;
    public let z: Float;
    public let yaw: Float;
    public let created: Uint64;
    public let district: String;   // where V stood when photo mode opened ("" when unknown)

    public static func Create(hash: Uint32, path: String, pos: Vector4, yaw: Float, created: Uint64) -> ref<NMPhotoSpot> {
        let s = new NMPhotoSpot();
        s.hash = hash;
        s.path = path;
        s.x = pos.X;
        s.y = pos.Y;
        s.z = pos.Z;
        s.yaw = yaw;
        s.created = created;
        return s;
    }

    public func Position() -> Vector4 {
        return new Vector4(this.x, this.y, this.z, 1.0);
    }
}

// Spots live in OverlayMap's own RedFileSystem storage (not the save game), one per line:
// hash;x;y;z;yaw;created;district;path. The path is last so it may contain ';'.
public abstract class NMPhotoStore {
    public static func FileName() -> String { return "photos.txt"; }

    public static func ToLine(s: ref<NMPhotoSpot>) -> String {
        return ToString(s.hash) + ";" + FloatToStringPrec(s.x, 2) + ";" + FloatToStringPrec(s.y, 2) + ";"
            + FloatToStringPrec(s.z, 2) + ";" + FloatToStringPrec(s.yaw, 2) + ";" + ToString(s.created) + ";" + s.district + ";" + s.path;
    }

    // Null when the line does not have 8 fields or a number does not parse.
    public static func FromLine(line: String) -> ref<NMPhotoSpot> {
        let f: array<String>;
        let rest = line;
        while ArraySize(f) < 7 {
            let i = StrFindFirst(rest, ";");
            if i < 0 {
                return null;
            }
            ArrayPush(f, StrLeft(rest, i));
            rest = StrMid(rest, i + 1);
        }
        if StrLen(rest) == 0 || !NMPhotoStore.IsUint(f[0]) || !NMPhotoStore.IsUint(f[5]) {
            return null;
        }
        let k = 1;
        while k <= 4 {
            if !NMPhotoStore.IsNumber(f[k]) {
                return null;
            }
            k += 1;
        }
        let s = new NMPhotoSpot();
        s.hash = Cast<Uint32>(StringToUint64(f[0]));
        s.x = StringToFloat(f[1]);
        s.y = StringToFloat(f[2]);
        s.z = StringToFloat(f[3]);
        s.yaw = StringToFloat(f[4]);
        s.created = StringToUint64(f[5]);
        s.district = f[6];
        s.path = rest;
        return s;
    }

    private static func IsUint(v: String) -> Bool {
        let n = StrLen(v);
        if n == 0 { return false; }
        let i = 0;
        while i < n {
            if StrFindFirst("0123456789", StrMid(v, i, 1)) < 0 { return false; }
            i += 1;
        }
        return true;
    }

    private static func IsNumber(v: String) -> Bool {
        let n = StrLen(v);
        let i = 0;
        let digits = 0;
        let dots = 0;
        while i < n {
            let c = StrMid(v, i, 1);
            if Equals(c, "-") && i == 0 {
            } else if Equals(c, ".") {
                dots += 1;
            } else if StrFindFirst("0123456789", c) >= 0 {
                digits += 1;
            } else {
                return false;
            }
            i += 1;
        }
        return digits > 0 && dots <= 1;
    }

    // Lines that do not parse are skipped; Skipped() reports how many from the last call.
    // Older versions wrote spots with no line break between them. Every record ends in the shot's ".png", so a line
    // splits back into its records there; a normal line comes back whole, and an empty one as nothing.
    public static func Unglue(line: String) -> array<String> {
        let out: array<String>;
        let rest = line;
        let at = StrFindFirst(rest, ".png");
        while at >= 0 {
            ArrayPush(out, StrLeft(rest, at + 4));
            rest = StrMid(rest, at + 4);
            at = StrFindFirst(rest, ".png");
        }
        if StrLen(rest) > 0 {
            ArrayPush(out, rest);
        }
        return out;
    }

    public static func Parse(lines: array<String>) -> array<ref<NMPhotoSpot>> {
        let out: array<ref<NMPhotoSpot>>;
        let bad = 0;
        for line in lines {
            for record in NMPhotoStore.Unglue(line) {
                let s = NMPhotoStore.FromLine(record);
                if IsDefined(s) {
                    ArrayPush(out, s);
                } else {
                    bad += 1;
                }
            }
        }
        NMPhotoStoreState.Get().skipped = bad;
        return out;
    }

    public static func Skipped() -> Int32 {
        return NMPhotoStoreState.Get().skipped;
    }

    public static func Load() -> array<ref<NMPhotoSpot>> {
        NMPhotoStoreState.Get().skipped = 0;   // a missing file parses nothing
        let out = NMPhotoStoreLoad();
        if NMPhotoStore.Skipped() > 0 {
            NMLog.Info("photo|store|skipped " + ToString(NMPhotoStore.Skipped()) + " bad lines");
        }
        return out;
    }

    // The file's lines, without line ends (RedFileSystem wrote CRLF) or empty lines.
    public static func Lines(text: String) -> array<String> {
        let out: array<String>;
        let rest = text;
        let at = StrFindFirst(rest, "\n");
        while at >= 0 {
            let l = StrReplaceAll(StrLeft(rest, at), "\r", "");
            if StrLen(l) > 0 { ArrayPush(out, l); }
            rest = StrMid(rest, at + 1);
            at = StrFindFirst(rest, "\n");
        }
        let last = StrReplaceAll(rest, "\r", "");
        if StrLen(last) > 0 { ArrayPush(out, last); }
        return out;
    }

    public static func Append(s: ref<NMPhotoSpot>) -> Bool {
        return NMPhotoStoreAppend(NMPhotoStore.ToLine(s));
    }
}

// Script-side state for the static store (redscript has no static fields).
public class NMPhotoStoreState extends ScriptableSystem {
    public let skipped: Int32;

    public static func Get() -> ref<NMPhotoStoreState> {
        return GameInstance.GetScriptableSystemsContainer(GetGameInstance()).Get(n"OverlayMap.NMPhotoStoreState") as NMPhotoStoreState;
    }
}

// The file lives in <game>/r6/storages/OverlayMap/, where RedFileSystem's storage kept it before, and is read and
// appended by the OverlayMapNative plugin.
@if(ModuleExists("OverlayMapNative"))
public func NMPhotoStoreLoad() -> array<ref<NMPhotoSpot>> {
    let text = OverlayMapNative_PhotoStoreRead();
    let lines = NMPhotoStore.Lines(text);
    return NMPhotoStore.Parse(lines);
}

@if(!ModuleExists("OverlayMapNative"))
public func NMPhotoStoreLoad() -> array<ref<NMPhotoSpot>> {
    let none: array<ref<NMPhotoSpot>>;
    NMLog.Error("photo|store|no OverlayMapNative plugin");
    return none;
}

@if(ModuleExists("OverlayMapNative"))
public func NMPhotoStoreAppend(line: String) -> Bool {
    let ok = OverlayMapNative_PhotoStoreAppend(line + "\n");
    if !ok {
        NMLog.Error("photo|store|unwritable");
    }
    return ok;
}

@if(!ModuleExists("OverlayMapNative"))
public func NMPhotoStoreAppend(line: String) -> Bool {
    NMLog.Error("photo|store|no OverlayMapNative plugin");
    return false;
}
