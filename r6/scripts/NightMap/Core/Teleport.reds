module NightMap

// Where a teleport goes. `exact`: land at (x, y, z) in one move (a fixed vanilla marker, on foot). Otherwise V goes to
// each height in `hops` in turn and a ray from `rayTop` finds the surface.
public class NMTeleportTarget {
    public let x: Float;
    public let y: Float;
    public let z: Float;
    public let exact: Bool;
    public let hops: array<Float>;
    public let rayTop: Float;
}

// Teleport target choice and landing maths (spec 2026-10-30-nightmap-teleport-anywhere-design.md). No game calls.
public abstract class NMTeleport {
    // Collision only loads within about 100 m of V (in-game, 2026-10-30), so V goes near the baked surface, never high.
    public static func HighMargin() -> Float { return 5.0; }         // above the cell's highest surface
    public static func LowMargin() -> Float { return 20.0; }         // above its lowest
    public static func OneHopGap() -> Float { return 40.0; }         // a cell flatter than this needs one hop
    public static func RayAboveHigh() -> Float { return 10.0; }
    public static func RayBottomZ() -> Float { return -200.0; }      // below the lowest ground and seabed
    // A hop lasts this long and this many frames: frames stop under the game's streaming screen, and a fast display
    // runs many frames in the time collision takes. In-game the slowest first hit was frame 7, 266 ms.
    public static func HopMs() -> Float { return 400.0; }
    public static func HopFrames() -> Int32 { return 12; }
    public static func WideAfterFrames() -> Int32 { return 6; }      // last hop: then also try beside the point
    public static func WideReach() -> Float { return 16.0; }         // an open shaft can have no surface at all
    public static func FootOffset() -> Float { return 0.5; }
    public static func VehicleOffset() -> Float { return 1.0; }
    public static func RefuseWindowMs() -> Float { return 500.0; }   // how long a vehicle may lag before it counts as refused
    public static func StableProbes() -> Int32 { return 3; }         // agreeing hits in a row before landing
    public static func StableTolerance() -> Float { return 0.2; }

    // Layers whose marker Z is a floor V can stand on: vanilla ones, and collectibles. Pinned (waypoint, tracked quest pin) and Other (markers
    // riding NPCs or vehicles) are not.
    public static func ExactLayer(layerId: CName) -> Bool {
        let s = NameToString(layerId);
        if StrBeginsWith(s, "Collect.") { return true; }   // collectibles sit where the world placed them
        return StrBeginsWith(s, "Vanilla.") && NotEquals(s, "Vanilla.Pinned") && NotEquals(s, "Vanilla.Other");
    }

    // The hops for a cell whose surfaces span low..high. The highest comes first, so a roof is found; a street beside
    // a tower then needs the low hop, because from the tower's height its collision never loads.
    public static func Hops(low: Float, high: Float) -> array<Float> {
        let hops: array<Float>;
        ArrayPush(hops, high + NMTeleport.HighMargin());
        if high - low > NMTeleport.OneHopGap() {
            ArrayPush(hops, low + NMTeleport.LowMargin());
        }
        return hops;
    }

    // selKind as in NMCrosshair: 0 item (marker = its position), anything else the map centre (cx, cy). A selected item
    // keeps its X/Y. Exact only for fixed vanilla markers on foot. low and high are the baked surfaces of the target.
    public static func Choose(selKind: Int32, layerId: CName, marker: Vector4, cx: Float, cy: Float, inVehicle: Bool) -> ref<NMTeleportTarget> {
        let t = new NMTeleportTarget();
        if selKind == 0 {
            t.x = marker.X;
            t.y = marker.Y;
            t.z = marker.Z;
            t.exact = !inVehicle && NMTeleport.ExactLayer(layerId);
        } else {
            t.x = cx;
            t.y = cy;
        }
        let high = NMHeight.High(t.x, t.y);
        t.hops = NMTeleport.Hops(NMHeight.Low(t.x, t.y), high);
        t.rayTop = high + NMTeleport.RayAboveHigh();
        return t;
    }

    public static func InBounds(x: Float, y: Float) -> Bool {
        return x >= NMTileManifest.WorldMinX() && x <= NMTileManifest.WorldMaxX()
            && y >= NMTileManifest.WorldMinY() && y <= NMTileManifest.WorldMaxY();
    }

    // The landing height: the hit plus the offset, or the water surface when water lies above that.
    public static func LandZ(hitZ: Float, hasWater: Bool, waterZ: Float, inVehicle: Bool) -> Float {
        let ground = hitZ + (inVehicle ? NMTeleport.VehicleOffset() : NMTeleport.FootOffset());
        return hasWater && waterZ > ground ? waterZ : ground;
    }

    public static func LandKind(hitZ: Float, hasWater: Bool, waterZ: Float, inVehicle: Bool) -> String {
        let ground = hitZ + (inVehicle ? NMTeleport.VehicleOffset() : NMTeleport.FootOffset());
        return hasWater && waterZ > ground ? "water" : "ground";
    }
}
