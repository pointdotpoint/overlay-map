module NightMap

// How a layer's individual items are drawn. Clusters are always hexes.
public enum NightMapPinStyle {
    Hex = 0,
    Icon = 1
}

// One source of map content. Items live in struct-of-arrays storage indexed by a stable id and are
// linked into the 3-level grid pyramid (NMGrid) so the renderer can aggregate by cell without scanning items.
public class NightMapLayer {
    public let id: CName;
    public let displayName: String;
    public let priority: Int32;
    public let index: Int32;
    public let visible: Bool = true;
    public let opacity: Float = 1.0;
    public let minMpp: Float = 0.0;
    public let maxMpp: Float = 100000.0;
    public let clustering: Bool = true;
    public let pinStyle: Int32;
    public let listener: ref<NightMapLayerListener>;
    public let revision: Int32;
    private let owner: wref<NightMap>;
    private let warned: array<String>;

    // local category slot -> global category index; the last slot is "other"
    public let catNames: array<CName>;
    public let catGlobal: array<Int32>;

    public let alive: array<Bool>;
    public let px: array<Float>;
    public let py: array<Float>;
    public let pz: array<Float>;
    public let cat: array<Int32>;
    public let hasAtlas: array<Bool>;
    public let atlas: array<ResRef>;
    public let part: array<CName>;
    public let image: array<String>;
    public let imageResolved: array<String>;
    public let hasTint: array<Bool>;
    public let tint: array<HDRColor>;
    public let label: array<String>;
    public let prio: array<Int32>;
    public let emph: array<Bool>;
    public let alpha: array<Float>;
    public let count: Int32;
    private let freeIds: array<Int32>;

    public let cellOf: array<Int32>;   // [id * 3 + level]
    public let nextIn: array<Int32>;   // [id * 3 + level]
    public let prevIn: array<Int32>;   // [id * 3 + level]
    public let head: array<Int32>;     // [cell]
    public let cnt: array<Int32>;      // [cell]
    public let sumX: array<Float>;     // [cell]
    public let sumY: array<Float>;     // [cell]
    public let tally: array<Int32>;    // [cell * MaxCats + local category]
    private let gridReady: Bool;

    public static func Create(owner: ref<NightMap>, id: CName, displayName: String, priority: Int32, index: Int32) -> ref<NightMapLayer> {
        let l = new NightMapLayer();
        l.owner = owner;
        l.id = id;
        l.displayName = displayName;
        l.priority = priority;
        l.index = index;
        return l;
    }

    // ---- public API -------------------------------------------------------------------------

    public func SetCategory(name: CName, display: String, color: HDRColor) {
        this.owner.RegisterCategory(name, display, color, true);
        this.LocalCat(name);
        this.Touch();
    }

    public func Add(item: ref<NightMapItem>) -> Int32 {
        if !IsDefined(item) {
            this.WarnOnce("null", "Add(null) ignored");
            return -1;
        }
        if !this.owner.InBounds(item.x, item.y) {
            this.WarnOnce("bounds", "item outside world bounds rejected (" + FloatToStringPrec(item.x, 0) + ", " + FloatToStringPrec(item.y, 0) + ")");
            return -1;
        }
        this.EnsureGrid();
        let id: Int32;
        if ArraySize(this.freeIds) > 0 {
            id = ArrayPop(this.freeIds);
        } else {
            id = ArraySize(this.alive);
            this.Grow();
        }
        this.alive[id] = true;
        this.Store(id, item);
        this.Link(id);
        this.count += 1;
        this.Touch();
        return id;
    }

    public func Move(id: Int32, pos: Vector4) -> Bool {
        if !this.IsAlive(id) {
            return false;
        }
        if !this.owner.InBounds(pos.X, pos.Y) {
            this.WarnOnce("bounds", "move outside world bounds rejected");
            return false;
        }
        this.Unlink(id);
        this.px[id] = pos.X;
        this.py[id] = pos.Y;
        this.pz[id] = pos.Z;
        this.Link(id);
        this.Touch();
        return true;
    }

