module NightMap

// Visual tokens. Sizes are 3840x2160 HUD units and MUST match tools/tiles/nmtiles/ui_atlas.py SIZES.
public abstract class NMTheme {
    public static func Cyan() -> HDRColor { return new HDRColor(0.478, 0.941, 1.0, 1.0); }
    public static func MapBackground() -> HDRColor { return new HDRColor(0.031, 0.071, 0.102, 1.0); }   // #08121a
    public static func Text() -> HDRColor { return new HDRColor(0.784, 0.965, 1.0, 1.0); }
    public static func Pink() -> HDRColor { return new HDRColor(1.0, 0.310, 0.847, 1.0); }
    public static func Yellow() -> HDRColor { return new HDRColor(1.0, 0.878, 0.400, 1.0); }
    public static func Muted() -> HDRColor { return new HDRColor(0.667, 0.863, 0.922, 1.0); }
    public static func PanelBg() -> HDRColor { return new HDRColor(0.024, 0.078, 0.118, 1.0); }
    public static func CardBg() -> HDRColor { return new HDRColor(0.039, 0.157, 0.216, 1.0); }
    public static func ZoomRatePerSecond() -> Float { return 4.0; }
    public static func CardOpacity() -> Float { return 0.5; }

    public static func BodyFont() -> String { return "base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily"; }

    public static func UiAtlas() -> ResRef { return r"nightmap\\ui\\ui.inkatlas"; }
    public static func HoloAtlas() -> ResRef { return r"nightmap\\ui\\holo.inkatlas"; }

    // ---- vanilla map markers (sub-project 2): values extracted from the vanilla world map (spike LOOK.md) ----
    public static func MappinAtlas() -> ResRef { return r"base\\gameplay\\gui\\common\\icons\\mappin_icons.inkatlas"; }
    public static func ShadowAtlas() -> ResRef { return r"base\\gameplay\\gui\\common\\shadow_blobs.inkatlas"; }
    public static func VanillaIconSize() -> Float { return 64.0; }        // 4K units, as the vanilla world map
    public static func VanillaShadowSize() -> Float { return 180.0; }     // soft blob under the icon; tune at checkpoint 4
    public static func VanillaShadowOpacity() -> Float { return 0.8; }
    public static func VanillaIdleOpacity() -> Float { return 0.5; }      // vanilla Mappin state opacity
    public static func VanillaEmphScale() -> Float { return 1.3; }        // vanilla OnSelect end scale
    public static func VanillaGrowMs() -> Float { return 150.0; }
    // Vanilla map-marker colour per widget state (MappinsGroup.WidgetState). Unknown states are white.
    public static func VanillaStateColor(state: CName) -> HDRColor {
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
        return new HDRColor(1.0, 1.0, 1.0, 1.0);   // ServicePoint, Vehicle, VehicleForPurchase and anything unknown
    }
    public static func ShadowColor() -> HDRColor { return new HDRColor(0.0, 0.0, 0.0, 1.0); }
    public static func ChipSize() -> Float { return 112.0; }
    public static func ChipSelSize() -> Float { return 136.0; }
    public static func ClusterSize() -> Float { return 176.0; }
    public static func ClusterSelSize() -> Float { return 200.0; }
    public static func MiniSize() -> Float { return 80.0; }
    public static func IconSize() -> Float { return 48.0; }
    public static func PlayerSize() -> Float { return 112.0; }
    public static func BracketSize() -> Float { return 110.0; }
    public static func MiniOffsetY() -> Float { return -106.0; }
    public static func MiniSpacing() -> Float { return 67.0; }

    public static func HintHeight() -> Float { return 110.0; }
    public static func SelectRadius() -> Float { return 100.0; }
    public static func ClusterSpacing() -> Float { return 192.0; }
    public static func ChipBudget() -> Int32 { return 300; }
    public static func SnapMs() -> Float { return 150.0; }   // ease onto the focused marker when panning stops
    public static func ClusterBudget() -> Int32 { return 80; }
    public static func MaxGlobalCategories() -> Int32 { return 64; }

    // 1.0 if ink rotates clockwise for positive angles; verified at Checkpoint 2.
    public static func PlayerRotationSign() -> Float { return 1.0; }

