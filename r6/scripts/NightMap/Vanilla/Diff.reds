module NightMap

// One vanilla mappin as read in a poll. filter: catalogue index (Other = catalog.Count()), -1 = never show.
public class NMVanillaSnap {
    public let key: Uint64;
    public let x: Float;
    public let y: Float;
    public let z: Float;
    public let variant: gamedataMappinVariant;
    public let phase: gamedataMappinPhase;
    public let visible: Bool;
    public let tracked: Bool;
    public let filter: Int32;

    public static func Make(key: Uint64, x: Float, y: Float, variant: gamedataMappinVariant, phase: gamedataMappinPhase,
                            visible: Bool, tracked: Bool, filter: Int32) -> ref<NMVanillaSnap> {
        let s = new NMVanillaSnap();
        s.key = key;
        s.x = x;
        s.y = y;
        s.variant = variant;
        s.phase = phase;
        s.visible = visible;
        s.tracked = tracked;
        s.filter = filter;
        return s;
    }
}

// A mirrored mappin: which NightMap layer slot and item it lives in.
public class NMVanillaEntry extends IScriptable {
    public let key: Uint64;
    public let snap: ref<NMVanillaSnap>;
    public let slot: Int32;    // filter index, or -2 = Vanilla.Pinned
    public let item: Int32;
    public let gen: Int32;
}

// Spec §6 visibility rule.
public abstract class NMVanillaRules {
    public static func Shown(s: ref<NMVanillaSnap>) -> Bool {
        if s.tracked { return true; }
        if !s.visible || s.filter < 0 { return false; }
        return !Equals(s.phase, gamedataMappinPhase.CompletedPhase);
    }

    public static func Slot(s: ref<NMVanillaSnap>) -> Int32 {
        return s.tracked ? -2 : s.filter;
    }

    // A change worth touching the layer for: moved > 0.5 m, or variant/phase/tracked/filter changed.
    public static func Differs(a: ref<NMVanillaSnap>, b: ref<NMVanillaSnap>) -> Bool {
        if AbsF(a.x - b.x) > 0.5 || AbsF(a.y - b.y) > 0.5 { return true; }
        if NotEquals(a.variant, b.variant) || NotEquals(a.phase, b.phase) { return true; }
        return NotEquals(a.tracked, b.tracked) || a.filter != b.filter;
    }
}

// Receives the diff. OnChange runs before the entry's snap/slot are replaced, so e.slot is still the old slot.
public abstract class NMVanillaSink extends IScriptable {
    public func OnAdd(e: ref<NMVanillaEntry>) {}
    public func OnChange(e: ref<NMVanillaEntry>, s: ref<NMVanillaSnap>) {}
    public func OnRemove(e: ref<NMVanillaEntry>) {}
}

// Keyed by NewMappinID.value: inkHashMap lookup per mappin, one sweep for removals. No per-frame work.
public class NMVanillaDiff {
    private let map: ref<inkHashMap>;
    private let entries: array<ref<NMVanillaEntry>>;
    private let gen: Int32;
    public let added: Int32;
    public let changed: Int32;
    public let removed: Int32;
    public let live: Int32;

    public static func Create() -> ref<NMVanillaDiff> {
        let d = new NMVanillaDiff();
        d.map = new inkHashMap();
        return d;
    }

    // Set to true once `inkHashMap.Get` on a missing key is confirmed to return null (self-test
    // diff.hashmap_get_missing_null): then Find costs one native call instead of two.
    public static func MissIsNull() -> Bool { return false; }

    public func Find(key: Uint64) -> ref<NMVanillaEntry> {
        if NMVanillaDiff.MissIsNull() {
            return this.map.Get(key) as NMVanillaEntry;
        }
        if !this.map.KeyExist(key) {
            return null;
        }
        return this.map.Get(key) as NMVanillaEntry;
    }

    public func Apply(snaps: array<ref<NMVanillaSnap>>, sink: ref<NMVanillaSink>) {
        this.Begin();
        for s in snaps {
            if IsDefined(s) {
                this.Observe(s.key, s.x, s.y, s.z, s.variant, s.phase, s.visible, s.tracked, s.filter, sink);
            }
        }
        this.End(sink);
    }

    public func Begin() {
        this.gen += 1;
        this.added = 0;
        this.changed = 0;
        this.removed = 0;
    }

    // One mappin of the current poll. Allocates a snapshot only when the marker is new or differs from the one
    // already held (the steady state allocates nothing).
    public func Observe(key: Uint64, x: Float, y: Float, z: Float, variant: gamedataMappinVariant, phase: gamedataMappinPhase,
                        visible: Bool, tracked: Bool, filter: Int32, sink: ref<NMVanillaSink>) {
        let shown = tracked || (visible && filter >= 0 && NotEquals(phase, gamedataMappinPhase.CompletedPhase));
        if !shown {
            return;
        }
        let e = this.Find(key);
        if !IsDefined(e) {
            let s = NMVanillaSnap.Make(key, x, y, variant, phase, visible, tracked, filter);
            s.z = z;
            e = new NMVanillaEntry();
            e.key = key;
            e.snap = s;
            e.slot = NMVanillaRules.Slot(s);
            e.item = -1;
            e.gen = this.gen;
            sink.OnAdd(e);
            this.map.Insert(key, e);
            ArrayPush(this.entries, e);
            this.added += 1;
            return;
        }
        e.gen = this.gen;
        let o = e.snap;
        if AbsF(o.x - x) > 0.5 || AbsF(o.y - y) > 0.5 || NotEquals(o.variant, variant) || NotEquals(o.phase, phase)
            || NotEquals(o.tracked, tracked) || o.filter != filter {
            let s2 = NMVanillaSnap.Make(key, x, y, variant, phase, visible, tracked, filter);
            s2.z = z;
            sink.OnChange(e, s2);
            e.snap = s2;
            e.slot = NMVanillaRules.Slot(s2);
            this.changed += 1;
        }
    }

    public func End(sink: ref<NMVanillaSink>) {
        // Sweep: anything not seen (or no longer shown) this generation goes away. Swap-remove keeps it O(n).
        let i = ArraySize(this.entries) - 1;
        while i >= 0 {
            let e = this.entries[i];
            if e.gen != this.gen {
                sink.OnRemove(e);
                this.map.Remove(e.key);
                let last = ArraySize(this.entries) - 1;
                this.entries[i] = this.entries[last];
                ArrayPop(this.entries);
                this.removed += 1;
            }
            i -= 1;
        }
        this.live = ArraySize(this.entries);
    }
}
