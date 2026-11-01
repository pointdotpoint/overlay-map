module NightMap

// Callback target for one by-hash screenshot load into a thumbnail cache image.
public class NMThumbListener extends IScriptable {
    public let r: wref<NMItemRenderer>;
    public let hash: Uint32;

    protected cb func OnLoaded(size: Vector2, err: Int32) -> Bool {
        if IsDefined(this.r) {
            this.r.OnThumb(this.hash, size, err);
        }
        return true;
    }
}

public class NMIconRef {
    public let atlas: ResRef;
    public let part: CName;
    public let key: String;   // identifies the atlas (not the part)
    public let pending: Bool;
}

// Draws every visible layer as individual pins through a fixed widget pool (ChipBudget slots), culled to the view.
// No clustering: each layer's tier (NMTiers, spec 2026-11-01 section 7) scales its pins down and fades them out as
// the map zooms out; a fully faded layer is skipped whole. Small layers are scanned item by item, larger ones cell by
// cell nearest-first, so the budget keeps the pins around the view centre.
// Relayout happens only when the camera or the API revision changed.
public class NMItemRenderer {
    private let api: wref<NightMap>;
    private let scale: Float;
    public let chipBg: array<ref<inkImage>>;
    public let chipIcon: array<ref<inkImage>>;
    private let chipOn: array<Bool>;
    private let chipIconKey: array<String>;   // atlas identity last set on the slot
    private let chipIconPart: array<CName>;
    private let chipTintOk: array<Bool>;
    private let chipTintBg: array<HDRColor>;
    private let chipTintIc: array<HDRColor>;
    public let chipAlpha: array<Float>;
    public let chipStyle: array<Int32>;   // -1 unset, 0 hex, 1 icon idle, 2 icon emphasised, 3 photo pin, 4 dot
    // Photo pins (style 3): a thumbnail in the slot's icon image, plus rectangles created on the slot's first photo:
    // a dark fill shown until the thumbnail loads, a 4-sided border, and a 45-degree point touching the spot.
    private let parent: wref<inkCanvas>;
    private let photoFill: array<ref<inkRectangle>>;
    private let photoEdge: array<ref<inkRectangle>>;   // [slot * 4 + side]
    private let photoPtr: array<ref<inkRectangle>>;
    private let photoOn: array<Bool>;
    // A scratch over a struck item's icon, created on the slot's first struck item.
    public let chipStrike: array<ref<inkImage>>;
    public let strikeOn: array<Bool>;
    // Thumbnails are held by shot hash in NMThumbPlan slots, each with its own image (never a chip's icon).
    private let thumbPlan: ref<NMThumbPlan>;
    private let thumbImg: array<ref<inkImage>>;
    private let thumbLoading: ref<NMThumbListener>;
    private let photoSel: Int32;
    private let thumbZoom: Float = 1.0;
    private let photoColor: array<HDRColor>;
    private let shotHandler: wref<inkISystemRequestsHandler>;
    public let growSlot: Int32;           // slot currently growing/grown for the selection (icon idle pins), -1 none
    public let growT: Float;              // 0..1 progress of the selection grow
    private let growLayer: Int32;
    private let growItem: Int32;
    private let chipK: array<Float>;      // tier scale on the slot's widgets; the selection grow multiplies it
    private let curFade: Float;           // tier fade and scale of the layer being placed (once per layer per relayout)
    private let curScale: Float;
    public let selChip: ref<inkImage>;
    public let candX: array<Float>;
    public let candY: array<Float>;
    public let candReach: array<Float>;  // extra selection radius, parallel to the other cand arrays
    public let candKind: array<Int32>;   // always 0 (an item); kept for NMCrosshair's identity check
    public let candLayer: array<Int32>;
    public let candItem: array<Int32>;
    public let candSlot: array<Int32>;
    // Level-0 cell range of this relayout, its (clamped) centre cell, and the ring order over it (built on first use).
    private let indRg: array<Int32>;
    private let ringCx: Int32;
    private let ringCy: Int32;
    private let ringBuilt: Bool;
    private let ordX: array<Int32>;
    private let ordY: array<Int32>;
    // Sparse layers: their occupied in-range cells, bucketed by ring (scratch).
    private let sCell: array<Int32>;
    private let sRing: array<Int32>;
    private let sStart: array<Int32>;
    private let sOrd: array<Int32>;
    private let halo: Bool;       // effects on: icon pins get a soft halo in their own colour instead of the dark shadow blob
    public let forceScan: Bool;   // test hook: bypass the occupied-cell lists (reference behaviour: the full ring scan)
    private let icon: ref<NMIconRef>;
    private let lastCamRev: Int32;
    private let lastApiRev: Int32;
    public let chipsUsed: Int32;
    public let pendingImages: Int32;
    public let relayouts: Int32;

