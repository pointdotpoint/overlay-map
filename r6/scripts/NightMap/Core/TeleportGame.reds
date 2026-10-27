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
    private let info: String;

    public static func Create(gi: GameInstance) -> ref<NMWorldGround> {
        let g = new NMWorldGround();
        g.gi = gi;
        return g;
    }

    public func Probe(x: Float, y: Float) -> ref<NMGroundHit> {
        let from = new Vector4(x, y, NMTeleport.LiftZ() - 2.0, 1.0);
        let to = new Vector4(x, y, NMTeleport.RayBottomZ(), 1.0);
        let sq = GameInstance.GetSpatialQueriesSystem(this.gi);
        let trace: TraceResult;
        let ok = sq.SyncRaycastByCollisionGroup(from, to, n"Static", trace, true, false) && TraceResult.IsValid(trace);
        // Diagnostics: the same ray against PlayerBlocker, and the water level at the target, every probe.
        let alt: TraceResult;
        let altOk = sq.SyncRaycastByCollisionGroup(from, to, n"PlayerBlocker", alt, false, false) && TraceResult.IsValid(alt);
        let wl: Float;
        let wOk = AIScriptUtils.GetWaterLevel(this.gi, new Vector3(x, y, 0.0), wl);
        this.info = "static=" + (ok ? FloatToStringPrec(trace.position.Z, 1) : "-") + "|blocker=" + (altOk ? FloatToStringPrec(alt.position.Z, 1) : "-")
            + "|water=" + (wOk ? FloatToStringPrec(wl, 1) : "-");
        if !ok {
            return null;
        }
        let h = new NMGroundHit();
        h.z = trace.position.Z;
        let level: Float;
        h.hasWater = AIScriptUtils.GetWaterLevel(this.gi, new Vector3(x, y, h.z), level);
        h.waterZ = level;
        return h;
    }

    public func Describe() -> String { return this.info; }
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
