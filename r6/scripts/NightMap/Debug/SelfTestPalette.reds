module NightMap

// HUD palette read-back (Follow HUD Painter colours) and NMTheme routing.
public abstract class NMPaletteTests {
    public static func Run(t: ref<NMSelfTest>) {
        t.Check("palette.slot_table",
            Equals(NMHudPalette.Slot(NMColorRole.Accent), n"MainColors.Blue")
            && Equals(NMHudPalette.Slot(NMColorRole.Highlight), n"MainColors.ActiveBlue")
            && Equals(NMHudPalette.Slot(NMColorRole.Background), n"MainColors.PanelDarkBlue")
            && Equals(NMHudPalette.Slot(NMColorRole.PanelBg), n"MainColors.PanelBlack")
            && Equals(NMHudPalette.Slot(NMColorRole.Text), n"MainColors.White")
            && Equals(NMHudPalette.Slot(NMColorRole.Muted), n"MainColors.MildBlue")
            && Equals(NMHudPalette.Slot(NMColorRole.Warn), n"MainColors.Red")
            && Equals(NMHudPalette.Slot(NMColorRole.Route), n"MainColors.Yellow")
            && Equals(NMHudPalette.Slot(NMColorRole.Enemy), n"MainColors.EnemyMinimapBase")
            && Equals(NMHudPalette.Slot(NMColorRole.Police), n"MainColors.SupBlue")
            && Equals(NMHudPalette.Slot(NMColorRole.Player), n"MainColors.ActiveGreen")
            && Equals(NMHudPalette.Slot(NMColorRole.Road), n"MainColors.DarkBlue")
            && Equals(NMHudPalette.Slot(NMColorRole.Floor), n"MainColors.White")
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
        t.Check("palette.set_get", q.Has(NMColorRole.Route) && y.Red == 1.1192 && y.Blue == 0.2565
            && q.Get(NMColorRole.Accent).Green == 0.2, "");
        p.Destroy();
        t.Check("palette.destroy_removes_probes", host.GetNumChildren() == 0, "");
    }
}
