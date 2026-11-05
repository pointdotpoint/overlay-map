module OverlayMap

// Pure polyline helpers for the GPS route layer. Units are whatever the caller passes (world metres or map pixels).
public abstract class NMRouteGeom {
    public static func TrimWindow() -> Float { return 30.0; }   // only segments starting this close to the route start

    // A new reading is worth a rebuild: point count differs, or the first or last point moved more than 0.5.
    public static func Changed(a: array<Vector2>, b: array<Vector2>) -> Bool {
        let n = ArraySize(a);
        if n != ArraySize(b) { return true; }
        if n == 0 { return false; }
        return NMRouteGeom.Dist2(a[0], b[0]) > 0.25 || NMRouteGeom.Dist2(a[n - 1], b[n - 1]) > 0.25;
    }

    // Trim from the route start (no cursor).
    public static func Trim(pts: array<Vector2>, px: Float, py: Float) -> array<Vector2> {
        return NMRouteGeom.TrimAt(pts, px, py, NMRouteGeom.Closest(pts, px, py, 0));
    }

    // Index of the segment closest to P among those starting less than TrimWindow() along the route from segment
    // `from` (the caller's cursor: the last matched segment). Never searches behind the cursor, so the line cannot
    // be pulled back to the route start when V is far along it. -1 when there is no segment.
    public static func Closest(pts: array<Vector2>, px: Float, py: Float, from: Int32) -> Int32 {
        let n = ArraySize(pts);
        if n < 2 { return -1; }
        let p = new Vector2(px, py);
        let best = -1;
        let bestD = 0.0;
        let along = 0.0;
        let i = Min(Max(from, 0), n - 2);
        while i < n - 1 && along < NMRouteGeom.TrimWindow() {
            let d = NMRouteGeom.Dist2(p, NMRouteGeom.Project(p, pts[i], pts[i + 1]));
            if best < 0 || d < bestD {
                best = i;
                bestD = d;
            }
            along += SqrtF(NMRouteGeom.Dist2(pts[i], pts[i + 1]));
            i += 1;
        }
        return best;
    }

    // [P, projection of P on segment `seg`, the rest of the route after that segment].
    // Drops the part V has passed, and joins V to the route when V strayed off it before the next re-plan.
    public static func TrimAt(pts: array<Vector2>, px: Float, py: Float, seg: Int32) -> array<Vector2> {
        let out: array<Vector2>;
        let n = ArraySize(pts);
        if n < 2 || seg < 0 {
            for p in pts { ArrayPush(out, p); }
            return out;
        }
        let p = new Vector2(px, py);
        ArrayPush(out, p);
        ArrayPush(out, NMRouteGeom.Project(p, pts[seg], pts[seg + 1]));
        let k = seg + 1;
        while k < n {
            ArrayPush(out, pts[k]);
            k += 1;
        }
        return out;
    }

    // Douglas-Peucker with an explicit stack. Always keeps the first and last points.
    public static func Simplify(pts: array<Vector2>, tol: Float) -> array<Vector2> {
        let out: array<Vector2>;
        for k in NMRouteGeom.SimplifyIdx(pts, tol) {
            ArrayPush(out, pts[k]);
        }
        return out;
    }

