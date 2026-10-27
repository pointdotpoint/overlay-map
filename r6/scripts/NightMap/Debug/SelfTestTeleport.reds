module NightMap

// Self-test group for teleport: target choice, landing maths and the driver with fake game seams. Called from
// NMSelfTest.Run(). Nothing is teleported.
public abstract class NMTeleportTests {
    public static func Run(t: ref<NMSelfTest>) {
        NMTeleportTests.TargetCases(t);
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