    public static func Create(api: ref<NightMap>, parent: ref<inkCanvas>, scale: Float) -> ref<NMItemRenderer> {
        let r = new NMItemRenderer();
        r.api = api;
        r.scale = scale;
        r.icon = new NMIconRef();
        r.lastCamRev = -1;
        r.lastApiRev = -1;
        r.parent = parent;
        r.photoSel = -1;
        r.curFade = 1.0;
        r.curScale = 1.0;
        // z-order (back to front): selected-chip rim, chips
        r.selChip = NMUi.Image(parent, n"chip_sel", 0.0, 0.0, NMTheme.ChipSelSize() * scale, NMTheme.Cyan(), true);
        r.selChip.SetVisible(false);
        let i = 0;
        while i < NMTheme.ChipBudget() {
            let bg = NMUi.Image(parent, n"chip", 0.0, 0.0, NMTheme.ChipSize() * scale, NMTheme.Cyan(), true);
            let ic = NMUi.Image(parent, n"icon_dot", 0.0, 0.0, NMTheme.IconSize() * scale, NMTheme.Cyan(), true);
            bg.SetVisible(false);
            ic.SetVisible(false);
            ArrayPush(r.chipBg, bg);
            ArrayPush(r.chipIcon, ic);
            ArrayPush(r.chipOn, false);
            ArrayPush(r.chipIconKey, "");
            ArrayPush(r.chipIconPart, n"");
            ArrayPush(r.chipTintOk, false);
            ArrayPush(r.chipTintBg, NMTheme.Cyan());
            ArrayPush(r.chipTintIc, NMTheme.Cyan());
            ArrayPush(r.chipAlpha, 1.0);
            ArrayPush(r.chipStyle, -1);
            ArrayPush(r.chipK, 1.0);
            ArrayPush(r.photoFill, null);
            ArrayPush(r.photoPtr, null);
            ArrayPush(r.photoOn, false);
            ArrayPush(r.chipStrike, null);
            ArrayPush(r.strikeOn, false);
            ArrayPush(r.photoColor, NMTheme.Cyan());
            let e = 0;
            while e < 4 { ArrayPush(r.photoEdge, null); e += 1; }
            i += 1;
        }
        r.growSlot = -1;
        r.growLayer = -1;
        r.growItem = -1;
        r.thumbPlan = NMThumbPlan.Create(NMPhotos.ThumbCap());
        i = 0;
        while i < NMPhotos.ThumbCap() {
            let im = new inkImage();
            im.SetAnchor(inkEAnchor.TopLeft);
            im.SetAnchorPoint(new Vector2(0.5, 0.5));
            im.SetSize(new Vector2(NMItemRenderer.ThumbW() * scale, NMItemRenderer.ThumbH() * scale));
            im.SetInteractive(false);
            im.SetVisible(false);
            im.Reparent(parent);
            ArrayPush(r.thumbImg, im);
            i += 1;
        }
        return r;
    }

    // The request handler photo thumbnails load through (NMPhotos.Handler()); set on map open.
    public func SetShotHandler(h: wref<inkISystemRequestsHandler>) { this.shotHandler = h; }

    // Identity of an item's icon for the pooled-widget change check: "shot:<hash>" for photo items.
    public static func IconKeyFor(L: ref<NightMapLayer>, id: Int32) -> String {
        if id >= 0 && id < ArraySize(L.shot) && L.shot[id] != 0u {
            return "shot:" + ToString(L.shot[id]);
        }
        return id >= 0 && id < ArraySize(L.atlasKey) ? L.atlasKey[id] : "";
    }

    // How much bigger a photo pin's picture is at this zoom: 1 down to the finest tiles, then with the zoom.
    public static func ThumbZoom(mpp: Float) -> Float {
        return MaxF(0.5 / MaxF(mpp, 0.0001), 1.0);
    }

    public static func ThumbW() -> Float { return 108.0; }   // 16:9, 4K units (about 54x31 px at 1080p)
    public static func ThumbH() -> Float { return 61.5; }
    public static func PhotoEdge() -> Float { return 4.5; }
    public static func PhotoPtr() -> Float { return 21.0; }

    public func OnThumb(hash: Uint32, size: Vector2, err: Int32) {
        this.thumbLoading = null;
        this.thumbPlan.Loaded(hash, size.X > 0.0 && err == 0);
        this.lastCamRev = -1;   // relayout: show it, and start the next load
    }

