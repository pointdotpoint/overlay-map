module NightMap

// One vector LOD level, copied from NMVectorManifest once per open. Manifest arrays are bound to locals
// first: ArraySize on a function-call temporary reads 0 in-game.
public class NMVecLevel {
    public let index: Int32;
    public let minMpp: Float;
    public let maxMpp: Float;
    public let unit: Float;
    public let ox: Float;
    public let otop: Float;
    public let nx: Int32;
    public let ny: Int32;
    public let cell: Float;
    public let keys: array<Int32>;      // cell key = iy * nx + ix
    public let bounds: array<Float>;    // 4 per cell: x, y, w, h in level units from (ox, otop), Y down
    public let counts: array<Int32>;    // NMTheme.VecStyleCount() per cell
    public let points: array<Int32>;
    public let lookup: array<Int32>;    // key -> cell index, -1 if empty
    public let reach: Int32;            // cells a draw bound can overhang its own cell
    public let exists: array<Int32>;    // per cell: -1 unknown, 0 resource missing, 1 present

    public static func FromManifest(i: Int32) -> ref<NMVecLevel> {
        let l = new NMVecLevel();
        l.index = i;
        l.minMpp = NMVectorManifest.LevelMinMpp(i);
        l.maxMpp = NMVectorManifest.LevelMaxMpp(i);
        l.unit = NMVectorManifest.LevelUnit(i);
        l.ox = NMVectorManifest.LevelOriginX(i);
        l.otop = NMVectorManifest.LevelOriginTop(i);
        l.nx = NMVectorManifest.LevelNx(i);
        l.ny = NMVectorManifest.LevelNy(i);
        l.cell = NMVectorManifest.LevelCell(i);
        let k: array<Int32> = NMVectorManifest.LevelCells(i);
        let b: array<Float> = NMVectorManifest.LevelBounds(i);
        let c: array<Int32> = NMVectorManifest.LevelCounts(i);
        let p: array<Int32> = NMVectorManifest.LevelPoints(i);
        l.keys = k;
        l.bounds = b;
        l.counts = c;
        l.points = p;
        l.BuildLookup();
        return l;
    }

    public func BuildLookup() {
        ArrayClear(this.lookup);
        ArrayClear(this.exists);
        let n = this.nx * this.ny;
        let i = 0;
        while i < n {
            ArrayPush(this.lookup, -1);
            i += 1;
        }
        this.reach = 0;
        let cu = this.cell / this.unit;
        let c = 0;
        while c < ArraySize(this.keys) {
            let key = this.keys[c];
            this.lookup[key] = c;
            ArrayPush(this.exists, -1);
            let ix = Cast<Float>(key % this.nx);
            let iy = Cast<Float>(key / this.nx);
            let over = MaxF(MaxF(ix * cu - this.bounds[4 * c], this.bounds[4 * c] + this.bounds[4 * c + 2] - (ix + 1.0) * cu),
                MaxF(iy * cu - this.bounds[4 * c + 1], this.bounds[4 * c + 1] + this.bounds[4 * c + 3] - (iy + 1.0) * cu));
            this.reach = Max(this.reach, CeilF(MaxF(over, 0.0) / cu));
            c += 1;
        }
    }

    public func CellCount() -> Int32 {
        return ArraySize(this.keys);
    }

    public func Path(c: Int32) -> String {
        let key = this.keys[c];
        return "nightmap\\vec\\V" + ToString(this.index) + "\\c_" + ToString(key % this.nx) + "_" + ToString(key / this.nx) + ".inkshapecollection";
    }

    // Does cell c's draw bounds intersect world rect r?
    public func Hits(c: Int32, r: ref<NMRect>) -> Bool {
        let x0 = this.ox + this.bounds[4 * c] * this.unit;
        let top = this.otop - this.bounds[4 * c + 1] * this.unit;
        let x1 = x0 + this.bounds[4 * c + 2] * this.unit;
        let bottom = top - this.bounds[4 * c + 3] * this.unit;
        return x1 >= r.minX && x0 <= r.maxX && top >= r.minY && bottom <= r.maxY;
    }

    // Index of the first preset of a style in cell c (presets are written in style order).
    public func FirstPreset(c: Int32, style: Int32) -> Int32 {
        let n = NMTheme.VecStyleCount();
        let first = 0;
        let s = 0;
        while s < style {
            first += this.counts[n * c + s];
            s += 1;
        }
        return first;
    }
}
