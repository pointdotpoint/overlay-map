module NightMap

// Vanilla minimap parity: the mirror, the shape layer's geometry and switches.
public abstract class NMParityTests {
    public static func Run(t: ref<NMSelfTest>) {
        let m = NMMinimapMirror.Create();
        let a = m.Upsert(42ul);
        let again = m.Upsert(42ul);
        let rev = m.revision;
        m.Remove(42ul);
        t.Check("parity.mirror_upsert_remove", Equals(a, again) && rev == 1 && m.Count() == 0 && !IsDefined(m.Find(42ul)) && m.revision == 2, "");
        m.Upsert(7ul);
        t.Check("parity.mirror_sweeps_dead_widgets", m.Sweep() == 1 && m.Count() == 0, "");   // no root widget = gone

        t.Check("parity.cone_geometry",
            NMShapeLayer.ConeScale(0.5, 0.0, 20.0, 100.0) * 100.0 == 40.0      // 20 m cone at 0.5 m/px: 40 px
            && NMShapeLayer.ConeScale(0.5, 2.0, 20.0, 100.0) == 1.0              // vanilla 2 px/m -> ours 2 px/m
            && NMShapeLayer.ConeRotation(30.0, 90.0) == 30.0 + 90.0 * NMShapeLayer.RotationSign(), "");
        // The shape layer has no filter-view input at all: enemies show whatever the view.
        t.Check("parity.enemies_ignore_filter", NMShapeLayer.Wanted(NMMiniKind.Enemy, true, true), "");
        t.Check("parity.enemies_switch", !NMShapeLayer.Wanted(NMMiniKind.Enemy, false, true) && !NMShapeLayer.Wanted(NMMiniKind.Police, true, false)
            && NMShapeLayer.Wanted(NMMiniKind.Device, false, false) && !NMShapeLayer.Wanted(NMMiniKind.Area, true, true), "");
        t.Check("parity.kind_table", NMMinimapWraps.KindOf(n"MinimapStealthMappinController") == EnumInt(NMMiniKind.Enemy)
            && NMMinimapWraps.KindOf(n"MinimapQuestMappinController") == -1 && NMMinimapWraps.KindOf(n"MinimapPOIMappinController") == -1
            && NMMinimapWraps.KindOf(n"MinimapPingSystemMappinController") == EnumInt(NMMiniKind.Other), "");
    }
}
