module OverlayMap

// HUD palette read-back (Follow HUD Painter colours) and NMTheme routing.
public abstract class NMPaletteTests {
    public static func Run(t: ref<NMSelfTest>) {
        t.Check("palette.slot_table",
            Equals(NMHudPalette.Slot(NMColorRole.Accent), n"MainColors.Blue")
            && Equals(NMHudPalette.Slot(NMColorRole.Highlight), n"MainColors.ActiveBlue")
            && Equals(NMHudPalette.Slot(NMColorRole.Background), n"MainColors.PanelBlack")
            && Equals(NMHudPalette.Slot(NMColorRole.PanelBg), n"MainColors.PanelBlack")
            && Equals(NMHudPalette.Slot(NMColorRole.Text), n"MainColors.White")
            && Equals(NMHudPalette.Slot(NMColorRole.Muted), n"MainColors.MildBlue")
            && Equals(NMHudPalette.Slot(NMColorRole.Warn), n"MainColors.Red")
            && Equals(NMHudPalette.Slot(NMColorRole.Route), n"MainColors.Yellow")
            && Equals(NMHudPalette.Slot(NMColorRole.Enemy), n"MainColors.EnemyMinimapBase")
            && Equals(NMHudPalette.Slot(NMColorRole.Police), n"MainColors.SupBlue")
            && Equals(NMHudPalette.Slot(NMColorRole.Player), n"MainColors.ActiveGreen")
            && Equals(NMHudPalette.Slot(NMColorRole.Road), n"MainColors.DarkBlue")
            && Equals(NMHudPalette.Slot(NMColorRole.Floor), n"MainColors.PanelDarkGrey")
            && Equals(NMHudPalette.Slot(NMColorRole.Wall), n"MainColors.Neutral")
            && Equals(NMHudPalette.Slot(NMColorRole.FastTravel), n"MainColors.FastTravel")
            && Equals(NMHudPalette.Slot(NMColorRole.Relic), n"MainColors.RelicColor"), "");

        // Unresolved probes (no layout pass yet) report nothing: NMTheme keeps today's colours.
        let host = new inkCanvas();
        let p = NMHudPalette.Create(host);
        t.Check("palette.unresolved_has_nothing", !p.Has(NMColorRole.Accent) && p.ProbeCount() == EnumInt(NMColorRole.Count), "");

        // Known colours injected: roles answer with them.
        let q = NMHudPalette.Fixed(new HDRColor(0.1, 0.2, 0.3, 1.0));
        q.Set(NMColorRole.Route, new HDRColor(1.1192, 0.8441, 0.2565, 1.0));
        let y = q.Get(NMColorRole.Route);
        let qa = q.Get(NMColorRole.Accent);   // bound first: a field read off a call's temporary is 0 in game
        let ag = qa.Green;
        t.Check("palette.set_get", q.Has(NMColorRole.Route) && AbsF(y.Red - 1.1192) < 0.0001 && AbsF(y.Blue - 0.2565) < 0.0001
            && AbsF(ag - 0.2) < 0.0001, "has " + ToString(q.Has(NMColorRole.Route)) + " r " + FloatToStringPrec(y.Red, 4)
            + " b " + FloatToStringPrec(y.Blue, 4) + " ag " + FloatToStringPrec(ag, 4));
        // HUD Painter alpha below 1 is not a change (review: the corner rebuilt every second).
        t.Check("palette.alpha_is_not_a_change", !NMHudPalette.Differs(new HDRColor(0.3, 0.6, 0.9, 1.0), new HDRColor(0.3, 0.6, 0.9, 0.5))
            && NMHudPalette.Differs(new HDRColor(0.3, 0.6, 0.9, 1.0), new HDRColor(0.3, 0.7, 0.9, 1.0)), "");
        // The map background must not share the road slot (vanilla PanelDarkBlue == DarkBlue: roads vanished).
        t.Check("palette.background_not_road", NotEquals(NMHudPalette.Slot(NMColorRole.Background), NMHudPalette.Slot(NMColorRole.Road))
            && NotEquals(NMHudPalette.Slot(NMColorRole.Background), n"MainColors.PanelDarkBlue"), "");
        p.Destroy();
        t.Check("palette.destroy_removes_probes", host.GetNumChildren() == 0, "");
    
        // NMTheme routing: no palette = today's colours; a palette answers by role.
        let prev = NMTheme.Palette();
        NMTheme.Use(null);
        let c = NMTheme.Cyan();
        let r = NMTheme.TileTint("road", 0);
        t.Check("palette.off_is_today", c.Red == 0.478 && c.Green == 0.941 && c.Blue == 1.0
            && r.Red == 0.363 && r.Green == 0.694 && r.Blue == 0.924, "");
        let f = NMHudPalette.Fixed(new HDRColor(0.5, 0.5, 0.5, 1.0));
        f.Set(NMColorRole.Accent, new HDRColor(0.9, 0.1, 0.1, 1.0));
        f.Set(NMColorRole.Floor, new HDRColor(0.1, 0.9, 0.1, 1.0));
        NMTheme.Use(f);
        let a = NMTheme.Cyan();
        let fl = NMTheme.TileTint("bfill", 0);
        let qc = NMTheme.VanillaStateColor(n"Quest");
        NMTheme.Use(prev);
        t.Check("palette.on_routes_roles", a.Red == 0.9 && a.Green == 0.1 && fl.Green == 0.9 && fl.Red == 0.1 && qc.Red == 0.5, "");
    }
}
