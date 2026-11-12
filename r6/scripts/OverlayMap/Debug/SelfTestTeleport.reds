module OverlayMap

// Test seam: records moves instead of teleporting. Position is the last move, or `start` when it ignores moves.
public class NMFakeMover extends NMMover {
    public let moves: array<Vector4>;
    public let start: Vector4;
    public let moving: Bool;
    public let invalidAfter: Int32;   // Valid() turns false once this many moves were made; 0 = never
    public let mountedFor: Int32;     // Ready() is false for this many calls (a dismount under way)
    public let readyCalls: Int32;

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

    public func Ready() -> Bool {
        this.readyCalls += 1;
        return this.readyCalls > this.mountedFor;
    }

    public func Last() -> Vector4 { return this.moves[ArraySize(this.moves) - 1]; }

    // Fields of a call temporary read garbage in-game, so tests ask for these.
    public func LastX() -> Float {
        let p = this.Last();
        return p.X;
    }

    public func LastZ() -> Float {
        let p = this.Last();
        return p.Z;
    }
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
        if AbsF(this.mover.LastZ() - this.z) > this.reach { return null; }
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
        let homeCar = NMTeleport.Home(NMTeleport.Choose(0, n"Vanilla.CommonFilter", marker, 90.0, 91.0, true), true);
        t.Check("teleport.home_in_car", homeCar.exact && homeCar.dismount && homeCar.z == 7.0, "");
        let homeTracked = NMTeleport.Home(NMTeleport.Choose(0, n"Vanilla.Pinned", marker, 90.0, 91.0, false), false);
        t.Check("teleport.home_tracked_on_foot", homeTracked.exact && !homeTracked.dismount, "");
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
        t.Check("teleport.driver_lands", f1 == 1 + NMTeleport.StableProbes() && m1.LastZ() == 50.5 && StrBeginsWith(d1.result, "ok|ground"), d1.result);

        // Beside a tower: nothing near the roof hop, so the low hop finds the street.
        let m2 = NMFakeMover.Create(start);
        let d2 = NMTeleportDriver.Create(NMTeleportTests.Target([316.0, 47.0]), m2, NMFakeGround.Create(m2, 13.0, 100.0), false);
        t.Check("teleport.driver_steps_down", NMTeleportTests.Run(d2, 40) > 0 && ArraySize(m2.moves) == 3 && m2.moves[1].Z == 47.0 && m2.LastZ() == 13.5, d2.result);

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
        t.Check("teleport.driver_shaft", NMTeleportTests.Run(d4, 40) > 0 && m4.LastX() == 116.0 && StrBeginsWith(d4.result, "ok|"), d4.result);

        // No surface anywhere: V goes back to the start.
        let m5 = NMFakeMover.Create(start);
        let g5 = NMFakeGround.Create(m5, 0.0, 0.0);
        g5.none = true;
        let d5 = NMTeleportDriver.Create(NMTeleportTests.Target([316.0, 47.0]), m5, g5, false);
        t.Check("teleport.driver_no_ground", NMTeleportTests.Run(d5, 80) > 0 && m5.LastX() == 1.0 && m5.LastZ() == 3.0 && Equals(d5.result, "failed|no ground"), d5.result);

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
        t.Check("teleport.driver_vehicle_lands", NMTeleportTests.Run(d9, 30) > 0 && m9.LastZ() == 51.0, d9.result);

        // An exact target lands in one move, with no ground search.
        let m10 = NMFakeMover.Create(start);
        let exact = NMTeleportTests.Target([55.0]);
        exact.exact = true;
        exact.z = 7.0;
        let g10 = NMFakeGround.Create(m10, 50.0, 100.0);
        let d10 = NMTeleportDriver.Create(exact, m10, g10, false);
        t.Check("teleport.driver_exact", NMTeleportTests.Run(d10, 2) == 1 && m10.LastZ() == 7.5 && ArraySize(g10.tops) == 0, d10.result);

