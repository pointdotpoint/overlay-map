module NightMap

// Callback target for one by-hash screenshot load into a photo chip's icon.
public class NMThumbListener extends IScriptable {
    public let r: wref<NMItemRenderer>;
    public let slot: Int32;
    public let key: String;

    protected cb func OnLoaded(size: Vector2, err: Int32) -> Bool {
        if IsDefined(this.r) {
            this.r.OnThumb(this.slot, this.key, size, err);
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

// Draws every visible layer through fixed widget pools.
// - Zoomed in (a 250 m cell >= ClusterSpacing on screen): individual chips, culled to the view.
// - Otherwise: screen-space blocks >= ClusterSpacing built from the grid pyramid; a block with one item
//   is a chip, larger blocks are a cluster hex with its top-3 categories.
// - A clustering layer that would overflow the chip budget is clustered at 250 m even when zoomed in.
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
    public let chipStyle: array<Int32>;   // -1 unset, 0 hex, 1 icon idle, 2 icon emphasised, 3 photo pin
    // Photo pins (style 3): a thumbnail in the slot's icon image, plus rectangles created on the slot's first photo:
    // a dark fill shown until the thumbnail loads, a 4-sided border, and a 45-degree point touching the spot.
    private let parent: wref<inkCanvas>;
    private let photoFill: array<ref<inkRectangle>>;
    private let photoEdge: array<ref<inkRectangle>>;   // [slot * 4 + side]
    private let photoPtr: array<ref<inkRectangle>>;
    private let photoOn: array<Bool>;
    private let thumbReady: array<Bool>;
    private let thumbsHeld: Int32;
    private let photoSel: Int32;
    private let photoColor: array<HDRColor>;
    private let shotHandler: wref<inkISystemRequestsHandler>;
    public let growSlot: Int32;           // slot currently growing/grown for the selection (icon idle pins), -1 none
    public let growT: Float;              // 0..1 progress of the selection grow
    private let growLayer: Int32;
    private let growItem: Int32;
    private let clBg: array<ref<inkImage>>;
    private let clText: array<ref<inkText>>;
    private let clShownCount: array<Int32>;
    private let clOn: array<Bool>;
    private let miniBg: array<ref<inkImage>>;
    private let miniIcon: array<ref<inkImage>>;
    private let miniCat: array<Int32>;
    private let miniOn: array<Bool>;
    public let selChip: ref<inkImage>;
    public let selCluster: ref<inkImage>;
    public let candX: array<Float>;
    public let candY: array<Float>;
    public let candKind: array<Int32>;
    public let candLayer: array<Int32>;
    public let candItem: array<Int32>;
    public let candSlot: array<Int32>;
    public let clWx: array<Float>;
    public let clWy: array<Float>;
    public let clWorld: array<Float>;
    public let clTotal: array<Int32>;
    // Stable identity of the cluster block: level * 100000000 + blockY * 10000 + blockX (absolute block coordinates).
    public let clKey: array<Int32>;
    public let clCats: array<Int32>;
    public let clCatCount: array<Int32>;
    public let clCatN: array<Int32>;
    private let bCount: array<Int32>;
    private let bSx: array<Float>;
    private let bSy: array<Float>;
    private let bAnyLayer: array<Int32>;
    private let bAnyCell: array<Int32>;
    private let bCat: array<Int32>;
    private let tGi: array<Int32>;
    private let tNext: array<Int32>;
    private let bTHead: array<Int32>;
    private let ordX: array<Int32>;
    private let ordY: array<Int32>;
    private let visit: array<Int32>;
    private let indRg: array<Int32>;
    private let halo: Bool;       // effects on: icon pins get a soft halo in their own colour instead of the dark shadow blob
    public let forceScan: Bool;   // test hook: bypass the occupied-cell lists (reference behaviour)
    private let icon: ref<NMIconRef>;
    private let lastCamRev: Int32;
    private let lastApiRev: Int32;
    private let thumbListeners: array<ref<NMThumbListener>>;
    public let chipsUsed: Int32;
    public let clustersUsed: Int32;
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
        // z-order (back to front): selected-cluster rim, clusters, selected-chip rim, chips
        r.selCluster = NMUi.Image(parent, n"cluster_sel", 0.0, 0.0, NMTheme.ClusterSelSize() * scale, NMTheme.Cyan(), true);
        r.selCluster.SetVisible(false);
        let i = 0;
        while i < NMTheme.ClusterBudget() {
            let bg = NMUi.Image(parent, n"cluster", 0.0, 0.0, NMTheme.ClusterSize() * scale, NMTheme.Cyan(), true);
            bg.SetVisible(false);
            ArrayPush(r.clBg, bg);
            let k = 0;
            while k < 3 {
                let mb = NMUi.Image(parent, n"mini", 0.0, 0.0, NMTheme.MiniSize() * scale, NMTheme.Cyan(), true);
                let mi = NMUi.Image(parent, n"icon_dot", 0.0, 0.0, NMTheme.IconSize() * 0.75 * scale, NMTheme.Cyan(), true);
                mb.SetVisible(false);
                mi.SetVisible(false);
                ArrayPush(r.miniBg, mb);
                ArrayPush(r.miniIcon, mi);
                ArrayPush(r.miniCat, -1);
                ArrayPush(r.miniOn, false);
                k += 1;
            }
            let t = NMUi.Text(parent, NMTheme.BodyFont(), n"Bold", Cast<Int32>(52.0 * scale), NMTheme.Text());
            t.SetAnchorPoint(new Vector2(0.5, 0.5));
            t.SetHorizontalAlignment(textHorizontalAlignment.Center);
            t.SetVisible(false);
            ArrayPush(r.clText, t);
            ArrayPush(r.clShownCount, -1);
            ArrayPush(r.clOn, false);
            ArrayPush(r.clWx, 0.0);
            ArrayPush(r.clWy, 0.0);
            ArrayPush(r.clWorld, 0.0);
            ArrayPush(r.clTotal, 0);
            ArrayPush(r.clKey, 0);
            ArrayPush(r.clCatN, 0);
            let c = 0;
            while c < 6 {
                ArrayPush(r.clCats, -1);
                ArrayPush(r.clCatCount, 0);
                c += 1;
            }
            i += 1;
        }
        r.selChip = NMUi.Image(parent, n"chip_sel", 0.0, 0.0, NMTheme.ChipSelSize() * scale, NMTheme.Cyan(), true);
        r.selChip.SetVisible(false);
        i = 0;
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
            ArrayPush(r.photoFill, null);
            ArrayPush(r.photoPtr, null);
            ArrayPush(r.photoOn, false);
            ArrayPush(r.thumbReady, false);
            ArrayPush(r.thumbListeners, null);
            ArrayPush(r.photoColor, NMTheme.Cyan());
            let e = 0;
            while e < 4 { ArrayPush(r.photoEdge, null); e += 1; }
            i += 1;
        }
        r.growSlot = -1;
        r.growLayer = -1;
        r.growItem = -1;
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

    public static func ThumbW() -> Float { return 72.0; }   // 16:9, 4K units (about 36x20 px at 1080p)
    public static func ThumbH() -> Float { return 41.0; }
    public static func PhotoEdge() -> Float { return 3.0; }
    public static func PhotoPtr() -> Float { return 14.0; }

    public func OnThumb(slot: Int32, key: String, size: Vector2, err: Int32) {
        if slot < 0 || slot >= ArraySize(this.chipIconKey) || NotEquals(this.chipIconKey[slot], key) {
            return;   // the slot moved on to another item
        }
        if size.X <= 0.0 || err != 0 {
            return;   // keep the plain frame
        }
        this.thumbReady[slot] = true;
        if this.photoOn[slot] {
            this.chipIcon[slot].SetVisible(true);
            this.photoFill[slot].SetVisible(false);
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
        this.photoFill[slot].SetVisible(on && !this.thumbReady[slot]);
        let e = 0;
        while e < 4 { this.photoEdge[slot * 4 + e].SetVisible(on); e += 1; }
        this.photoPtr[slot].SetVisible(on);
        this.chipIcon[slot].SetVisible(on && this.thumbReady[slot]);
        this.photoOn[slot] = on;
    }

    // Drops the slot's thumbnail (frees the full-size texture) so another pin can hold one.
    private func ReleaseThumb(slot: Int32) {
        if StrBeginsWith(this.chipIconKey[slot], "shot:") {
            this.thumbsHeld -= 1;
            let ic = this.chipIcon[slot];
            ic.SetAtlasResource(NMTheme.UiAtlas());
            ic.SetTexturePart(n"icon_dot");
            this.chipIconKey[slot] = "";
            this.chipIconPart[slot] = n"";
        }
        this.thumbReady[slot] = false;
    }

    private func PlacePhoto(L: ref<NightMapLayer>, id: Int32, slot: Int32, p: Vector2, color: HDRColor) -> Vector2 {
        this.EnsurePhotoWidgets(slot);
        let key = NMItemRenderer.IconKeyFor(L, id);
        if NotEquals(this.chipIconKey[slot], key) {
            this.ReleaseThumb(slot);
            if NMPhotos.ThumbAllowed(this.thumbsHeld, NMPhotos.ThumbCap()) && IsDefined(this.shotHandler) {
                let lst = new NMThumbListener();
                lst.r = this;
                lst.slot = slot;
                lst.key = key;
                this.chipIcon[slot].SetVisible(false);
                if this.shotHandler.RequestGameScreenshotByHash(L.shot[id], this.chipIcon[slot], lst, n"OnLoaded") {
                    this.chipIconKey[slot] = key;
                    this.thumbsHeld += 1;
                    this.thumbListeners[slot] = lst;
                }
            }
        }
        let s = this.scale;
        let tw = NMItemRenderer.ThumbW() * s;
        let th = NMItemRenderer.ThumbH() * s;
        let ed = NMItemRenderer.PhotoEdge() * s;
        let half = NMItemRenderer.PhotoPtr() * s * 0.7071;
        let c = new Vector2(p.X, p.Y - half - ed - th * 0.5);   // thumbnail centre; the point's tip sits on p
        let ic = this.chipIcon[slot];
        ic.SetSize(new Vector2(tw, th));
        ic.SetTintColor(new HDRColor(1.0, 1.0, 1.0, 1.0));
        ic.SetOpacity(L.opacity * L.alpha[id]);
        ic.SetTranslation(c);
        this.photoFill[slot].SetTranslation(c);
        let edgeColor = slot == this.photoSel ? NMTheme.Yellow() : color;
        let e = 0;
        while e < 4 {
            let r = this.photoEdge[slot * 4 + e];
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
        ArrayClear(this.candX);
        ArrayClear(this.candY);
        ArrayClear(this.candKind);
        ArrayClear(this.candLayer);
        ArrayClear(this.candItem);
        ArrayClear(this.candSlot);
        this.chipsUsed = 0;
        this.clustersUsed = 0;
        this.pendingImages = 0;
        let spacing = NMTheme.ClusterSpacing() * this.scale;
        let individual = NMGrid.CellSize(0) / cam.mpp >= spacing;
        let clusterLayers: array<Int32>;
        let order: array<Int32> = this.LayerOrder();
        if individual {
            // Same level-0 range and ring order for every layer: build them once per relayout.
            this.indRg = this.CellRange(0, cam, 60.0 * this.scale);
            this.RingOrder(this.indRg[0], this.indRg[1], this.indRg[2], this.indRg[3], this.CenterCell(0, cam, false), this.CenterCell(0, cam, true));
        }
        for li in order {
            let L = api.layers[li];
            if L.VisibleAt(cam.mpp) && L.count > 0 {
                if !L.clustering {
                    this.PlaceAllOf(L, cam, viewW, viewH);
                } else if individual && (this.chipsUsed + L.count <= NMTheme.ChipBudget() || this.chipsUsed + this.CountVisible(L) <= NMTheme.ChipBudget()) {
                    this.PlaceCellsOf(L, cam, viewW, viewH);
                } else {
                    ArrayPush(clusterLayers, li);
                }
            }
        }
        if ArraySize(clusterLayers) > 0 {
            this.PlaceClusters(clusterLayers, cam, viewW, viewH, individual);
        }
        this.HideUnused();
        return true;
    }

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

    // Items of L in the level-0 range of this relayout (this.indRg). Sparse layers sum their occupied cells.
    private func CountVisible(L: ref<NightMapLayer>) -> Int32 {
        let rg = this.indRg;
        let side = NMGrid.Side(0);
        let n = 0;
        let on = L.occN[0];
        let area = (rg[2] - rg[0] + 1) * (rg[3] - rg[1] + 1);
        if !this.forceScan && on * 2 < area {
            let oi = 0;
            while oi < on {
                let cell = L.occ[NMGrid.Base(0) + oi];
                oi += 1;
                let rel = cell - NMGrid.Base(0);
                let gy = rel / side;
                let gx = rel - gy * side;
                if gx >= rg[0] && gx <= rg[2] && gy >= rg[1] && gy <= rg[3] {
                    n += L.cnt[cell];
                }
            }
            return n;
        }
        let gy = rg[1];
        while gy <= rg[3] {
            let gx = rg[0];
            while gx <= rg[2] {
                n += L.cnt[NMGrid.Base(0) + gy * side + gx];
                gx += 1;
            }
            gy += 1;
        }
        return n;
    }

    // Fills ordX/ordY with the cells of [x0..x1]x[y0..y1] ordered by ring distance from (cx, cy).
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

    // Uses the ring order Update built for this relayout (ordX/ordY over the level-0 range).
    private func PlaceCellsOf(L: ref<NightMapLayer>, cam: ref<NMCamera>, viewW: Float, viewH: Float) {
        let side = NMGrid.Side(0);
        let n = ArraySize(this.ordX);
        let i = 0;
        while i < n {
            let id = L.head[this.ordY[i] * side + this.ordX[i]];
            while id >= 0 {
                this.PlaceChip(L, id, cam, viewW, viewH);
                id = L.nextIn[id * 3];
            }
            i += 1;
        }
    }

    // Non-clustering layers scan every alive item per relayout: only for small item counts.
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
            this.ReleaseThumb(slot);
        }
        if style == 3 {
            bg.SetVisible(false);
            bg.SetScale(new Vector2(1.0, 1.0));
            ic.SetScale(new Vector2(1.0, 1.0));
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
        if slot == this.growSlot {
            this.growSlot = -1;
        }
        this.chipStyle[slot] = style;
    }

    // t in 0..1: scale 1 -> VanillaEmphScale and opacity idle -> full, like the vanilla OnSelect animation.
    private func SetGrow(slot: Int32, t: Float) {
        let k = 1.0 + (NMTheme.VanillaEmphScale() - 1.0) * t;
        let base = this.chipAlpha[slot];
        let full = MinF(1.0, base / NMTheme.VanillaIdleOpacity());
        let o = base + (full - base) * t;
        this.chipBg[slot].SetScale(new Vector2(k, k));
        this.chipIcon[slot].SetScale(new Vector2(k, k));
        this.chipIcon[slot].SetOpacity(o);
        this.chipBg[slot].SetOpacity(o * this.BlobOpacity());
    }

    // Called every frame after the pick. Icon pins have no selection rim; an idle icon pin grows to the
    // emphasis look over VanillaGrowMs. cand indexes the cand* arrays (-1 none); kind is the selection kind.
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
        let style = L.shot[id] != 0u ? 3 : (L.pinStyle == 1 ? (L.emph[id] ? 2 : 1) : 0);
        if this.chipStyle[slot] != style {
            this.ApplyChipStyle(slot, style);
            this.chipTintOk[slot] = false;  // force the tint refresh below
            this.chipAlpha[slot] = -1.0;    // force the opacity refresh below
        }
        if style == 3 {
            let c = this.PlacePhoto(L, id, slot, p, color);
            this.chipOn[slot] = true;
            ArrayPush(this.candX, c.X);
            ArrayPush(this.candY, c.Y);
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
        let a = L.opacity * L.alpha[id];
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
            bg.SetVisible(true);
            ic.SetVisible(true);
            this.chipOn[slot] = true;
        }
        ArrayPush(this.candX, p.X);
        ArrayPush(this.candY, p.Y);
        ArrayPush(this.candKind, 0);
        ArrayPush(this.candLayer, L.index);
        ArrayPush(this.candItem, id);
        ArrayPush(this.candSlot, slot);
        return true;
    }

    // Fills this.visit with the non-empty cells of L at a level inside rg, in ascending cell index (= row-major,
    // the order a full scan visits them, so float sums and "last cell wins" are unchanged). The layer's occupied list
    // is already sorted, so a sparse layer is one filtered pass; a layer dense in view (or forceScan) scans.
    private func CollectCells(L: ref<NightMapLayer>, level: Int32, rg: array<Int32>) {
        ArrayClear(this.visit);
        let side = NMGrid.Side(level);
        let base = NMGrid.Base(level);
        let area = (rg[2] - rg[0] + 1) * (rg[3] - rg[1] + 1);
        let on = L.occN[level];
        if !this.forceScan && on * 2 < area {
            let oi = 0;
            while oi < on {
                let cell = L.occ[base + oi];
                oi += 1;
                let rel = cell - base;
                let gy = rel / side;
                let gx = rel - gy * side;
                if gx >= rg[0] && gx <= rg[2] && gy >= rg[1] && gy <= rg[3] {
                    ArrayPush(this.visit, cell);
                }
            }
            return;
        }
        let gy = rg[1];
        while gy <= rg[3] {
            let gx = rg[0];
            while gx <= rg[2] {
                let cell = base + gy * side + gx;
                if L.cnt[cell] > 0 {
                    ArrayPush(this.visit, cell);
                }
                gx += 1;
            }
            gy += 1;
        }
    }

    private func PlaceClusters(layers: array<Int32>, cam: ref<NMCamera>, viewW: Float, viewH: Float, individual: Bool) {
        let sp = NMTheme.ClusterSpacing() * this.scale;
        let level = 0;
        let k = 1;
        if !individual {
            level = 2;
            while level > 0 && NMGrid.CellSize(level) / cam.mpp > sp {
                level -= 1;
            }
            k = Max(1, CeilF(sp / (NMGrid.CellSize(level) / cam.mpp)));
        }
        let rg = this.CellRange(level, cam, 200.0 * this.scale);
        let side = NMGrid.Side(level);
        let base = NMGrid.Base(level);
        let bx0 = rg[0] / k;
        let by0 = rg[1] / k;
        let bw = rg[2] / k - bx0 + 1;
        let bh = rg[3] / k - by0 + 1;
        let nb = bw * bh;
        let maxCats = NMTheme.MaxGlobalCategories();
        if ArraySize(this.bCount) < nb {
            ArrayResize(this.bCount, nb);
            ArrayResize(this.bSx, nb);
            ArrayResize(this.bSy, nb);
            ArrayResize(this.bAnyLayer, nb);
            ArrayResize(this.bAnyCell, nb);
            ArrayResize(this.bCat, nb * maxCats);
            ArrayResize(this.bTHead, nb);
        }
        let b = 0;
        while b < nb {
            this.bCount[b] = 0;
            this.bSx[b] = 0.0;
            this.bSy[b] = 0.0;
            this.bAnyLayer[b] = -1;
            this.bAnyCell[b] = -1;
            this.bTHead[b] = -1;
            b += 1;
        }
        for li in layers {
            let L = this.api.layers[li];
            let ncat = ArraySize(L.catGlobal);
            this.CollectCells(L, level, rg);
            let vn = ArraySize(this.visit);
            let vi = 0;
            while vi < vn {
                let cell = this.visit[vi];
                vi += 1;
                let rel = cell - base;
                let gy = rel / side;
                let gx = rel - gy * side;
                b = (gy / k - by0) * bw + (gx / k - bx0);
                this.bCount[b] += L.cnt[cell];
                this.bSx[b] += L.sumX[cell];
                this.bSy[b] += L.sumY[cell];
                this.bAnyLayer[b] = li;
                this.bAnyCell[b] = cell;
                let lc = 0;
                while lc < ncat {
                    let t = L.tally[cell * NMGrid.MaxCats() + lc];
                    if t > 0 {
                        let gi = b * maxCats + L.catGlobal[lc];
                        if this.bCat[gi] == 0 {
                            ArrayPush(this.tGi, gi);
                            ArrayPush(this.tNext, this.bTHead[b]);
                            this.bTHead[b] = ArraySize(this.tGi) - 1;
                        }
                        this.bCat[gi] += t;
                    }
                    lc += 1;
                }
            }
        }
        let worldSize = Cast<Float>(k) * NMGrid.CellSize(level);
        this.RingOrder(0, 0, bw - 1, bh - 1, this.CenterCell(level, cam, false) / k - bx0, this.CenterCell(level, cam, true) / k - by0);
        let oi = 0;
        let on = ArraySize(this.ordX);
        while oi < on {
            let obx = this.ordX[oi];
            let oby = this.ordY[oi];
            b = oby * bw + obx;
            oi += 1;
            let n = this.bCount[b];
            if n == 1 {
                let L1 = this.api.layers[this.bAnyLayer[b]];
                this.PlaceChip(L1, L1.head[this.bAnyCell[b]], cam, viewW, viewH);
            } else if n > 1 {
                this.PlaceCluster(b, level * 100000000 + (by0 + oby) * 10000 + bx0 + obx, n, worldSize, cam, viewW, viewH);
            }
        }
        for gi in this.tGi {
            this.bCat[gi] = 0;
        }
        ArrayClear(this.tGi);
        ArrayClear(this.tNext);
    }

    private func PlaceCluster(b: Int32, key: Int32, n: Int32, worldSize: Float, cam: ref<NMCamera>, viewW: Float, viewH: Float) {
        if this.clustersUsed >= NMTheme.ClusterBudget() {
            return;
        }
        let wx = this.bSx[b] / Cast<Float>(n);
        let wy = this.bSy[b] / Cast<Float>(n);
        let p = cam.WorldToMap(wx, wy);
        let m = MaxF(100.0 * this.scale, worldSize / cam.mpp);
        if p.X < -m || p.X > viewW + m || p.Y < -m || p.Y > viewH + m {
            return;
        }
        let slot = this.clustersUsed;
        this.clustersUsed += 1;
        this.clWx[slot] = wx;
        this.clWy[slot] = wy;
        this.clWorld[slot] = worldSize;
        this.clTotal[slot] = n;
        this.clKey[slot] = key;
        // top 6 categories by count (ties: lower global index first), from this block's touched entries only
        let maxCats = NMTheme.MaxGlobalCategories();
        let found = 0;
        let ti = this.bTHead[b];
        while ti >= 0 {
            let gi = this.tGi[ti];
            let g = gi - b * maxCats;
            let v = this.bCat[gi];
            let pos = found;
            while pos > 0 && (this.clCatCount[slot * 6 + pos - 1] < v || (this.clCatCount[slot * 6 + pos - 1] == v && this.clCats[slot * 6 + pos - 1] > g)) {
                pos -= 1;
            }
            if pos < 6 {
                let q = Min(found, 5);
                while q > pos {
                    this.clCats[slot * 6 + q] = this.clCats[slot * 6 + q - 1];
                    this.clCatCount[slot * 6 + q] = this.clCatCount[slot * 6 + q - 1];
                    q -= 1;
                }
                this.clCats[slot * 6 + pos] = g;
                this.clCatCount[slot * 6 + pos] = v;
                if found < 6 {
                    found += 1;
                }
            }
            ti = this.tNext[ti];
        }
        this.clCatN[slot] = found;
        let c = found;
        while c < 6 {
            this.clCats[slot * 6 + c] = -1;
            this.clCatCount[slot * 6 + c] = 0;
            c += 1;
        }
        let bg = this.clBg[slot];
        let text = this.clText[slot];
        bg.SetTranslation(p);
        text.SetTranslation(p);
        if this.clShownCount[slot] != n {
            text.SetText(ToString(n));
            text.SetFontSize(Cast<Int32>((n >= 100 ? 40.0 : 52.0) * this.scale));
            this.clShownCount[slot] = n;
        }
        if !this.clOn[slot] {
            bg.SetVisible(true);
            text.SetVisible(true);
            this.clOn[slot] = true;
        }
        let shown = Min(found, 3);
        let mk = 0;
        while mk < 3 {
            let mi = slot * 3 + mk;
            if mk < shown {
                let g2 = this.clCats[slot * 6 + mk];
                let x = p.X + (Cast<Float>(mk) - Cast<Float>(shown - 1) * 0.5) * NMTheme.MiniSpacing() * this.scale;
                let y = p.Y + NMTheme.MiniOffsetY() * this.scale;
                this.miniBg[mi].SetTranslation(new Vector2(x, y));
                this.miniIcon[mi].SetTranslation(new Vector2(x, y));
                if this.miniCat[mi] != g2 {
                    let color = this.api.catColor[g2];
                    this.miniBg[mi].SetTintColor(color);
                    this.miniIcon[mi].SetTintColor(color);
                    if this.api.catHasIcon[g2] {
                        this.miniIcon[mi].SetAtlasResource(this.api.catAtlas[g2]);
                        this.miniIcon[mi].SetTexturePart(this.api.catPart[g2]);
                    } else {
                        this.miniIcon[mi].SetAtlasResource(NMTheme.UiAtlas());
                        this.miniIcon[mi].SetTexturePart(n"icon_dot");
                    }
                    this.miniCat[mi] = g2;
                }
                if !this.miniOn[mi] {
                    this.miniBg[mi].SetVisible(true);
                    this.miniIcon[mi].SetVisible(true);
                    this.miniOn[mi] = true;
                }
            } else if this.miniOn[mi] {
                this.miniBg[mi].SetVisible(false);
                this.miniIcon[mi].SetVisible(false);
                this.miniOn[mi] = false;
            }
            mk += 1;
        }
        ArrayPush(this.candX, p.X);
        ArrayPush(this.candY, p.Y);
        ArrayPush(this.candKind, 1);
        ArrayPush(this.candLayer, -1);
        ArrayPush(this.candItem, this.clKey[slot]);
        ArrayPush(this.candSlot, slot);
    }

    private func HideUnused() {
        let firstUsed = NMTheme.ChipBudget() - this.chipsUsed;
        let s = 0;
        while s < firstUsed {
            if this.chipOn[s] {
                this.chipBg[s].SetVisible(false);
                this.chipIcon[s].SetVisible(false);
                if this.photoOn[s] {
                    this.SetPhotoVisible(s, false);
                    this.ReleaseThumb(s);
                }
                if s == this.growSlot {
                    this.SetGrow(s, 0.0);
                    this.growSlot = -1;
                }
                this.chipOn[s] = false;
            }
            s += 1;
        }
        s = this.clustersUsed;
        while s < NMTheme.ClusterBudget() {
            if this.clOn[s] {
                this.clBg[s].SetVisible(false);
                this.clText[s].SetVisible(false);
                this.clOn[s] = false;
            }
            let mk = 0;
            while mk < 3 {
                let mi = s * 3 + mk;
                if this.miniOn[mi] {
                    this.miniBg[mi].SetVisible(false);
                    this.miniIcon[mi].SetVisible(false);
                    this.miniOn[mi] = false;
                }
                mk += 1;
            }
            s += 1;
        }
    }
}
