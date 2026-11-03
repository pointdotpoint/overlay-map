module NightMap

// A named, tintable map layer. The renderer is a stack of these (see NMLayerStack), drawn bottom to top.
// Colour is never baked into tiles: it is applied here with a tint colour and an opacity.
public class NMMapLayer {
    public func Name() -> String { return ""; }
    public func SetVisible(visible: Bool) {}
    public func SetTint(color: HDRColor, opacity: Float) {}
    public func Opacity() -> Float { return 0.0; }
    public func Root() -> ref<inkCanvas> { return null; }   // the layer's own container, for effects
    public func Update(cam: ref<NMCamera>, dtMs: Float) {}
}

// Draw order, bottom to top. Only the first group lives in NMLayerStack; the rest are separate canvases in NMPanel.
//   0. [effects on] hologram grid, under everything (NMHolo; a tiled image in NMPanel.mapContent).
//   1. Tile sets, in NMTileManifest.SetName order: glow, road, bfill, outline.   (NMTileLayer, one per set; glow is
//      drawn from a level NMTheme.GlowLevelOffset() coarser than the camera's, and is not created with effects off)
//      then [effects on] scanlines and noise (NMHolo), still under the markers.
//   2. [future] photos: the user's photo pins / imagery. Add one more NMMapLayer after the last tile set in
//      NMLayerStack.Create; a generic NMTileLayer bound to a new manifest set already does it.
//   2b. GPS routes (NMPanel.routes, drawn by NMRouteLayer): the minimap's waypoint and quest routes, under the markers.
//   3. Items and markers (NMPanel.items, drawn by NMItemRenderer). Never assumes live game pins only.
//   4. Overlay and widgets (NMPanel.overlay: player marker, tooltip).
public class NMLayerStack {
    private let layers: array<ref<NMMapLayer>>;
    public let available: Bool;
    private let theme: Int32;
    private let bloomed: Bool;
    private let fx: ref<NMHoloFx>;   // unset: the glow layer keeps NMTheme.TileOpacity("glow")

    // Does a set get a layer? The glow set only exists while the hologram effects are on.
    public static func WantsSet(name: String, effects: Bool) -> Bool {
        return effects || NotEquals(name, "glow");
    }

    public static func SetOffset(name: String) -> Int32 {
        return Equals(name, "glow") ? NMTheme.GlowLevelOffset() : 0;
    }

    public static func Create(parent: ref<inkCanvas>, theme: Int32, effects: Bool) -> ref<NMLayerStack> {
        let st = new NMLayerStack();
        st.available = NMTileLayer.ArchiveAvailable();
        if st.available {
            let s = 0;
            while s < NMTileManifest.SetCount() {
                let name = NMTileManifest.SetName(s);
                if NMLayerStack.WantsSet(name, effects) {
                    ArrayPush(st.layers, NMTileLayer.Create(parent, s, NMLayerStack.SetOffset(name)));
                }
                s += 1;
            }
        } else {
            ArrayPush(st.layers, NMGridLayer.Create(parent));
        }
        st.ApplyTheme(theme);
        return st;
    }

    public func LayerCount() -> Int32 { return ArraySize(this.layers); }

    // Re-reads every layer's tint and opacity from NMTheme. Call after the theme changes.
    public func ApplyTheme(theme: Int32) {
        this.theme = theme;
        for l in this.layers {
            let op = NMTheme.TileOpacity(l.Name());
            let tint = NMTheme.TileTint(l.Name(), theme);
            if Equals(l.Name(), "glow") && IsDefined(this.fx) {
                op = this.fx.GlowOpacity();
                let k = this.fx.GlowBoost();
                tint = new HDRColor(tint.Red * k, tint.Green * k, tint.Blue * k, tint.Alpha);
            }
            l.SetTint(tint, op);
        }
    }

