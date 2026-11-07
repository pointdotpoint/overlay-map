module OverlayMap

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

    // Keep equal to the OverlayMapSettings defaults.
    public static func Default() -> ref<NMHoloFx> { return NMHoloFx.Make(0.3, 1.5, true, true); }

    public static func From(s: ref<OverlayMapSettings>) -> ref<NMHoloFx> {
        if !IsDefined(s) {
            return NMHoloFx.Default();
        }
        return NMHoloFx.Make(s.scanlineStrength, s.glowStrength, s.vhsTracking, s.vhsGlitch);
    }

    // The glow tile layer's opacity at this gain (its base opacity is NMTheme.TileOpacity("glow")).
    public func GlowOpacity() -> Float {
        return ClampF(NMTheme.TileOpacity("glow") * this.glow, 0.0, 1.0);
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
    public static func LookName() -> CName { return n"nm_look"; }

    // Brightness is the engine's colour-correction multiplier around 1.0 (vanilla widgets use 0.7-5). Contrast is ours
    // (ContrastTint/ContrastBg): the engine's contrast is a per-channel curve that bent the cyan map to deep blue or
    // white in game. Keep these equal to the OverlayMapSettings slider ranges.
    public static func LookMin() -> Float { return 0.5; }
    public static func LookMax() -> Float { return 2.0; }
    public static func OpacityMin() -> Float { return 0.2; }

    // Contrast k: the map colours scaled by k and the map background by 1/k. Every channel scales alike, so the hue
    // and the theme colour stay; HDR tints above 1 still add light.
    public static func ContrastTint(c: HDRColor, k: Float) -> HDRColor {
        let f = ClampF(k, NMFx.LookMin(), NMFx.LookMax());
        return new HDRColor(c.Red * f, c.Green * f, c.Blue * f, c.Alpha);
    }

    public static func ContrastBg(c: HDRColor, k: Float) -> HDRColor {
        return NMFx.ContrastTint(c, 1.0 / ClampF(k, NMFx.LookMin(), NMFx.LookMax()));
    }

    public static func ApplyLook(tiles: ref<inkWidget>, root: ref<inkWidget>, brightness: Float, opacity: Float) {
        let b = ClampF(brightness, NMFx.LookMin(), NMFx.LookMax());
        if IsDefined(root) {
            root.SetOpacity(ClampF(opacity, NMFx.OpacityMin(), 1.0));
        }
        if !IsDefined(tiles) {
            return;
        }
        let neutral = AbsF(b - 1.0) < 0.001;
        let i = 0;
        while i < ArraySize(tiles.effects) {
            let e = tiles.effects[i] as inkColorCorrectionEffect;
            if IsDefined(e) && Equals(e.effectName, NMFx.LookName()) {
                e.brightness = b;
                e.isEnabled = !neutral;
                tiles.SetEffectEnabled(inkEffectType.ColorCorrection, NMFx.LookName(), !neutral);
                return;
            }
            i += 1;
        }
        if neutral {
            return;
        }
        let cc = new inkColorCorrectionEffect();
        cc.effectName = NMFx.LookName();
        cc.isEnabled = true;
        cc.brightness = b;
        cc.contrast = 1.0;
        cc.saturation = 1.0;
        NMFx.Push(tiles, cc);
        tiles.SetEffectEnabled(inkEffectType.ColorCorrection, NMFx.LookName(), true);
    }

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
