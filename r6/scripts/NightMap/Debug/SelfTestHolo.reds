module NightMap

// Self-test group for the hologram look (glow level offset, theme tints, effects off, panel opacity). Called from
// NMSelfTest.Run(). Everything builds on detached widgets: nothing is drawn and no animation is started.
public abstract class NMHoloTests {
    public static func SetIndex(name: String) -> Int32 {
        let i = 0;
        while i < NMTileManifest.SetCount() {
            if Equals(NMTileManifest.SetName(i), name) {
                return i;
            }
            i += 1;
        }
        return 0;
    }

    // Tint luminance times opacity: how bright a set reads.
    private static func Lum(set: String, theme: Int32) -> Float {
        let c: HDRColor = NMTheme.TileTint(set, theme);
        return (0.2126 * c.Red + 0.7152 * c.Green + 0.0722 * c.Blue) * NMTheme.TileOpacity(set);
    }

    public static func Run(t: ref<NMSelfTest>) {
        NMHoloTests.GlowCases(t);
        NMHoloTests.ThemeCases(t);
        NMHoloTests.EffectsCases(t);
        NMHoloTests.RendererCases(t);
    }

    private static func GlowCases(t: ref<NMSelfTest>) {
        if !NMTileManifest.Available() {
            t.Check("holo.glow_manifest", false, "tile manifest is the stub");
            return;
        }
        let n = NMTileManifest.LevelCount();
        let g = NMHoloTests.SetIndex("glow");
        t.Check("holo.glow_set_exists", Equals(NMTileManifest.SetName(g), "glow"), NMTileManifest.SetName(g));
        let l0: array<Int32> = NMTileManifest.SetTiles(g, 0);
        let l1: array<Int32> = NMTileManifest.SetTiles(g, 1);
        let l2: array<Int32> = NMTileManifest.SetTiles(g, 2);
        let l5: array<Int32> = NMTileManifest.SetTiles(g, n - 1);
        t.Check("holo.glow_only_from_l2", ArraySize(l0) == 0 && ArraySize(l1) == 0 && ArraySize(l2) > 0 && ArraySize(l5) > 0,
            ToString(ArraySize(l0)) + "/" + ToString(ArraySize(l1)) + "/" + ToString(ArraySize(l2)) + "/" + ToString(ArraySize(l5)));
        t.Check("holo.pick_offset_math", NMTileLayer.PickLevelOffset(0.5, 2) == 2 && NMTileLayer.PickLevelOffset(16.0, 2) == n - 1
            && NMTileLayer.PickLevelOffset(2.0, 0) == NMTileLayer.PickLevel(2.0) && NMTileLayer.PickLevelOffset(4.0, 2) == n - 1,
            ToString(NMTileLayer.PickLevelOffset(0.5, 2)) + "/" + ToString(NMTileLayer.PickLevelOffset(16.0, 2)));
        // A glow layer (offset 2) at 0.5 m/px shows level index 2; at 16 m/px it clamps to the last level.
        let canvas = new inkCanvas();
        let b = NMRect.Create(NMTileManifest.WorldMinX(), NMTileManifest.WorldMinY(), NMTileManifest.WorldMaxX(), NMTileManifest.WorldMaxY());
        let cam = NMCamera.Create(1880.0, 1480.0, b, NightMapSystem.MinMpp(), NightMapSystem.MaxMpp());
        cam.SetCenter(-1800.0, 150.0);
        let near = NMTileLayer.Create(canvas, g, NMTheme.GlowLevelOffset());
        cam.SetMpp(0.5);
        near.Update(cam, 16.0);
        let far = NMTileLayer.Create(canvas, g, NMTheme.GlowLevelOffset());
        cam.SetMpp(16.0);
        far.Update(cam, 16.0);
        t.Check("holo.glow_layer_level_offset", near.CurrentLevel() == 2 && far.CurrentLevel() == n - 1 && near.LevelOffset() == 2,
            ToString(near.CurrentLevel()) + "/" + ToString(far.CurrentLevel()));
        t.Check("holo.glow_has_no_l0_tiles", !near.Has(0, 0, 0) && !near.Has(1, 0, 0), "");
        t.Check("holo.set_offsets", NMLayerStack.WantsSet("glow", true) && NMLayerStack.SetOffset("glow") == 2 && NMLayerStack.SetOffset("road_major") == 0, "");
        let stack = NMLayerStack.Create(canvas, 0, false);
        let withFx = NMLayerStack.Create(canvas, 0, true);
        t.Check("holo.effects_off_drops_glow_layer", !IsDefined(stack.Layer("glow")) && stack.LayerCount() == 4 && IsDefined(withFx.Layer("glow")) && withFx.LayerCount() == 5,
            ToString(stack.LayerCount()) + "/" + ToString(withFx.LayerCount()));
    }