    // The glow knobs: the glow layer's opacity follows the gain (Glow strength); 0 hides it.
    // The glow layer is also blurred (an engine box blur on its container), so bright roads bloom instead of
    // showing the coarse tiles' edges.
    public func SetGlow(fx: ref<NMHoloFx>) {
        this.fx = fx;
        this.ApplyTheme(this.theme);
        let g = this.Layer("glow");
        if !this.bloomed && IsDefined(fx) && fx.glow > 0.001 && IsDefined(g) && IsDefined(g.Root()) {
            let root = g.Root();
            NMFx.AddBlur2D(root, fx.BloomIntensity(), NMTheme.BloomSamples());
            root.SetEffectEnabled(inkEffectType.BoxBlur, NMFx.BlurName(inkEBlurDimension.Horizontal), true);
            root.SetEffectEnabled(inkEffectType.BoxBlur, NMFx.BlurName(inkEBlurDimension.Vertical), true);
            this.bloomed = true;
        }
        if this.bloomed && IsDefined(fx) && IsDefined(g) && IsDefined(g.Root()) {
            g.Root().SetEffectParamValue(inkEffectType.BoxBlur, NMFx.BlurName(inkEBlurDimension.Horizontal), n"intensity", fx.BloomIntensity());
            g.Root().SetEffectParamValue(inkEffectType.BoxBlur, NMFx.BlurName(inkEBlurDimension.Vertical), n"intensity", fx.BloomIntensity());
        }
    }

    public func Layer(name: String) -> ref<NMMapLayer> {
        for l in this.layers {
            if Equals(l.Name(), name) {
                return l;
            }
        }
        return null;
    }

    public func Update(cam: ref<NMCamera>, dtMs: Float) {
        // The tile sets cross a level together: one that fades in early shows as a seam against the others.
        let held = false;
        for l in this.layers {
            let t = l as NMTileLayer;
            if IsDefined(t) && t.WaitingOnCurrent() { held = true; }
        }
        for l in this.layers {
            let t = l as NMTileLayer;
            if IsDefined(t) { t.holdFade = held; }
            l.Update(cam, dtMs);
        }
    }
}

// Fallback without the archive: a plain 1 km / 2 km grid.
public class NMGridLayer extends NMMapLayer {
    private let box: ref<inkCanvas>;
    private let grid: array<ref<inkRectangle>>;
    private let lastRev: Int32;

    public static func Create(parent: ref<inkCanvas>) -> ref<NMGridLayer> {
        let t = new NMGridLayer();
        t.lastRev = -1;
        t.box = NMTileLayer.MakeContainer(parent);
        let g = 0;
        while g < 48 {
            let r = new inkRectangle();
            r.SetAnchor(inkEAnchor.TopLeft);
            r.SetTintColor(NMTheme.Cyan());
            r.SetOpacity(0.18);
            r.SetVisible(false);
            r.SetInteractive(false);
            r.Reparent(t.box);
            ArrayPush(t.grid, r);
            g += 1;
        }
        return t;
    }

    public func Name() -> String { return "grid"; }

    public func SetVisible(visible: Bool) {
        this.box.SetVisible(visible);
    }

    public func Update(cam: ref<NMCamera>, dtMs: Float) {
        if cam.revision == this.lastRev {
            return;
        }
        this.lastRev = cam.revision;
        let vis = cam.VisibleRect(0.0);
        let step = cam.mpp > 6.0 ? 2000.0 : 1000.0;
        let used = 0;
        let x = Cast<Float>(FloorF(vis.minX / step) + 1) * step;
        while x <= vis.maxX && used < ArraySize(this.grid) {
            let p = cam.WorldToMap(x, vis.maxY);
            let r = this.grid[used];
            r.SetTranslation(new Vector2(p.X, 0.0));
            r.SetSize(new Vector2(2.0, cam.viewH));
            r.SetVisible(true);
            used += 1;
            x += step;
        }
        let y = Cast<Float>(FloorF(vis.minY / step) + 1) * step;
        while y <= vis.maxY && used < ArraySize(this.grid) {
            let p = cam.WorldToMap(vis.minX, y);
            let r = this.grid[used];
            r.SetTranslation(new Vector2(0.0, p.Y));
            r.SetSize(new Vector2(cam.viewW, 2.0));
            r.SetVisible(true);
            used += 1;
            y += step;
        }
        while used < ArraySize(this.grid) {
            this.grid[used].SetVisible(false);
            used += 1;
        }
    }
}
