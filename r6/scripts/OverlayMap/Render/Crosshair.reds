module OverlayMap

// Selection state; picks the nearest candidate to the map-area centre within SelectRadius (no reticle is drawn).
public class NMCrosshair {
    public let sel: Int32;
    public let selKind: Int32;   // 0 an item, -1 nothing
    public let selLayer: Int32;
    public let selItem: Int32;
    public let selX: Float;
    public let selY: Float;
    private let chipX: Float;   // the selection rim's last translation and scale (set only on change)
    private let chipY: Float;
    private let chipK: Float;

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
        let n = ArraySize(xs);
        let nr = ArraySize(reach);
        while i < n {
            // Runs every frame of a pan over up to ChipBudget candidates: reject on one axis before the full distance.
            let far = i < nr ? radius + reach[i] : radius;
            let dx = xs[i] - cx;
            let dy = 0.0;
            let d = far * far + 1.0;   // outside unless both axes are within reach
            if dx <= far && dx >= -far {
                dy = ys[i] - cy;
                if dy <= far && dy >= -far {
                    d = dx * dx + dy * dy;
                }
            }
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
        // The candidates are in layout coordinates; the markers have slid r.offX/offY since (NMItemRenderer.Slide).
        let idx = NMCrosshair.Pick(r.candX, r.candY, r.candReach, r.candKind, r.candLayer, r.candItem, NMCrosshair.FocusX(mapW, shiftX) - r.offX, mapH * 0.5 - r.offY,
            NMTheme.SelectRadius() * scale, this.selKind, this.selLayer, this.selItem);
        let kind = idx >= 0 ? r.candKind[idx] : -1;
        let layer = idx >= 0 ? r.candLayer[idx] : -1;
        let item = idx >= 0 ? r.candItem[idx] : -1;
        let lx = idx >= 0 ? r.candX[idx] : 0.0;
        let ly = idx >= 0 ? r.candY[idx] : 0.0;
        let x = idx >= 0 ? lx + r.offX : 0.0;   // screen (map area) position, for the reticle and the card
        let y = idx >= 0 ? ly + r.offY : 0.0;
        let changed = kind != this.selKind || layer != this.selLayer || item != this.selItem;
        this.sel = idx;
        this.selKind = kind;
        this.selLayer = layer;
        this.selItem = item;
        this.selX = x;
        this.selY = y;
        // The rim lives in the sliding canvas: it only moves when the selection or a relayout moves it.
        if kind == 0 {
            let k = r.CandScale(idx);   // the rim shrinks with the pin's tier scale
            if lx != this.chipX || ly != this.chipY || k != this.chipK {
                r.selChip.SetTranslation(new Vector2(lx, ly));
                r.selChip.SetScale(new Vector2(k, k));
                this.chipX = lx;
                this.chipY = ly;
                this.chipK = k;
            }
        }
        r.selChip.SetVisible(kind == 0);   // every time: ApplySelection hides it again for icon markers
        return changed;
    }
}
