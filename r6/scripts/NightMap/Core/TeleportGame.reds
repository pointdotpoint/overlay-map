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

// Raycasts straight down against what has loaded: buildings are Static, open ground is Terrain, and the higher hit is
// the surface. Then asks for the water level there, which only answers from below the surface.
public class NMWorldGround extends NMGround {
    private let gi: GameInstance;

    public static func Create(gi: GameInstance) -> ref<NMWorldGround> {
        let g = new NMWorldGround();
        g.gi = gi;
        return g;
    }

    private func Surface(x: Float, y: Float, top: Float, out z: Float) -> Bool {
        let from = new Vector4(x, y, top, 1.0);
        let to = new Vector4(x, y, NMTeleport.RayBottomZ(), 1.0);
        let sq = GameInstance.GetSpatialQueriesSystem(this.gi);
        let s: TraceResult;
        let t: TraceResult;
        let hasS = sq.SyncRaycastByCollisionGroup(from, to, n"Static", s, false, false) && TraceResult.IsValid(s);
        let hasT = sq.SyncRaycastByCollisionGroup(from, to, n"Terrain", t, false, false) && TraceResult.IsValid(t);
        if hasS && hasT {
            z = MaxF(s.position.Z, t.position.Z);
        } else if hasS {
            z = s.position.Z;
        } else if hasT {
            z = t.position.Z;
        }
        return hasS || hasT;
    }

    private func Hit(x: Float, y: Float, z: Float) -> ref<NMGroundHit> {
        let h = new NMGroundHit();
        h.x = x;
        h.y = y;
        h.z = z;
        let level: Float;
        h.hasWater = AIScriptUtils.GetWaterLevel(this.gi, new Vector3(x, y, z), level);
        h.waterZ = level;
        return h;
    }

    public func Probe(x: Float, y: Float, top: Float, wide: Bool) -> ref<NMGroundHit> {
        let z: Float;
        if this.Surface(x, y, top, z) {
            return this.Hit(x, y, z);
        }
        if wide {
            let r = NMTeleport.WideReach();
            let dx = [r, -r, 0.0, 0.0];
            let dy = [0.0, 0.0, r, -r];
            let i = 0;
            while i < 4 {
                if this.Surface(x + dx[i], y + dy[i], top, z) {
                    return this.Hit(x + dx[i], y + dy[i], z);
                }
                i += 1;
            }
        }
        return null;
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
