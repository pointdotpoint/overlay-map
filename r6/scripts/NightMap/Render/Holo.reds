module NightMap

// Hologram overlays for the map panel: static tinted images from holo.inkatlas plus a few engine-driven animation loops.
//
// Cost model: every widget is created once and tinted once. The animations are inkAnimDef + PlayAnimationWithOptions
// with an infinite Cycle loop, started once when the panel opens; the engine runs them, no script runs per frame (no
// Tick, no SetOpacity / SetTranslation loops). Nothing animates while the map is closed: the panel is destroyed on close
// and Stop() ends the loops first. With effects off no widget exists and no animation is started.
//
// Stack inside the clipped map content, bottom to top (the panel inserts them between its own canvases):
//   grid (under the tile layers) | tiles: glow, road, bfill, outline | scanlines, noise | items | scan bar | overlay
// The edge glow sits on the panel root, under the corner brackets.
public class NMHolo {
    public let effects: Bool;
    public let green: Bool;
    public let grid: ref<inkImage>;
    public let scan: ref<inkImage>;
    public let noise: ref<inkImage>;
    public let bar: ref<inkImage>;
    public let edges: array<ref<inkImage>>;
    private let proxies: array<ref<inkAnimProxy>>;
    private let mapW: Float;
    private let mapH: Float;
    private let scale: Float;

    public static func Create(effects: Bool, green: Bool, mapW: Float, mapH: Float, scale: Float) -> ref<NMHolo> {
        let h = new NMHolo();
        h.effects = effects;
        h.green = green;
        h.mapW = mapW;
        h.mapH = mapH;
        h.scale = scale;
        return h;
    }

    // One period of the scanline texture (a tiled part repeats at its native size, so no scale term); the scanline loop translates by exactly this much.
    public func ScanPeriod() -> Float { return NMTheme.ScanPeriod(); }
    public func BarHeight() -> Float { return this.mapH * 0.14; }
    public func ProxyCount() -> Int32 { return ArraySize(this.proxies); }

    public func AddGrid(parent: wref<inkCompoundWidget>) {
        if !this.effects {
            return;
        }
        this.grid = NMUi.HoloImage(parent, n"holo_grid", 0.0, 0.0, this.mapW, this.mapH, NMTheme.HoloAccent(this.green), NMTheme.HoloGridOpacity(), inkBrushTileType.Both);
    }

    // Scanlines (black) and noise (accent), over the tiles, under the markers. The scanline image is one period taller
    // than the map and starts one period up, so the looped translation by one period is seamless.
    public func AddScan(parent: wref<inkCompoundWidget>) {
        if !this.effects {
            return;
        }
        let p = this.ScanPeriod();
        this.scan = NMUi.HoloImage(parent, n"holo_scan", 0.0, 0.0 - p, this.mapW, this.mapH + p, NMTheme.HoloScanColor(), NMTheme.HoloScanOpacity(), inkBrushTileType.Both);
        this.noise = NMUi.HoloImage(parent, n"holo_noise", 0.0, 0.0, this.mapW, this.mapH, NMTheme.HoloAccent(this.green), NMTheme.HoloNoiseOpacity(), inkBrushTileType.Both);
    }

    // Starts invisible above the map; its loop fades it in while it sweeps down.
    public func AddBar(parent: wref<inkCompoundWidget>) {
        if !this.effects {
            return;
        }
        this.bar = NMUi.HoloImage(parent, n"holo_bar", 0.0, 0.0 - this.BarHeight(), this.mapW, this.BarHeight(), NMTheme.HoloAccent(this.green), 0.0, inkBrushTileType.NoTile);
    }

    // Soft glowing line along the inside of the frame: four stretched strips, bright on the frame side.
    public func AddEdges(parent: wref<inkCompoundWidget>, w: Float, h: Float) {
        if !this.effects {
            return;
        }
        let t = 40.0 * this.scale;
        let c = NMTheme.HoloAccent(this.green);
        let o = NMTheme.HoloEdgeOpacity();
        ArrayPush(this.edges, NMUi.HoloImage(parent, n"holo_edge_t", 0.0, 0.0, w, t, c, o, inkBrushTileType.NoTile));
        ArrayPush(this.edges, NMUi.HoloImage(parent, n"holo_edge_b", 0.0, h - t, w, t, c, o, inkBrushTileType.NoTile));
        ArrayPush(this.edges, NMUi.HoloImage(parent, n"holo_edge_l", 0.0, t, t, h - 2.0 * t, c, o, inkBrushTileType.NoTile));
        ArrayPush(this.edges, NMUi.HoloImage(parent, n"holo_edge_r", w - t, t, t, h - 2.0 * t, c, o, inkBrushTileType.NoTile));
    }

