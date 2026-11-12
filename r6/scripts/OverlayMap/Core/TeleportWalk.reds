module OverlayMap

// Seam: the game's human navmesh, the walkable surface NPCs path on. Like collision it only streams in near V, so it
// is asked after V has arrived. The base knows nothing (no spot: the landing stays as it was); NMWorldWalk asks the
// game, tests use a fake.
public class NMWalk {
    public func Streamed(p: Vector4) -> Bool { return false; }
    // The nearest walkable point within r of p.
    public func Near(p: Vector4, r: Float, out q: Vector4) -> Bool { return false; }
    // Walking distance from a to b, or -1 when no path reaches b.
    public func PathLen(a: Vector4, b: Vector4) -> Float { return -1.0; }
}

// Where V stands after a teleport, so V is never left inside a drop point's terminal, in a shopkeeper's cage behind
// the counter, or on a roof (user reports, 2026-11-12). A spot must be walkable and "open": a path from it reaches the
// walkable ground about FarReach away without a long detour. A cage behind bars or a sealed roof fails that test.
public abstract class NMWalkSpot {
    public static func FarReach() -> Float { return 25.0; }
    public static func FarSnap() -> Float { return 6.0; }
    public static func NearSnap() -> Float { return 1.5; }
    public static func MaxDetour() -> Float { return 2.5; }      // path length / straight distance
    public static func DetourSlack() -> Float { return 10.0; }   // metres allowed on top, for doors and corners
    public static func FarChecks() -> Int32 { return 3; }        // open if a path reaches any of the first few far points

    // A pin: beside it (never on it), at the pin's floor.
    public static func PinRings() -> array<Float> { return [2.5, 4.0, 6.0]; }
    public static func PinMinFrom() -> Float { return 1.5; }
    public static func PinZTol() -> Float { return 3.0; }
    // The map centre: the street below, or near it.
    public static func GroundRings() -> array<Float> { return [0.0, 4.0, 8.0]; }
    public static func GroundZTol() -> Float { return 6.0; }

    private static func Dir(i: Int32) -> Vector4 {
        let a = Cast<Float>(i) * 0.785398;   // 8 directions, 45 degrees apart
        return new Vector4(CosF(a), SinF(a), 0.0, 0.0);
    }

    private static func Dist2(a: Vector4, b: Vector4) -> Float {
        let dx = a.X - b.X;
        let dy = a.Y - b.Y;
        return SqrtF(dx * dx + dy * dy);
    }

    public static func Open(w: ref<NMWalk>, p: Vector4, far: array<Vector4>) -> Bool {
        let i = 0;
        while i < ArraySize(far) && i < NMWalkSpot.FarChecks() {
            let f = far[i];
            let len = w.PathLen(p, f);
            if len >= 0.0 && len <= NMWalkSpot.MaxDetour() * Vector4.Distance(p, f) + NMWalkSpot.DetourSlack() {
                return true;
            }
            i += 1;
        }
        return false;
    }

    // The nearest open walkable spot around `anchor`, ring by ring. pin: a pin's spot (beside it, at its floor);
    // otherwise the map centre's (at the anchor if open, the street level the caller puts in anchor.Z).
    public static func Pick(w: ref<NMWalk>, anchor: Vector4, pin: Bool, out spot: Vector4) -> Bool {
        let far: array<Vector4>;
        let i = 0;
        while i < 8 {
            let d = NMWalkSpot.Dir(i);
            let c = new Vector4(anchor.X + d.X * NMWalkSpot.FarReach(), anchor.Y + d.Y * NMWalkSpot.FarReach(), anchor.Z, 1.0);
            let f: Vector4;
            if w.Near(c, NMWalkSpot.FarSnap(), f) { ArrayPush(far, f); }
            i += 1;
        }
        if ArraySize(far) == 0 { return false; }
        let rings = pin ? NMWalkSpot.PinRings() : NMWalkSpot.GroundRings();
        let minFrom = pin ? NMWalkSpot.PinMinFrom() : 0.0;
        let zTol = pin ? NMWalkSpot.PinZTol() : NMWalkSpot.GroundZTol();
        for r in rings {
            let found = false;
            let bestD = 0.0;
            let n = r > 0.0 ? 8 : 1;
            let k = 0;
            while k < n {
                let d = NMWalkSpot.Dir(k);
                let c = new Vector4(anchor.X + d.X * r, anchor.Y + d.Y * r, anchor.Z, 1.0);
                let p: Vector4;
                if w.Near(c, NMWalkSpot.NearSnap(), p) {
                    let from = NMWalkSpot.Dist2(p, anchor);
                    if from >= minFrom && AbsF(p.Z - anchor.Z) <= zTol && (!found || from < bestD) && NMWalkSpot.Open(w, p, far) {
                        found = true;
                        bestD = from;
                        spot = p;
                    }
                }
                k += 1;
            }
            if found { return true; }
        }
        return false;
    }
}
