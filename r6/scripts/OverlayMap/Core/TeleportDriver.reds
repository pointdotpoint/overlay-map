module OverlayMap

// The first solid surface below a point, and the water surface there if any. x and y are where it was found.
public class NMGroundHit {
    public let x: Float;
    public let y: Float;
    public let z: Float;
    public let hasWater: Bool;
    public let waterZ: Float;
}

// Seam: finds the ground below (x, y), from `top` down. `wide` also tries beside the point. The base finds nothing;
// NMWorldGround asks the game, tests use a fake.
public class NMGround {
    public func Probe(x: Float, y: Float, top: Float, wide: Bool) -> ref<NMGroundHit> { return null; }
}

// Seam: the object being teleported (V, or V's vehicle). The base is never valid; NMGameMover moves the real object
// and keeps its yaw, tests use a fake.
public class NMMover {
    public func Valid() -> Bool { return false; }
    public func Ready() -> Bool { return true; }   // false while still mounted (a dismount is under way)
    public func Position() -> Vector4 { return new Vector4(0.0, 0.0, 0.0, 1.0); }
    public func Move(p: Vector4) {}
}

// One teleport, one decision per frame (spec 2026-10-30-overlaymap-teleport-anywhere-design.md). Exact targets land in
// one move. Otherwise V hops near the baked surface and a ray straight down finds the real one; StableProbes agreeing
// hits land V, on the water surface when water lies above. A hop with no hit moves on to the next, and after the last
// V goes back to the start: some cells have no surface at all. Landing is a teleport, so a fall so far does no harm.
public class NMTeleportDriver {
    private let target: ref<NMTeleportTarget>;
    private let mover: ref<NMMover>;
    private let ground: ref<NMGround>;
    private let inVehicle: Bool;
    private let start: Vector4;
    private let steps: Int32;
    private let elapsedMs: Float;
    private let moved: Bool;               // the vehicle was seen off the start
    private let stable: Int32;             // agreeing hits in a row
    private let lastHitZ: Float;
    private let hop: Int32;                // index into target.hops
    private let hopMs: Float;
    private let hopFrames: Int32;
    private let done: Bool;
    private let held: Int32;               // dismount: frames V has been placed at the target
    private let heldMs: Float;
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
        if t.dismount {
            return this.StepDismount(dtMs);
        }
        if this.steps == 1 {
            this.start = this.mover.Position();
            if t.exact {
                let z = t.z + (this.inVehicle ? NMTeleport.VehicleOffset() : NMTeleport.FootOffset());
                this.mover.Move(new Vector4(t.x, t.y, z, 1.0));
                return this.Finish("ok|marker|" + NMTeleportDriver.Xyz(t.x, t.y, z));
            }
            this.mover.Move(new Vector4(t.x, t.y, t.hops[0], 1.0));
            return 0;
        }
        this.elapsedMs += dtMs;
        this.hopMs += dtMs;
        this.hopFrames += 1;
        // A vehicle may follow a few frames late; one still at the start after RefuseWindowMs was refused.
        if this.inVehicle && !this.moved {
            let p = this.mover.Position();
            if Vector4.Distance(p, this.start) > 1.0 {
                this.moved = true;
            } else {
                if this.elapsedMs >= NMTeleport.RefuseWindowMs() {
                    return this.Finish("refused|vehicle");
                }
                return 0;
            }
        }
        let last = this.hop + 1 >= ArraySize(t.hops);
        let wide = last && this.hopFrames >= NMTeleport.WideAfterFrames();
        let hit = this.ground.Probe(t.x, t.y, t.rayTop, wide);
        if IsDefined(hit) {
            this.stable = this.stable > 0 && AbsF(hit.z - this.lastHitZ) <= NMTeleport.StableTolerance() ? this.stable + 1 : 1;
            this.lastHitZ = hit.z;
            if this.stable >= NMTeleport.StableProbes() {
                let z = NMTeleport.LandZ(hit.z, hit.hasWater, hit.waterZ, this.inVehicle);
                this.mover.Move(new Vector4(hit.x, hit.y, z, 1.0));
                return this.Finish("ok|" + NMTeleport.LandKind(hit.z, hit.hasWater, hit.waterZ, this.inVehicle) + "|" + NMTeleportDriver.Xyz(hit.x, hit.y, z)
                    + "|hop=" + IntToString(this.hop) + "|frames=" + IntToString(this.steps));
            }
            return 0;
        }
        this.stable = 0;
        if this.hopMs >= NMTeleport.HopMs() && this.hopFrames >= NMTeleport.HopFrames() {
            if last {
                this.mover.Move(this.start);
                return this.Finish("failed|no ground");
            }
            this.hop += 1;
            this.hopMs = 0.0;
            this.hopFrames = 0;
            this.mover.Move(new Vector4(t.x, t.y, t.hops[this.hop], 1.0));
        }
        return 0;
    }

    // V is leaving the vehicle (the caller asked for it): wait until V is free, then place V at the target and hold it
    // there for SettleMs and SettleFrames, since the game's exit can still move V beside the car.
    private func StepDismount(dtMs: Float) -> Int32 {
        let t = this.target;
        if this.steps > 1 {
            this.elapsedMs += dtMs;
        }
        if !this.mover.Ready() {
            if this.elapsedMs >= NMTeleport.DismountWindowMs() {
                return this.Finish("failed|still mounted");
            }
            return 0;
        }
        if this.held > 0 {
            this.heldMs += dtMs;
        }
        let z = t.z + NMTeleport.FootOffset();
        this.mover.Move(new Vector4(t.x, t.y, z, 1.0));
        this.held += 1;
        if this.held >= NMTeleport.SettleFrames() && this.heldMs >= NMTeleport.SettleMs() {
            return this.Finish("ok|home|" + NMTeleportDriver.Xyz(t.x, t.y, z) + "|frames=" + IntToString(this.steps));
        }
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
