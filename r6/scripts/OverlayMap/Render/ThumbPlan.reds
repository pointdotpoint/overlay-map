module OverlayMap

// Which photo thumbnails to hold, keyed by shot hash (not by chip slot, which changes with every relayout).
// Fixed slots 0..cap-1 (hash 0 = free); one load in flight at a time; a want that is off screen by the next
// layout is dropped before it is ever requested. Pure: the renderer owns one inkImage per slot.
public class NMThumbPlan {
    private let hashes: array<Uint32>;
    private let ready: array<Bool>;
    private let used: array<Bool>;
    private let wanted: array<Uint32>;
    private let inFlight: Uint32;

    public static func Create(cap: Int32) -> ref<NMThumbPlan> {
        let p = new NMThumbPlan();
        let i = 0;
        while i < cap {
            ArrayPush(p.hashes, 0u);
            ArrayPush(p.ready, false);
            ArrayPush(p.used, false);
            i += 1;
        }
        return p;
    }

    public func Cap() -> Int32 { return ArraySize(this.hashes); }
    public func HashAt(slot: Int32) -> Uint32 { return this.hashes[slot]; }
    public func IsReady(slot: Int32) -> Bool { return slot >= 0 && slot < ArraySize(this.ready) && this.ready[slot]; }
    public func IsUsed(slot: Int32) -> Bool { return this.used[slot]; }

    public func SlotOf(h: Uint32) -> Int32 {
        let i = 0;
        while i < ArraySize(this.hashes) {
            if this.hashes[i] == h { return i; }
            i += 1;
        }
        return -1;
    }

    public func BeginLayout() {
        let i = 0;
        while i < ArraySize(this.used) {
            this.used[i] = false;
            i += 1;
        }
        ArrayClear(this.wanted);
    }

    // The slot holding h (marked used this layout), or -1 when h is not held yet (queued, in placement order).
    public func Want(h: Uint32) -> Int32 {
        let s = this.SlotOf(h);
        if s >= 0 {
            this.used[s] = true;
            return s;
        }
        if !ArrayContains(this.wanted, h) {
            ArrayPush(this.wanted, h);
        }
        return -1;
    }

    // Frees slots this layout did not use (never the one loading), so wanted shots can take them.
    public func EndLayout() {
        let i = 0;
        while i < ArraySize(this.hashes) {
            if !this.used[i] && this.hashes[i] != 0u && this.hashes[i] != this.inFlight {
                this.hashes[i] = 0u;
                this.ready[i] = false;
            }
            i += 1;
        }
    }

    // The next hash to load into SlotOf(it), or 0 (one already loading, nothing wanted, or no free slot).
    public func NextRequest() -> Uint32 {
        if this.inFlight != 0u || ArraySize(this.wanted) == 0 {
            return 0u;
        }
        let free = this.SlotOf(0u);
        if free < 0 {
            return 0u;
        }
        let h = this.wanted[0];
        ArrayErase(this.wanted, 0);
        this.hashes[free] = h;
        this.ready[free] = false;
        this.inFlight = h;
        return h;
    }

    public func Loaded(h: Uint32, ok: Bool) {
        if h == this.inFlight {
            this.inFlight = 0u;
        }
        let s = this.SlotOf(h);
        if s < 0 { return; }
        if ok {
            this.ready[s] = true;
        } else {
            this.hashes[s] = 0u;
            this.ready[s] = false;
        }
    }

    public func Clear() {
        let i = 0;
        while i < ArraySize(this.hashes) {
            this.hashes[i] = 0u;
            this.ready[i] = false;
            this.used[i] = false;
            i += 1;
        }
        ArrayClear(this.wanted);
        this.inFlight = 0u;
    }
}
