module NightMap

// Zoom behaviour per marker tier: markers shrink with the map to a minimum, then fade out by tier.
public abstract class NMTiers {
    private static func Ramp(mpp: Float, lo: Float, hi: Float) -> Float {
        return mpp <= lo ? 1.0 : (mpp >= hi ? 0.0 : (hi - mpp) / (hi - lo));
    }

    // 1 -> 0 as the map zooms out. Always never hides; Major hides beyond the zoom range for now.
    public static func Fade(tier: Int32, mpp: Float) -> Float {
        if tier <= 0 { return 1.0; }
        if tier == 1 { return NMTiers.Ramp(mpp, 24.0, 32.0); }
        return NMTiers.Ramp(mpp, 4.0, 6.0);
    }

    // 1.0 at mpp <= 2, linear in log2(mpp) down to 0.7 at mpp >= 8. Always-tier markers keep full size.
    public static func Scale(tier: Int32, mpp: Float) -> Float {
        if tier <= 0 || mpp <= 2.0 { return 1.0; }
        if mpp >= 8.0 { return 0.7; }
        return 1.0 - 0.3 * ((LogF(mpp) / LogF(2.0)) - 1.0) / 2.0;
    }
}