    private static func ThemeCases(t: ref<NMSelfTest>) {
        // Read through locals: field access on a call temporary reads 0 in redscript.
        let accC: HDRColor = NMTheme.HoloAccent(0);
        let accG: HDRColor = NMTheme.HoloAccent(1);
        let roadC: HDRColor = NMTheme.TileTint("road_major", 0);
        let roadG: HDRColor = NMTheme.TileTint("road_major", 1);
        let fillC: HDRColor = NMTheme.TileTint("bfill", 0);
        let outG: HDRColor = NMTheme.TileTint("outline", 1);
        let glowC: HDRColor = NMTheme.TileTint("glow", 0);
        let glowG: HDRColor = NMTheme.TileTint("glow", 1);
        let bgC: HDRColor = NMTheme.HoloBackground(0);
        let bgG: HDRColor = NMTheme.HoloBackground(1);
        t.Check("holo.accent_cyan_vs_green", t.Near(accC.Red, 0.310, 0.002) && t.Near(accC.Green, 0.890, 0.002) && t.Near(accC.Blue, 1.0, 0.002)
            && t.Near(accG.Red, 0.365, 0.002) && t.Near(accG.Green, 1.0, 0.002) && t.Near(accG.Blue, 0.541, 0.002), "");
        t.Check("holo.road_tint_cyan_vs_green", t.Near(roadC.Red, 0.561, 0.002) && t.Near(roadC.Green, 0.863, 0.002) && t.Near(roadG.Red, 0.561, 0.002) && t.Near(roadG.Green, 1.0, 0.002) && t.Near(roadG.Blue, 0.707, 0.002), "");
        t.Check("holo.line_tints_cyan_vs_green", t.Near(fillC.Red, 0.106, 0.002) && t.Near(fillC.Blue, 0.471, 0.002) && t.Near(outG.Red, 0.227, 0.002) && t.Near(outG.Green, 0.816, 0.002) && t.Near(outG.Blue, 0.424, 0.002), "");
        t.Check("holo.glow_tint_is_accent", t.Near(glowC.Red, 0.184, 0.002) && t.Near(glowC.Blue, 1.0, 0.002) && t.Near(glowG.Green, 1.0, 0.002) && t.Near(glowG.Red, 0.184, 0.002), "");
        t.Check("holo.background_cyan_vs_green", t.Near(bgC.Red, 0.020, 0.002) && t.Near(bgC.Green, 0.051, 0.002) && t.Near(bgC.Blue, 0.094, 0.002) && t.Near(bgG.Green, 0.063, 0.002) && t.Near(bgG.Blue, 0.031, 0.002), "");
        let lumFx = NMHoloTests.Lum("road_major", 0) > NMHoloTests.Lum("road_minor", 0) && NMHoloTests.Lum("road_minor", 0) > NMHoloTests.Lum("outline", 0) && NMHoloTests.Lum("outline", 0) > NMHoloTests.Lum("bfill", 0);
        let lumFxG = NMHoloTests.Lum("road_major", 1) > NMHoloTests.Lum("road_minor", 1) && NMHoloTests.Lum("road_minor", 1) > NMHoloTests.Lum("outline", 1) && NMHoloTests.Lum("outline", 1) > NMHoloTests.Lum("bfill", 1);
        t.Check("theme.roads_brighter_than_buildings", lumFx && lumFxG,
            t.F(NMHoloTests.Lum("road_major", 0)) + "/" + t.F(NMHoloTests.Lum("bfill", 0)) + "/" + t.F(NMHoloTests.Lum("outline", 0)));
        t.Check("theme.overlay_opacities", t.Near(NMTheme.RingsOpacity(), 0.05, 0.0001) && t.Near(NMTheme.VignetteOpacity(), 0.55, 0.0001)
            && t.Near(NMTheme.HoloBarOpacity(), 0.035, 0.0001) && t.Near(NMTheme.HoloEdgeOpacity(), 0.3, 0.0001), "");
        t.Check("theme.rings_fade_with_zoom", NMTheme.RingsFade(0.5) == 1.0 && NMTheme.RingsFade(1.0) == 1.0 && t.Near(NMTheme.RingsFade(16.0), 0.2, 0.0001)
            && NMTheme.RingsFade(2.0) > NMTheme.RingsFade(4.0) && NMTheme.RingsFade(4.0) > NMTheme.RingsFade(8.0), t.F(NMTheme.RingsFade(4.0)));
        t.Check("holo.glow_opacity", t.Near(NMTheme.TileOpacity("glow"), 0.50, 0.0001), "");
        t.Check("holo.panel_opacity_default", t.Near(NMTheme.DefaultPanelOpacity(), 0.5, 0.0001), t.F(NMTheme.DefaultPanelOpacity()));
        let ms = new NightMapSettings();
        t.Check("holo.marker_size_default", ms.markerSize == 0.5, t.F(ms.markerSize));
        t.Check("holo.marker_scale", t.Near(NMTheme.MapMarkerScale(2.0, 0.5), 1.0, 0.0001) && t.Near(NMTheme.MapMarkerScale(1.0, 1.0), 1.0, 0.0001)
            && t.Near(NMTheme.MapMarkerScale(1.0, 0.0), 0.25, 0.0001) && t.Near(NMTheme.MapMarkerScale(1.0, 9.0), 1.5, 0.0001),
            t.F(NMTheme.MapMarkerScale(2.0, 0.5)) + " " + t.F(NMTheme.MapMarkerScale(1.0, 0.0)));
        t.Check("holo.theme_index", NMTheme.ThemeIndex(NightMapHoloColor.Cyan) == 0 && NMTheme.ThemeIndex(NightMapHoloColor.Green) == 1
            && NMTheme.ThemeIndex(NightMapHoloColor.Red) == 2 && NMTheme.ThemeIndex(NightMapHoloColor.Purple) == 3
            && NMTheme.ThemeIndex(NightMapHoloColor.Amber) == 4, "");
        NMHoloTests.PresetHues(t);
        let brC: HDRColor = NMTheme.BracketColor(0, true);
        let brOff: HDRColor = NMTheme.BracketColor(0, false);
        t.Check("holo.brackets_brighter_with_effects", brC.Red > brOff.Red && t.Near(brOff.Red, 0.478, 0.002), t.F(brC.Red));
    }

