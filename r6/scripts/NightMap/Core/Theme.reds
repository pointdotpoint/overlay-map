module NightMap

// Visual tokens. Sizes are 3840x2160 HUD units and MUST match tools/tiles/nmtiles/ui_atlas.py SIZES.
public abstract class NMTheme {
    public static func Cyan() -> HDRColor { return new HDRColor(0.478, 0.941, 1.0, 1.0); }
    public static func Text() -> HDRColor { return new HDRColor(0.784, 0.965, 1.0, 1.0); }
    public static func Pink() -> HDRColor { return new HDRColor(1.0, 0.310, 0.847, 1.0); }
    public static func Yellow() -> HDRColor { return new HDRColor(1.0, 0.878, 0.400, 1.0); }
    public static func Muted() -> HDRColor { return new HDRColor(0.667, 0.863, 0.922, 1.0); }
    public static func PanelBg() -> HDRColor { return new HDRColor(0.024, 0.078, 0.118, 1.0); }
    public static func CardBg() -> HDRColor { return new HDRColor(0.039, 0.157, 0.216, 1.0); }
    public static func ZoomRatePerSecond() -> Float { return 4.0; }
    public static func CardOpacity() -> Float { return 0.5; }

    public static func HeadingFont() -> String { return "base\\gameplay\\gui\\fonts\\orbitron\\orbitron.inkfontfamily"; }
    public static func BodyFont() -> String { return "base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily"; }

    public static func UiAtlas() -> ResRef { return r"nightmap\\ui\\ui.inkatlas"; }

    public static func ChipSize() -> Float { return 112.0; }
    public static func ChipSelSize() -> Float { return 136.0; }
    public static func ClusterSize() -> Float { return 176.0; }
    public static func ClusterSelSize() -> Float { return 200.0; }
    public static func MiniSize() -> Float { return 80.0; }
    public static func IconSize() -> Float { return 48.0; }
    public static func RingSize() -> Float { return 216.0; }
    public static func PlayerSize() -> Float { return 112.0; }
    public static func BracketSize() -> Float { return 110.0; }
    public static func MiniOffsetY() -> Float { return -106.0; }
    public static func MiniSpacing() -> Float { return 67.0; }

    public static func HintHeight() -> Float { return 110.0; }
    public static func SelectRadius() -> Float { return 100.0; }
    public static func ClusterSpacing() -> Float { return 192.0; }
    public static func ChipBudget() -> Int32 { return 300; }
    public static func ClusterBudget() -> Int32 { return 80; }
    public static func MaxGlobalCategories() -> Int32 { return 64; }

    // 1.0 if ink rotates clockwise for positive angles; verified at Checkpoint 2.
    public static func PlayerRotationSign() -> Float { return 1.0; }

    // Vector layer (sub-project 1b). Style ids match tools/tiles nmtiles.vector_config.STYLES:
    // 0 land, 1 water, 2 block0, 3 block1, 4 block2, 5 road, 6 metro.
    public static func VecStyleCount() -> Int32 { return 7; }
    public static func VecPoolSize() -> Int32 { return 1000; }
    public static func VecPointBudget() -> Int32 { return 30000; }
    public static func VecShapeBudget() -> Int32 { return 900; }
    public static func VecHysteresis() -> Float { return 0.08; }
    public static func VecThicknessStep() -> Float { return 0.05; }
    public static func VecFailMs() -> Float { return 3000.0; }
    public static func VecIsBlock(style: Int32) -> Bool { return style >= 2 && style <= 4; }
    public static func VecVariant(style: Int32) -> inkEShapeVariant {
        if style == 6 { return inkEShapeVariant.Border; }
        return inkEShapeVariant.Fill;
    }
    public static func VecColor(style: Int32) -> HDRColor { return style == 6 ? NMTheme.Pink() : NMTheme.Cyan(); }
    public static func VecFillOpacity(style: Int32) -> Float {
        if style == 0 { return 0.05; }
        if style == 1 { return 0.16; }
        if style == 2 { return 0.14; }
        if style == 3 { return 0.19; }
        if style == 4 { return 0.24; }
        if style == 5 { return 0.22; }
        return 0.0;
    }
    public static func VecBorderOpacity(style: Int32) -> Float {
        if style == 6 { return 0.80; }
        return 0.0;
    }
    // Target stroke width in map (screen) units.
    public static func VecLineWidth(style: Int32, level: Int32) -> Float {
        if style == 6 { return 2.0; }
        if style == 5 { return level <= 2 ? 1.5 : 1.2; }
        if NMTheme.VecIsBlock(style) { return 1.0; }
        return 0.0;
    }
}
