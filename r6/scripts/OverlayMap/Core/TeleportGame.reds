module OverlayMap

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

    public func Ready() -> Bool {
        let o: ref<GameObject> = this.obj;
        return !GameInstance.GetMountingFacility(o.GetGame()).IsMountedToAnything(o.GetEntityID());
    }

    public func Position() -> Vector4 { return this.obj.GetWorldPosition(); }

    public func Move(p: Vector4) {
        let o: ref<GameObject> = this.obj;
        let rot = new EulerAngles();
        rot.Yaw = this.yaw;
        GameInstance.GetTeleportationFacility(o.GetGame()).Teleport(o, p, rot);
    }
}

public abstract class NMTeleportGame {
    // Takes V out of the mounted vehicle at once, the way the game's own instant exits do (vehicleTransition.script).
    public static func Dismount(player: ref<GameObject>) {
        let mf = GameInstance.GetMountingFacility(player.GetGame());
        let req = new UnmountingRequest();
        req.lowLevelMountingInfo = mf.GetMountingInfoSingleWithObjects(player);
        req.mountData = new MountEventData();
        req.mountData.isInstant = true;
        mf.Unmount(req);
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

// The game's human navmesh (NavigationSystem), for NMWalkSpot.
public class NMWorldWalk extends NMWalk {
    private let gi: GameInstance;

    public static func Create(gi: GameInstance) -> ref<NMWorldWalk> {
        let w = new NMWorldWalk();
        w.gi = gi;
        return w;
    }

    public func Streamed(p: Vector4) -> Bool {
        return GameInstance.GetNavigationSystem(this.gi).IsNavmeshStreamedInLocation(p, 2.0);
    }

    public func Near(p: Vector4, r: Float, out q: Vector4) -> Bool {
        let res = GameInstance.GetNavigationSystem(this.gi).FindPointInSphereOnlyHumanNavmesh(p, r, NavGenAgentSize.Human, true);
        if NotEquals(res.status, worldNavigationRequestStatus.OK) { return false; }
        q = res.point;
        return true;
    }

    public func PathLen(a: Vector4, b: Vector4) -> Float {
        let path = GameInstance.GetNavigationSystem(this.gi).CalculatePathOnlyHumanNavmesh(a, b, NavGenAgentSize.Human, 0.5);
        if !IsDefined(path) { return -1.0; }
        let n = ArraySize(path.path);
        if n == 0 { return -1.0; }
        if Vector4.Distance(path.path[n - 1], b) > 1.5 { return -1.0; }   // a partial path stops short of b
        return path.CalculateLength();
    }
}

// Ticks a running teleport after the map has closed (the map's own loop stops with it).
public class OverlayMapTeleportFrame extends DelayCallback {
    public let system: wref<OverlayMapSystem>;

    public func Call() {
        if IsDefined(this.system) {
            this.system.TeleportTick();
        }
    }
}
