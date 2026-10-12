module NightMap

// Vector map layer (spec docs/superpowers/specs/2026-10-12-nightmap-vector-layer-design.md §5).
public class NMVectorLayer {
    // The current level is kept while mpp stays inside its range widened by h; otherwise the first level whose
    // max covers mpp (the last one beyond the range). -1 without levels.
    public let available: Bool;
    public let failed: Bool;
    public let current: Int32;
    private let levels: array<ref<NMVecLevel>>;
    private let canvases: array<ref<inkCanvas>>;
    private let mins: array<Float>;
    private let maxs: array<Float>;
    private let pool: array<ref<inkShape>>;
    private let used: array<ref<inkShape>>;
    private let usedLevel: array<Int32>;
    private let usedGroup: array<Int32>;
    private let groups: array<Int32>;
    private let lastCells: array<Int32>;
    private let previous: Int32;
    private let releaseIn: Int32;
    private let lastRev: Int32;
    private let lastScale: Float;
    private let wanted: Int32;
    private let missing: Int32;
    private let missingMs: Float;
    private let warnedBudget: Bool;
    private let warnedPool: Bool;
    private let warnedMissing: Bool;

    public static func Create(parent: ref<inkCanvas>) -> ref<NMVectorLayer> {
        let v = new NMVectorLayer();
        v.current = -1;
        v.previous = -1;
        v.lastRev = -1;
        v.available = NMVectorManifest.Available() && NMVectorManifest.LevelCount() > 0;
        if !v.available {
            return v;
        }
        let i = 0;
        while i < NMVectorManifest.LevelCount() {
            let l = NMVecLevel.FromManifest(i);
            ArrayPush(v.levels, l);
            ArrayPush(v.mins, l.minMpp);
            ArrayPush(v.maxs, l.maxMpp);
            let c = new inkCanvas();
            c.SetAnchor(inkEAnchor.TopLeft);
            c.SetRenderTransformPivot(new Vector2(0.0, 0.0));
            c.SetInteractive(false);
            c.Reparent(parent);
            ArrayPush(v.canvases, c);
            i += 1;
        }
        let p = 0;
        while p < NMTheme.VecPoolSize() {
            let s = new inkShape();
            s.SetAnchor(inkEAnchor.TopLeft);
            s.SetInteractive(false);
            s.SetEndCapStyle(inkEEndCapStyle.ROUND);
            s.SetJointStyle(inkEJointStyle.ROUND);
            ArrayPush(v.pool, s);
            p += 1;
        }
        return v;
    }

    public func Update(cam: ref<NMCamera>, dtMs: Float) {
        if !this.available || this.failed {
            return;
        }
        let lv = NMVectorLayer.PickLevel(this.mins, this.maxs, this.current, cam.mpp, NMTheme.VecHysteresis());
        if lv != this.current {
            if this.previous >= 0 {
                this.DetachLevel(this.previous);    // one transition at a time: finish the older one
            }
            this.previous = this.current;
            this.current = lv;
            this.releaseIn = 2;
            ArrayClear(this.groups);
            ArrayClear(this.lastCells);
            this.lastRev = -1;
            this.lastScale = 0.0;
        }
        this.Place(this.current, cam);
        if this.previous >= 0 {
            this.Place(this.previous, cam);
        }
        if cam.revision != this.lastRev {
            this.lastRev = cam.revision;
            this.Sync(cam);
        }
        if this.previous >= 0 {
            this.releaseIn -= 1;
            if this.releaseIn <= 0 {
                this.DetachLevel(this.previous);
                this.previous = -1;
            }
        }
        let scale = this.levels[this.current].unit / cam.mpp;
        if NMVectorLayer.NeedsThickness(this.lastScale, scale, NMTheme.VecThicknessStep()) {
            this.lastScale = scale;
            this.Restroke(scale);
        }
        this.WatchMissing(dtMs);
    }

    public func Destroy() {
        let i = ArraySize(this.used) - 1;
        while i >= 0 {
            this.DetachAt(i);
            i -= 1;
        }
        for c in this.canvases {
            let parent = c.GetParentWidget() as inkCompoundWidget;
            if IsDefined(parent) {
                parent.RemoveChild(c);
            }
        }
        ArrayClear(this.canvases);
        ArrayClear(this.pool);
    }

    private func Place(l: Int32, cam: ref<NMCamera>) {
        let lv = this.levels[l];
        let s = lv.unit / cam.mpp;
        let c = this.canvases[l];
        c.SetScale(new Vector2(s, s));
        c.SetTranslation(cam.WorldToMap(lv.ox, lv.otop));
    }