    // After a layout: hide thumbnails no pin used, then start the next wanted load (one at a time).
    private func FinishThumbs() {
        let p = this.thumbPlan;
        p.EndLayout();
        let i = 0;
        while i < p.Cap() {
            if !p.IsUsed(i) || !p.IsReady(i) {
                this.thumbImg[i].SetVisible(false);
            }
            i += 1;
        }
        if !IsDefined(this.shotHandler) || IsDefined(this.thumbLoading) {
            return;
        }
        let tries = 0;
        while tries < p.Cap() {
            let h = p.NextRequest();
            if h == 0u { return; }
            let lst = new NMThumbListener();
            lst.r = this;
            lst.hash = h;
            let img = this.thumbImg[p.SlotOf(h)];
            img.SetVisible(false);
            if this.shotHandler.RequestGameScreenshotByHash(h, img, lst, n"OnLoaded") {
                this.thumbLoading = lst;
                return;
            }
            p.Loaded(h, false);
            tries += 1;
        }
    }

    private func EnsurePhotoWidgets(slot: Int32) {
        if IsDefined(this.photoFill[slot]) { return; }
        let fill = NMUi.Rect(this.parent, 0.0, 0.0, NMItemRenderer.ThumbW() * this.scale, NMItemRenderer.ThumbH() * this.scale, NMTheme.PanelBg(), 0.85);
        fill.SetAnchorPoint(new Vector2(0.5, 0.5));
        fill.SetVisible(false);
        this.photoFill[slot] = fill;
        let e = 0;
        while e < 4 {
            let r = NMUi.Rect(this.parent, 0.0, 0.0, 1.0, 1.0, NMTheme.Cyan(), 1.0);
            r.SetAnchorPoint(new Vector2(0.5, 0.5));
            r.SetVisible(false);
            this.photoEdge[slot * 4 + e] = r;
            e += 1;
        }
        let k = NMItemRenderer.PhotoPtr() * this.scale;
        let ptr = NMUi.Rect(this.parent, 0.0, 0.0, k, k, NMTheme.Cyan(), 1.0);
        ptr.SetAnchorPoint(new Vector2(0.5, 0.5));
        ptr.SetRotation(45.0);
        ptr.SetVisible(false);
        this.photoPtr[slot] = ptr;
    }

    private func PaintPhoto(slot: Int32, color: HDRColor) {
        if !IsDefined(this.photoPtr[slot]) { return; }
        let e = 0;
        while e < 4 { this.photoEdge[slot * 4 + e].SetTintColor(color); e += 1; }
        this.photoPtr[slot].SetTintColor(color);
    }

    private func SetPhotoVisible(slot: Int32, on: Bool) {
        if !IsDefined(this.photoFill[slot]) { return; }
        if !on { this.photoFill[slot].SetVisible(false); }
        let e = 0;
        while e < 4 { this.photoEdge[slot * 4 + e].SetVisible(on); e += 1; }
        this.photoPtr[slot].SetVisible(on);
        this.chipIcon[slot].SetVisible(false);
        this.photoOn[slot] = on;
    }

    private func PlacePhoto(L: ref<NightMapLayer>, id: Int32, slot: Int32, p: Vector2, color: HDRColor) -> Vector2 {
        this.EnsurePhotoWidgets(slot);
        let ts = this.thumbPlan.Want(L.shot[id]);
        let s = this.scale * this.curScale;   // the tier scale shrinks the whole pin
        let f = this.curFade;
        let tw = NMItemRenderer.ThumbW() * s * this.thumbZoom;
        let th = NMItemRenderer.ThumbH() * s * this.thumbZoom;
        let ed = NMItemRenderer.PhotoEdge() * s;
        let half = NMItemRenderer.PhotoPtr() * s * 0.7071;
        let c = new Vector2(p.X, p.Y - half - ed - th * 0.5);   // thumbnail centre; the point's tip sits on p
        let ready = this.thumbPlan.IsReady(ts);
        if ready {
            let im = this.thumbImg[ts];
            im.SetSize(new Vector2(tw, th));
            im.SetOpacity(L.opacity * L.alpha[id] * f);
            im.SetTranslation(c);
            im.SetVisible(true);
        }
        this.photoFill[slot].SetSize(new Vector2(tw, th));
        this.photoFill[slot].SetTranslation(c);
        this.photoFill[slot].SetOpacity(0.85 * f);
        this.photoFill[slot].SetVisible(!ready);
        this.photoPtr[slot].SetScale(new Vector2(this.curScale, this.curScale));
        this.photoPtr[slot].SetOpacity(f);
        let edgeColor = slot == this.photoSel ? NMTheme.Yellow() : color;
        let e = 0;
        while e < 4 {
            let r = this.photoEdge[slot * 4 + e];
            r.SetOpacity(f);
            if e < 2 {
                r.SetSize(new Vector2(tw + ed * 2.0, ed));
                r.SetTranslation(new Vector2(c.X, c.Y + (e == 0 ? -1.0 : 1.0) * (th + ed) * 0.5));
            } else {
                r.SetSize(new Vector2(ed, th + ed * 2.0));
                r.SetTranslation(new Vector2(c.X + (e == 2 ? -1.0 : 1.0) * (tw + ed) * 0.5, c.Y));
            }
            e += 1;
        }
        this.photoPtr[slot].SetTranslation(new Vector2(p.X, p.Y - half));
        this.photoColor[slot] = color;
        this.PaintPhoto(slot, edgeColor);
        if !this.photoOn[slot] {
            this.SetPhotoVisible(slot, true);
        }
        return c;
    }

