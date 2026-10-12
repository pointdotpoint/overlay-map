module NightMap

public class NMIconRef {
    public let atlas: ResRef;
    public let part: CName;
    public let key: String;
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
    private let chipBg: array<ref<inkImage>>;
    private let chipIcon: array<ref<inkImage>>;
    private let chipOn: array<Bool>;
    private let chipCat: array<Int32>;
    private let chipIconKey: array<String>;
    private let chipAlpha: array<Float>;
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
    public let clCats: array<Int32>;
    public let clCatCount: array<Int32>;
    public let clCatN: array<Int32>;
    private let bCount: array<Int32>;
    private let bSx: array<Float>;
    private let bSy: array<Float>;
    private let bAnyLayer: array<Int32>;
    private let bAnyCell: array<Int32>;
    private let bCat: array<Int32>;
    private let bTouched: array<Int32>;
    private let icon: ref<NMIconRef>;
    private let lastCamRev: Int32;
    private let lastApiRev: Int32;
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
            let t = NMUi.Text(parent, NMTheme.HeadingFont(), n"Bold", Cast<Int32>(52.0 * scale), NMTheme.Text());
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
            ArrayPush(r.chipCat, -1);
            ArrayPush(r.chipIconKey, "");
            ArrayPush(r.chipAlpha, 1.0);
            i += 1;
        }
        return r;
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
        for li in this.LayerOrder() {
            let L = api.layers[li];
            if L.VisibleAt(cam.mpp) && L.count > 0 {
                if !L.clustering {
                    this.PlaceAllOf(L, cam, viewW, viewH);
                } else if individual && this.chipsUsed + this.CountVisible(L, cam) <= NMTheme.ChipBudget() {
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

    private func CountVisible(L: ref<NightMapLayer>, cam: ref<NMCamera>) -> Int32 {
        let rg = this.CellRange(0, cam, 60.0 * this.scale);
        let side = NMGrid.Side(0);
        let n = 0;
        let gy = rg[1];
        while gy <= rg[3] {
            let gx = rg[0];
            while gx <= rg[2] {
                n += L.cnt[gy * side + gx];
                gx += 1;
            }
            gy += 1;
        }
        return n;
    }

    private func PlaceCellsOf(L: ref<NightMapLayer>, cam: ref<NMCamera>, viewW: Float, viewH: Float) {
        let rg = this.CellRange(0, cam, 60.0 * this.scale);
        let side = NMGrid.Side(0);
        let gy = rg[1];
        while gy <= rg[3] {
            let gx = rg[0];
            while gx <= rg[2] {
                let id = L.head[gy * side + gx];
                while id >= 0 {
                    this.PlaceChip(L, id, cam, viewW, viewH);
                    id = L.nextIn[id * 3];
                }
                gx += 1;
            }
            gy += 1;
        }
    }

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
            ic.pending = true;
        }
        if L.hasAtlas[id] {
            ic.atlas = L.atlas[id];
            ic.part = L.part[id];
            ic.key = ResRef.ToString(L.atlas[id]) + "|" + NameToString(L.part[id]);
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
        let g = L.catGlobal[L.cat[id]];
        let color = this.api.catColor[g];
        if this.chipCat[slot] != g || L.hasTint[id] {
            bg.SetTintColor(color);
            ic.SetTintColor(L.hasTint[id] ? L.tint[id] : color);
            this.chipCat[slot] = L.hasTint[id] ? -1 : g;
        }
        this.ResolveIcon(L, id);
        if this.icon.pending {
            this.pendingImages += 1;
        }
        if NotEquals(this.chipIconKey[slot], this.icon.key) {
            ic.SetAtlasResource(this.icon.atlas);
            ic.SetTexturePart(this.icon.part);
            this.chipIconKey[slot] = this.icon.key;
        }
        if this.chipAlpha[slot] != L.opacity {
            bg.SetOpacity(L.opacity);
            ic.SetOpacity(L.opacity);
            this.chipAlpha[slot] = L.opacity;
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
        }
        let b = 0;
        while b < nb {
            this.bCount[b] = 0;
            this.bSx[b] = 0.0;
            this.bSy[b] = 0.0;
            this.bAnyLayer[b] = -1;
            this.bAnyCell[b] = -1;
            b += 1;
        }
        for li in layers {
            let L = this.api.layers[li];
            let ncat = ArraySize(L.catGlobal);
            let gy = rg[1];
            while gy <= rg[3] {
                let gx = rg[0];
                while gx <= rg[2] {
                    let cell = base + gy * side + gx;
                    let c = L.cnt[cell];
                    if c > 0 {
                        b = (gy / k - by0) * bw + (gx / k - bx0);
                        this.bCount[b] += c;
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
                                    ArrayPush(this.bTouched, gi);
                                }
                                this.bCat[gi] += t;
                            }
                            lc += 1;
                        }
                    }
                    gx += 1;
                }
                gy += 1;
            }
        }
        let worldSize = Cast<Float>(k) * NMGrid.CellSize(level);
        b = 0;
        while b < nb {
            let n = this.bCount[b];
            if n == 1 {
                let L1 = this.api.layers[this.bAnyLayer[b]];
                this.PlaceChip(L1, L1.head[this.bAnyCell[b]], cam, viewW, viewH);
            } else if n > 1 {
                this.PlaceCluster(b, n, worldSize, cam, viewW, viewH);
            }
            b += 1;
        }
        for gi in this.bTouched {
            this.bCat[gi] = 0;
        }
        ArrayClear(this.bTouched);
    }

    private func PlaceCluster(b: Int32, n: Int32, worldSize: Float, cam: ref<NMCamera>, viewW: Float, viewH: Float) {
        if this.clustersUsed >= NMTheme.ClusterBudget() {
            return;
        }
        let wx = this.bSx[b] / Cast<Float>(n);
        let wy = this.bSy[b] / Cast<Float>(n);
        let p = cam.WorldToMap(wx, wy);
        let m = 100.0 * this.scale;
        if p.X < -m || p.X > viewW + m || p.Y < -m || p.Y > viewH + m {
            return;
        }
        let slot = this.clustersUsed;
        this.clustersUsed += 1;
        this.clWx[slot] = wx;
        this.clWy[slot] = wy;
        this.clWorld[slot] = worldSize;
        this.clTotal[slot] = n;
        // top 6 categories by count (repeated max over the 64 global slots)
        let maxCats = NMTheme.MaxGlobalCategories();
        let found = 0;
        let last = 2147483647;
        let lastIdx = -1;
        while found < 6 {
            let best = -1;
            let bestN = 0;
            let g = 0;
            while g < maxCats {
                let v = this.bCat[b * maxCats + g];
                let before = v < last || (v == last && g > lastIdx);
                if v > bestN && before {
                    best = g;
                    bestN = v;
                }
                g += 1;
            }
            if best < 0 {
                break;
            }
            this.clCats[slot * 6 + found] = best;
            this.clCatCount[slot * 6 + found] = bestN;
            last = bestN;
            lastIdx = best;
            found += 1;
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
        ArrayPush(this.candItem, -1);
        ArrayPush(this.candSlot, slot);
    }

    private func HideUnused() {
        let firstUsed = NMTheme.ChipBudget() - this.chipsUsed;
        let s = 0;
        while s < firstUsed {
            if this.chipOn[s] {
                this.chipBg[s].SetVisible(false);
                this.chipIcon[s].SetVisible(false);
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
