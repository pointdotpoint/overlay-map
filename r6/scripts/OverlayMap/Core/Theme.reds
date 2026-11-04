module OverlayMap

// Visual tokens. Sizes are 3840x2160 HUD units and MUST match tools/tiles/nmtiles/ui_atlas.py SIZES.
public abstract class NMTheme {
    // "Follow HUD Painter colours": the live HUD palette, or null (today's colours). Held by OverlayMapSystem.
    public static func Palette() -> ref<NMHudPalette> {
        let sys = OverlayMapSystem.Get(GetGameInstance());
        return IsDefined(sys) ? sys.Palette() : null;
    }
    public static func Use(p: ref<NMHudPalette>) {
        let sys = OverlayMapSystem.Get(GetGameInstance());
        if IsDefined(sys) { sys.UsePalette(p); }
    }
    // The palette's colour for the role once resolved, else `own`.
    public static func Pick(role: NMColorRole, own: HDRColor) -> HDRColor {
        let p = NMTheme.Palette();
        if IsDefined(p) && p.Has(role) { return p.Get(role); }
        return own;
    }
    public static func Cyan() -> HDRColor { return NMTheme.Pick(NMColorRole.Accent, new HDRColor(0.478, 0.941, 1.0, 1.0)); }
    public static func MapBackground() -> HDRColor { return NMTheme.Pick(NMColorRole.Background, new HDRColor(0.031, 0.071, 0.102, 1.0)); }   // #08121a
    public static func Text() -> HDRColor { return NMTheme.Pick(NMColorRole.Text, new HDRColor(0.784, 0.965, 1.0, 1.0)); }
    public static func Pink() -> HDRColor { return NMTheme.Pick(NMColorRole.Warn, new HDRColor(1.0, 0.310, 0.847, 1.0)); }
    public static func Yellow() -> HDRColor { return NMTheme.Pick(NMColorRole.Route, new HDRColor(1.0, 0.878, 0.400, 1.0)); }
    public static func Muted() -> HDRColor { return NMTheme.Pick(NMColorRole.Muted, new HDRColor(0.667, 0.863, 0.922, 1.0)); }
    // Hint bar / tooltip / photo fills. Each theme keeps cyan's saturation and brightness at its own hue.
    public static func PanelBg(opt theme: Int32) -> HDRColor { return NMTheme.Pick(NMColorRole.PanelBg, NMTheme.PanelBgOwn(theme)); }
    public static func PanelBgOwn(theme: Int32) -> HDRColor {
        if theme == 1 { return new HDRColor(0.024, 0.118, 0.057, 1.0); }
        if theme == 2 { return new HDRColor(0.118, 0.024, 0.037, 1.0); }
        if theme == 3 { return new HDRColor(0.079, 0.024, 0.118, 1.0); }
        if theme == 4 { return new HDRColor(0.118, 0.080, 0.024, 1.0); }
        return new HDRColor(0.024, 0.078, 0.118, 1.0);
    }
    public static func CardBg(opt theme: Int32) -> HDRColor { return NMTheme.Pick(NMColorRole.PanelBg, NMTheme.CardBgOwn(theme)); }
    public static func CardBgOwn(theme: Int32) -> HDRColor {
        if theme == 1 { return new HDRColor(0.039, 0.216, 0.101, 1.0); }
        if theme == 2 { return new HDRColor(0.216, 0.039, 0.063, 1.0); }
        if theme == 3 { return new HDRColor(0.142, 0.039, 0.216, 1.0); }
        if theme == 4 { return new HDRColor(0.216, 0.145, 0.039, 1.0); }
        return new HDRColor(0.039, 0.157, 0.216, 1.0);
    }
    public static func ZoomRatePerSecond() -> Float { return 4.0; }
    public static func CardOpacity() -> Float { return 0.5; }

    public static func BodyFont() -> String { return "base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily"; }

    public static func UiAtlas() -> ResRef { return r"overlaymap\\ui\\ui.inkatlas"; }
    public static func HoloAtlas() -> ResRef { return r"overlaymap\\ui\\holo.inkatlas"; }

