module NightMap

// Vector map layer (spec docs/superpowers/specs/2026-10-12-nightmap-vector-layer-design.md §5).
public class NMVectorLayer {
    // The current level is kept while mpp stays inside its range widened by h; otherwise the first level whose
    // max covers mpp (the last one beyond the range). -1 without levels.
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