    private func SameCells(a: array<Int32>, b: array<Int32>) -> Bool {
        if ArraySize(a) != ArraySize(b) {
            return false;
        }
        let i = 0;
        while i < ArraySize(a) {
            if a[i] != b[i] {
                return false;
            }
            i += 1;
        }
        return true;
    }

    private func Sync(cam: ref<NMCamera>) {
        let lv = this.levels[this.current];
        let cells = NMVectorLayer.VisibleCells(lv, cam.VisibleRect(0.0));
        if this.SameCells(cells, this.lastCells) {
            return;
        }
        this.lastCells = cells;
        this.wanted = ArraySize(cells);
        this.missing = 0;
        for c in cells {
            if lv.exists[c] < 0 {
                lv.exists[c] = GameInstance.GetResourceDepot().ResourceExists(ResRef.FromString(lv.Path(c))) ? 1 : 0;
            }
            if lv.exists[c] == 0 {
                this.missing += 1;
            }
        }
        if this.missing > 0 && !this.warnedMissing {
            this.warnedMissing = true;
            NMLog.Error("vector: " + ToString(this.missing) + " visible cells have no shape resource (archive stale or missing?)");
        }
        let plan = NMVectorLayer.PlanGroups(lv, cells, NMTheme.VecPointBudget(), NMTheme.VecShapeBudget());
        let full = NMVectorLayer.PlanGroups(lv, cells, 2147483647, 2147483647);
        if ArraySize(plan) < ArraySize(full) && !this.warnedBudget {
            this.warnedBudget = true;
            NMLog.Info("vector: view over budget, skipped " + ToString(ArraySize(full) - ArraySize(plan)) + " shape groups");
        }
        let i = ArraySize(this.used) - 1;
        while i >= 0 {
            if this.usedLevel[i] == this.current && !ArrayContains(plan, this.usedGroup[i]) {
                this.DetachAt(i);
            }
            i -= 1;
        }
        let kept: array<Int32>;
        for g in this.groups {
            if ArrayContains(plan, g) {
                ArrayPush(kept, g);
            }
        }
        this.groups = kept;
        let scale = lv.unit / cam.mpp;
        for g in plan {
            if !ArrayContains(this.groups, g) && lv.exists[g / 8] == 1 {
                if this.AttachGroup(lv, g / 8, g % 8, scale) {
                    ArrayPush(this.groups, g);
                }
            }
        }
    }

    private func AttachGroup(lv: ref<NMVecLevel>, cell: Int32, style: Int32, scale: Float) -> Bool {
        let n = lv.counts[NMTheme.VecStyleCount() * cell + style];
        let path = ResRef.FromString(lv.Path(cell));
        let first = lv.FirstPreset(cell, style);
        let color = NMTheme.VecColor(style);
        let pos = new Vector2(lv.bounds[4 * cell], lv.bounds[4 * cell + 1]);
        let size = new Vector2(MaxF(lv.bounds[4 * cell + 2], 0.01), MaxF(lv.bounds[4 * cell + 3], 0.01));
        let k = 0;
        while k < n {
            if ArraySize(this.pool) == 0 {
                if !this.warnedPool {
                    this.warnedPool = true;
                    NMLog.Error("vector: widget pool exhausted (" + ToString(NMTheme.VecPoolSize()) + ")");
                }
                return false;
            }
            let s = ArrayPop(this.pool);
            s.SetResource(path);
            s.SetShape(StringToName("s" + ToString(first + k)));
            s.SetVariant(NMTheme.VecVariant(style));
            s.SetTintColor(color);
            s.SetFillOpacity(NMTheme.VecFillOpacity(style));
            s.SetBorderColor(color);
            s.SetBorderOpacity(NMTheme.VecBorderOpacity(style));
            s.SetLineThickness(NMVectorLayer.LineWidthFor(style, lv.index, scale));
            s.SetTranslation(pos);
            s.SetSize(size);
            s.Reparent(this.canvases[lv.index]);
            ArrayPush(this.used, s);
            ArrayPush(this.usedLevel, lv.index);
            ArrayPush(this.usedGroup, cell * 8 + style);
            k += 1;
        }
        return true;
    }

    private func DetachAt(i: Int32) {
        let s = this.used[i];
        this.canvases[this.usedLevel[i]].RemoveChild(s);
        ArrayPush(this.pool, s);
        ArrayErase(this.used, i);
        ArrayErase(this.usedLevel, i);
        ArrayErase(this.usedGroup, i);
    }

