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
    public static func MinimapAtlas() -> ResRef { return r"base\\gameplay\\gui\\widgets\\minimap\\atlas_minimap.inkatlas"; }
    public static func DotSize() -> Float { return 32.0; }                // police dots (4K units)
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
        if Equals(state, n"Prevention_LightBlue") { return new HDRColor(0.369, 0.965, 1.0, 1.0); }   // MainColors.Blue #5EF6FF
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

    // ---- hologram themes: 0 cyan (default), 1 green. Every function takes the theme index; nothing here reads
    // settings, so the look is testable. The system passes ThemeIndex(NightMapSettings.holoColor) on open.
    // Accent: glow tiles and overlays (grid, noise, scan bar, edge glow). Highlight: frame, brackets, hint/header text.
    public static func ThemeIndex(c: NightMapHoloColor) -> Int32 {
        if Equals(c, NightMapHoloColor.Green) { return 1; }
        return 0;
    }
    public static func HoloAccent(theme: Int32) -> HDRColor {
        if theme == 1 { return new HDRColor(0.365, 1.0, 0.541, 1.0); }   // #5dff8a
        return new HDRColor(0.310, 0.890, 1.0, 1.0);                     // #4fe3ff
    }
    public static func HoloHighlight(theme: Int32) -> HDRColor {
        if theme == 1 { return new HDRColor(0.553, 1.0, 0.659, 1.0); }   // #8dffa8
        return NMTheme.Cyan();
    }
    public static func HoloBackground(theme: Int32) -> HDRColor {
        if theme == 1 { return new HDRColor(0.016, 0.063, 0.031, 1.0); } // #041008
        return new HDRColor(0.020, 0.051, 0.094, 1.0);                   // #050d18
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
    public static func HoloGridOpacity() -> Float { return 0.08; }
    public static func HoloScanOpacity() -> Float { return 0.14; }
    public static func RingsOpacity() -> Float { return 0.10; }
    public static func VignetteOpacity() -> Float { return 0.55; }
    public static func RingsSize() -> Float { return 1440.0; }   // 4K units across
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
        if theme == 1 {   // same lightness and saturation as cyan, hue ~140 degrees
            if Equals(set, "glow") { return new HDRColor(0.184, 1.0, 0.456, 1.0); }          // #2fff74
            if Equals(set, "outline") { return new HDRColor(0.227, 0.816, 0.424, 1.0); }     // #3ad06c
            if Equals(set, "road_minor") { return new HDRColor(0.165, 0.847, 0.392, 1.0); }  // #2ad864
            if Equals(set, "road_major") { return new HDRColor(0.561, 1.0, 0.707, 1.0); }    // #8fffb4
            return new HDRColor(0.184, 0.682, 0.350, 1.0);                                   // #2fae59 (bfill)
        }
        if Equals(set, "glow") { return new HDRColor(0.184, 0.612, 1.0, 1.0); }              // #2f9cff
        if Equals(set, "outline") { return new HDRColor(0.227, 0.561, 0.816, 1.0); }         // #3a8fd0
        if Equals(set, "road_minor") { return new HDRColor(0.165, 0.525, 0.847, 1.0); }      // #2a86d8
        if Equals(set, "road_major") { return new HDRColor(0.561, 0.863, 1.0, 1.0); }        // #8fdcff
        return new HDRColor(0.184, 0.435, 0.682, 1.0);                                       // #2f6fae (bfill; one tint for fill and dots)
    }
    public static func TileOpacity(set: String) -> Float {
        if Equals(set, "glow") { return 0.50; }
        if Equals(set, "bfill") { return 0.60; }
        if Equals(set, "outline") { return 0.40; }
        if Equals(set, "road_minor") { return 0.60; }
        if Equals(set, "road_major") { return 0.90; }
        return 1.0;
    }
}
