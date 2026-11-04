module NightMap

// The VHS knobs from Mod Settings, read once per open. All of them only apply while "Hologram effects" is on.
public class NMHoloFx {
    public let scan: Float;       // scanline opacity (0 = no scanline widget)
    public let glow: Float;       // glow gain: multiplies the glow tile layer's opacity (0 = no glow)
    public let tracking: Bool;    // VHS tracking band
    public let glitch: Bool;      // VHS glitch bursts

    public static func Make(scan: Float, glow: Float, tracking: Bool, glitch: Bool) -> ref<NMHoloFx> {
        let f = new NMHoloFx();
        f.scan = ClampF(scan, 0.0, 0.6);   // the sliders' ranges
        f.glow = ClampF(glow, 0.0, 3.0);
        f.tracking = tracking;
        f.glitch = glitch;
        return f;
    }

    // Keep equal to the NightMapSettings defaults.
    public static func Default() -> ref<NMHoloFx> { return NMHoloFx.Make(0.3, 1.5, true, true); }

    public static func From(s: ref<NightMapSettings>) -> ref<NMHoloFx> {
        if !IsDefined(s) {
            return NMHoloFx.Default();
        }
        return NMHoloFx.Make(s.scanlineStrength, s.glowStrength, s.vhsTracking, s.vhsGlitch);
    }

    // The glow tile layer's opacity at this gain (its base opacity is NMTheme.TileOpacity("glow")).
    public func GlowOpacity() -> Float {
        return ClampF(NMTheme.TileOpacity("glow") * this.glow, 0.0, 1.0);
    }

    // Box blur intensity on the glow layer. Fixed at every gain: the engine blur's sample spacing grows with its
    // intensity, so widening it with the gain stamped shifted copies of the road network across the whole map.
    public func BloomIntensity() -> Float {
        return NMTheme.BloomIntensity();
    }

    // Does the map get a glow layer? Glow strength is its own switch (0 = off), independent of Hologram effects.
    public func WantsGlow() -> Bool {
        return this.glow > 0.001;
    }

    // Multiplier on the glow tint's RGB. Opacity tops out at gain 2, so above gain 1 the colour itself goes past 1
    // (HDR) to keep adding light up to the top of the slider.
    public func GlowBoost() -> Float {
        return MaxF(1.0, this.glow);
    }
}

// Engine UI effects attached from script. Vanilla only toggles effects authored in .inkwidget files; Codeware exposes
// inkWidget.effects, so a script can push an inkIEffect onto its own widget and the renderer applies it (GPU, no
// script per frame). Parameters are animated with inkAnimEffect, so pulses run on the engine like the other holo loops.
public abstract class NMFx {
    public static func BlurName(dim: inkEBlurDimension) -> CName {
        return Equals(dim, inkEBlurDimension.Horizontal) ? n"nm_blur_h" : n"nm_blur_v";
    }
    public static func GlitchName() -> CName { return n"nm_glitch"; }

    // One box blur pass along one axis; a soft 2D blur is a horizontal and a vertical pass.
    public static func AddBlur(w: ref<inkWidget>, dim: inkEBlurDimension, intensity: Float, samples: Int32) -> ref<inkBoxBlurEffect> {
        let e = new inkBoxBlurEffect();
        e.effectName = NMFx.BlurName(dim);
        e.isEnabled = true;
        e.intensity = intensity;
        e.samples = Cast<Uint8>(Max(1, Min(samples, 255)));
        e.blurDimension = dim;
        NMFx.Push(w, e);
        return e;
    }

    public static func AddBlur2D(w: ref<inkWidget>, intensity: Float, samples: Int32) {
        NMFx.AddBlur(w, inkEBlurDimension.Horizontal, intensity, samples);
        NMFx.AddBlur(w, inkEBlurDimension.Vertical, intensity, samples);
    }

    // Starts at intensity 0 (invisible); a loop raises it in short bursts. sizeX/sizeY: the glitched area in pixels
    // (vanilla authors the widget's own size).
    public static func AddGlitch(w: ref<inkWidget>, sizeX: Float, sizeY: Float) -> ref<inkGlitchEffect> {
        let e = new inkGlitchEffect();
        e.effectName = NMFx.GlitchName();
        e.isEnabled = true;
        e.intensity = 0.0;
        e.offsetX = 0.0;
        e.offsetY = 0.0;
        e.sizeX = sizeX;
        e.sizeY = sizeY;
        NMFx.Push(w, e);
        return e;
    }

    public static func EffectCount(w: ref<inkWidget>) -> Int32 {
        return IsDefined(w) ? ArraySize(w.effects) : 0;
    }

    // An inkAnimEffect step on one parameter of a named effect.
    public static func Param(kind: inkEffectType, name: CName, param: CName, from: Float, to: Float, delay: Float, dur: Float) -> ref<inkAnimEffect> {
        let a = new inkAnimEffect();
        a.SetEffectType(kind);
        a.SetEffectName(name);
        a.SetParamName(param);
        a.SetStartValue(from);
        a.SetEndValue(to);
        a.SetStartDelay(delay);
        a.SetDuration(dur);
        a.SetType(inkanimInterpolationType.Linear);
        a.SetDirection(inkanimInterpolationDirection.FromTo);
        return a;
    }

    private static func Push(w: ref<inkWidget>, e: ref<inkIEffect>) {
        if !IsDefined(w) {
            return;
        }
        let list = w.effects;
        ArrayPush(list, e);
        w.effects = list;
    }
}