    // ---- vanilla map markers (sub-project 2): values extracted from the vanilla world map (spike LOOK.md) ----
    public static func MappinAtlas() -> ResRef { return r"base\\gameplay\\gui\\common\\icons\\mappin_icons.inkatlas"; }
    public static func MinimapAtlas() -> ResRef { return r"base\\gameplay\\gui\\widgets\\minimap\\atlas_minimap.inkatlas"; }
    public static func DotSize() -> Float { return 32.0; }                // police dots (4K units)
    public static func VanillaIconSize() -> Float { return 64.0; }        // 4K units, as the vanilla world map
    public static func VanillaIdleOpacity() -> Float { return 0.5; }      // vanilla Mappin state opacity
    public static func VanillaEmphScale() -> Float { return 1.3; }        // vanilla OnSelect end scale
    public static func VanillaGrowMs() -> Float { return 150.0; }
    // Vanilla map-marker colour per widget state (MappinsGroup.WidgetState). Unknown states are white.
    public static func VanillaStateColor(state: CName) -> HDRColor {
        let own = NMTheme.VanillaStateColorOwn(state);
        if Equals(state, n"Quest") { return NMTheme.Pick(NMColorRole.Route, own); }
        if Equals(state, n"Player") { return NMTheme.Pick(NMColorRole.Player, own); }
        if Equals(state, n"FastTravel") || Equals(state, n"FastTravelMetro") { return NMTheme.Pick(NMColorRole.FastTravel, own); }
        if Equals(state, n"Relic") { return NMTheme.Pick(NMColorRole.Relic, own); }
        if Equals(state, n"Prevention_LightBlue") { return NMTheme.Pick(NMColorRole.Police, own); }
        return own;
    }
    public static func VanillaStateColorOwn(state: CName) -> HDRColor {
        if Equals(state, n"Quest") { return new HDRColor(1.0, 1.0, 0.306, 1.0); }            // #FFFF4E
        if Equals(state, n"Gigs") { return new HDRColor(0.0, 1.0, 0.835, 1.0); }             // #00FFD5
        if Equals(state, n"Default") { return new HDRColor(1.0, 0.443, 0.404, 1.0); }        // #FF7167
        if Equals(state, n"QuestComplete") { return new HDRColor(0.42, 0.424, 0.424, 1.0); } // #6B6C6C
        if Equals(state, n"QuestUntracked") { return new HDRColor(0.847, 0.349, 0.071, 1.0); } // #D85912
        if Equals(state, n"Story") { return new HDRColor(0.369, 0.965, 1.0, 1.0); }          // #5EF6FF
        if Equals(state, n"FastTravel") { return new HDRColor(0.349, 0.706, 1.0, 1.0); }     // #59B4FF
        if Equals(state, n"FastTravelMetro") { return new HDRColor(0.8, 0.506, 1.0, 1.0); }  // #CC81FF
        if Equals(state, n"Relic") { return new HDRColor(0.471, 0.678, 1.0, 1.0); }          // #78ADFF
        if Equals(state, n"Player") { return new HDRColor(0.161, 1.0, 0.725, 1.0); }         // #29FFB9
        if Equals(state, n"Prevention_LightBlue") { return new HDRColor(0.369, 0.965, 1.0, 1.0); }   // MainColors.Blue #5EF6FF
        return new HDRColor(1.0, 1.0, 1.0, 1.0);   // ServicePoint, Vehicle, VehicleForPurchase and anything unknown
    }
    public static func ChipSize() -> Float { return 72.0; }       // hex chip (collectibles, our pins)
    public static func ChipSelSize() -> Float { return 92.0; }    // selection rim around a hex chip
    // The dark plate behind a vanilla icon (spec 5.1): disc to half its radius, falloff beyond, ring and a faint glow in
    // the icon colour. Sized so the ring hugs the visible glyph (~1.3x its radius; mappin art is padded in its 64 box).
    public static func PlateSize() -> Float { return 152.0; }
    // Declutter: two markers collide when their centres are closer than this times the sum of their visible radii.
    // 1.0: plate rings may touch but never overlap (0.75 let neighbours stack into walls at mid zoom; Task 11).
    public static func DeclutterOverlap() -> Float { return 1.0; }
    public static func PlateOpacity() -> Float { return 1.0; }    // times the icon's own opacity
    public static func IconSize() -> Float { return 24.0; }       // a hex chip's centre dot
    public static func PlayerSize() -> Float { return 112.0; }
    public static func BracketSize() -> Float { return 110.0; }

