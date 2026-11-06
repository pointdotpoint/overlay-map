module OverlayMap

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
// cell nearest-first, so the budget keeps the pins around the view centre. In that order, a pin that would overlap
// one already placed is skipped (declutter), so a more important marker wins and piles thin out as the map zooms out.
// Markers persist: at its layer's turn, each layer first replays what the last relayout placed, then walks its cells.
// The cull caps end a walk at a point that depends on the view centre's cell, so without the replay a pan across a
// 250 m cell edge swapped which pins of a dense layer showed (shards around the Pacifica stadium, 2026-11-02).
// Relayout happens only when the camera or the API revision changed.
public class NMItemRenderer {
    private let api: wref<OverlayMap>;
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
    private let strikeStale: array<Bool>;   // the slot's size, scale, opacity or tint changed since its strike copied them
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
    public let forceScan: Bool;   // test hook: bypass the occupied-cell lists (reference behaviour: the full ring scan)
    private let icon: ref<NMIconRef>;
    private let lastCamRev: Int32;
    private let lastApiRev: Int32;
    public let chipsUsed: Int32;
    public let pendingImages: Int32;
    public let relayouts: Int32;
    // Declutter: a marker that collides on screen with one already placed this relayout is skipped (no slot, no
    // candidate). Placed markers go into a spatial hash over the view, rebuilt per relayout in reused arrays.
    public let culled: Int32;       // items skipped by the declutter in the last relayout
    public let capStops: Int32;     // layers whose walk the cull cap ended in the last relayout (tests)
    public let noDeclutter: Bool;   // test hook: place every item as before the declutter (budget and order tests)
    private let curAlways: Bool;    // the layer being placed is Always tier: never culled
    private let keepLayer: Int32;   // the selection (layer + item): never culled while selected
    private let keepItem: Int32;
    private let keptPlaced: Bool;   // this relayout placed the selection up front; the layer walk skips it
    // The last relayout's placements, bucketed by layer index (prevOrd[prevStart[li] .. prevStart[li + 1]) are layer
    // li's item ids, in placement order), replayed at each layer's turn. Dropped when layer indices change (layerEpoch).
    private let prevStart: array<Int32>;
    private let prevOrd: array<Int32>;
    private let prevEpoch: Int32;
    private let stamp: Int32;       // this relayout's NightMap.placeStamp: an item with placedAt == stamp was tested
    private let reserved: array<ref<NMRect>>;   // screen areas markers keep clear of (the panel header), padded
    private let hHead: array<Int32>;   // per hash cell: last placed marker in it, -1 none
    private let hNext: array<Int32>;   // per placed marker: the previous one in its cell
    private let hX: array<Float>;
    private let hY: array<Float>;
    private let hR: array<Float>;
    private let hN: Int32;
    private let hCols: Int32;
    private let hRows: Int32;
    private let hCell: Float;
    private let hOrg: Float;           // the grid starts at (hOrg, hOrg): the view's top-left minus the cull margin
    private let hK: Float;             // DeclutterOverlap, read once per relayout
    private let hRmax: Float;          // largest DeclutterOverlap x radius placed so far this relayout
    private let cellMiss: Int32;       // consecutive culls that end the walk of one level-0 cell (its pile is full)
    private let cullLimit: Int32;      // the culled count where the layer being placed stops (no limit for Always or noDeclutter)
    private let chipCap: Int32;        // NMTheme.ChipBudget(), read once (the walk loops test it per item)
    // Visible radii of the layer being placed (UI scale x tier scale), and a photo picture's lift above its spot.
    private let rChip: Float;
    private let rDot: Float;
    private let rPlate: Float;
    private let rPlateEmph: Float;
    private let rPhoto: Float;
    private let photoLift: Float;

