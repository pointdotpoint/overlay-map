module NightMap

// Where a teleport goes. `exact`: land at (x, y, z) in one move (a fixed vanilla marker, on foot); otherwise z is
// unknown and the driver finds the ground below (x, y).
public class NMTeleportTarget {
    public let x: Float;
    public let y: Float;
    public let z: Float;
    public let exact: Bool;
}

// Teleport target choice and landing maths (spec 2026-10-27-nightmap-teleport-design.md §4). Pure; no game calls.
public abstract class NMTeleport {
    public static func LiftZ() -> Float { return 600.0; }            // above the tallest structure
    public static func SettleTimeoutMs() -> Float { return 5000.0; }
    public static func RayBottomZ() -> Float { return -200.0; }      // below the lowest ground and seabed
    public static func FootOffset() -> Float { return 0.5; }
    public static func VehicleOffset() -> Float { return 1.0; }
    public static func RefuseDrop() -> Float { return 50.0; }        // a lifted vehicle this far below LiftZ did not move
    public static func RefuseWindowMs() -> Float { return 500.0; }   // how long a vehicle may lag the lift before it counts as refused
    public static func StableProbes() -> Int32 { return 3; }         // agreeing hits in a row before landing (collision streams in)
    public static func StableTolerance() -> Float { return 0.1; }

    // Vanilla layers whose marker Z is a floor V can stand on. Pinned (waypoint, tracked quest pin) and Other (markers
    // riding NPCs or vehicles) are not.
    public static func ExactLayer(layerId: CName) -> Bool {
        let s = NameToString(layerId);
        return StrBeginsWith(s, "Vanilla.") && NotEquals(s, "Vanilla.Pinned") && NotEquals(s, "Vanilla.Other");
    }

    // selKind as in NMCrosshair: 0 item (marker = its position), 1 cluster, anything else none. A selected item keeps
    // its X/Y; only no item uses the map centre (cx, cy). Exact only for fixed vanilla markers on foot.
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
