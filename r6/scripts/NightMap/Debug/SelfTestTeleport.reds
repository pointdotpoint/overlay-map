module NightMap

// Test seam: records moves instead of teleporting. Position is the last move, or `start` when it ignores moves.
public class NMFakeMover extends NMMover {
    public let moves: array<Vector4>;
    public let start: Vector4;
    public let moving: Bool;
    public let positionAfter: Int32;  // Position() follows moves only from this many calls on (a late vehicle); 0 = at once
    public let positionCalls: Int32;
    public let invalidAfter: Int32;   // Valid() turns false once this many moves were made; 0 = never
    public let zeroZ: Bool;           // Position().Z reads 0 after the first move (a pending teleport, as in game)

    public static func Create(start: Vector4) -> ref<NMFakeMover> {
        let m = new NMFakeMover();
        m.start = start;
        m.moving = true;
        return m;
    }

    public func Valid() -> Bool { return this.invalidAfter <= 0 || ArraySize(this.moves) < this.invalidAfter; }

    public func Position() -> Vector4 {
        this.positionCalls += 1;
        let n = ArraySize(this.moves);
        let p = this.moving && n > 0 && this.positionCalls >= this.positionAfter ? this.moves[n - 1] : this.start;
        if this.zeroZ && n > 0 { p.Z = 0.0; }
        return p;
    }

    public func Move(p: Vector4) { ArrayPush(this.moves, p); }
}

// Test seam: no hit until the `hitOn`-th probe (0 = never).
public class NMFakeGround extends NMGround {
    public let hitOn: Int32;
    public let calls: Int32;
    public let zs: array<Float>;      // when set: the hit Z per probe from hitOn on (last value repeats)
    public let z: Float;
    public let hasWater: Bool;
    public let waterZ: Float;
    public let mover: ref<NMFakeMover>;  // when set: no hit while the last move is above streamZ (collision streams near V)
    public let streamZ: Float;

    public static func Create(hitOn: Int32, z: Float, hasWater: Bool, waterZ: Float) -> ref<NMFakeGround> {
        let g = new NMFakeGround();
        g.hitOn = hitOn;
        g.z = z;
        g.hasWater = hasWater;
        g.waterZ = waterZ;
        return g;
    }

    public func Probe(x: Float, y: Float) -> ref<NMGroundHit> {
        if IsDefined(this.mover) && ArraySize(this.mover.moves) > 0 && this.mover.moves[ArraySize(this.mover.moves) - 1].Z > this.streamZ {
            return null;
        }
        this.calls += 1;
        if this.hitOn <= 0 || this.calls < this.hitOn { return null; }
        let h = new NMGroundHit();
        h.z = this.z;
        let n = ArraySize(this.zs);
        if n > 0 { h.z = this.zs[Min(this.calls - this.hitOn, n - 1)]; }
        h.hasWater = this.hasWater;
        h.waterZ = this.waterZ;
        return h;
    }
}

// Self-test group for teleport: target choice, landing maths and the driver with fake game seams. Called from
// NMSelfTest.Run(). Nothing is teleported.
public abstract class NMTeleportTests {
    public static func Run(t: ref<NMSelfTest>) {
        NMTeleportTests.TargetCases(t);
        NMTeleportTests.DriverCases(t);
        NMTeleportTests.WiringCases(t);
    }

    private static func WiringCases(t: ref<NMSelfTest>) {
        let s = new NightMapSettings();
        s.teleportEnabled = true;
        t.Check("teleport.hint_on", StrContains(NMInput.HintText(s, "ALL"), "TELEPORT"), "");
        s.teleportEnabled = false;
        t.Check("teleport.hint_off", !StrContains(NMInput.HintText(s, "ALL"), "TELEPORT"), "");

        let sys = NightMapSystem.Get(GetGameInstance());
        if IsDefined(sys) {
            let busy = NMTeleportDriver.Create(NMTeleportTests.Target(0.0, 0.0, 0.0, false), new NMMover(), new NMGround(), false);
            sys.SetTeleportDriverForTest(busy);
            t.Check("teleport.busy", !sys.StartTeleport(), "");
            sys.SetTeleportDriverForTest(null);
        } else {
            t.Check("teleport.busy", false, "no NightMapSystem");
        }
    }