        // Home from a car: nothing moves until V is out, then V is held at the door, never ray-cast to the roof.
        let m11 = NMFakeMover.Create(start);
        m11.mountedFor = 3;
        let home = NMTeleportTests.Target([355.0]);
        home.exact = true;
        home.dismount = true;
        home.z = 123.0;
        let g11 = NMFakeGround.Create(m11, 312.0, 400.0);
        let d11 = NMTeleportDriver.Create(home, m11, g11, false);
        let f11 = NMTeleportTests.Run(d11, 40);
        t.Check("teleport.driver_dismount_home", f11 > 3 && StrBeginsWith(d11.result, "ok|home") && m11.LastZ() == 123.5
            && ArraySize(m11.moves) >= NMTeleport.SettleFrames() && ArraySize(g11.tops) == 0, d11.result + " f=" + ToString(f11));

        // V never leaves the car: give up without moving V.
        let m12 = NMFakeMover.Create(start);
        m12.mountedFor = 1000;
        let d12 = NMTeleportDriver.Create(home, m12, NMFakeGround.Create(m12, 312.0, 400.0), false);
        t.Check("teleport.driver_dismount_stuck", NMTeleportTests.Run(d12, 100) > 0 && Equals(d12.result, "failed|still mounted") && ArraySize(m12.moves) == 0, d12.result);

        NMTeleportTests.RunWalk(t, start);
    }

    private static func PinTarget() -> ref<NMTeleportTarget> {
        let p = NMTeleportTests.Target([55.0]);
        p.exact = true;
        p.z = 7.0;
        p.walk = true;
        p.walkPin = true;
        p.anchor = new Vector4(p.x, p.y, 7.0, 1.0);
        return p;
    }

    // The walkable spot after a landing (user reports 2026-11-12: inside a drop point, behind a shop's bars, on a roof).
    private static func RunWalk(t: ref<NMSelfTest>, start: Vector4) {
        let a = new Vector4(100.0, 200.0, 7.0, 1.0);
        let spot: Vector4;

        // Open ground: beside the pin (the nearest ring), never on it.
        let open = NMFakeWalk.Create(100.0, 200.0, 7.0);
        let ok1 = NMWalkSpot.Pick(open, a, true, spot);
        let d1 = NMTeleportTests.Flat(spot, a);
        t.Check("teleport.walk_pin_beside", ok1 && AbsF(d1 - 2.5) < 0.01 && spot.Z == 7.0, FloatToStringPrec(d1, 2));

        // A cage 3 m round the pin (the shopkeeper behind bars): the first ring is inside and closed, so V stands outside.
        let caged = NMFakeWalk.Create(100.0, 200.0, 7.0);
        caged.cageR = 3.0;
        let ok2 = NMWalkSpot.Pick(caged, a, true, spot);
        let d2 = NMTeleportTests.Flat(spot, a);
        t.Check("teleport.walk_pin_cage", ok2 && d2 > 3.0, FloatToStringPrec(d2, 2));

        // A terminal 3 m wide on the pin (a drop point): no walkable floor there, so V stands past it.
        let term = NMFakeWalk.Create(100.0, 200.0, 7.0);
        term.blockR = 3.0;
        let ok3 = NMWalkSpot.Pick(term, a, true, spot);
        t.Check("teleport.walk_pin_terminal", ok3 && NMTeleportTests.Flat(spot, a) > 3.0, "");

        // No navmesh at all: no spot.
        let none = NMFakeWalk.Create(100.0, 200.0, 7.0);
        none.none = true;
        t.Check("teleport.walk_none", !NMWalkSpot.Pick(none, a, true, spot), "");

        // The map centre: the anchor itself when open (the street, not the roof).
        let street = new Vector4(100.0, 200.0, 7.0, 1.0);
        let ok5 = NMWalkSpot.Pick(open, street, false, spot);
        t.Check("teleport.walk_centre_street", ok5 && NMTeleportTests.Flat(spot, street) < 0.01 && spot.Z == 7.0, "");

        // Driver: an exact pin on foot lands on the pin, then steps to the open spot.
        let m1 = NMFakeMover.Create(start);
        let w1 = NMFakeWalk.Create(100.0, 200.0, 7.0);
        w1.cageR = 3.0;
        let dr1 = NMTeleportDriver.Create(NMTeleportTests.PinTarget(), m1, NMFakeGround.Create(m1, 50.0, 100.0), false, w1);
        let f1 = NMTeleportTests.Run(dr1, 10);
        t.Check("teleport.driver_walk_pin", f1 > 1 && StrBeginsWith(dr1.result, "ok|walk|") && ArraySize(m1.moves) == 2
            && NMTeleportTests.Flat(m1.Last(), a) > 3.0 && m1.LastZ() == 7.5, dr1.result);

        // The navmesh never streams in: the landing on the pin stands, after the wait.
        let m2 = NMFakeMover.Create(start);
        let w2 = NMFakeWalk.Create(100.0, 200.0, 7.0);
        w2.unstreamed = true;
        let dr2 = NMTeleportDriver.Create(NMTeleportTests.PinTarget(), m2, NMFakeGround.Create(m2, 50.0, 100.0), false, w2);
        let f2 = NMTeleportTests.Run(dr2, 200);
        t.Check("teleport.driver_walk_unstreamed", f2 > NMTeleportDriver.WalkWaitFrames() && StrBeginsWith(dr2.result, "ok|marker|")
            && StrContains(dr2.result, "walk=unstreamed") && ArraySize(m2.moves) == 1, dr2.result);

        // In a vehicle there is no walk phase.
        let m3 = NMFakeMover.Create(start);
        let dr3 = NMTeleportDriver.Create(NMTeleportTests.Target([55.0]), m3, NMFakeGround.Create(m3, 50.0, 100.0), true, NMFakeWalk.Create(100.0, 200.0, 50.0));
        NMTeleportTests.Run(dr3, 30);
        t.Check("teleport.driver_walk_not_in_car", StrBeginsWith(dr3.result, "ok|ground|"), dr3.result);
    }

    private static func Flat(p: Vector4, a: Vector4) -> Float {
        let dx = p.X - a.X;
        let dy = p.Y - a.Y;
        return SqrtF(dx * dx + dy * dy);
    }
}

