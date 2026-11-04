module OverlayMap

public enum NMMiniKind {
    Enemy = 0,
    Police = 1,
    Device = 2,
    Other = 3,
    Area = 4,
    Zone = 5,
    Shadow = 6   // drawn by NMVanilla already: only its rim clamp and above / below arrow come from here
}

// One vanilla minimap marker, as its controller drew it. Holds weak refs to the controller's own widgets and re-reads
// them when drawn, so it never depends on how often the native side calls Update().
public class NMMiniEntry extends IScriptable {
    public let key: Uint64;
    public let cls: CName;
    public let kind: NMMiniKind;
    public let mappin: wref<IMappin>;
    public let obj: wref<GameObject>;   // stealth: the NPC / device (position, facing)
    public let root: wref<inkWidget>;
    public let icon: wref<inkImage>;
    public let cone: wref<inkImage>;
    public let shape: wref<inkWidget>;  // quest / security area shape (Task 11)
    public let coneLen: Float;          // metres, StealthMappin.GetSenseCone().length
    public let radius: Float;           // metres: device effect area (0 = none)
    public let tracked: Bool;
    public let vertical: Int32;         // -1 below, 0 level, 1 above (vanilla's own relation)
    public let clamped: Bool;           // vanilla clamped it to its own rim
    public let clampable: Bool;         // vanilla keeps it on its rim when off the minimap (tracked objective, ...)

    public func Position() -> Vector4 {
        if IsDefined(this.obj) { return this.obj.GetWorldPosition(); }
        if IsDefined(this.mappin) { return this.mappin.GetWorldPosition(); }
        return new Vector4(0.0, 0.0, 0.0, 0.0);
    }

    // Shown by the vanilla minimap: its root is alive, visible and not faded out by the controller.
    public func Shown() -> Bool {
        return IsDefined(this.root) && this.root.IsVisible() && this.root.GetOpacity() > 0.01;
    }
}

// Every vanilla minimap marker OverlayMap copies (FINDINGS "How OverlayMap gets parity"). Fed by Minimap/Wraps.reds while
// a OverlayMap view is live; entries whose widgets are gone are swept.
public class NMMinimapMirror {
    private let map: ref<inkHashMap>;
    private let entries: array<ref<NMMiniEntry>>;
    public let revision: Int32;
    public let live: Bool;   // a OverlayMap view (corner or panel) wants the copies

    public static func Create() -> ref<NMMinimapMirror> {
        let m = new NMMinimapMirror();
        m.map = new inkHashMap();
        return m;
    }

    public func Find(key: Uint64) -> ref<NMMiniEntry> {
        if !this.map.KeyExist(key) { return null; }
        return this.map.Get(key) as NMMiniEntry;
    }

    // The entry for `key`, created when new.
    public func Upsert(key: Uint64) -> ref<NMMiniEntry> {
        let e = this.Find(key);
        if IsDefined(e) { return e; }
        e = new NMMiniEntry();
        e.key = key;
        this.map.Insert(key, e);
        ArrayPush(this.entries, e);
        this.revision += 1;
        return e;
    }

    public func Remove(key: Uint64) {
        if !this.map.KeyExist(key) { return; }
        this.map.Remove(key);
        let i = ArraySize(this.entries) - 1;
        while i >= 0 {
            if this.entries[i].key == key { ArrayErase(this.entries, i); }
            i -= 1;
        }
        this.revision += 1;
    }

    // Drops entries whose controller widget is gone. Returns how many.
    public func Sweep() -> Int32 {
        let n = 0;
        let i = ArraySize(this.entries) - 1;
        while i >= 0 {
            let e = this.entries[i];
            if !IsDefined(e.root) {
                this.map.Remove(e.key);
                ArrayErase(this.entries, i);
                n += 1;
            }
            i -= 1;
        }
        if n > 0 { this.revision += 1; }
        return n;
    }

    public func Clear() {
        this.map.Clear();
        ArrayClear(this.entries);
        this.revision += 1;
    }

    // The vanilla minimap's px per metre from the first shown, unclamped marker 10 m or more from V; 0 if none.
    public func EstimateScale(player: Vector4) -> Float {
        for e in this.entries {
            if e.Shown() && !e.clamped && !Equals(e.kind, NMMiniKind.Area) && !Equals(e.kind, NMMiniKind.Zone) {
                let w = e.Position();
                let s = NMParity.ScaleFrom(e.root.GetTranslation(), w.X - player.X, w.Y - player.Y);
                if s > 0.0 { return s; }
            }
        }
        return 0.0;
    }

    public func All() -> array<ref<NMMiniEntry>> { return this.entries; }
    public func Count() -> Int32 { return ArraySize(this.entries); }
}