    public static func Fade(from: Float, to: Float, delay: Float, dur: Float) -> ref<inkAnimTransparency> {
        let a = new inkAnimTransparency();
        a.SetStartTransparency(from);
        a.SetEndTransparency(to);
        a.SetStartDelay(delay);
        a.SetDuration(dur);
        a.SetType(inkanimInterpolationType.Linear);
        a.SetDirection(inkanimInterpolationDirection.FromTo);
        return a;
    }

    public static func Move(x0: Float, y0: Float, x1: Float, y1: Float, delay: Float, dur: Float) -> ref<inkAnimTranslation> {
        let a = new inkAnimTranslation();
        a.SetStartTranslation(new Vector2(x0, y0));
        a.SetEndTranslation(new Vector2(x1, y1));
        a.SetStartDelay(delay);
        a.SetDuration(dur);
        a.SetType(inkanimInterpolationType.Linear);
        a.SetDirection(inkanimInterpolationDirection.FromTo);
        return a;
    }

    private func Loop(target: ref<inkWidget>, def: ref<inkAnimDef>) {
        let o: inkAnimOptions;
        o.loopType = inkanimLoopType.Cycle;
        o.loopInfinite = true;
        ArrayPush(this.proxies, target.PlayAnimationWithOptions(def, o));
    }

    // Starts every loop once. content is the clipped map content canvas (the whole-map dip runs on it).
    // The loop length is the end of the latest interpolator, so a short no-op fade pads the quiet part of a cycle.
    public func Play(content: ref<inkCanvas>) {
        if !this.effects {
            return;
        }
        // Scanlines: down by exactly one period over 2 s, forever (seamless).
        if IsDefined(this.scan) {
            let dScan = new inkAnimDef();
            dScan.AddInterpolator(NMHolo.Move(0.0, 0.0 - this.ScanPeriod(), 0.0, 0.0, 0.0, 2.0));
            this.Loop(this.scan, dScan);
        }
        // Scan bar: sweep top to bottom over 2.5 s with a fade at both ends, invisible for the rest of a 6 s cycle.
        if IsDefined(this.bar) {
            let a = NMTheme.HoloBarOpacity();
            let dBar = new inkAnimDef();
            dBar.AddInterpolator(NMHolo.Move(0.0, 0.0 - this.BarHeight(), 0.0, this.mapH, 0.0, 2.5));
            dBar.AddInterpolator(NMHolo.Fade(0.0, a, 0.0, 0.3));
            dBar.AddInterpolator(NMHolo.Fade(a, 0.0, 2.2, 0.3));
            dBar.AddInterpolator(NMHolo.Fade(0.0, 0.0, 5.9, 0.1));
            this.Loop(this.bar, dBar);
        }
        // Noise flicker: hard steps between 0.08 and 0.14, five per second.
        if IsDefined(this.noise) {
            let steps: array<Float> = [0.12, 0.08, 0.14, 0.10, 0.13, 0.09];
            let dNoise = new inkAnimDef();
            let i = 0;
            while i < ArraySize(steps) {
                dNoise.AddInterpolator(NMHolo.Fade(steps[i], steps[i], Cast<Float>(i) * 0.2, 0.2));
                i += 1;
            }
            this.Loop(this.noise, dNoise);
        }
        // Dip: the whole map content 1 -> 0.86 -> 1 over 0.12 s, once per ~7 s (a long hold, then the dip).
        if IsDefined(content) {
            let dDip = new inkAnimDef();
            dDip.AddInterpolator(NMHolo.Fade(1.0, 0.86, 7.0, 0.06));
            dDip.AddInterpolator(NMHolo.Fade(0.86, 1.0, 7.06, 0.06));
            this.Loop(content, dDip);
        }
    }

    public func Stop() {
        for p in this.proxies {
            if IsDefined(p) {
                p.Stop();
            }
        }
        ArrayClear(this.proxies);
    }
}
