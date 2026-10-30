module NightMap

// Test seam: records moves instead of teleporting. Position is the last move, or `start` when it ignores moves.
public class NMFakeMover extends NMMover {
    public let moves: array<Vector4>;
    public let start: Vector4;
    public let moving: Bool;
    public let invalidAfter: Int32;   // Valid() turns false once this many moves were made; 0 = never

    public static func Create(start: Vector4) -> ref<NMFakeMover> {
        let m = new NMFakeMover();
        m.start = start;
        m.moving = true;
        return m;
    }

    public func Valid() -> Bool { return this.invalidAfter <= 0 || ArraySize(this.moves) < this.invalidAfter; }

    public func Position() -> Vector4 {
        let n = ArraySize(this.moves);
        return this.moving && n > 0 ? this.moves[n - 1] : this.start;
    }

    public func Move(p: Vector4) { ArrayPush(this.moves, p); }

    public func Last() -> Vector4 { return this.moves[ArraySize(this.moves) - 1]; }
}

// Test seam: a surface at `z` that only answers once V is within `reach` of it (collision loads near V).
public class NMFakeGround extends NMGround {
    public let mover: ref<NMFakeMover>;
    public let z: Float;
    public let reach: Float;
    public let hasWater: Bool;
    public let waterZ: Float;
    public let onlyWide: Bool;        // the point itself is an open shaft: only `wide` probes find anything
    public let none: Bool;
    public let tops: array<Float>;

    public static func Create(mover: ref<NMFakeMover>, z: Float, reach: Float) -> ref<NMFakeGround> {
        let g = new NMFakeGround();
        g.mover = mover;
        g.z = z;
        g.reach = reach;
        return g;
    }

    public func Probe(x: Float, y: Float, top: Float, wide: Bool) -> ref<NMGroundHit> {
        ArrayPush(this.tops, top);
        if this.none || this.onlyWide && !wide { return null; }
        let v = this.mover.Last();
        if AbsF(v.Z - this.z) > this.reach { return null; }
        let h = new NMGroundHit();
        h.x = x + (this.onlyWide ? NMTeleport.WideReach() : 0.0);
        h.y = y;
        h.z = this.z;
        h.hasWater = this.hasWater;
        h.waterZ = this.waterZ;
        return h;
    }
}

// Self-test group for teleport: heights, target choice, landing maths and the driver with fake game seams. Called from
// NMSelfTest.Run(). Nothing is teleported.
public abstract class NMTeleportTests {
    private static func Target(hops: array<Float>) -> ref<NMTeleportTarget> {
        let t = new NMTeleportTarget();
        t.x = 100.0;
        t.y = 200.0;
        t.hops = hops;
        t.rayTop = 330.0;
        return t;
    }

    private static func Run(d: ref<NMTeleportDriver>, frames: Int32) -> Int32 {
        let i = 0;
        while i < frames {
            if d.Step(40.0) == 1 { return i + 1; }
            i += 1;
        }
        return -1;
    }