    // Steps a driver at 16 ms until it is done (at most 1000 steps); returns the step count.
    private static func Drive(d: ref<NMTeleportDriver>) -> Int32 {
        let n = 0;
        while n < 1000 {
            n += 1;
            if d.Step(16.0) == 1 { return n; }
        }
        return n;
    }

    private static func Target(x: Float, y: Float, z: Float, exact: Bool) -> ref<NMTeleportTarget> {
        let t = new NMTeleportTarget();
        t.x = x;
        t.y = y;
        t.z = z;
        t.exact = exact;
        return t;
    }

    private static func Last(m: ref<NMFakeMover>) -> Vector4 {
        return m.moves[ArraySize(m.moves) - 1];
    }

    private static func DriverCases(t: ref<NMSelfTest>) {
        let start = new Vector4(7.0, 8.0, 9.0, 1.0);

        let m1 = NMFakeMover.Create(start);
        let d1 = NMTeleportDriver.Create(NMTeleportTests.Target(1.0, 2.0, 3.0, true), m1, NMFakeGround.Create(0, 0.0, false, 0.0), false);
        NMTeleportTests.Drive(d1);
        t.Check("teleport.driver_marker", ArraySize(m1.moves) == 1 && t.Near(m1.moves[0].Z, 3.5, 0.001) && m1.moves[0].X == 1.0
            && StrBeginsWith(d1.result, "ok|marker"), d1.result);

        let m2 = NMFakeMover.Create(start);
        let d2 = NMTeleportDriver.Create(NMTeleportTests.Target(1.0, 2.0, 0.0, false), m2, NMFakeGround.Create(3, 40.0, false, 0.0), false);
        NMTeleportTests.Drive(d2);
        t.Check("teleport.driver_ground", t.Near(NMTeleportTests.Last(m2).Z, 40.5, 0.001) && StrBeginsWith(d2.result, "ok|ground"), d2.result);
        let held = ArraySize(m2.moves) >= 2;
        let i = 0;
        while i < ArraySize(m2.moves) - 1 {
            if m2.moves[i].Z != NMTeleport.LiftZ() { held = false; }
            i += 1;
        }
        t.Check("teleport.driver_holds", held, ToString(ArraySize(m2.moves)) + " moves");
        // One lift, then no teleports while waiting: a teleport every frame keeps V mid-teleport (position reads 0
        // and nothing streams in; in-game trace 2026-10-27).
        t.Check("teleport.driver_single_lift", ArraySize(m2.moves) == 2, ToString(ArraySize(m2.moves)) + " moves");

        let m3 = NMFakeMover.Create(start);
        let d3 = NMTeleportDriver.Create(NMTeleportTests.Target(1.0, 2.0, 0.0, false), m3, NMFakeGround.Create(1, -10.0, true, 0.0), false);
        NMTeleportTests.Drive(d3);
        t.Check("teleport.driver_water", t.Near(NMTeleportTests.Last(m3).Z, 0.0, 0.001) && StrBeginsWith(d3.result, "ok|water"), d3.result);

        let m4 = NMFakeMover.Create(start);
        let d4 = NMTeleportDriver.Create(NMTeleportTests.Target(1.0, 2.0, 0.0, false), m4, NMFakeGround.Create(0, 0.0, false, 0.0), false);
        let steps = NMTeleportTests.Drive(d4);
        let back = NMTeleportTests.Last(m4);
        t.Check("teleport.driver_timeout", back.X == 7.0 && back.Y == 8.0 && back.Z == 9.0 && Equals(d4.result, "failed|no ground")
            && Cast<Float>(steps) * 16.0 >= NMTeleport.SettleTimeoutMs(), d4.result + " " + ToString(steps));

        let m5 = NMFakeMover.Create(new Vector4(7.0, 8.0, 20.0, 1.0));
        m5.moving = false;
        let d5 = NMTeleportDriver.Create(NMTeleportTests.Target(1.0, 2.0, 0.0, false), m5, NMFakeGround.Create(1, 40.0, false, 0.0), true);
        NMTeleportTests.Drive(d5);
        let back5 = NMTeleportTests.Last(m5);
        t.Check("teleport.driver_refused", Equals(d5.result, "refused|vehicle") && back5.Z == 20.0 && back5.X == 7.0,
            d5.result + " " + ToString(ArraySize(m5.moves)));

        // A vehicle that follows the teleport a few frames late is not a refusal; it lands with the vehicle offset.
        let m7 = NMFakeMover.Create(new Vector4(7.0, 8.0, 20.0, 1.0));
        m7.positionAfter = 4;
        let d7 = NMTeleportDriver.Create(NMTeleportTests.Target(1.0, 2.0, 0.0, false), m7, NMFakeGround.Create(1, 40.0, false, 0.0), true);
        NMTeleportTests.Drive(d7);
        t.Check("teleport.driver_vehicle_late", StrBeginsWith(d7.result, "ok|ground") && t.Near(NMTeleportTests.Last(m7).Z, 41.0, 0.001), d7.result);

        // Collision still streaming in: the first hits disagree; land only on StableProbes() agreeing hits.
        let m8 = NMFakeMover.Create(start);
        let g8 = NMFakeGround.Create(1, 0.0, false, 0.0);
        ArrayPush(g8.zs, 10.0);
        ArrayPush(g8.zs, 25.0);
        ArrayPush(g8.zs, 40.0);
        let d8 = NMTeleportDriver.Create(NMTeleportTests.Target(1.0, 2.0, 0.0, false), m8, g8, false);
        NMTeleportTests.Drive(d8);
        t.Check("teleport.driver_stable", t.Near(NMTeleportTests.Last(m8).Z, 40.5, 0.001) && g8.calls >= 2 + NMTeleport.StableProbes(),
            d8.result + " calls " + ToString(g8.calls));

        // Ground 600 m below V never streams in (in-game trace 2026-10-27): step down through LiftLevels() until it
        // does, never below the level where it was found.
        let m9 = NMFakeMover.Create(start);
        let g9 = NMFakeGround.Create(1, 40.0, false, 0.0);
        g9.mover = m9;
        g9.streamZ = 150.0;
        let d9 = NMTeleportDriver.Create(NMTeleportTests.Target(1.0, 2.0, 0.0, false), m9, g9, false);
        NMTeleportTests.Drive(d9);
        let desc = ArraySize(m9.moves) >= 3;
        let j = 1;
        while j < ArraySize(m9.moves) - 1 {
            if m9.moves[j].Z >= m9.moves[j - 1].Z || m9.moves[j].Z < 150.0 { desc = false; }
            j += 1;
        }
        t.Check("teleport.driver_descends", desc && StrBeginsWith(d9.result, "ok|ground") && t.Near(NMTeleportTests.Last(m9).Z, 40.5, 0.001),
            d9.result + " " + ToString(ArraySize(m9.moves)) + " moves");

        // Height reads 0 while a teleport is pending (in-game trace): a vehicle that moved off its start counts as lifted.
        let m10 = NMFakeMover.Create(new Vector4(500.0, 8.0, 20.0, 1.0));
        m10.zeroZ = true;
        let d10 = NMTeleportDriver.Create(NMTeleportTests.Target(1.0, 2.0, 0.0, false), m10, NMFakeGround.Create(1, 40.0, false, 0.0), true);
        NMTeleportTests.Drive(d10);
        t.Check("teleport.driver_vehicle_zero_z", StrBeginsWith(d10.result, "ok|ground"), d10.result);

        let m6 = NMFakeMover.Create(start);
        m6.invalidAfter = 1;
        let d6 = NMTeleportDriver.Create(NMTeleportTests.Target(1.0, 2.0, 0.0, false), m6, NMFakeGround.Create(1, 40.0, false, 0.0), false);
        NMTeleportTests.Drive(d6);
        t.Check("teleport.driver_lost", Equals(d6.result, "failed|lost") && ArraySize(m6.moves) == 1, d6.result + " " + ToString(ArraySize(m6.moves)));
    }

