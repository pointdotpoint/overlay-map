module NightMap

// Moves the real object (V, or V's vehicle with V in it) with the teleportation facility. The yaw is captured once,
// so every move keeps the facing V had and levels pitch and roll.
public class NMGameMover extends NMMover {
    private let obj: wref<GameObject>;
    private let yaw: Float;

    public static func Create(obj: ref<GameObject>) -> ref<NMGameMover> {
        let m = new NMGameMover();
        m.obj = obj;
        m.yaw = obj.GetWorldYaw();
        return m;
    }

    public func Valid() -> Bool { return IsDefined(this.obj); }

    public func Position() -> Vector4 { return this.obj.GetWorldPosition(); }

    public func Move(p: Vector4) {
        let o: ref<GameObject> = this.obj;
        let rot = new EulerAngles();
        rot.Yaw = this.yaw;
        GameInstance.GetTeleportationFacility(o.GetGame()).Teleport(o, p, rot);
    }
}

// Raycasts straight down against static collision (only what is streamed in), then asks for the water level there.
public class NMWorldGround extends NMGround {
    private let gi: GameInstance;

    public static func Create(gi: GameInstance) -> ref<NMWorldGround> {
        let g = new NMWorldGround();
        g.gi = gi;
        return g;
    }

    public func Probe(x: Float, y: Float) -> ref<NMGroundHit> {
        let from = new Vector4(x, y, NMTeleport.LiftZ() - 2.0, 1.0);
        let to = new Vector4(x, y, NMTeleport.RayBottomZ(), 1.0);
        let trace: TraceResult;
        if !GameInstance.GetSpatialQueriesSystem(this.gi).SyncRaycastByCollisionGroup(from, to, n"Static", trace, true, false)
            || !TraceResult.IsValid(trace) {
            return null;
        }
        let h = new NMGroundHit();
        h.z = trace.position.Z;
        let level: Float;
        h.hasWater = AIScriptUtils.GetWaterLevel(this.gi, new Vector3(x, y, h.z), level);
        h.waterZ = level;
        return h;
    }
}

// Ticks a running teleport after the map has closed (the map's own loop stops with it).
public class NightMapTeleportFrame extends DelayCallback {
    public let system: wref<NightMapSystem>;

    public func Call() {
        if IsDefined(this.system) {
            this.system.TeleportTick();
        }
    }
}