    public static func Run(t: ref<NMSelfTest>) {
        let start = new Vector4(1.0, 2.0, 3.0, 1.0);

        // The bake, at a street and in a cell shared with a tall roof (values checked against the game on 2026-10-30).
        t.Check("teleport.height_street", NMHeight.Low(-2184.0, -2200.0) > 0.0 && NMHeight.High(-2184.0, -2200.0) < 30.0, FloatToStringPrec(NMHeight.High(-2184.0, -2200.0), 1));
        t.Check("teleport.height_tall_cell", NMHeight.Low(-1456.0, 112.0) < 40.0 && NMHeight.High(-1456.0, 112.0) > 600.0, FloatToStringPrec(NMHeight.High(-1456.0, 112.0), 1));
        t.Check("teleport.height_outside", NMHeight.High(-90000.0, 0.0) == 0.0, "");

        // A flat cell needs one hop; a tall one starts at the roof and then tries the street.
        let flat = NMTeleport.Hops(10.0, 15.0);
        t.Check("teleport.hops_flat", ArraySize(flat) == 1 && flat[0] == 20.0, "");
        let tall = NMTeleport.Hops(10.0, 300.0);
        t.Check("teleport.hops_tall", ArraySize(tall) == 2 && tall[0] == 305.0 && tall[1] == 30.0, "");

        // Target choice: an item keeps its position, nothing selected is the map centre; exact only for a fixed marker on foot.
        let marker = new Vector4(5.0, 6.0, 7.0, 1.0);
        let fixedFoot = NMTeleport.Choose(0, n"Vanilla.Vendors", marker, 90.0, 91.0, false);
        t.Check("teleport.choose_marker_exact", fixedFoot.exact && fixedFoot.x == 5.0 && fixedFoot.z == 7.0, "");
        t.Check("teleport.choose_marker_in_car", !NMTeleport.Choose(0, n"Vanilla.Vendors", marker, 90.0, 91.0, true).exact, "");
        t.Check("teleport.choose_pinned_not_exact", !NMTeleport.Choose(0, n"Vanilla.Pinned", marker, 90.0, 91.0, false).exact, "");
        let empty = NMTeleport.Choose(-1, n"", marker, 90.0, 91.0, false);
        t.Check("teleport.choose_center", !empty.exact && empty.x == 90.0 && empty.y == 91.0, "");
        t.Check("teleport.choose_ray_above_hops", empty.rayTop >= empty.hops[0], "");

        // Landing height.
        t.Check("teleport.land_ground", NMTeleport.LandZ(10.0, false, 0.0, false) == 10.5, "");
        t.Check("teleport.land_car", NMTeleport.LandZ(10.0, false, 0.0, true) == 11.0, "");
        t.Check("teleport.land_water", NMTeleport.LandZ(-6.6, true, 0.0, false) == 0.0 && Equals(NMTeleport.LandKind(-6.6, true, 0.0, false), "water"), "");
        t.Check("teleport.land_shallow", NMTeleport.LandZ(10.0, true, 9.0, false) == 10.5, "");

        // One hop lands after StableProbes agreeing hits, at the surface.
        let m1 = NMFakeMover.Create(start);
        let d1 = NMTeleportDriver.Create(NMTeleportTests.Target([55.0]), m1, NMFakeGround.Create(m1, 50.0, 100.0), false);
        let f1 = NMTeleportTests.Run(d1, 20);
        t.Check("teleport.driver_lands", f1 == 1 + NMTeleport.StableProbes() && m1.Last().Z == 50.5 && StrBeginsWith(d1.result, "ok|ground"), d1.result);

        // Beside a tower: nothing near the roof hop, so the low hop finds the street.
        let m2 = NMFakeMover.Create(start);
        let d2 = NMTeleportDriver.Create(NMTeleportTests.Target([316.0, 47.0]), m2, NMFakeGround.Create(m2, 13.0, 100.0), false);
        t.Check("teleport.driver_steps_down", NMTeleportTests.Run(d2, 40) > 0 && ArraySize(m2.moves) == 3 && m2.moves[1].Z == 47.0 && m2.Last().Z == 13.5, d2.result);

        // A hop waits out both its time and its frames: frames stop under the streaming screen.
        let m3 = NMFakeMover.Create(start);
        let d3 = NMTeleportDriver.Create(NMTeleportTests.Target([316.0, 47.0]), m3, NMFakeGround.Create(m3, 13.0, 100.0), false);
        let i3 = 0;
        while i3 < NMTeleport.HopFrames() - 1 {
            d3.Step(1000.0);
            i3 += 1;
        }
        t.Check("teleport.driver_hop_counts_frames", ArraySize(m3.moves) == 1, ToString(ArraySize(m3.moves)));

        // An open shaft: the point never hits, the ring beside it does, and V lands there.
        let m4 = NMFakeMover.Create(start);
        let g4 = NMFakeGround.Create(m4, 50.0, 100.0);
        g4.onlyWide = true;
        let d4 = NMTeleportDriver.Create(NMTeleportTests.Target([55.0]), m4, g4, false);
        t.Check("teleport.driver_shaft", NMTeleportTests.Run(d4, 40) > 0 && m4.Last().X == 116.0 && StrBeginsWith(d4.result, "ok|"), d4.result);

        // No surface anywhere: V goes back to the start.
        let m5 = NMFakeMover.Create(start);
        let g5 = NMFakeGround.Create(m5, 0.0, 0.0);
        g5.none = true;
        let d5 = NMTeleportDriver.Create(NMTeleportTests.Target([316.0, 47.0]), m5, g5, false);
        t.Check("teleport.driver_no_ground", NMTeleportTests.Run(d5, 80) > 0 && m5.Last().X == 1.0 && m5.Last().Z == 3.0 && Equals(d5.result, "failed|no ground"), d5.result);

        // Collision loading piece by piece: V waits for hits that agree.
        let m6 = NMFakeMover.Create(start);
        let g6 = NMFakeGround.Create(m6, 50.0, 100.0);
        let d6 = NMTeleportDriver.Create(NMTeleportTests.Target([55.0]), m6, g6, false);
        d6.Step(40.0);
        d6.Step(40.0);
        g6.z = 91.0;
        d6.Step(40.0);
        t.Check("teleport.driver_needs_agreement", ArraySize(m6.moves) == 1, ToString(ArraySize(m6.moves)));

        // The object gone mid-teleport: stop without touching it.
        let m7 = NMFakeMover.Create(start);
        m7.invalidAfter = 1;
        let g7 = NMFakeGround.Create(m7, 0.0, 0.0);
        g7.none = true;
        let d7 = NMTeleportDriver.Create(NMTeleportTests.Target([55.0]), m7, g7, false);
        t.Check("teleport.driver_lost", NMTeleportTests.Run(d7, 5) > 0 && ArraySize(m7.moves) == 1 && Equals(d7.result, "failed|lost"), d7.result);

        // A vehicle the game will not move is refused, and nothing moves again.
        let m8 = NMFakeMover.Create(start);
        m8.moving = false;
        let d8 = NMTeleportDriver.Create(NMTeleportTests.Target([55.0]), m8, NMFakeGround.Create(m8, 50.0, 100.0), true);
        t.Check("teleport.driver_vehicle_refused", NMTeleportTests.Run(d8, 30) > 0 && ArraySize(m8.moves) == 1 && Equals(d8.result, "refused|vehicle"), d8.result);

        // A vehicle lands higher than V does.
        let m9 = NMFakeMover.Create(start);
        let d9 = NMTeleportDriver.Create(NMTeleportTests.Target([55.0]), m9, NMFakeGround.Create(m9, 50.0, 100.0), true);
        t.Check("teleport.driver_vehicle_lands", NMTeleportTests.Run(d9, 30) > 0 && m9.Last().Z == 51.0, d9.result);

        // An exact target lands in one move, with no ground search.
        let m10 = NMFakeMover.Create(start);
        let exact = NMTeleportTests.Target([55.0]);
        exact.exact = true;
        exact.z = 7.0;
        let g10 = NMFakeGround.Create(m10, 50.0, 100.0);
        let d10 = NMTeleportDriver.Create(exact, m10, g10, false);
        t.Check("teleport.driver_exact", NMTeleportTests.Run(d10, 2) == 1 && m10.Last().Z == 7.5 && ArraySize(g10.tops) == 0, d10.result);

    }
}