// Test seam: a flat walkable floor at `z` around (cx, cy). blockR: no floor within it (a terminal). cageR: floor, but
// no path crosses its edge (bars). Paths elsewhere are straight.
public class NMFakeWalk extends NMWalk {
    public let cx: Float;
    public let cy: Float;
    public let z: Float;
    public let blockR: Float;
    public let cageR: Float;
    public let none: Bool;
    public let unstreamed: Bool;

    public static func Create(cx: Float, cy: Float, z: Float) -> ref<NMFakeWalk> {
        let w = new NMFakeWalk();
        w.cx = cx;
        w.cy = cy;
        w.z = z;
        return w;
    }

    private func R(p: Vector4) -> Float {
        let dx = p.X - this.cx;
        let dy = p.Y - this.cy;
        return SqrtF(dx * dx + dy * dy);
    }

    public func Streamed(p: Vector4) -> Bool { return !this.unstreamed; }

    public func Near(p: Vector4, r: Float, out q: Vector4) -> Bool {
        if this.none || AbsF(p.Z - this.z) > r { return false; }
        if this.R(p) < this.blockR { return false; }
        q = new Vector4(p.X, p.Y, this.z, 1.0);
        return true;
    }

    public func PathLen(a: Vector4, b: Vector4) -> Float {
        if this.cageR > 0.0 && NotEquals(this.R(a) < this.cageR, this.R(b) < this.cageR) { return -1.0; }
        return Vector4.Distance(a, b);
    }
}