    public static func Create(api: ref<OverlayMap>, parent: ref<inkCanvas>, scale: Float) -> ref<NMItemRenderer> {
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
            ArrayPush(r.strikeStale, true);
            ArrayPush(r.photoColor, NMTheme.Cyan());
            let e = 0;
            while e < 4 { ArrayPush(r.photoEdge, null); e += 1; }
            i += 1;
        }
        r.growSlot = -1;
        r.growLayer = -1;
        r.growItem = -1;
        r.keepLayer = -1;
        r.keepItem = -1;
        r.chipCap = NMTheme.ChipBudget();
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
    public static func IconKeyFor(L: ref<OverlayMapLayer>, id: Int32) -> String {
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

    // How far a photo pin's thumbnail centre sits above the spot (s: UI scale x tier scale).
    public static func PhotoLift(s: Float, thumbZoom: Float) -> Float {
        return NMItemRenderer.PhotoPtr() * s * 0.7071 + NMItemRenderer.PhotoEdge() * s + NMItemRenderer.ThumbH() * s * thumbZoom * 0.5;
    }

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

    private func PlacePhoto(L: ref<OverlayMapLayer>, id: Int32, slot: Int32, p: Vector2, color: HDRColor) -> Vector2 {
        this.EnsurePhotoWidgets(slot);
        let ts = this.thumbPlan.Want(L.shot[id]);
        let s = this.scale * this.curScale;   // the tier scale shrinks the whole pin
        let f = this.curFade;
        let tw = NMItemRenderer.ThumbW() * s * this.thumbZoom;
        let th = NMItemRenderer.ThumbH() * s * this.thumbZoom;
        let ed = NMItemRenderer.PhotoEdge() * s;
        let half = NMItemRenderer.PhotoPtr() * s * 0.7071;
        let c = new Vector2(p.X, p.Y - NMItemRenderer.PhotoLift(s, this.thumbZoom));   // thumbnail centre; the point's tip sits on p
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

    // Markers are placed out to this far past the view's edges (the clip cuts a marker straddling an edge).
    public static func CullMargin(scale: Float) -> Float { return 60.0 * scale; }

    // Relayout for the panel: culled to the map visible left of the sidebar (layout.viewW), not the whole map area, so
    // nothing is placed under the sidebar (the viewport clips there too, NMPanel).
    public func UpdateFor(cam: ref<NMCamera>, l: ref<NMPanelLayout>) -> Bool { return this.Update(cam, l.viewW, l.mapH); }

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
        this.TakeHistory();
        api.placeStamp += 1;
        this.stamp = api.placeStamp;
        ArrayClear(this.candX);
        ArrayClear(this.candY);
        ArrayClear(this.candReach);
        ArrayClear(this.candKind);
        ArrayClear(this.candLayer);
        ArrayClear(this.candItem);
        ArrayClear(this.candSlot);
        this.chipsUsed = 0;
        this.pendingImages = 0;
        this.BeginDeclutter(viewW, viewH);
        let order: array<Int32> = this.LayerOrder();
        // Same level-0 range and ring centre for every layer. The ring order itself is built on first use: sparse
        // layers never need it, and over the whole city it is ~9,000 cells.
        this.indRg = this.CellRange(0, cam, NMItemRenderer.CullMargin(this.scale));
        this.ringCx = Clamp(this.CenterCell(0, cam, false), this.indRg[0], this.indRg[2]);
        this.ringCy = Clamp(this.CenterCell(0, cam, true), this.indRg[1], this.indRg[3]);
        this.ringBuilt = false;
        this.PlaceKept(cam, viewW, viewH);
        for li in order {
            let L = api.layers[li];
            let tier = L.EffectiveTier();
            this.curAlways = tier <= 0;
            // Major layers come before every Minor one, so `culled` is theirs alone while they are placed.
            this.cullLimit = this.curAlways || this.noDeclutter ? 2147483647
                : (tier == 1 ? NMItemRenderer.CullCap() : this.culled + NMItemRenderer.LayerCullCap());
            if L.VisibleAt(cam.mpp) && L.count > 0 && !this.Saturated() {
                let f = NMTiers.LayerFade(L, cam.mpp);
                if f > 0.0 {   // fully faded: skipped whole, not a candidate (spec 7.2)
                    this.curFade = f;
                    this.curScale = NMTiers.Scale(tier, cam.mpp);
                    this.cellMiss = this.noDeclutter ? 2147483647 : this.CellMissCap(cam.mpp);
                    this.LayerRadii();
                    this.PlacePrev(L, cam, viewW, viewH);
                    if L.count <= NMItemRenderer.ScanAllMax() {
                        this.PlaceAllOf(L, cam, viewW, viewH);
                    } else {
                        this.PlaceCellsOf(L, cam, viewW, viewH);
                    }
                    if this.culled >= this.cullLimit { this.capStops += 1; }
                }
            }
        }
        this.HideUnused();
        this.FinishThumbs();
        return true;
    }

    // Buckets the last relayout's placements (the candidates, in placement order) by layer for PlacePrev.
    private func TakeHistory() {
        let n = ArraySize(this.api.layers);
        ArrayResize(this.prevStart, n + 1);
        let q = 0;
        while q <= n { this.prevStart[q] = 0; q += 1; }
        if this.api.layerEpoch != this.prevEpoch {   // RemoveLayer renumbered the layers: the history names others
            this.prevEpoch = this.api.layerEpoch;
            ArrayClear(this.candLayer);
            ArrayClear(this.candItem);
        }
        let m = ArraySize(this.candLayer);
        let k = 0;
        while k < m {
            let li = this.candLayer[k];
            if li >= 0 && li < n { this.prevStart[li + 1] += 1; }
            k += 1;
        }
        q = 1;
        while q <= n { this.prevStart[q] += this.prevStart[q - 1]; q += 1; }
        ArrayResize(this.prevOrd, this.prevStart[n]);
        k = 0;
        while k < m {
            let li = this.candLayer[k];
            if li >= 0 && li < n {   // prevStart[li] is the next free spot of bucket li; shifted back below
                this.prevOrd[this.prevStart[li]] = this.candItem[k];
                this.prevStart[li] += 1;
            }
            k += 1;
        }
        q = n;
        while q > 0 { this.prevStart[q] = this.prevStart[q - 1]; q -= 1; }
        this.prevStart[0] = 0;
    }

    // The last relayout's placements of layer L, before its walk: a pin stays while it is in view and nothing placed
    // before it (a higher layer, the selection, or an earlier pin of its own layer) covers it. Off under noDeclutter.
    private func PlacePrev(L: ref<NightMapLayer>, cam: ref<NMCamera>, viewW: Float, viewH: Float) {
        if this.noDeclutter || L.index < 0 || L.index + 1 >= ArraySize(this.prevStart) { return; }
        let k = this.prevStart[L.index];
        let end = this.prevStart[L.index + 1];
        while k < end && !this.Saturated() {
            let id = this.prevOrd[k];
            if L.IsAlive(id) { this.PlaceChip(L, id, cam, viewW, viewH); }
            k += 1;
        }
    }

    // A relayout from scratch: no placements to replay (tests comparing walks; the next Update still relays out only
    // if the camera or the API changed, so pair it with Invalidate).
    public func Forget() {
        ArrayClear(this.candLayer);
        ArrayClear(this.candItem);
    }

    // Rule 2: the selection is placed (and occupies its space) before every layer, like an Always item, so neither
    // the cull cap, a cell's miss cap nor a full budget can drop it under the reticle. It still follows its layer's
    // visibility and tier fade.
    private func PlaceKept(cam: ref<NMCamera>, viewW: Float, viewH: Float) {
        this.keptPlaced = false;
        if this.noDeclutter || this.keepLayer < 0 || this.keepLayer >= ArraySize(this.api.layers) { return; }
        let L = this.api.layers[this.keepLayer];
        if !L.IsAlive(this.keepItem) || !L.VisibleAt(cam.mpp) { return; }
        let tier = L.EffectiveTier();
        let f = NMTiers.LayerFade(L, cam.mpp);
        if f <= 0.0 { return; }
        this.curFade = f;
        this.curScale = NMTiers.Scale(tier, cam.mpp);
        this.curAlways = tier <= 0;
        this.LayerRadii();
        this.keptPlaced = this.PlaceChip(L, this.keepItem, cam, viewW, viewH);
    }

    // ---- declutter: a spatial hash of this relayout's placed markers over the view plus the cull margin ----

    // Empties the hash for a relayout. A cell is twice the largest possible radius, so any collision distance
    // (DeclutterOverlap x (rA + rB) <= 2 x the largest radius) reaches at most the neighbouring cells.
    private func BeginDeclutter(viewW: Float, viewH: Float) {
        this.culled = 0;
        this.capStops = 0;
        this.hN = 0;
        this.hRmax = 0.0;
        this.hK = NMTheme.DeclutterOverlap();
        let m = NMItemRenderer.CullMargin(this.scale);
        let plate = NMTheme.PlateSize() * 0.25 * NMTheme.VanillaEmphScale();
        let biggest = MaxF(MaxF(plate, NMTheme.ChipSize() * 0.5), MaxF(NMTheme.DotSize() * 0.5, NMItemRenderer.ThumbW() * 0.5 * this.thumbZoom));
        this.hCell = MaxF(2.0 * biggest * this.scale, 1.0);
        this.hOrg = -m;
        this.hCols = Max(1, CeilF((viewW + 2.0 * m) / this.hCell));
        this.hRows = Max(1, CeilF((viewH + 2.0 * m) / this.hCell));
        let n = this.hCols * this.hRows;
        if ArraySize(this.hHead) != n {
            ArrayResize(this.hHead, n);
        }
        let i = 0;
        while i < n {
            this.hHead[i] = -1;
            i += 1;
        }
    }

    // Screen rectangles (map coordinates) that culled markers keep clear of, like a marker placed before every layer:
    // the panel's header text. Always-tier items and the selection are placed regardless. A change relays out.
    public func SetReserved(rects: array<ref<NMRect>>) {
        if NMItemRenderer.SameRects(this.reserved, rects) {
            return;
        }
        this.reserved = rects;
        this.Invalidate();
    }

    private static func SameRects(a: array<ref<NMRect>>, b: array<ref<NMRect>>) -> Bool {
        if ArraySize(a) != ArraySize(b) {
            return false;
        }
        let i = 0;
        while i < ArraySize(a) {
            if a[i].minX != b[i].minX || a[i].minY != b[i].minY || a[i].maxX != b[i].maxX || a[i].maxY != b[i].maxY {
                return false;
            }
            i += 1;
        }
        return true;
    }

    // True when a marker's visible circle (radius r at x, y) touches a reserved rectangle.
    private func InReserved(x: Float, y: Float, r: Float) -> Bool {
        for q in this.reserved {
            let dx = MaxF(MaxF(q.minX - x, 0.0), x - q.maxX);
            let dy = MaxF(MaxF(q.minY - y, 0.0), y - q.maxY);
            if dx * dx + dy * dy < r * r {
                return true;
            }
        }
        return false;
    }

    // Declutter work bounds. Culled items cost a test but draw nothing, so a dense layer at a far zoom would otherwise
    // be walked item by item until the chip budget fills (tens of thousands of tests per relayout).
    // 1. A level-0 cell's chain stops after CellMissCap culls with no placement in between (items outside the view
    //    neither count nor reset): about as many markers as fit in the cell on screen, at least 2, so a cell smaller
    //    than a marker gives up after two misses while a cell many markers across (close zoom) keeps looking.
    // 2. Major layers (fast travel, quests: all a far view shows) stop together after CullCap culls. They are walked
    //    first (tier, then priority), so the count is theirs alone.
    // 3. Each Minor layer then gets its own slice of LayerCullCap culls, whatever the layers before it used: dense
    //    layers walked first (fast travel, vendors, drop points) can't starve the ones after them (the collectibles,
    //    last by priority). A relayout's culls are at most CullCap + LayerCullCap x the Minor layers in view.
    //    Always-tier items never cull, and the selection is placed before any layer (PlaceKept), so no bound drops them.
    // Task 11, measured with NMPerfSuite: a cull costs about as much as a placement, and one cap of 300 per relayout
    // kept the real-marker sweep (vanilla_open) over main's frame time while starving the collectibles at mid zoom.
    // 24 per Minor layer: with a slice per layer, 40 cost vanilla_open +0.56 ms script avg against main.
    public static func LayerCullCap() -> Int32 { return 24; }
    public static func CullCap() -> Int32 { return 160; }

    private func LayerRadii() {
        let s = this.scale * this.curScale;
        this.rChip = NMTheme.ChipSize() * 0.5 * s;
        this.rDot = NMTheme.DotSize() * 0.5 * s;
        this.rPlate = NMTheme.PlateSize() * 0.25 * s;
        this.rPlateEmph = this.rPlate * NMTheme.VanillaEmphScale();
        this.rPhoto = NMItemRenderer.ThumbW() * 0.5 * s * this.thumbZoom;
        this.photoLift = NMItemRenderer.PhotoLift(s, this.thumbZoom);
    }

    private func CellMissCap(mpp: Float) -> Int32 {
        let cellPx = NMGrid.CellSize(0) / MaxF(mpp, 0.0001);
        let d = MaxF(this.hK * NMTheme.ChipSize() * this.scale * this.curScale, 1.0);   // two nominal radii, overlapped
        let fit = cellPx / d;
        return Max(2, Cast<Int32>(MinF(fit * fit, 1000000.0)));
    }

    // True when nothing more can be placed for the current layer: the chip budget is spent, or the cull cap is hit
    // and the layer is not Always tier.
    private func Saturated() -> Bool {
        return this.chipsUsed >= this.chipCap || this.culled >= this.cullLimit;
    }

    // Hash cell of a screen coordinate on one axis. Points beyond the grid (a photo's picture above the view) clamp
    // to the border cells; clamping never moves two points within one cell of each other further apart.
    private func HashCol(v: Float, n: Int32) -> Int32 {
        return Clamp(FloorF((v - this.hOrg) / this.hCell), 0, n - 1);
    }

    // True when a marker of radius r at (x, y) collides with one already placed. Only the cells its collision reach
    // (DeclutterOverlap x (r + the largest radius placed so far)) touches are walked: within the 3 x 3 neighbourhood,
    // usually 2 x 2 of it. hR holds radii already times DeclutterOverlap.
    private func Collides(x: Float, y: Float, r: Float) -> Bool {
        let kr = this.hK * r;
        let reach = kr + this.hRmax;
        let o = this.hOrg;
        let c = this.hCell;
        let x0 = Clamp(FloorF((x - reach - o) / c), 0, this.hCols - 1);
        let x1 = Clamp(FloorF((x + reach - o) / c), 0, this.hCols - 1);
        let y0 = Clamp(FloorF((y - reach - o) / c), 0, this.hRows - 1);
        let y1 = Clamp(FloorF((y + reach - o) / c), 0, this.hRows - 1);
        let cy = y0;
        while cy <= y1 {
            let cx = x0;
            while cx <= x1 {
                let j = this.hHead[cy * this.hCols + cx];
                while j >= 0 {
                    let dx = this.hX[j] - x;
                    let dy = this.hY[j] - y;
                    let lim = kr + this.hR[j];
                    if dx * dx + dy * dy < lim * lim {
                        return true;
                    }
                    j = this.hNext[j];
                }
                cx += 1;
            }
            cy += 1;
        }
        return false;
    }

    private func Occupy(x: Float, y: Float, r: Float) {
        let cell = this.HashCol(y, this.hRows) * this.hCols + this.HashCol(x, this.hCols);
        r = this.hK * r;
        if r > this.hRmax { this.hRmax = r; }
        let j = this.hN;
        if j < ArraySize(this.hX) {
            this.hX[j] = x;
            this.hY[j] = y;
            this.hR[j] = r;
            this.hNext[j] = this.hHead[cell];
        } else {
            ArrayPush(this.hX, x);
            ArrayPush(this.hY, y);
            ArrayPush(this.hR, r);
            ArrayPush(this.hNext, this.hHead[cell]);
        }
        this.hHead[cell] = j;
        this.hN = j + 1;
    }

    // Layers up to this many items are scanned item by item; larger ones cell by cell, nearest first.
    public static func ScanAllMax() -> Int32 { return 64; }

    // Layer indices by effective tier (Always, Major, Minor), then priority, highest first. The first placed get the
    // topmost chip slots, and a big Minor layer can't spend the chip budget before fast travel and quests.
    private func LayerOrder() -> array<Int32> {
        let order: array<Int32>;
        let i = 0;
        while i < ArraySize(this.api.layers) {
            let j = ArraySize(order);
            ArrayPush(order, i);
            while j > 0 && NMItemRenderer.PlacesAfter(this.api.layers[order[j - 1]], this.api.layers[i]) {
                order[j] = order[j - 1];
                j -= 1;
            }
            order[j] = i;
            i += 1;
        }
        return order;
    }

    // True when layer a is placed after layer b: a lower tier (higher EffectiveTier), or the same tier and a lower priority.
    public static func PlacesAfter(a: ref<OverlayMapLayer>, b: ref<OverlayMapLayer>) -> Bool {
        let ta = a.EffectiveTier();
        let tb = b.EffectiveTier();
        if ta != tb { return ta > tb; }
        return a.priority < b.priority;
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

    // Level-0 cells of the relayout's range, nearest ring first, until Saturated (budget or cull cap). A layer occupying few
    // of those cells walks its occupied list instead of the whole range: the list is ascending (row-major), so a stable
    // bucket by ring gives exactly the ring order. forceScan always walks the full ring order (the reference).
    private func PlaceCellsOf(L: ref<OverlayMapLayer>, cam: ref<NMCamera>, viewW: Float, viewH: Float) {
        let rg = this.indRg;
        let side = NMGrid.Side(0);
        let base = NMGrid.Base(0);
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
            while k < n && !this.Saturated() {
                this.PlaceChain(L, L.head[this.sOrd[k]], cam, viewW, viewH);
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
        while i < n2 && !this.Saturated() {
            this.PlaceChain(L, L.head[base + this.ordY[i] * side + this.ordX[i]], cam, viewW, viewH);
            i += 1;
        }
    }

    // One level-0 cell's items, until the cell's pile is full: cellMiss culls with no placement in between. Items
    // outside the view (or the selection, placed up front) neither count as a miss nor reset the count.
    private func PlaceChain(L: ref<OverlayMapLayer>, id: Int32, cam: ref<NMCamera>, viewW: Float, viewH: Float) {
        let miss = 0;
        while id >= 0 && miss < this.cellMiss && this.chipsUsed < this.chipCap && this.culled < this.cullLimit {
            let culledBefore = this.culled;
            let usedBefore = this.chipsUsed;
            this.PlaceChip(L, id, cam, viewW, viewH);
            if this.chipsUsed > usedBefore {
                miss = 0;
            } else if this.culled > culledBefore {
                miss += 1;
            }
            id = L.nextIn[id * 3];
        }
    }

    // Small layers (ScanAllMax items or fewer) scan every alive item per relayout.
    private func PlaceAllOf(L: ref<OverlayMapLayer>, cam: ref<NMCamera>, viewW: Float, viewH: Float) {
        let id = 0;
        let n = ArraySize(L.alive);
        while id < n && this.chipsUsed < this.chipCap && this.culled < this.cullLimit {
            if L.alive[id] {
                this.PlaceChip(L, id, cam, viewW, viewH);
            }
            id += 1;
        }
    }

    private func ResolveIcon(L: ref<OverlayMapLayer>, id: Int32) {
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
            ic.key = this.api.catKey[g];
            return;
        }
        ic.atlas = NMTheme.UiAtlas();
        ic.part = n"icon_dot";
        ic.key = "dot";
    }

    // The icon an item draws with, for the sidebar card: a fresh ref (ResolveIcon fills a shared scratch).
    public func IconOf(L: ref<OverlayMapLayer>, id: Int32) -> ref<NMIconRef> {
        this.ResolveIcon(L, id);
        let r = new NMIconRef();
        r.atlas = this.icon.atlas;
        r.part = this.icon.part;
        r.key = this.icon.key;
        return r;
    }

    // The tier scale (chipK) of the slot a candidate drew into; 1 for no candidate. Photo slots keep chipK at 1 (their
    // widgets take the tier scale directly), and OverlayMapSystem forces the reticle's scale to 1 for them anyway.
    public func CandScale(cand: Int32) -> Float {
        if cand < 0 || cand >= ArraySize(this.candSlot) { return 1.0; }
        return this.chipK[this.candSlot[cand]];
    }

    // Switches a pooled chip between the hex chip (0: collectibles, our pins) and the vanilla icon on its plate
    // (1 idle, 2 emphasised). The plate is a dark disc with a white ring, tinted with the icon colour in PlaceChip.
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
            bg.SetAtlasResource(NMTheme.UiAtlas());
            bg.SetTexturePart(n"plate");
            bg.SetSize(new Vector2(NMTheme.PlateSize() * k * this.scale, NMTheme.PlateSize() * k * this.scale));
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

    // Shows or hides the slot's scratch; it copies the icon's size, scale and opacity (on a hex chip, the chip's, so the
    // scratch crosses the whole chip), so call it after those are set.
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
        // Only the position changes from frame to frame; the rest is copied when the slot's look changed (PlaceChip
        // marks it stale; SetGrow keeps a shown strike in step itself).
        if !this.strikeOn[slot] || this.strikeStale[slot] {
            let ic = style == 0 ? this.chipBg[slot] : this.chipIcon[slot];
            st.SetSize(ic.GetSize());
            st.SetScale(ic.GetScale());
            st.SetOpacity(ic.GetOpacity());
            st.SetTintColor(tint);
            this.strikeStale[slot] = false;
        }
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
        this.chipBg[slot].SetOpacity(full * NMTheme.PlateOpacity());   // the plate is never idle-dimmed
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
        this.keepLayer = layer;   // the declutter never culls the selection, so it can't vanish under the reticle
        this.keepItem = item;
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

    // The declutter test of one item at screen point p, before it takes a slot. Returns false (and counts it culled)
    // when it collides with a marker already placed or a reserved area; Always-tier items and the selection are placed
    // regardless.
    // Either way a placed item occupies its visible circle: icon pins the plate's ring (PlateSize / 4, emphasised and
    // selected ones grown), hex chips and dots half their size, photo pins half the picture's width around its centre.
    private func Declutter(L: ref<OverlayMapLayer>, id: Int32, style: Int32, p: Vector2) -> Bool {
        let y = p.Y;
        let kept = L.index == this.keepLayer && id == this.keepItem;
        let r = this.rChip;
        if style == 3 {
            r = this.rPhoto;
            y -= this.photoLift;
        } else if style == 4 {
            r = this.rDot;
        } else if style != 0 {
            r = style == 2 || kept ? this.rPlateEmph : this.rPlate;
        }
        let x = p.X;
        if !this.curAlways && !kept && (this.Collides(x, y, r) || this.InReserved(x, y, r)) {   // most culls collide
            this.culled += 1;
            return false;
        }
        this.Occupy(x, y, r);
        return true;
    }

    private func PlaceChip(L: ref<OverlayMapLayer>, id: Int32, cam: ref<NMCamera>, viewW: Float, viewH: Float) -> Bool {
        if this.chipsUsed >= this.chipCap {
            return false;
        }
        if this.keptPlaced && id == this.keepItem && L.index == this.keepLayer {
            return false;   // the selection, already placed up front
        }
        if L.placedAt[id] == this.stamp {
            return false;   // already tested this relayout (replayed from the last one): placed, or culled for good
        }
        let p = cam.WorldToMap(L.px[id], L.py[id]);
        let m = NMItemRenderer.CullMargin(this.scale);
        if p.X < -m || p.X > viewW + m || p.Y < -m || p.Y > viewH + m {
            return false;
        }
        L.placedAt[id] = this.stamp;
        let style = L.shot[id] != 0u ? 3 : (L.dot[id] ? 4 : (L.pinStyle == 1 ? (L.emph[id] ? 2 : 1) : 0));
        if !this.noDeclutter && !this.Declutter(L, id, style, p) {
            return false;   // collides with a more important marker: no slot, no candidate
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
        if this.chipStyle[slot] != style {
            let wasPhoto = this.chipStyle[slot] == 3;
            let wasDot = this.chipStyle[slot] == 4;
            this.ApplyChipStyle(slot, style);
            this.strikeStale[slot] = true;
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
        let bgTint = style == 0 ? color : icTint;   // hex: the category colour; plate: its ring takes the icon colour
        if !this.chipTintOk[slot] || !NMItemRenderer.SameColor(this.chipTintBg[slot], bgTint) {
            bg.SetTintColor(bgTint);
            this.chipTintBg[slot] = bgTint;
        }
        if !this.chipTintOk[slot] || !NMItemRenderer.SameColor(this.chipTintIc[slot], icTint) {
            ic.SetTintColor(icTint);
            this.chipTintIc[slot] = icTint;
            this.strikeStale[slot] = true;
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
            this.strikeStale[slot] = true;
            if slot == this.growSlot {
                this.SetGrow(slot, this.growT);
            } else {
                bg.SetScale(new Vector2(k, k));
                ic.SetScale(new Vector2(k, k));
            }
        }
        let item = L.opacity * L.alpha[id] * this.curFade;
        let a = style == 1 ? item * NMTheme.VanillaIdleOpacity() : item;
        if this.chipAlpha[slot] != a {
            this.strikeStale[slot] = true;
            // The idle dim is the icon's only (spec 5.1): the plate keeps the item's alpha so its disc cuts out the city.
            bg.SetOpacity(style == 0 ? a : item * NMTheme.PlateOpacity());
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
