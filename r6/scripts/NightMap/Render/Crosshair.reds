module NightMap

// Fixed reticle at the map-area center; selects the nearest candidate within SelectRadius.
public class NMCrosshair {
    public let sel: Int32;
    public let selKind: Int32;
    public let selLayer: Int32;
    public let selItem: Int32;
    public let selX: Float;
    public let selY: Float;

    public static func Create(parent: ref<inkCanvas>, viewW: Float, viewH: Float, scale: Float) -> ref<NMCrosshair> {
        let c = new NMCrosshair();
        c.sel = -1;
        c.selKind = -1;
        c.selLayer = -1;
        c.selItem = -1;
        let cx = viewW * 0.5;
        let cy = viewH * 0.5;
        NMUi.Image(parent, n"ring", cx, cy, NMTheme.RingSize() * scale, NMTheme.Cyan(), true);
        let a = 154.0 * scale;
        let len = 39.0 * scale;
        let w = 5.0 * scale;
        NMUi.Rect(parent, cx - a, cy - w * 0.5, len, w, NMTheme.Cyan(), 0.95);
        NMUi.Rect(parent, cx + a - len, cy - w * 0.5, len, w, NMTheme.Cyan(), 0.95);
        NMUi.Rect(parent, cx - w * 0.5, cy - a, w, len, NMTheme.Cyan(), 0.95);
        NMUi.Rect(parent, cx - w * 0.5, cy + a - len, w, len, NMTheme.Cyan(), 0.95);
        return c;
    }

    // Nearest candidate within radius; the previous selection is kept while it is within 4 units of the
    // nearest one (prevents flicker). Chips are identified by layer+item, clusters by their pyramid level + block (key in the item slot).
    public static func Pick(xs: array<Float>, ys: array<Float>, kinds: array<Int32>, layers: array<Int32>, items: array<Int32>,
                            cx: Float, cy: Float, radius: Float, prevKind: Int32, prevLayer: Int32, prevItem: Int32) -> Int32 {
        let r2 = radius * radius;
        let best = -1;
        let bestD = 0.0;
        let prev = -1;
        let prevD = 0.0;
        let i = 0;
        while i < ArraySize(xs) {
            let dx = xs[i] - cx;
            let dy = ys[i] - cy;
            let d = dx * dx + dy * dy;
            if d <= r2 {
                if best < 0 || d < bestD {
                    best = i;
                    bestD = d;
                }
                let same = false;
                if kinds[i] == prevKind {
                    same = layers[i] == prevLayer && items[i] == prevItem;
                }
                if same {
                    prev = i;
                    prevD = d;
                }
            }
            i += 1;
        }
        if prev >= 0 && SqrtF(prevD) <= SqrtF(bestD) + 4.0 {
            return prev;
        }
        return best;
    }

    // Forget the selection (layer indices changed) so the next Update re-picks and reports a change.
    public func Reset() {
        this.sel = -1;
        this.selKind = -1;
        this.selLayer = -1;
        this.selItem = -1;
    }

    public func Update(r: ref<NMItemRenderer>, viewW: Float, viewH: Float, scale: Float) -> Bool {
        let idx = NMCrosshair.Pick(r.candX, r.candY, r.candKind, r.candLayer, r.candItem, viewW * 0.5, viewH * 0.5,
            NMTheme.SelectRadius() * scale, this.selKind, this.selLayer, this.selItem);
        let kind = idx >= 0 ? r.candKind[idx] : -1;
        let layer = idx >= 0 ? r.candLayer[idx] : -1;
        let item = idx >= 0 ? r.candItem[idx] : -1;
        let x = idx >= 0 ? r.candX[idx] : 0.0;
        let y = idx >= 0 ? r.candY[idx] : 0.0;
        let changed = kind != this.selKind || layer != this.selLayer || item != this.selItem;
        this.sel = idx;
        this.selKind = kind;
        this.selLayer = layer;
        this.selItem = item;
        this.selX = x;
        this.selY = y;
        r.selChip.SetVisible(kind == 0);
        r.selCluster.SetVisible(kind == 1);
        if kind == 0 {
            r.selChip.SetTranslation(new Vector2(x, y));
        } else if kind == 1 {
            r.selCluster.SetTranslation(new Vector2(x, y));
        }
        return changed;
    }
}
