module NightMap

// The first solid surface below a point, and the water surface there if any.
public class NMGroundHit {
    public let z: Float;
    public let hasWater: Bool;
    public let waterZ: Float;
}

// Seam: finds the ground below (x, y). The base finds nothing; NMWorldGround asks the game, tests use a fake.
public class NMGround {
    public func Probe(x: Float, y: Float) -> ref<NMGroundHit> { return null; }
}

// Seam: the object being teleported (V, or V's vehicle). The base is never valid; NMGameMover moves the real object
// and keeps its yaw, tests use a fake.
public class NMMover {
    public func Valid() -> Bool { return false; }
    public func Position() -> Vector4 { return new Vector4(0.0, 0.0, 0.0, 1.0); }
    public func Move(p: Vector4) {}
}

// One teleport, one decision per frame (spec 2026-10-27-nightmap-teleport-design.md §4.3-4.5). Exact targets land
// in one move. Otherwise: lift to LiftZ, then each frame probe the ground; a hit lands (on the water surface when
// water lies above it), no hit re-lifts so V never falls, and after SettleTimeoutMs V goes back to the start.
public class NMTeleportDriver {
    private let target: ref<NMTeleportTarget>;
    private let mover: ref<NMMover>;
    private let ground: ref<NMGround>;
    private let inVehicle: Bool;
    private let start: Vector4;
    private let steps: Int32;
    private let elapsedMs: Float;
    private let done: Bool;
    public let result: String;

    public static func Create(t: ref<NMTeleportTarget>, mover: ref<NMMover>, ground: ref<NMGround>, inVehicle: Bool) -> ref<NMTeleportDriver> {
        let d = new NMTeleportDriver();
        d.target = t;
        d.mover = mover;
        d.ground = ground;
        d.inVehicle = inVehicle;
        return d;
    }

    // 0 running, 1 done (`result` holds the log tail).
    public func Step(dtMs: Float) -> Int32 {
        if this.done { return 1; }
        this.steps += 1;
        let t = this.target;
        if !this.mover.Valid() {
            return this.Finish("failed|lost");
        }
        if this.steps == 1 {
            this.start = this.mover.Position();
            if t.exact {
                let z = t.z + (this.inVehicle ? NMTeleport.VehicleOffset() : NMTeleport.FootOffset());
                this.mover.Move(new Vector4(t.x, t.y, z, 1.0));
                return this.Finish("ok|marker|" + NMTeleportDriver.Xyz(t.x, t.y, z));
            }
            this.mover.Move(new Vector4(t.x, t.y, NMTeleport.LiftZ(), 1.0));
            return 0;
        }
        if this.steps == 2 && this.inVehicle && this.mover.Position().Z < NMTeleport.LiftZ() - NMTeleport.RefuseDrop() {
            return this.Finish("refused|vehicle");
        }
        this.elapsedMs += dtMs;
        let hit = this.ground.Probe(t.x, t.y);
        if IsDefined(hit) {
            let z = NMTeleport.LandZ(hit.z, hit.hasWater, hit.waterZ, this.inVehicle);
            this.mover.Move(new Vector4(t.x, t.y, z, 1.0));
            return this.Finish("ok|" + NMTeleport.LandKind(hit.z, hit.hasWater, hit.waterZ, this.inVehicle) + "|" + NMTeleportDriver.Xyz(t.x, t.y, z));
        }
        if this.elapsedMs >= NMTeleport.SettleTimeoutMs() {
            this.mover.Move(this.start);
            return this.Finish("failed|no ground");
        }
        this.mover.Move(new Vector4(t.x, t.y, NMTeleport.LiftZ(), 1.0));
        return 0;
    }

    private func Finish(r: String) -> Int32 {
        this.done = true;
        this.result = r;
        return 1;
    }

    private static func Xyz(x: Float, y: Float, z: Float) -> String {
        return FloatToStringPrec(x, 1) + "," + FloatToStringPrec(y, 1) + "," + FloatToStringPrec(z, 1);
    }
}