    public func Invalidate() {
        this.lastCamRev = -1;
    }

    public func Update(cam: ref<NMCamera>, viewW: Float, viewH: Float) -> Bool {
        let api = this.api;
        if cam.revision == this.lastCamRev && api.revision == this.lastApiRev {
            return false;
        }
        this.lastCamRev = cam.revision;
        this.lastApiRev = api.revision;
        this.relayouts += 1;
        this.thumbZoom = NMItemRenderer.ThumbZoom(cam.mpp);
        this.thumbPlan.BeginLayout();
        ArrayClear(this.candX);
        ArrayClear(this.candY);
        ArrayClear(this.candReach);
        ArrayClear(this.candKind);
        ArrayClear(this.candLayer);
        ArrayClear(this.candItem);
        ArrayClear(this.candSlot);
        this.chipsUsed = 0;
        this.pendingImages = 0;
        let order: array<Int32> = this.LayerOrder();
        // Same level-0 range and ring centre for every layer. The ring order itself is built on first use: sparse
        // layers never need it, and over the whole city it is ~9,000 cells.
        this.indRg = this.CellRange(0, cam, 60.0 * this.scale);
        this.ringCx = Clamp(this.CenterCell(0, cam, false), this.indRg[0], this.indRg[2]);
        this.ringCy = Clamp(this.CenterCell(0, cam, true), this.indRg[1], this.indRg[3]);
        this.ringBuilt = false;
        for li in order {
            let L = api.layers[li];
            if L.VisibleAt(cam.mpp) && L.count > 0 && this.chipsUsed < NMTheme.ChipBudget() {
                let tier = L.EffectiveTier();
                let f = NMTiers.Fade(tier, cam.mpp);
                if f > 0.0 {   // fully faded: skipped whole, not a candidate (spec 7.2)
                    this.curFade = f;
                    this.curScale = NMTiers.Scale(tier, cam.mpp);
                    if L.count <= NMItemRenderer.ScanAllMax() {
                        this.PlaceAllOf(L, cam, viewW, viewH);
                    } else {
                        this.PlaceCellsOf(L, cam, viewW, viewH);
                    }
                }
            }
        }
        this.HideUnused();
        this.FinishThumbs();
        return true;
    }

    // Layers up to this many items are scanned item by item; larger ones cell by cell, nearest first.
    public static func ScanAllMax() -> Int32 { return 64; }

    // Layer indices by priority, highest first (highest gets the topmost chip slots).
    private func LayerOrder() -> array<Int32> {
        let order: array<Int32>;
        let i = 0;
        while i < ArraySize(this.api.layers) {
            let j = ArraySize(order);
            ArrayPush(order, i);
            while j > 0 && this.api.layers[order[j - 1]].priority < this.api.layers[i].priority {
                order[j] = order[j - 1];
                j -= 1;
            }
            order[j] = i;
            i += 1;
        }
        return order;
    }

    // [gx0, gy0, gx1, gy1] of cells at a level intersecting the view plus a margin.
    private func CellRange(level: Int32, cam: ref<NMCamera>, marginPx: Float) -> array<Int32> {
        let vis = cam.VisibleRect(marginPx);
        let cs = NMGrid.CellSize(level);
        let side = NMGrid.Side(level);
        let r: array<Int32>;
        ArrayPush(r, Clamp(FloorF((vis.minX - NMGrid.OriginX()) / cs), 0, side - 1));
        ArrayPush(r, Clamp(FloorF((vis.minY - NMGrid.OriginY()) / cs), 0, side - 1));
        ArrayPush(r, Clamp(FloorF((vis.maxX - NMGrid.OriginX()) / cs), 0, side - 1));
        ArrayPush(r, Clamp(FloorF((vis.maxY - NMGrid.OriginY()) / cs), 0, side - 1));
        return r;
    }

