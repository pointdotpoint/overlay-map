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
}