    private static func TargetCases(t: ref<NMSelfTest>) {
        let m = new Vector4(100.0, 200.0, 35.0, 1.0);
        let a = NMTeleport.Choose(0, n"Vanilla.FastTravel", m, 5.0, 6.0, false);
        t.Check("teleport.choose_fixed_marker", a.exact && a.x == 100.0 && a.y == 200.0 && a.z == 35.0, "");
        let b = NMTeleport.Choose(0, n"Vanilla.Pinned", m, 5.0, 6.0, false);
        t.Check("teleport.choose_pinned", !b.exact && b.x == 100.0 && b.y == 200.0, "");
        let c = NMTeleport.Choose(0, n"Vanilla.Other", m, 5.0, 6.0, false);
        t.Check("teleport.choose_other", !c.exact && c.x == 100.0, "");
        let d = NMTeleport.Choose(0, n"Vanilla.FastTravel", m, 5.0, 6.0, true);
        t.Check("teleport.choose_vehicle_marker", !d.exact && d.x == 100.0 && d.y == 200.0, "");
        let e = NMTeleport.Choose(1, n"Vanilla.FastTravel", m, 5.0, 6.0, false);
        t.Check("teleport.choose_cluster", !e.exact && e.x == 5.0 && e.y == 6.0, "");
        let f = NMTeleport.Choose(-1, n"", m, 5.0, 6.0, false);
        t.Check("teleport.choose_none", !f.exact && f.x == 5.0 && f.y == 6.0, "");
        let g = NMTeleport.Choose(0, n"mymod.pins", m, 5.0, 6.0, false);
        t.Check("teleport.choose_other_mod", !g.exact && g.x == 100.0 && g.y == 200.0, "");

        t.Check("teleport.bounds_in", NMTeleport.InBounds(0.0, 0.0), "");
        t.Check("teleport.bounds_out", !NMTeleport.InBounds(NMTileManifest.WorldMaxX() + 1.0, 0.0), "");
        t.Check("teleport.bounds_edge", NMTeleport.InBounds(NMTileManifest.WorldMaxX(), NMTileManifest.WorldMinY()), "");

        t.Check("teleport.landing_ground", t.Near(NMTeleport.LandZ(30.0, false, 0.0, false), 30.5, 0.001)
            && Equals(NMTeleport.LandKind(30.0, false, 0.0, false), "ground"), "");
        t.Check("teleport.landing_vehicle", t.Near(NMTeleport.LandZ(30.0, false, 0.0, true), 31.0, 0.001), "");
        t.Check("teleport.landing_water", t.Near(NMTeleport.LandZ(-10.0, true, 0.0, false), 0.0, 0.001)
            && Equals(NMTeleport.LandKind(-10.0, true, 0.0, false), "water"), "");
        t.Check("teleport.landing_shallow", t.Near(NMTeleport.LandZ(10.0, true, 10.2, false), 10.5, 0.001)
            && Equals(NMTeleport.LandKind(10.0, true, 10.2, false), "ground"), "");
        t.Check("teleport.landing_water_below", t.Near(NMTeleport.LandZ(10.0, true, 5.0, false), 10.5, 0.001), "");
    }
}