    private static func EffectsCases(t: ref<NMSelfTest>) {
        let canvas = new inkCanvas();
        let off = NMHolo.Create(false, 0, 1880.0, 1480.0, 1.0);
        off.AddGrid(canvas);
        off.AddScan(canvas);
        off.AddNoise(canvas);
        off.AddVignette(canvas);
        off.AddBar(canvas);
        off.AddEdges(canvas, 1880.0, 1480.0);
        off.Play(null);
        t.Check("holo.effects_off_builds_nothing", !IsDefined(off.grid) && !IsDefined(off.scan) && !IsDefined(off.noise) && !IsDefined(off.bar) && !IsDefined(off.vignette)
            && ArraySize(off.edges) == 0 && off.ProxyCount() == 0, "");
        let on = NMHolo.Create(true, 1, 1880.0, 1480.0, 2.0);
        on.AddGrid(canvas);
        on.AddScan(canvas);
        on.AddNoise(canvas);
        on.AddVignette(canvas);
        on.AddBar(canvas);
        on.AddEdges(canvas, 1880.0, 1480.0);
        t.Check("holo.effects_on_builds_overlays", IsDefined(on.grid) && IsDefined(on.scan) && IsDefined(on.noise) && IsDefined(on.bar) && IsDefined(on.vignette) && ArraySize(on.edges) == 4, "");
        t.Check("holo.overlay_opacities", t.Near(on.grid.GetOpacity(), 0.08, 0.0001) && t.Near(on.scan.GetOpacity(), 0.14, 0.0001) && t.Near(on.vignette.GetOpacity(), 0.55, 0.0001)
            && t.Near(on.noise.GetOpacity(), 0.008, 0.0001) && t.Near(on.bar.GetOpacity(), 0.0, 0.0001), "");
        t.Check("holo.scan_period_is_native", t.Near(on.ScanPeriod(), 4.0, 0.0001) && t.Near(on.scan.GetHeight(), 1480.0 + 4.0, 0.01), t.F(on.ScanPeriod()));
        // A whole panel with effects off: the Part 1 look, no overlay widgets, no animations, the see-through default opacity.
        let host = new inkCanvas();
        let layout = NMPanelLayout.Compute(3840.0, 2160.0);
        let panel = NMPanel.Build(host, layout, NMTheme.DefaultPanelOpacity(), 0, false);
        t.Check("holo.panel_effects_off_hides_overlays", IsDefined(panel.holo) && !panel.holo.effects && !IsDefined(panel.holo.grid)
            && !IsDefined(panel.holo.scan) && !IsDefined(panel.holo.bar) && ArraySize(panel.holo.edges) == 0 && panel.holo.ProxyCount() == 0, "");
        panel.Destroy();
        // Range rings: created only with effects on, and they follow the arrow.
        let mkOff = NMPlayerMarker.Create(canvas, 1.0, false, 0);
        let mkOn = NMPlayerMarker.Create(canvas, 1.0, true, 0);
        t.Check("holo.rings_only_with_effects", !mkOff.HasRings() && mkOn.HasRings(), "");
        let cb = NMRect.Create(NMTileManifest.WorldMinX(), NMTileManifest.WorldMinY(), NMTileManifest.WorldMaxX(), NMTileManifest.WorldMaxY());
        let pl = GetPlayer(GetGameInstance());
        if IsDefined(pl) {
            let ppos = pl.GetWorldPosition();
            let pcam = NMCamera.Create(1880.0, 1480.0, cb, NightMapSystem.MinMpp(), NightMapSystem.MaxMpp());
            pcam.SetCenter(ppos.X, ppos.Y);
            pcam.SetMpp(2.0);
            mkOn.Update(pcam, pl, 1880.0, 1480.0);
            let ra: Vector2 = mkOn.RingsTranslation();
            let aa: Vector2 = mkOn.ArrowTranslation();
            t.Check("holo.rings_follow_player", t.Near(ra.X, aa.X, 0.01) && t.Near(ra.Y, aa.Y, 0.01) && t.Near(aa.X, 940.0, 1.0),
                t.F(ra.X) + "," + t.F(ra.Y) + " / " + t.F(aa.X) + "," + t.F(aa.Y));
        } else {
            t.Check("holo.rings_follow_player", false, "no player in this test context");
        }
    }