    // Copies an item's fields into slot id (position, category, icon, tint, label, priority, emphasis, opacity).
    private func Store(id: Int32, item: ref<NightMapItem>) {
        this.px[id] = item.x;
        this.py[id] = item.y;
        this.pz[id] = item.z;
        this.cat[id] = this.LocalCat(item.category);
        this.hasAtlas[id] = item.hasAtlas;
        this.atlas[id] = item.atlas;
        this.part[id] = item.part;
        this.image[id] = item.imageKey;
        this.imageResolved[id] = "";
        this.hasTint[id] = item.hasTint;
        this.tint[id] = item.tint;
        this.label[id] = item.label;
        this.prio[id] = item.priority;
        this.emph[id] = item.emphasis;
        this.alpha[id] = item.opacity;
    }

    // Replaces an item's content in place (position, category, icon, tint, label, emphasis, opacity). The id stays valid.
    public func Update(id: Int32, item: ref<NightMapItem>) -> Bool {
        if !this.IsAlive(id) || !IsDefined(item) {
            return false;
        }
        if !this.owner.InBounds(item.x, item.y) {
            this.WarnOnce("bounds", "update outside world bounds rejected");
            return false;
        }
        this.Unlink(id);
        this.Store(id, item);
        this.Link(id);
        this.Touch();
        return true;
    }

    public func SetPinStyle(style: NightMapPinStyle) {
        this.pinStyle = EnumInt(style);
        this.Touch();
    }

    public func Remove(id: Int32) -> Bool {
        if !this.IsAlive(id) {
            return false;
        }
        this.Unlink(id);
        this.alive[id] = false;
        ArrayPush(this.freeIds, id);
        this.count -= 1;
        this.Touch();
        return true;
    }

    public func Clear() {
        ArrayClear(this.alive);
        ArrayClear(this.px);
        ArrayClear(this.py);
        ArrayClear(this.pz);
        ArrayClear(this.cat);
        ArrayClear(this.hasAtlas);
        ArrayClear(this.atlas);
        ArrayClear(this.part);
        ArrayClear(this.image);
        ArrayClear(this.imageResolved);
        ArrayClear(this.hasTint);
        ArrayClear(this.tint);
        ArrayClear(this.label);
        ArrayClear(this.prio);
        ArrayClear(this.emph);
        ArrayClear(this.alpha);
        ArrayClear(this.freeIds);
        ArrayClear(this.cellOf);
        ArrayClear(this.nextIn);
        ArrayClear(this.prevIn);
        this.count = 0;
        this.gridReady = false;
        this.EnsureGrid();
        this.Touch();
    }

    public func SetVisible(v: Bool) {
        this.visible = v;
        this.Touch();
    }

    public func SetOpacity(o: Float) {
        this.opacity = ClampF(o, 0.0, 1.0);
        this.Touch();
    }

    // Visible only while minMpp <= camera meters-per-unit <= maxMpp.
    public func SetZoomRange(minMpp: Float, maxMpp: Float) {
        this.minMpp = minMpp;
        this.maxMpp = maxMpp;
        this.Touch();
    }

    // Non-clustered layers always draw individual chips; keep them small (< 500 items).
    // The renderer scans every alive item of such a layer on each relayout; it is not meant for large counts.
    public func SetClustering(enabled: Bool) {
        this.clustering = enabled;
        this.Touch();
    }

    public func SetListener(l: ref<NightMapLayerListener>) {
        this.listener = l;
    }

    public func IsAlive(id: Int32) -> Bool {
        return id >= 0 && id < ArraySize(this.alive) && this.alive[id];
    }

    public func VisibleAt(mpp: Float) -> Bool {
        return this.visible && mpp >= this.minMpp && mpp <= this.maxMpp;
    }

    public func Position(id: Int32) -> Vector4 {
        return this.IsAlive(id) ? new Vector4(this.px[id], this.py[id], this.pz[id], 1.0) : new Vector4(0.0, 0.0, 0.0, 0.0);
    }

    public func Label(id: Int32) -> String {
        return this.IsAlive(id) ? this.label[id] : "";
    }

    public func CategoryOf(id: Int32) -> CName {
        return this.IsAlive(id) ? this.catNames[this.cat[id]] : n"";
    }

    // ---- internals --------------------------------------------------------------------------

    private func Touch() {
        this.revision += 1;
        this.owner.Touch();
    }

    private func WarnOnce(key: String, msg: String) {
        if !ArrayContains(this.warned, key) {
            ArrayPush(this.warned, key);
            NMLog.Error("layer " + NameToString(this.id) + ": " + msg);
        }
    }

