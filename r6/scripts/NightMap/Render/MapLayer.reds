module NightMap

// A named, tintable map layer. The renderer is a stack of these (see NMLayerStack), drawn bottom to top.
// Colour is never baked into tiles: it is applied here with a tint colour and an opacity.
public class NMMapLayer {
    public func Name() -> String { return ""; }
    public func SetVisible(visible: Bool) {}
    public func SetTint(color: HDRColor, opacity: Float) {}
    public func Update(cam: ref<NMCamera>, dtMs: Float) {}
}

// Draw order, bottom to top. Only the first group lives in NMLayerStack; the rest are separate canvases in NMPanel.
//   1. Tile sets, in NMTileManifest.SetName order: road, bfill, outline.   (NMTileLayer, one per set)
//   2. [future] photos: the user's photo pins / imagery. Add one more NMMapLayer after the last tile set in
//      NMLayerStack.Create; a generic NMTileLayer bound to a new manifest set already does it.
//   3. Items and markers (NMPanel.items, drawn by NMItemRenderer). Never assumes live game pins only.
//   4. Overlay and widgets (NMPanel.overlay: crosshair, player marker, hints).
public class NMLayerStack {
    private let layers: array<ref<NMMapLayer>>;
    public let available: Bool;

    public static func Create(parent: ref<inkCanvas>) -> ref<NMLayerStack> {
        let st = new NMLayerStack();
        st.available = NMTileLayer.ArchiveAvailable();
        if st.available {
            let s = 0;
            while s < NMTileManifest.SetCount() {
                ArrayPush(st.layers, NMTileLayer.Create(parent, s));
                s += 1;
            }
        } else {
            ArrayPush(st.layers, NMGridLayer.Create(parent));
        }
        st.ApplyTheme();
        return st;
    }

    // Re-reads every layer's tint and opacity from NMTheme. Call after the theme changes.
    public func ApplyTheme() {
        for l in this.layers {
            l.SetTint(NMTheme.TileTint(l.Name()), NMTheme.TileOpacity(l.Name()));
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
        for l in this.layers {
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
