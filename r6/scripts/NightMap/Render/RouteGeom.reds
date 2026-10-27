module NightMap

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

    // [P, projection of P on the closest early segment, the rest of the route after that segment].
    // Drops the part V has passed, and joins V to the route when V strayed off it before the next re-plan.
    public static func Trim(pts: array<Vector2>, px: Float, py: Float) -> array<Vector2> {
        let out: array<Vector2>;
        let n = ArraySize(pts);
        if n < 2 {
            for p in pts { ArrayPush(out, p); }
            return out;
        }
        let p = new Vector2(px, py);
        let best = -1;
        let bestD = 0.0;
        let bestQ = pts[0];
        let along = 0.0;
        let i = 0;
        while i < n - 1 && along < NMRouteGeom.TrimWindow() {
            let q = NMRouteGeom.Project(p, pts[i], pts[i + 1]);
            let d = NMRouteGeom.Dist2(p, q);
            if best < 0 || d < bestD {
                best = i;
                bestD = d;
                bestQ = q;
            }
            along += SqrtF(NMRouteGeom.Dist2(pts[i], pts[i + 1]));
            i += 1;
        }
        ArrayPush(out, p);
        ArrayPush(out, bestQ);
        let k = best + 1;
        while k < n {
            ArrayPush(out, pts[k]);
            k += 1;
        }
        return out;
    }

    // Douglas-Peucker with an explicit stack. Always keeps the first and last points.
    public static func Simplify(pts: array<Vector2>, tol: Float) -> array<Vector2> {
        let n = ArraySize(pts);
        let out: array<Vector2>;
        if n <= 2 {
            for p in pts { ArrayPush(out, p); }
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
            if keep[k] { ArrayPush(out, pts[k]); }
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