    public static func HintHeight() -> Float { return 110.0; }
    public static func SelectRadius() -> Float { return 100.0; }
    public static func ChipBudget() -> Int32 { return 300; }
    public static func SnapMs() -> Float { return 150.0; }   // ease onto the focused marker when panning stops
    public static func MaxGlobalCategories() -> Int32 { return 64; }

    // 1.0 if ink rotates clockwise for positive angles; verified at Checkpoint 2.
    public static func PlayerRotationSign() -> Float { return 1.0; }

    // ---- hologram themes: 0 cyan (default), 1 green, 2 red, 3 purple, 4 amber; the presets keep cyan's lightness and
    // saturation at another hue. Every function takes the theme index; nothing here reads
    // settings, so the look is testable. The system passes ThemeIndex(OverlayMapSettings.holoColor) on open.
    // Accent: glow tiles and overlays (grid, noise, scan bar, edge glow). Highlight: frame, brackets, hint/header text.
    public static func ThemeIndex(c: OverlayMapHoloColor) -> Int32 {
        if Equals(c, OverlayMapHoloColor.Green) { return 1; }
        if Equals(c, OverlayMapHoloColor.Red) { return 2; }
        if Equals(c, OverlayMapHoloColor.Purple) { return 3; }
        if Equals(c, OverlayMapHoloColor.Amber) { return 4; }
        return 0;
    }
    public static func HoloAccent(theme: Int32) -> HDRColor { return NMTheme.Pick(NMColorRole.Accent, NMTheme.HoloAccentOwn(theme)); }
    public static func HoloAccentOwn(theme: Int32) -> HDRColor {
        if theme == 1 { return new HDRColor(0.365, 1.0, 0.541, 1.0); }   // #5dff8a
        if theme == 2 { return new HDRColor(1.0, 0.310, 0.402, 1.0); }
        if theme == 3 { return new HDRColor(0.712, 0.310, 1.0, 1.0); }
        if theme == 4 { return new HDRColor(1.0, 0.724, 0.310, 1.0); }
        return new HDRColor(0.310, 0.890, 1.0, 1.0);                     // #4fe3ff
    }
    public static func HoloHighlight(theme: Int32) -> HDRColor { return NMTheme.Pick(NMColorRole.Highlight, NMTheme.HoloHighlightOwn(theme)); }
    public static func HoloHighlightOwn(theme: Int32) -> HDRColor {
        if theme == 1 { return new HDRColor(0.553, 1.0, 0.659, 1.0); }   // #8dffa8
        if theme == 2 { return new HDRColor(1.0, 0.478, 0.548, 1.0); }
        if theme == 3 { return new HDRColor(0.782, 0.478, 1.0, 1.0); }
        if theme == 4 { return new HDRColor(1.0, 0.791, 0.478, 1.0); }
        return NMTheme.Cyan();
    }
    public static func HoloBackground(theme: Int32) -> HDRColor { return NMTheme.Pick(NMColorRole.Background, NMTheme.HoloBackgroundOwn(theme)); }
    public static func HoloBackgroundOwn(theme: Int32) -> HDRColor {
        if theme == 1 { return new HDRColor(0.016, 0.063, 0.031, 1.0); } // #041008
        if theme == 2 { return new HDRColor(0.094, 0.020, 0.030, 1.0); }
        if theme == 3 { return new HDRColor(0.063, 0.020, 0.094, 1.0); }
        if theme == 4 { return new HDRColor(0.094, 0.064, 0.020, 1.0); }
        return new HDRColor(0.020, 0.051, 0.094, 1.0);                   // #050d18
    }
    // District title in the top-left header (#e6f7ff), mirrored in green.
    public static func HeaderTitle(theme: Int32) -> HDRColor { return NMTheme.Pick(NMColorRole.Highlight, NMTheme.HeaderTitleOwn(theme)); }
    public static func HeaderTitleOwn(theme: Int32) -> HDRColor {
        if theme == 1 { return new HDRColor(0.902, 1.0, 0.925, 1.0); }  // #e6ffec
        if theme == 2 { return new HDRColor(1.0, 0.902, 0.915, 1.0); }
        if theme == 3 { return new HDRColor(0.959, 0.902, 1.0, 1.0); }
        if theme == 4 { return new HDRColor(1.0, 0.961, 0.902, 1.0); }
        return new HDRColor(0.902, 0.969, 1.0, 1.0);                     // #e6f7ff
    }
    // Sidebar glass (spec 6): a dark fill over the panel fill, a bright left edge and a soft inner gradient.
    public static func SidebarBg(theme: Int32) -> HDRColor { return NMTheme.Pick(NMColorRole.PanelBg, NMTheme.SidebarBgOwn(theme)); }
    public static func SidebarBgOwn(theme: Int32) -> HDRColor {
        if theme == 1 { return new HDRColor(0.012, 0.047, 0.024, 1.0); } // #030c06
        if theme == 2 { return new HDRColor(0.071, 0.012, 0.020, 1.0); }
        if theme == 3 { return new HDRColor(0.046, 0.012, 0.071, 1.0); }
        if theme == 4 { return new HDRColor(0.071, 0.047, 0.012, 1.0); }
        return new HDRColor(0.012, 0.035, 0.071, 1.0);                   // #030912
    }
    // At least .80 and always above the panel fill it sits on (0.92 -> 0.98), so the world and the map never show
    // through: ink blends in linear light, where a few percent of a bright pixel still reads on a dark fill.
    public static func SidebarOpacity(panel: Float) -> Float { return ClampF(panel + 0.06, 0.80, 1.0); }
    public static func SidebarEdgeOpacity() -> Float { return 0.55; }
    public static func SidebarGradientOpacity() -> Float { return 0.10; }
    // Small uppercase labels (HOVERED, TRACKING) and the card's description text.
    public static func CardLabel(theme: Int32) -> HDRColor { return NMTheme.Pick(NMColorRole.Muted, NMTheme.CardLabelOwn(theme)); }
    public static func CardLabelOwn(theme: Int32) -> HDRColor {
        if theme == 1 { return new HDRColor(0.435, 0.753, 0.541, 1.0); } // #6fc08a
        if theme == 2 { return new HDRColor(0.753, 0.435, 0.477, 1.0); }
        if theme == 3 { return new HDRColor(0.620, 0.435, 0.753, 1.0); }
        if theme == 4 { return new HDRColor(0.753, 0.626, 0.435, 1.0); }
        return new HDRColor(0.435, 0.612, 0.753, 1.0);                   // #6f9cc0
    }
    public static func CardBody(theme: Int32) -> HDRColor { return NMTheme.Pick(NMColorRole.Text, NMTheme.CardBodyOwn(theme)); }
    public static func CardBodyOwn(theme: Int32) -> HDRColor {
        if theme == 1 { return new HDRColor(0.710, 0.878, 0.761, 1.0); } // #b5e0c2
        if theme == 2 { return new HDRColor(0.878, 0.710, 0.732, 1.0); }
        if theme == 3 { return new HDRColor(0.808, 0.710, 0.878, 1.0); }
        if theme == 4 { return new HDRColor(0.878, 0.811, 0.710, 1.0); }
        return new HDRColor(0.710, 0.804, 0.878, 1.0);                   // #b5cde0
    }
    // Keycap box (spec 6: fill @ .14, edge @ .55 in the sRGB mockup). Ink blends in linear light, where a .14 fill of
    // the highlight reads about .40 on the dark glass and drowns the key; .04 lands on the mockup's look.
    public static func KeycapFillOpacity() -> Float { return 0.04; }
    public static func KeycapEdgeOpacity() -> Float { return 0.55; }
    public static func DividerOpacity() -> Float { return 0.14; }   // card and tracking dividers
    public static func HeaderScrimOpacity() -> Float { return 0.4; }   // holo_halo behind the title, map-background tint
    public static func HeaderPad() -> Float { return 16.0; }           // markers keep this clear of the header text
    // Corner brackets: the highlight colour; with effects on it gets HDR gain so it reads brighter than the frame.
    public static func BracketColor(theme: Int32, effects: Bool) -> HDRColor {
        let c = NMTheme.HoloHighlight(theme);
        if !effects {
            return c;
        }
        let g = NMTheme.HoloBracketGain();
        return new HDRColor(c.Red * g, c.Green * g, c.Blue * g, 1.0);
    }
    // Reticle brackets: light #d8f4ff (spec 5.2), mirrored in green.
    public static func ReticleColor(theme: Int32) -> HDRColor {
        if theme == 1 { return new HDRColor(0.847, 1.0, 0.894, 1.0); }  // #d8ffe4
        if theme == 2 { return new HDRColor(1.0, 0.847, 0.867, 1.0); }
        if theme == 3 { return new HDRColor(0.936, 0.847, 1.0, 1.0); }
        if theme == 4 { return new HDRColor(1.0, 0.939, 0.847, 1.0); }
        return new HDRColor(0.847, 0.957, 1.0, 1.0);                     // #d8f4ff
    }
    public static func HoloScanColor() -> HDRColor { return new HDRColor(0.0, 0.0, 0.0, 1.0); }
    // Accent overlays over a near-black map. Ink blends in linear light, where a few percent of the bright accent
    // already lifts the dark map visibly (.04 noise read as an sRGB teal wash of ~+30), so these sit far below the
    // sRGB mockup's numbers. Tuned in-game (Task 11).
    public static func HoloGridOpacity() -> Float { return 0.08; }
    public static func HoloScanOpacity() -> Float { return 0.14; }
    public static func RingsOpacity() -> Float { return 0.05; }   // at close zoom; RingsFade thins them out further
    public static func VignetteOpacity() -> Float { return 0.55; }
    public static func RingsSize() -> Float { return 1440.0; }   // 4K units across
    // The range rings keep their screen size, so zoomed out they span districts: 1 up to 1 m/unit, linear in log2(mpp)
    // down to 0.2 at 8 m/unit and beyond (an ambient texture, not a target over the city).
    public static func RingsFade(mpp: Float) -> Float {
        if mpp <= 1.0 { return 1.0; }
        if mpp >= 8.0 { return 0.2; }
        return 1.0 - 0.8 * (LogF(mpp) / LogF(2.0)) / 3.0;
    }
    public static func HoloNoiseOpacity() -> Float { return 0.008; }   // the flicker moves it between 0.68x and 1.18x
    public static func HoloBarOpacity() -> Float { return 0.035; }
    public static func HoloBarHeight() -> Float { return 0.06; }        // of the map height
    public static func HoloTrackOpacity() -> Float { return 0.6; }      // VHS tracking band at its brightest (0.35 measured ~3% brighter: too faint)
    public static func HoloTrackHeight() -> Float { return 0.07; }      // of the map height
    public static func GlitchIntensity() -> Float { return 0.35; }      // inkGlitchEffect intensity at a burst's peak
    public static func HoloEdgeOpacity() -> Float { return 0.3; }
    public static func HoloBracketGain() -> Float { return 1.25; }   // brackets brighten with HDR gain (bloom not verified)
    public static func ScanPeriod() -> Float { return 4.0; }          // holo_scan line spacing in 4K units
    public static func DefaultPanelOpacity() -> Float { return 0.5; }   // half see-through; keep equal to OverlayMapSettings.panelOpacity
    // The oldest default (0.45) becomes the current one. The 0.02 slider step from 0.3 can't produce 0.45, so a saved 0.45
    // is never the player's choice; any other value is kept.
    public static func MapMarkerScale(layoutScale: Float, markerSize: Float) -> Float {
        return layoutScale * ClampF(markerSize, 0.25, 1.5);   // the Map marker size slider's range
    }
    public static func MigratePanelOpacity(saved: Float) -> Float {
        return AbsF(saved - 0.45) < 0.0005 ? NMTheme.DefaultPanelOpacity() : saved;   // float 0.449 is 0.0009999 away
    }
    // The glow layer draws a level this many steps coarser than the camera's, upscaled (bilinear = soft bloom).
    public static func GlowLevelOffset() -> Int32 { return 0; }   // glow draws at the camera's own level: a tight halo