    // Fills ordX/ordY with the cells of [x0..x1]x[y0..y1] ordered by ring distance from (cx, cy). Within a ring the
    // order is row-major (y, then x), which the sparse path in PlaceCellsOf relies on.
    private func RingOrder(x0: Int32, y0: Int32, x1: Int32, y1: Int32, cx: Int32, cy: Int32) {
        ArrayClear(this.ordX);
        ArrayClear(this.ordY);
        cx = Clamp(cx, x0, x1);
        cy = Clamp(cy, y0, y1);
        let maxR = Max(Max(cx - x0, x1 - cx), Max(cy - y0, y1 - cy));
        let r = 0;
        while r <= maxR {
            let y = cy - r;
            while y <= cy + r {
                if y >= y0 && y <= y1 {
                    if y == cy - r || y == cy + r {
                        let x = cx - r;
                        while x <= cx + r {
                            if x >= x0 && x <= x1 {
                                ArrayPush(this.ordX, x);
                                ArrayPush(this.ordY, y);
                            }
                            x += 1;
                        }
                    } else {
                        if cx - r >= x0 {
                            ArrayPush(this.ordX, cx - r);
                            ArrayPush(this.ordY, y);
                        }
                        if cx + r <= x1 {
                            ArrayPush(this.ordX, cx + r);
                            ArrayPush(this.ordY, y);
                        }
                    }
                }
                y += 1;
            }
            r += 1;
        }
    }

    private func CenterCell(level: Int32, cam: ref<NMCamera>, axisY: Bool) -> Int32 {
        let cs = NMGrid.CellSize(level);
        if axisY {
            return FloorF((cam.cy - NMGrid.OriginY()) / cs);
        }
        return FloorF((cam.cx - NMGrid.OriginX()) / cs);
    }

    // Level-0 cells of the relayout's range, nearest ring first, until the chip budget is spent. A layer occupying few
    // of those cells walks its occupied list instead of the whole range: the list is ascending (row-major), so a stable
    // bucket by ring gives exactly the ring order. forceScan always walks the full ring order (the reference).
    private func PlaceCellsOf(L: ref<NightMapLayer>, cam: ref<NMCamera>, viewW: Float, viewH: Float) {
        let rg = this.indRg;
        let side = NMGrid.Side(0);
        let base = NMGrid.Base(0);
        let budget = NMTheme.ChipBudget();
        let on = L.occN[0];
        let area = (rg[2] - rg[0] + 1) * (rg[3] - rg[1] + 1);
        if !this.forceScan && on * 2 < area {
            ArrayClear(this.sCell);
            ArrayClear(this.sRing);
            let maxR = 0;
            let oi = 0;
            while oi < on {
                let cell = L.occ[base + oi];
                oi += 1;
                let rel = cell - base;
                let gy = rel / side;
                let gx = rel - gy * side;
                if gx >= rg[0] && gx <= rg[2] && gy >= rg[1] && gy <= rg[3] {
                    let r = Max(Max(gx - this.ringCx, this.ringCx - gx), Max(gy - this.ringCy, this.ringCy - gy));
                    ArrayPush(this.sCell, cell);
                    ArrayPush(this.sRing, r);
                    if r > maxR { maxR = r; }
                }
            }
            let n = ArraySize(this.sCell);
            ArrayResize(this.sStart, maxR + 2);
            let q = 0;
            while q < maxR + 2 { this.sStart[q] = 0; q += 1; }
            let k = 0;
            while k < n { this.sStart[this.sRing[k] + 1] += 1; k += 1; }
            q = 1;
            while q < maxR + 2 { this.sStart[q] += this.sStart[q - 1]; q += 1; }
            ArrayResize(this.sOrd, n);
            k = 0;
            while k < n {
                let at = this.sStart[this.sRing[k]];
                this.sOrd[at] = this.sCell[k];
                this.sStart[this.sRing[k]] = at + 1;
                k += 1;
            }
            k = 0;
            while k < n && this.chipsUsed < budget {
                let id = L.head[this.sOrd[k]];
                while id >= 0 {
                    this.PlaceChip(L, id, cam, viewW, viewH);
                    id = L.nextIn[id * 3];
                }
                k += 1;
            }
            return;
        }
        if !this.ringBuilt {
            this.RingOrder(rg[0], rg[1], rg[2], rg[3], this.ringCx, this.ringCy);
            this.ringBuilt = true;
        }
        let n2 = ArraySize(this.ordX);
        let i = 0;
        while i < n2 && this.chipsUsed < budget {
            let id = L.head[base + this.ordY[i] * side + this.ordX[i]];
            while id >= 0 {
                this.PlaceChip(L, id, cam, viewW, viewH);
                id = L.nextIn[id * 3];
            }
            i += 1;
        }
    }

    // Small layers (ScanAllMax items or fewer) scan every alive item per relayout.
    private func PlaceAllOf(L: ref<NightMapLayer>, cam: ref<NMCamera>, viewW: Float, viewH: Float) {
        let id = 0;
        while id < ArraySize(L.alive) {
            if L.alive[id] {
                this.PlaceChip(L, id, cam, viewW, viewH);
            }
            id += 1;
        }
    }

