module NightMap

// Corner minimap: settings, layout, the corner view, modes.
public abstract class NMCornerTests {
    public static func Run(t: ref<NMSelfTest>) {
        NMCornerTests.Settings(t);
    }

    private static func Settings(t: ref<NMSelfTest>) {
        let s = new NightMapSettings();
        t.Check("corner.settings_defaults",
            !s.replaceMinimap && Equals(s.cornerStyle, NightMapCornerStyle.SquareStrip)
            && s.cornerScale == 1.0 && s.cornerMarkerSize == 1.0 && s.cornerTextSize == 1.0
            && s.cornerFrameThickness == 1.0 && s.cornerOpacity == 0.92
            && s.cornerEnemies && s.cornerPolice && s.expandedScale == 1.0 && !s.followHudPainter, "");
    }
}
