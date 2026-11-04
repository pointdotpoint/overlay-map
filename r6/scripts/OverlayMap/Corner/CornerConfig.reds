module OverlayMap

// The settings the corner is built from. A change to any of them rebuilds the corner (NMCornerConfig.Same).
public class NMCornerConfig {
    public let style: OverlayMapCornerStyle;
    public let scale: Float;
    public let markerSize: Float;
    public let textSize: Float;
    public let frame: Float;
    public let opacity: Float;
    public let enemies: Bool;
    public let police: Bool;
    public let theme: Int32;
    public let effects: Bool;
    public let hudPainter: Bool;

    public static func From(s: ref<OverlayMapSettings>) -> ref<NMCornerConfig> {
        let c = new NMCornerConfig();
        c.style = s.cornerStyle;
        c.scale = s.cornerScale;
        c.markerSize = s.cornerMarkerSize;
        c.textSize = s.cornerTextSize;
        c.frame = s.cornerFrameThickness;
        c.opacity = s.cornerOpacity;
        c.enemies = s.cornerEnemies;
        c.police = s.cornerPolice;
        c.theme = NMTheme.ThemeIndex(s.holoColor);
        c.effects = s.hologramEffects;
        c.hudPainter = s.followHudPainter;
        return c;
    }

    public func Same(o: ref<NMCornerConfig>) -> Bool {
        return IsDefined(o) && Equals(this.style, o.style) && this.scale == o.scale && this.markerSize == o.markerSize
            && this.textSize == o.textSize && this.frame == o.frame && this.opacity == o.opacity
            && Equals(this.enemies, o.enemies) && Equals(this.police, o.police) && this.theme == o.theme
            && Equals(this.effects, o.effects) && Equals(this.hudPainter, o.hudPainter);
    }
}