    // ---- map themes: 0 cyan hologram (default), 1 green hologram, 2 topographic (near-black survey map: teal
    // linework, pale contour outlines, orange frame). Every function takes the theme index; nothing here reads settings,
    // so the look is testable. The system passes ThemeIndex(NightMapSettings.holoColor) on open.
    // Accent: glow tiles and overlays (grid, noise, scan bar, edge glow). Highlight: frame, brackets, hint/header text.
    public static func ThemeIndex(c: NightMapHoloColor) -> Int32 {
        if Equals(c, NightMapHoloColor.Green) { return 1; }
        if Equals(c, NightMapHoloColor.Topographic) { return 2; }
        return 0;
    }
    public static func HoloAccent(theme: Int32) -> HDRColor {
        if theme == 1 { return new HDRColor(0.365, 1.0, 0.541, 1.0); }   // #5dff8a
        if theme == 2 { return new HDRColor(0.180, 0.820, 0.860, 1.0); } // #2ed1db teal
        return new HDRColor(0.310, 0.890, 1.0, 1.0);                     // #4fe3ff
    }
    public static func HoloHighlight(theme: Int32) -> HDRColor {
        if theme == 1 { return new HDRColor(0.553, 1.0, 0.659, 1.0); }   // #8dffa8
        if theme == 2 { return new HDRColor(1.0, 0.553, 0.180, 1.0); }   // #ff8d2e orange
        return NMTheme.Cyan();
    }
    public static func HoloBackground(theme: Int32) -> HDRColor {
        if theme == 1 { return new HDRColor(0.027, 0.078, 0.051, 1.0); } // #07140d
        if theme == 2 { return new HDRColor(0.016, 0.024, 0.031, 1.0); } // #040608 near-black
        return NMTheme.MapBackground();                                  // #08121a
    }
    // The map ground's opacity: the topographic theme is an opaque black survey map whatever the see-through setting.
    public static func PanelOpacityFor(theme: Int32, opacity: Float) -> Float {
        return theme == 2 ? MaxF(opacity, 0.92) : opacity;
    }
    // The always-visible sidebar behind marker details and photo previews.
    public static func SidebarBg(theme: Int32) -> HDRColor {
        if theme == 2 { return new HDRColor(0.012, 0.016, 0.020, 1.0); }
        return NMTheme.CardBg();
    }
    // Corner brackets: the highlight colour; with effects on it gets HDR gain so it reads brighter than the frame.
    public static func BracketColor(theme: Int32, effects: Bool) -> HDRColor {
        let c = NMTheme.HoloHighlight(theme);
        if !effects {
            return c;
        }
        let g = NMTheme.HoloBracketGain();
        return new HDRColor(c.Red * g, c.Green * g, c.Blue * g, 1.0);
    }
    public static func HoloScanColor() -> HDRColor { return new HDRColor(0.0, 0.0, 0.0, 1.0); }
    public static func HoloGridOpacity() -> Float { return 0.07; }
    public static func HoloScanOpacity() -> Float { return 0.20; }
    public static func HoloNoiseOpacity() -> Float { return 0.12; }   // the flicker animation moves it between 0.08 and 0.14
    public static func HoloBarOpacity() -> Float { return 0.25; }
    public static func HoloEdgeOpacity() -> Float { return 0.6; }
    public static func HoloBracketGain() -> Float { return 1.25; }   // brackets brighten with HDR gain (bloom not verified)
    public static func HaloOpacity() -> Float { return 0.35; }       // marker halo in the pin's own colour (effects on)
    public static func HaloSize() -> Float { return 200.0; }
    public static func ScanPeriod() -> Float { return 4.0; }          // holo_scan line spacing in 4K units
    public static func DefaultPanelOpacity() -> Float { return 0.45; }   // see-through; keep equal to NightMapSettings.panelOpacity
    // The glow layer draws a level this many steps coarser than the camera's, upscaled (bilinear = soft bloom).
    public static func GlowLevelOffset() -> Int32 { return 2; }

    // Tile-set tints. Tiles are colourless masks; these are applied at runtime, so a theme change needs no rebuild.
    // Keys are NMTileManifest.SetName values.
    public static func TileTint(set: String, theme: Int32) -> HDRColor {
        if Equals(set, "glow") { return NMTheme.HoloAccent(theme); }
        if Equals(set, "road") {
            if theme == 1 { return new HDRColor(0.122, 0.604, 0.322, 1.0); }   // #1f9a52
            if theme == 2 { return new HDRColor(0.086, 0.400, 0.447, 1.0); }   // #166672 dim teal
            return new HDRColor(0.118, 0.549, 0.588, 1.0);                     // #1e8c96
        }
        if theme == 1 { return new HDRColor(0.659, 1.0, 0.749, 1.0); }         // #a8ffbf (bfill, outline)
        if theme == 2 { return new HDRColor(0.800, 0.910, 0.937, 1.0); }       // #cce8ef pale contour line
        return new HDRColor(0.624, 0.953, 1.0, 1.0);                           // #9ff3ff
    }
    // Per theme: the topographic map is linework on black: faint road fills and building fills, crisp pale outlines,
    // a soft teal glow.
    public static func TileOpacityFor(set: String, theme: Int32) -> Float {
        if theme == 2 {
            if Equals(set, "glow") { return 0.35; }
            if Equals(set, "road") { return 0.18; }
            if Equals(set, "bfill") { return 0.04; }
            if Equals(set, "outline") { return 0.95; }
        }
        return NMTheme.TileOpacity(set);
    }
    public static func TileOpacity(set: String) -> Float {
        if Equals(set, "glow") { return 0.45; }
        if Equals(set, "road") { return 0.55; }
        if Equals(set, "bfill") { return 0.12; }
        if Equals(set, "outline") { return 0.9; }
        return 1.0;
    }
}