    // Tile-set tints. Tiles are colourless masks; these are applied at runtime, so a theme change needs no rebuild.
    // Keys are NMTileManifest.SetName values.
    public static func TileTint(set: String, theme: Int32) -> HDRColor {
        if Equals(set, "metro") { return new HDRColor(1.0, 1.0, 1.0, 1.0); }   // NCART colours are baked in; never themed
        let own = NMTheme.TileTintOwn(set, theme);
        if Equals(set, "road") { return NMTheme.Pick(NMColorRole.Road, own); }
        if Equals(set, "outline") || Equals(set, "glow") { return NMTheme.Pick(NMColorRole.Wall, own); }
        return NMTheme.Pick(NMColorRole.Floor, own);   // bfill
    }
    public static func TileTintOwn(set: String, theme: Int32) -> HDRColor {
        if theme == 1 {   // same lightness and saturation as cyan, hue ~140 degrees
            if Equals(set, "glow") { return new HDRColor(0.184, 1.0, 0.456, 1.0); }          // #2fff74
            if Equals(set, "outline") { return new HDRColor(0.227, 0.816, 0.424, 1.0); }     // #3ad06c
            if Equals(set, "road") { return new HDRColor(0.363, 0.924, 0.550, 1.0); }
            return new HDRColor(0.106, 0.471, 0.227, 1.0);                                   // #1b783a (bfill)
        }
        if theme == 2 {   // red, hue ~352 degrees; same lightness and saturation as cyan
            if Equals(set, "glow") { return new HDRColor(1.0, 0.184, 0.293, 1.0); }
            if Equals(set, "outline") { return new HDRColor(0.816, 0.227, 0.306, 1.0); }
            if Equals(set, "road") { return new HDRColor(0.924, 0.363, 0.438, 1.0); }
            return new HDRColor(0.471, 0.106, 0.155, 1.0);   // bfill
        }
        if theme == 3 {   // purple, hue ~275 degrees; same lightness and saturation as cyan
            if Equals(set, "glow") { return new HDRColor(0.660, 0.184, 1.0, 1.0); }
            if Equals(set, "outline") { return new HDRColor(0.571, 0.227, 0.816, 1.0); }
            if Equals(set, "road") { return new HDRColor(0.690, 0.363, 0.924, 1.0); }
            return new HDRColor(0.319, 0.106, 0.471, 1.0);   // bfill
        }
        if theme == 4 {   // amber, hue ~36 degrees; same lightness and saturation as cyan
            if Equals(set, "glow") { return new HDRColor(1.0, 0.674, 0.184, 1.0); }
            if Equals(set, "outline") { return new HDRColor(0.816, 0.580, 0.227, 1.0); }
            if Equals(set, "road") { return new HDRColor(0.924, 0.699, 0.363, 1.0); }
            return new HDRColor(0.471, 0.325, 0.106, 1.0);   // bfill
        }
        if Equals(set, "glow") { return new HDRColor(0.184, 0.612, 1.0, 1.0); }              // #2f9cff
        if Equals(set, "outline") { return new HDRColor(0.227, 0.561, 0.816, 1.0); }         // #3a8fd0
        // One road colour like the vanilla minimap (halfway between the old minor and major tints): one highway is
        // many road shapes, so tinting them by width striped it.
        if Equals(set, "road") { return new HDRColor(0.363, 0.694, 0.924, 1.0); }            // #5cb1ec
        return new HDRColor(0.106, 0.290, 0.471, 1.0);                                       // #1b4a78 (bfill; one tint for fill and dots)
    }
    public static func TileOpacity(set: String) -> Float {
        if Equals(set, "glow") { return 0.50; }
        if Equals(set, "bfill") { return 0.40; }
        if Equals(set, "outline") { return 0.40; }
        if Equals(set, "road") { return 0.90; }
        return 1.0;   // metro: full colour tiles
    }
}