    private func ResolveIcon(L: ref<NightMapLayer>, id: Int32) {
        let ic = this.icon;
        ic.pending = false;
        if NotEquals(L.image[id], "") {
            if Equals(L.imageResolved[id], "") {
                L.imageResolved[id] = NMResolveImage(L.image[id]);
            }
            if NotEquals(L.imageResolved[id], "") {
                ic.atlas = ResRef.FromString(L.imageResolved[id]);
                ic.part = n"full";
                ic.key = L.imageResolved[id];
                return;
            }
            ic.pending = NMImagesAvailable();
        }
        if L.hasAtlas[id] {
            ic.atlas = L.atlas[id];
            ic.part = L.part[id];
            ic.key = L.atlasKey[id];
            return;
        }
        let g = L.catGlobal[L.cat[id]];
        if this.api.catHasIcon[g] {
            ic.atlas = this.api.catAtlas[g];
            ic.part = this.api.catPart[g];
            ic.key = "cat" + ToString(g);
            return;
        }
        ic.atlas = NMTheme.UiAtlas();
        ic.part = n"icon_dot";
        ic.key = "dot";
    }

    // Set once right after Create (before the first Update): the per-slot style, size, tint and opacity caches below
    // already carry the halo, so there is no per-frame work.
    public func SetHalo(on: Bool) { this.halo = on; }
    public func HaloOn() -> Bool { return this.halo; }

    // Opacity factor of the blob behind an icon pin: the halo (own colour) or the vanilla dark shadow.
    private func BlobOpacity() -> Float {
        return this.halo ? NMTheme.HaloOpacity() : NMTheme.VanillaShadowOpacity();
    }

    // Switches a pooled chip between the hologram hex (0) and the vanilla icon look (1 idle, 2 emphasised).
    private func ApplyChipStyle(slot: Int32, style: Int32) {
        let bg = this.chipBg[slot];
        let ic = this.chipIcon[slot];
        if this.chipStyle[slot] == 3 && style != 3 {
            this.SetPhotoVisible(slot, false);
        }
        if style == 3 || style == 4 {
            bg.SetVisible(false);
            bg.SetScale(new Vector2(1.0, 1.0));
            ic.SetScale(new Vector2(1.0, 1.0));
            this.chipK[slot] = 1.0;
            if style == 4 {
                ic.SetSize(new Vector2(NMTheme.DotSize() * this.scale, NMTheme.DotSize() * this.scale));
            }
            if slot == this.growSlot { this.growSlot = -1; }
            this.chipStyle[slot] = style;
            return;
        }
        if style == 0 {
            bg.SetAtlasResource(NMTheme.UiAtlas());
            bg.SetTexturePart(n"chip");
            bg.SetSize(new Vector2(NMTheme.ChipSize() * this.scale, NMTheme.ChipSize() * this.scale));
            ic.SetSize(new Vector2(NMTheme.IconSize() * this.scale, NMTheme.IconSize() * this.scale));
        } else {
            let k = style == 2 ? NMTheme.VanillaEmphScale() : 1.0;
            let blob = this.halo ? NMTheme.HaloSize() : NMTheme.VanillaShadowSize();
            if this.halo {
                bg.SetAtlasResource(NMTheme.HoloAtlas());
                bg.SetTexturePart(n"holo_halo");
            } else {
                bg.SetAtlasResource(NMTheme.ShadowAtlas());
                bg.SetTexturePart(n"shadowBlobSquare_big");
            }
            bg.SetSize(new Vector2(blob * k * this.scale, blob * k * this.scale));
            ic.SetSize(new Vector2(NMTheme.VanillaIconSize() * k * this.scale, NMTheme.VanillaIconSize() * k * this.scale));
        }
        bg.SetScale(new Vector2(1.0, 1.0));
        ic.SetScale(new Vector2(1.0, 1.0));
        this.chipK[slot] = 1.0;   // PlaceChip applies the tier scale right after
        if slot == this.growSlot {
            this.growSlot = -1;
        }
        this.chipStyle[slot] = style;
    }

    // Shows or hides the slot's scratch; it copies the icon's size, scale and opacity, so call it after those are set.
    private func SetStrike(slot: Int32, on: Bool, style: Int32, p: Vector2, tint: HDRColor) {
        if !on {
            if this.strikeOn[slot] {
                this.chipStrike[slot].SetVisible(false);
                this.strikeOn[slot] = false;
            }
            return;
        }
        if !IsDefined(this.chipStrike[slot]) {
            this.chipStrike[slot] = NMUi.Image(this.parent, n"icon_strike", 0.0, 0.0, NMTheme.VanillaIconSize() * this.scale, tint, true);
        }
        let st = this.chipStrike[slot];
        let ic = this.chipIcon[slot];
        st.SetSize(ic.GetSize());
        st.SetScale(ic.GetScale());
        st.SetOpacity(ic.GetOpacity());
        st.SetTintColor(tint);
        st.SetTranslation(p);
        if !this.strikeOn[slot] {
            st.SetVisible(true);
            this.strikeOn[slot] = true;
        }
    }