    private func DetachLevel(l: Int32) {
        let i = ArraySize(this.used) - 1;
        while i >= 0 {
            if this.usedLevel[i] == l {
                this.DetachAt(i);
            }
            i -= 1;
        }
    }

    private func Restroke(scale: Float) {
        let i = 0;
        while i < ArraySize(this.used) {
            if this.usedLevel[i] == this.current {
                this.used[i].SetLineThickness(NMVectorLayer.LineWidthFor(this.usedGroup[i] % 8, this.current, scale));
            }
            i += 1;
        }
    }

    // Every visible cell's resource missing for VecFailMs -> failed (the system falls back to raster).
    private func WatchMissing(dtMs: Float) {
        if this.wanted > 0 && this.missing == this.wanted {
            this.missingMs += dtMs;
            if this.missingMs >= NMTheme.VecFailMs() {
                this.failed = true;
            }
        } else {
            this.missingMs = 0.0;
        }
    }

    public static func PickLevel(mins: array<Float>, maxs: array<Float>, current: Int32, mpp: Float, h: Float) -> Int32 {
        let n = ArraySize(mins);
        if n == 0 {
            return -1;
        }
        if current >= 0 && current < n && mpp >= mins[current] * (1.0 - h) && mpp <= maxs[current] * (1.0 + h) {
            return current;
        }
        let i = 0;
        while i < n {
            if mpp <= maxs[i] {
                return i;
            }
            i += 1;
        }
        return n - 1;
    }

    // Cells whose draw bounds intersect r, nearest centre first.
    public static func VisibleCells(lv: ref<NMVecLevel>, r: ref<NMRect>) -> array<Int32> {
        let out: array<Int32>;
        let dist: array<Float>;
        let ix0 = Max(FloorF((r.minX - lv.ox) / lv.cell) - lv.reach, 0);
        let ix1 = Min(FloorF((r.maxX - lv.ox) / lv.cell) + lv.reach, lv.nx - 1);
        let iy0 = Max(FloorF((lv.otop - r.maxY) / lv.cell) - lv.reach, 0);
        let iy1 = Min(FloorF((lv.otop - r.minY) / lv.cell) + lv.reach, lv.ny - 1);
        let cx = (r.minX + r.maxX) * 0.5;
        let cy = (r.minY + r.maxY) * 0.5;
        let iy = iy0;
        while iy <= iy1 {
            let ix = ix0;
            while ix <= ix1 {
                let c = lv.lookup[iy * lv.nx + ix];
                if c >= 0 && lv.Hits(c, r) {
                    let dx = lv.ox + (Cast<Float>(ix) + 0.5) * lv.cell - cx;
                    let dy = lv.otop - (Cast<Float>(iy) + 0.5) * lv.cell - cy;
                    let d = dx * dx + dy * dy;
                    let j = ArraySize(out);
                    ArrayPush(out, c);
                    ArrayPush(dist, d);
                    while j > 0 && dist[j - 1] > d {
                        out[j] = out[j - 1];
                        dist[j] = dist[j - 1];
                        j -= 1;
                    }
                    out[j] = c;
                    dist[j] = d;
                }
                ix += 1;
            }
            iy += 1;
        }
        return out;
    }

    // Groups (cell * 8 + style) to attach. Pass 1: land, water, roads, metro; pass 2: blocks. A group is skipped
    // when it would push the totals past the point or shape budget.
    public static func PlanGroups(lv: ref<NMVecLevel>, cells: array<Int32>, maxPoints: Int32, maxShapes: Int32) -> array<Int32> {
        let out: array<Int32>;
        let n = NMTheme.VecStyleCount();
        let pts = 0;
        let shp = 0;
        let pass = 0;
        while pass < 2 {
            for c in cells {
                let s = 0;
                while s < n {
                    let block = NMTheme.VecIsBlock(s);
                    if (pass == 0 && !block) || (pass == 1 && block) {
                        let gc = lv.counts[n * c + s];
                        let gp = lv.points[n * c + s];
                        if gc > 0 && pts + gp <= maxPoints && shp + gc <= maxShapes {
                            pts += gp;
                            shp += gc;
                            ArrayPush(out, c * 8 + s);
                        }
                    }
                    s += 1;
                }
            }
            pass += 1;
        }
        return out;
    }

    public static func LineWidthFor(style: Int32, level: Int32, scale: Float) -> Float {
        let w = NMTheme.VecLineWidth(style, level);
        return scale > 0.0 ? w / scale : w;
    }

    public static func NeedsThickness(last: Float, now: Float, step: Float) -> Bool {
        if last <= 0.0 {
            return true;
        }
        return AbsF(now / last - 1.0) > step;
    }
}