    // Local category slot for a name; registers it globally with defaults if unseen.
    private func LocalCat(name: CName) -> Int32 {
        let i = 0;
        while i < ArraySize(this.catNames) {
            if Equals(this.catNames[i], name) {
                return i;
            }
            i += 1;
        }
        let max = NMGrid.MaxCats();
        if ArraySize(this.catNames) < max - 1 {
            ArrayPush(this.catNames, name);
            ArrayPush(this.catGlobal, this.owner.RegisterCategory(name, NameToString(name), NMTheme.Cyan(), false));
            return ArraySize(this.catNames) - 1;
        }
        if ArraySize(this.catNames) == max - 1 {
            ArrayPush(this.catNames, n"other");
            ArrayPush(this.catGlobal, this.owner.CategoryIndex(n"other"));
            this.WarnOnce("cats", "more than " + ToString(max - 1) + " categories; extra ones map to 'other'");
        }
        return max - 1;
    }

    private func EnsureGrid() {
        if this.gridReady {
            return;
        }
        let total = NMGrid.TotalCells();
        ArrayClear(this.head);
        ArrayClear(this.cnt);
        ArrayClear(this.sumX);
        ArrayClear(this.sumY);
        ArrayClear(this.tally);
        ArrayResize(this.head, total);
        ArrayResize(this.cnt, total);
        ArrayResize(this.sumX, total);
        ArrayResize(this.sumY, total);
        ArrayResize(this.tally, total * NMGrid.MaxCats());
        let c = 0;
        while c < total {
            this.head[c] = -1;
            c += 1;
        }
        this.gridReady = true;
    }

    private func Grow() {
        ArrayPush(this.alive, false);
        ArrayPush(this.px, 0.0);
        ArrayPush(this.py, 0.0);
        ArrayPush(this.pz, 0.0);
        ArrayPush(this.cat, 0);
        ArrayPush(this.hasAtlas, false);
        let emptyRef: ResRef;
        ArrayPush(this.atlas, emptyRef);
        ArrayPush(this.part, n"");
        ArrayPush(this.image, "");
        ArrayPush(this.imageResolved, "");
        ArrayPush(this.hasTint, false);
        ArrayPush(this.tint, new HDRColor(1.0, 1.0, 1.0, 1.0));
        ArrayPush(this.label, "");
        ArrayPush(this.prio, 0);
        ArrayPush(this.emph, false);
        ArrayPush(this.alpha, 1.0);
        let l = 0;
        while l < 3 {
            ArrayPush(this.cellOf, -1);
            ArrayPush(this.nextIn, -1);
            ArrayPush(this.prevIn, -1);
            l += 1;
        }
    }

    private func Link(id: Int32) {
        let l = 0;
        while l < 3 {
            let c = NMGrid.CellIndex(l, this.px[id], this.py[id]);
            let k = id * 3 + l;
            let h = this.head[c];
            this.cellOf[k] = c;
            this.nextIn[k] = h;
            this.prevIn[k] = -1;
            if h >= 0 {
                this.prevIn[h * 3 + l] = id;
            }
            this.head[c] = id;
            this.cnt[c] += 1;
            this.sumX[c] += this.px[id];
            this.sumY[c] += this.py[id];
            this.tally[c * NMGrid.MaxCats() + this.cat[id]] += 1;
            l += 1;
        }
    }

    private func Unlink(id: Int32) {
        let l = 0;
        while l < 3 {
            let k = id * 3 + l;
            let c = this.cellOf[k];
            let n = this.nextIn[k];
            let p = this.prevIn[k];
            if p >= 0 {
                this.nextIn[p * 3 + l] = n;
            } else {
                this.head[c] = n;
            }
            if n >= 0 {
                this.prevIn[n * 3 + l] = p;
            }
            this.cnt[c] -= 1;
            if this.cnt[c] == 0 {
                this.sumX[c] = 0.0;   // reset float drift
                this.sumY[c] = 0.0;
            } else {
                this.sumX[c] -= this.px[id];
                this.sumY[c] -= this.py[id];
            }
            this.tally[c * NMGrid.MaxCats() + this.cat[id]] -= 1;
            this.nextIn[k] = -1;
            this.prevIn[k] = -1;
            this.cellOf[k] = -1;
            l += 1;
        }
    }
}