    // t in 0..1: scale 1 -> VanillaEmphScale and opacity idle -> full, like the vanilla OnSelect animation. The grow
    // multiplies the slot's tier scale, so t = 0 restores the tier-scaled size.
    private func SetGrow(slot: Int32, t: Float) {
        let k = this.chipK[slot] * (1.0 + (NMTheme.VanillaEmphScale() - 1.0) * t);
        let base = this.chipAlpha[slot];
        let full = MinF(1.0, base / NMTheme.VanillaIdleOpacity());
        let o = base + (full - base) * t;
        this.chipBg[slot].SetScale(new Vector2(k, k));
        this.chipIcon[slot].SetScale(new Vector2(k, k));
        this.chipIcon[slot].SetOpacity(o);
        if this.strikeOn[slot] {
            this.chipStrike[slot].SetScale(new Vector2(k, k));
            this.chipStrike[slot].SetOpacity(o);
        }
        this.chipBg[slot].SetOpacity(o * this.BlobOpacity());
    }

    // Called every frame after the pick. Icon pins have no selection rim; an idle icon pin grows to the
    // emphasis look over VanillaGrowMs. cand indexes the cand* arrays (-1 none); kind is the selection kind (0 item).
    public func ApplySelection(cand: Int32, kind: Int32, dtMs: Float) {
        let slot = -1;
        let layer = -1;
        let item = -1;
        if cand >= 0 && kind == 0 && cand < ArraySize(this.candSlot) {
            slot = this.candSlot[cand];
            layer = this.candLayer[cand];
            item = this.candItem[cand];
        }
        let photo = slot >= 0 && this.chipStyle[slot] == 3 ? slot : -1;
        if photo != this.photoSel {
            if this.photoSel >= 0 && this.photoSel < ArraySize(this.photoColor) {
                this.PaintPhoto(this.photoSel, this.photoColor[this.photoSel]);
            }
            this.photoSel = photo;
            if photo >= 0 {
                this.PaintPhoto(photo, NMTheme.Yellow());
            }
        }
        let isIcon = slot >= 0 && this.chipStyle[slot] >= 1;
        if isIcon {
            this.selChip.SetVisible(false);
        }
        let target = isIcon && this.chipStyle[slot] == 1 ? slot : -1;
        let sameItem = layer == this.growLayer && item == this.growItem;
        if target != this.growSlot || !sameItem {
            if this.growSlot >= 0 {
                this.SetGrow(this.growSlot, 0.0);
            }
            if !sameItem {
                this.growT = 0.0;
            }
            this.growSlot = target;
            this.growLayer = target >= 0 ? layer : -1;
            this.growItem = target >= 0 ? item : -1;
            if target >= 0 && this.growT > 0.0 {
                this.SetGrow(target, this.growT);   // same item moved to another slot: keep its progress
            }
        }
        if this.growSlot >= 0 && this.growT < 1.0 {
            this.growT = MinF(1.0, this.growT + MaxF(dtMs, 0.0) / NMTheme.VanillaGrowMs());
            this.SetGrow(this.growSlot, this.growT);
        }
    }

    private static func SameColor(a: HDRColor, b: HDRColor) -> Bool {
        return a.Red == b.Red && a.Green == b.Green && a.Blue == b.Blue && a.Alpha == b.Alpha;
    }

