module NightMap

// Selection state; picks the nearest candidate to the map-area centre within SelectRadius (no reticle is drawn).
public class NMCrosshair {
    public let sel: Int32;
    public let selKind: Int32;   // 0 an item, -1 nothing
    public let selLayer: Int32;
    public let selItem: Int32;
    public let selX: Float;
    public let selY: Float;

    public static func Create() -> ref<NMCrosshair> {
        let c = new NMCrosshair();
        c.sel = -1;
        c.selKind = -1;
        c.selLayer = -1;
        c.selItem = -1;
        return c;
    }

    // Nearest candidate within radius; the previous selection is kept while it is within 4 units of the
    // nearest one (prevents flicker). Candidates are items (kind 0), identified by layer + item.
    // reach[i], when present, widens the radius for that candidate: a big photo pin's centre sits far from its tip.
    public static func Pick(xs: array<Float>, ys: array<Float>, reach: array<Float>, kinds: array<Int32>, layers: array<Int32>, items: array<Int32>,
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
            let far = i < ArraySize(reach) ? radius + reach[i] : radius;
            if d <= far * far {
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

    // The focus point's X: the centre of the map area (mapW, the width the camera centres on) less shiftX. With the
    // sidebar's shift (NMPhotoDrawer.FocusShift) it is the middle of the view the renderer culls to (viewW / 2).
    public static func FocusX(mapW: Float, shiftX: Float) -> Float {
        return mapW * 0.5 - shiftX;
    }

    // mapW / mapH: the map area (not the view left of the sidebar). shiftX: the focus point sits this far left of the
    // map-area centre (the sidebar, spec 6.5).
    public func Update(r: ref<NMItemRenderer>, mapW: Float, mapH: Float, scale: Float, shiftX: Float) -> Bool {
        let idx = NMCrosshair.Pick(r.candX, r.candY, r.candReach, r.candKind, r.candLayer, r.candItem, NMCrosshair.FocusX(mapW, shiftX), mapH * 0.5,
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
        if kind == 0 {
            let k = r.CandScale(idx);   // the rim shrinks with the pin's tier scale
            r.selChip.SetTranslation(new Vector2(x, y));
            r.selChip.SetScale(new Vector2(k, k));
        }
        return changed;
    }
}