    // Simplify's kept indices, ascending.
    public static func SimplifyIdx(pts: array<Vector2>, tol: Float) -> array<Int32> {
        let n = ArraySize(pts);
        let out: array<Int32>;
        if n <= 2 {
            let i = 0;
            while i < n { ArrayPush(out, i); i += 1; }
            return out;
        }
        let keep: array<Bool>;
        ArrayResize(keep, n);
        keep[0] = true;
        keep[n - 1] = true;
        let stack: array<Int32>;
        ArrayPush(stack, 0);
        ArrayPush(stack, n - 1);
        let tol2 = tol * tol;
        while ArraySize(stack) > 0 {
            let hi = ArrayPop(stack);
            let lo = ArrayPop(stack);
            let worst = -1;
            let worstD = tol2;
            let j = lo + 1;
            while j < hi {
                let d = NMRouteGeom.Dist2(pts[j], NMRouteGeom.Project(pts[j], pts[lo], pts[hi]));
                if d > worstD {
                    worst = j;
                    worstD = d;
                }
                j += 1;
            }
            if worst >= 0 {
                keep[worst] = true;
                ArrayPush(stack, lo);
                ArrayPush(stack, worst);
                ArrayPush(stack, worst);
                ArrayPush(stack, hi);
            }
        }
        let k = 0;
        while k < n {
            if keep[k] { ArrayPush(out, k); }
            k += 1;
        }
        return out;
    }

    // Douglas-Peucker run once to the end: for each point, the squared tolerance below which it is kept. Splits do not
    // depend on the tolerance (always the first farthest point), and a point survives only if every split above it
    // does, so its importance is its own split distance capped by its parent's. Ends are always kept.
    public static func Importance(pts: array<Vector2>) -> array<Float> {
        let n = ArraySize(pts);
        let imp: array<Float>;
        ArrayResize(imp, n);
        if n == 0 { return imp; }
        imp[0] = 1000000000000.0;
        imp[n - 1] = 1000000000000.0;
        let stack: array<Int32>;
        let caps: array<Float>;
        if n > 2 {
            ArrayPush(stack, 0);
            ArrayPush(stack, n - 1);
            ArrayPush(caps, 1000000000000.0);
        }
        while ArraySize(stack) > 0 {
            let hi = ArrayPop(stack);
            let lo = ArrayPop(stack);
            let cap = ArrayPop(caps);
            let worst = -1;
            let worstD = -1.0;
            let a = pts[lo];
            let b = pts[hi];
            let j = lo + 1;
            while j < hi {
                let d = NMRouteGeom.Dist2(pts[j], NMRouteGeom.Project(pts[j], a, b));
                if d > worstD {
                    worst = j;
                    worstD = d;
                }
                j += 1;
            }
            let v = MinF(worstD, cap);
            imp[worst] = v;
            if worst - lo > 1 {
                ArrayPush(stack, lo);
                ArrayPush(stack, worst);
                ArrayPush(caps, v);
            }
            if hi - worst > 1 {
                ArrayPush(stack, worst);
                ArrayPush(stack, hi);
                ArrayPush(caps, v);
            }
        }
        return imp;
    }

    // The indices SimplifyIdx(pts, tol) keeps, from Importance(pts).
    public static func KeepIdx(imp: array<Float>, tol: Float) -> array<Int32> {
        let out: array<Int32>;
        let tol2 = tol * tol;
        let n = ArraySize(imp);
        let k = 0;
        while k < n {
            if imp[k] > tol2 || k == 0 || k == n - 1 { ArrayPush(out, k); }
            k += 1;
        }
        return out;
    }

    public static func Length(pts: array<Vector2>) -> Float {
        let len = 0.0;
        let i = 1;
        while i < ArraySize(pts) {
            len += SqrtF(NMRouteGeom.Dist2(pts[i - 1], pts[i]));
            i += 1;
        }
        return len;
    }

    public static func Dist2(a: Vector2, b: Vector2) -> Float {
        return (a.X - b.X) * (a.X - b.X) + (a.Y - b.Y) * (a.Y - b.Y);
    }

    // Closest point to p on segment a-b.
    public static func Project(p: Vector2, a: Vector2, b: Vector2) -> Vector2 {
        let dx = b.X - a.X;
        let dy = b.Y - a.Y;
        let len2 = dx * dx + dy * dy;
        if len2 <= 0.0 { return a; }
        let u = ClampF(((p.X - a.X) * dx + (p.Y - a.Y) * dy) / len2, 0.0, 1.0);
        return new Vector2(a.X + u * dx, a.Y + u * dy);
    }
}
