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
            && NMShapeLayer.Wanted(NMMiniKind.Device, false, false) && NMShapeLayer.Wanted(NMMiniKind.Area, false, false)
            && NMShapeLayer.Wanted(NMMiniKind.Zone, false, false), "");
        t.Check("parity.kind_table", NMMinimapWraps.KindOf(n"MinimapStealthMappinController") == EnumInt(NMMiniKind.Enemy)
            && NMMinimapWraps.KindOf(n"MinimapRemotePlayerMappinController") == -1
            && NMMinimapWraps.KindOf(n"MinimapPingSystemMappinController") == EnumInt(NMMiniKind.Other), "");
    
        // Rim clamping: a point far east of a 400 px circle lands on the circle (inset 10) at angle 90 (pointing east).
        let rc = NMParity.ClampToRim(1000.0, 200.0, 400.0, 400.0, true, 10.0);
        t.Check("parity.rim_circle", AbsF(rc.X - 390.0) < 0.01 && AbsF(rc.Y - 200.0) < 0.01
            && NMParity.IsOff(1000.0, 200.0, 400.0, 400.0, true, 10.0) && !NMParity.IsOff(200.0, 200.0, 400.0, 400.0, true, 10.0)
            && NMParity.IsOff(395.0, 395.0, 400.0, 400.0, true, 10.0)            // inside the square, outside the circle
            && AbsF(NMParity.ArrowAngle(1000.0, 200.0, 400.0, 400.0) - 90.0) < 0.01, FloatToStringPrec(rc.X, 2));
        let rs = NMParity.ClampToRim(200.0, -1000.0, 400.0, 300.0, false, 10.0);
        t.Check("parity.rim_square", AbsF(rs.X - 200.0) < 0.01 && AbsF(rs.Y - 10.0) < 0.01
            && !NMParity.IsOff(395.0, 295.0, 400.0, 300.0, false, 0.0) && AbsF(NMParity.ArrowAngle(200.0, -1000.0, 400.0, 300.0)) < 0.01, "");
        t.Check("parity.vertical", NMParity.VerticalRotation(1) == 0.0 && NMParity.VerticalRotation(-1) == 180.0, "");
        // GetClassName() on the native controllers reports the native names, with a gameui prefix (corner campaign).
        t.Check("parity.kind_native_names", NMMinimapWraps.KindOf(n"gameuiMinimapQuestMappinController") == EnumInt(NMMiniKind.Shadow)
            && NMMinimapWraps.KindOf(n"gameuiMinimapStealthMappinController") == EnumInt(NMMiniKind.Enemy)
            && NMMinimapWraps.KindOf(n"gameuiMinimapPreventionVehicleMappinController") == EnumInt(NMMiniKind.Shadow)
            && NMMinimapWraps.KindOf(n"gameuiMinimapQuestAreaMappinController") == EnumInt(NMMiniKind.Area), "");
        t.Check("parity.shadow_kind", NMMinimapWraps.KindOf(n"MinimapQuestMappinController") == EnumInt(NMMiniKind.Shadow)
            && !NMShapeLayer.Wanted(NMMiniKind.Shadow, true, true), "");
    
        // Area shapes: vanilla minimap px relative to the mappin -> world (GPS transform, mappin as origin).
        let aw = NMParity.AreaToWorld(new Vector2(10.0, 0.0), 100.0, 200.0, 0.0, 2.0);
        // No GPS route: the vanilla scale comes from a marker's minimap offset over its world distance (review: no areas).
        t.Check("parity.scale_from_marker", AbsF(NMParity.ScaleFrom(new Vector2(30.0, 40.0), 25.0, 0.0) - 2.0) < 0.001
            && NMParity.ScaleFrom(new Vector2(30.0, 40.0), 5.0, 0.0) == 0.0, "");   // too close to measure
        t.Check("parity.area_vertices_to_world", AbsF(aw.X - 105.0) < 0.01 && AbsF(aw.Y - 200.0) < 0.01, FloatToStringPrec(aw.X, 2));
        // Zone label line: vanilla text, autodrive and the courier timer joined; nothing when all are off.
        let z = new NMZoneInfo();
        t.Check("parity.zone_text_empty", Equals(NMCorner.ZoneText(z), ""), "");
        z.label = "HOSTILE";
        z.autodrive = true;
        z.timer = "02:13";
        t.Check("parity.zone_text", Equals(NMCorner.ZoneText(z), "HOSTILE  ·  AUTODRIVE  ·  02:13"), NMCorner.ZoneText(z));
        let zs = NMCorner.ZoneTint(n"Safe");
        let zd = NMCorner.ZoneTint(n"Dangerous");
        let zc = NMCorner.ZoneTint(n"Combat");
        t.Check("parity.zone_tint", zs.Red == 1.0 && zs.Green == 1.0 && zd.Green < zd.Red && zc.Green < zc.Red,
            "safe " + FloatToStringPrec(zs.Red, 2) + "," + FloatToStringPrec(zs.Green, 2) + " danger " + FloatToStringPrec(zd.Red, 2) + ","
            + FloatToStringPrec(zd.Green, 2) + " palette " + ToString(IsDefined(NMTheme.Palette())));
        // The label sits inside the corner's box in every style.
        let host = new inkCanvas();
        let ok = true;
        let st = 0;
        while st < 3 {
            let set = new NightMapSettings();
            set.cornerStyle = IntEnum<NightMapCornerStyle>(st);
            let l = NMCornerLayout.Compute(NMRect.Create(3300.0, 100.0, 3700.0, 500.0), set.cornerStyle, 1.0, 1.0, 3840.0, 2160.0);
            let c = NMCorner.Build(host, l, NMCornerConfig.From(set), NightMap.Create(), 0.4);
            let r = c.ZoneLabelRect();
            ok = ok && r.minX >= 0.0 && r.minY >= 0.0 && r.maxX <= l.w && r.maxY <= l.h;
            c.Destroy();
            st += 1;
        }
        t.Check("parity.zone_label_inside_box", ok, "");
    }
}