    private static func RendererCases(t: ref<NMSelfTest>) {
        NMHoloTests.PlateCase(t);
        // Player arrow in the vanilla player colour; reticle brackets in the light bracket colour, green mirrored.
        let canvas = new inkCanvas();
        let mk = NMPlayerMarker.Create(canvas, 1.0, true, 0);
        let pc: HDRColor = mk.ArrowTint();
        t.Check("player.tint", NMHoloTests.SameRgb(pc, NMTheme.VanillaStateColor(n"Player")), t.F(pc.Red) + "," + t.F(pc.Green) + "," + t.F(pc.Blue));
        let rc: HDRColor = NMTheme.ReticleColor(0);
        let rg: HDRColor = NMTheme.ReticleColor(1);
        let ret = NMReticle.Create(canvas, 1.0, 0);
        ret.Update(100.0, 100.0, true, 120.0, 110.0, false, 1.0, 1.0, 16.0);
        let lc: HDRColor = ret.LegColor();
        t.Check("reticle.tint", NMHoloTests.SameRgb(lc, rc) && t.Near(rc.Red, 0.847, 0.002) && t.Near(rc.Green, 0.957, 0.002) && t.Near(rc.Blue, 1.0, 0.002)
            && rg.Green > rg.Blue && rg.Green > rg.Red, t.F(lc.Red) + "," + t.F(lc.Green) + "," + t.F(lc.Blue));
    }