    private func PlaceChip(L: ref<NightMapLayer>, id: Int32, cam: ref<NMCamera>, viewW: Float, viewH: Float) -> Bool {
        if this.chipsUsed >= NMTheme.ChipBudget() {
            return false;
        }
        let p = cam.WorldToMap(L.px[id], L.py[id]);
        let m = 60.0 * this.scale;
        if p.X < -m || p.X > viewW + m || p.Y < -m || p.Y > viewH + m {
            return false;
        }
        let slot = NMTheme.ChipBudget() - 1 - this.chipsUsed;
        this.chipsUsed += 1;
        let bg = this.chipBg[slot];
        let ic = this.chipIcon[slot];
        if slot == this.growSlot && (L.index != this.growLayer || id != this.growItem) {
            this.SetGrow(slot, 0.0);
            this.growSlot = -1;
        }
        let g = L.catGlobal[L.cat[id]];
        let color = this.api.catColor[g];
        let style = L.shot[id] != 0u ? 3 : (L.dot[id] ? 4 : (L.pinStyle == 1 ? (L.emph[id] ? 2 : 1) : 0));
        if this.chipStyle[slot] != style {
            let wasPhoto = this.chipStyle[slot] == 3;
            let wasDot = this.chipStyle[slot] == 4;
            this.ApplyChipStyle(slot, style);
            this.chipTintOk[slot] = false;  // force the tint refresh below
            this.chipAlpha[slot] = -1.0;    // force the opacity refresh below
            if wasPhoto || wasDot {
                // A photo pin hides both widgets and a dot its blob while chipOn stays true, so the check below would
                // leave them hidden.
                bg.SetVisible(style != 4);
                ic.SetVisible(true);
            }
        }
        if style == 3 {
            this.SetStrike(slot, false, 3, p, color);
            let c = this.PlacePhoto(L, id, slot, p, color);
            this.chipOn[slot] = true;
            ArrayPush(this.candX, c.X);
            ArrayPush(this.candY, c.Y);
            ArrayPush(this.candReach, p.Y - c.Y);   // to the pin's tip
            ArrayPush(this.candKind, 0);
            ArrayPush(this.candLayer, L.index);
            ArrayPush(this.candItem, id);
            ArrayPush(this.candSlot, slot);
            return true;
        }
        let icTint = L.hasTint[id] ? L.tint[id] : color;
        let bgTint = style == 0 ? color : (this.halo ? icTint : NMTheme.ShadowColor());
        if !this.chipTintOk[slot] || !NMItemRenderer.SameColor(this.chipTintBg[slot], bgTint) {
            bg.SetTintColor(bgTint);
            this.chipTintBg[slot] = bgTint;
        }
        if !this.chipTintOk[slot] || !NMItemRenderer.SameColor(this.chipTintIc[slot], icTint) {
            ic.SetTintColor(icTint);
            this.chipTintIc[slot] = icTint;
        }
        this.chipTintOk[slot] = true;
        this.ResolveIcon(L, id);
        if this.icon.pending { this.pendingImages += 1; }
        if NotEquals(this.chipIconKey[slot], this.icon.key) {
            ic.SetAtlasResource(this.icon.atlas);
            ic.SetTexturePart(this.icon.part);
            this.chipIconKey[slot] = this.icon.key;
            this.chipIconPart[slot] = this.icon.part;
        } else if NotEquals(this.chipIconPart[slot], this.icon.part) {
            ic.SetTexturePart(this.icon.part);
            this.chipIconPart[slot] = this.icon.part;
        }
        let k = this.curScale;
        if this.chipK[slot] != k {
            this.chipK[slot] = k;
            if slot == this.growSlot {
                this.SetGrow(slot, this.growT);
            } else {
                bg.SetScale(new Vector2(k, k));
                ic.SetScale(new Vector2(k, k));
            }
        }
        let a = L.opacity * L.alpha[id] * this.curFade;
        if style == 1 {
            a *= NMTheme.VanillaIdleOpacity();
        }
        if this.chipAlpha[slot] != a {
            bg.SetOpacity(style == 0 ? a : a * this.BlobOpacity());
            ic.SetOpacity(a);
            this.chipAlpha[slot] = a;
            if slot == this.growSlot {
                this.SetGrow(slot, this.growT);   // keep the grown (full) opacity for the new base alpha
            }
        }
        bg.SetTranslation(p);
        ic.SetTranslation(p);
        if !this.chipOn[slot] {
            bg.SetVisible(style != 4);
            ic.SetVisible(true);
            this.chipOn[slot] = true;
        }
        this.SetStrike(slot, L.struck[id], style, p, icTint);
        ArrayPush(this.candX, p.X);
        ArrayPush(this.candY, p.Y);
        ArrayPush(this.candReach, 0.0);
        ArrayPush(this.candKind, 0);
        ArrayPush(this.candLayer, L.index);
        ArrayPush(this.candItem, id);
        ArrayPush(this.candSlot, slot);
        return true;
    }

    private func HideUnused() {
        let firstUsed = NMTheme.ChipBudget() - this.chipsUsed;
        let s = 0;
        while s < firstUsed {
            if this.chipOn[s] {
                this.chipBg[s].SetVisible(false);
                this.chipIcon[s].SetVisible(false);
                this.SetStrike(s, false, 0, new Vector2(0.0, 0.0), NMTheme.Cyan());
                if this.photoOn[s] {
                    this.SetPhotoVisible(s, false);
                }
                if s == this.growSlot {
                    this.SetGrow(s, 0.0);
                    this.growSlot = -1;
                }
                this.chipOn[s] = false;
            }
            s += 1;
        }
    }
}