    // Each preset keeps its hue in every role: the strongest channel of the accent, highlight, road and building tints.
    private static func Dominant(c: HDRColor) -> Int32 {
        if c.Red >= c.Green && c.Red >= c.Blue { return 0; }
        if c.Green >= c.Blue { return 1; }
        return 2;
    }
    private static func PresetHues(t: ref<NMSelfTest>) {
        let want: array<Int32> = [2, 1, 0, 2, 0];   // cyan: blue, green: green, red: red, purple: blue, amber: red
        let ok = true;
        let detail = "";
        let th = 0;
        while th < 5 {
            let a = NMTheme.HoloAccentOwn(th);
            let h = NMTheme.HoloHighlightOwn(th);
            let r = NMTheme.TileTintOwn("road_major", th);
            let f = NMTheme.TileTintOwn("bfill", th);
            let w = want[th];
            if NMHoloTests.Dominant(a) != w || NMHoloTests.Dominant(h) != w || NMHoloTests.Dominant(r) != w || NMHoloTests.Dominant(f) != w {
                ok = false;
                detail += " theme" + IntToString(th);
            }
            th += 1;
        }
        let purple = NMTheme.HoloAccentOwn(3);
        let amber = NMTheme.HoloAccentOwn(4);
        let red = NMTheme.HoloAccentOwn(2);
        ok = ok && purple.Red > purple.Green && amber.Green > amber.Blue && red.Blue > red.Green;   // not blue, yellow or orange
        t.Check("holo.preset_hues", ok, detail);
        t.Check("holo.preset_distinct", !NMHoloTests.SameRgb(NMTheme.HoloAccentOwn(2), NMTheme.HoloAccentOwn(4))
            && !NMHoloTests.SameRgb(NMTheme.HoloAccentOwn(3), NMTheme.HoloAccentOwn(0)), "");
    }
    public static func SameRgb(a: HDRColor, b: HDRColor) -> Bool {
        return AbsF(a.Red - b.Red) < 0.002 && AbsF(a.Green - b.Green) < 0.002 && AbsF(a.Blue - b.Blue) < 0.002;
    }

    // Icon-style pins sit on the dark plate with the ring in the icon's own colour. The renderer takes no effects
    // setting at all, so this one look holds with hologram effects on and off.
    private static func PlateCase(t: ref<NMSelfTest>) {
        let name = "plate.icon_background";
        let api = NMVanillaTests.TestApi();
        let L = api.CreateLayer(n"test.plate", "Plate", 5);
        L.SetPinStyle(NightMapPinStyle.Icon);
        let ft = NMTheme.VanillaStateColor(n"FastTravel");
        L.Add(NightMapItem.Create(new Vector4(-1800.0, 150.0, 0.0, 1.0), n"v", NMTheme.MappinAtlas(), n"fast_travel").WithTint(ft));
        let r = NMItemRenderer.Create(api, new inkCanvas(), 1.0);
        let cam = NMCamera.Create(1880.0, 1480.0, NMRect.Create(-6000.0, -4600.0, 4600.0, 7400.0), 0.5, 16.0);
        cam.SetCenter(-1800.0, 150.0);
        cam.SetMpp(0.5);
        r.Update(cam, 1880.0, 1480.0);
        if ArraySize(r.candSlot) != 1 {
            t.Check(name, false, "placed " + ToString(ArraySize(r.candSlot)));
            return;
        }
        let s = r.candSlot[0];
        let bg = r.chipBg[s];
        let tint: HDRColor = bg.GetTintColor();
        let size: Vector2 = bg.GetSize();
        let part = bg.GetTexturePart();
        t.Check(name, Equals(part, n"plate") && NMHoloTests.SameRgb(tint, ft) && bg.IsVisible() && t.Near(size.X, NMTheme.PlateSize(), 0.01)
            // The idle 50 % dims the icon only: the plate keeps the item's own alpha so its disc still cuts out the city.
            && t.Near(r.chipIcon[s].GetOpacity(), NMTheme.VanillaIdleOpacity(), 0.001) && t.Near(bg.GetOpacity(), 1.0 * NMTheme.PlateOpacity(), 0.001)
            && t.Near(NMTheme.PlateSize(), 152.0, 0.001)
            && t.Near(NMTheme.PlateOpacity(), 1.0, 0.001),
            NameToString(part) + " " + t.F(tint.Red) + "," + t.F(tint.Green) + "," + t.F(tint.Blue) + " size " + t.F(size.X) + " op " + t.F(bg.GetOpacity()));
        // The selection grow brings the icon to full strength; the plate's opacity stays put.
        r.ApplySelection(0, 0, NMTheme.VanillaGrowMs() * 0.5);
        let mid = bg.GetOpacity();
        r.ApplySelection(0, 0, NMTheme.VanillaGrowMs());
        t.Check("plate.steady_on_grow", t.Near(mid, NMTheme.PlateOpacity(), 0.001) && t.Near(bg.GetOpacity(), NMTheme.PlateOpacity(), 0.001)
            && t.Near(r.chipIcon[s].GetOpacity(), 1.0, 0.001), t.F(mid) + " " + t.F(bg.GetOpacity()));
    }
}
