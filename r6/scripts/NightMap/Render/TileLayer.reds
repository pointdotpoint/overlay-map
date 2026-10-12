module NightMap

// Background tiles from NightMap.archive. Pool of 64 images; slots keep their tile while it stays visible
// so panning never re-assigns textures. Without the archive, draws a plain 1 km / 2 km grid instead.
public class NMTileLayer {
    private let pool: array<ref<inkImage>>;
    private let shownKey: array<Int32>;
    private let present: array<Bool>;
    private let levelBase: array<Int32>;
    private let grid: array<ref<inkRectangle>>;
    private let lastRev: Int32;
    public let available: Bool;
    public let level: Int32;

    public static func Create(parent: ref<inkCanvas>) -> ref<NMTileLayer> {
        let t = new NMTileLayer();
        t.lastRev = -1;
        t.level = -1;
        t.available = NMTileManifest.Available() && GameInstance.GetResourceDepot().ResourceExists(NMTheme.UiAtlas());
        if t.available {
            let base = 0;
            let i = 0;
            while i < NMTileManifest.LevelCount() {
                ArrayPush(t.levelBase, base);
                let n = NMTileManifest.LevelNx(i) * NMTileManifest.LevelNy(i);
                let k = 0;
                while k < n {
                    ArrayPush(t.present, false);
                    k += 1;
                }
                for idx in NMTileManifest.LevelTiles(i) {
                    t.present[base + idx] = true;
                }
                base += n;
                i += 1;
            }
            let p = 0;
            while p < 64 {
                let img = new inkImage();
                img.SetAnchor(inkEAnchor.TopLeft);
                img.SetVisible(false);
                img.SetInteractive(false);
                img.Reparent(parent);
                ArrayPush(t.pool, img);
                ArrayPush(t.shownKey, -1);
                p += 1;
            }
        } else {
            let g = 0;
            while g < 48 {
                let r = new inkRectangle();
                r.SetAnchor(inkEAnchor.TopLeft);
                r.SetTintColor(NMTheme.Cyan());
                r.SetOpacity(0.18);
                r.SetVisible(false);
                r.SetInteractive(false);
                r.Reparent(parent);
                ArrayPush(t.grid, r);
                g += 1;
            }
        }
        return t;
    }

    public static func PickLevel(mpp: Float) -> Int32 {
        let n = NMTileManifest.LevelCount();
        let i = 0;
        while i < n {
            if NMTileManifest.LevelMpp(i) >= mpp {
                return i;
            }
            i += 1;
        }
        return n - 1;
    }

    public func Update(cam: ref<NMCamera>) {
        if cam.revision == this.lastRev {
            return;
        }
        this.lastRev = cam.revision;
        if !this.available {
            this.UpdateGrid(cam);
            return;
        }
        let lv = NMTileLayer.PickLevel(cam.mpp);
        this.level = lv;
        let tw = 512.0 * NMTileManifest.LevelMpp(lv);
        let ox = NMTileManifest.LevelOriginX(lv);
        let otop = NMTileManifest.LevelOriginTop(lv);
        let nx = NMTileManifest.LevelNx(lv);
        let ny = NMTileManifest.LevelNy(lv);
        let vis = cam.VisibleRect(0.0);
        let ix0 = Max(FloorF((vis.minX - ox) / tw), 0);
        let ix1 = Min(FloorF((vis.maxX - ox) / tw), nx - 1);
        let iy0 = Max(FloorF((otop - vis.maxY) / tw), 0);
        let iy1 = Min(FloorF((otop - vis.minY) / tw), ny - 1);
        let want: array<Int32>;
        let iy = iy0;
        while iy <= iy1 {
            let ix = ix0;
            while ix <= ix1 {
                let key = this.levelBase[lv] + iy * nx + ix;
                if this.present[key] {
                    ArrayPush(want, key);
                }
                ix += 1;
            }
            iy += 1;
        }
        let s = 0;
        while s < ArraySize(this.pool) {
            if this.shownKey[s] >= 0 && !ArrayContains(want, this.shownKey[s]) {
                this.pool[s].SetVisible(false);
                this.shownKey[s] = -1;
            }
            s += 1;
        }
        let size = tw / cam.mpp + 1.0;   // +1 unit overlap hides seams
        for key in want {
            let slot = this.SlotFor(key);
            if slot < 0 {
                break;
            }
            let local = key - this.levelBase[lv];
            let tix = local % nx;
            let tiy = local / nx;
            let img = this.pool[slot];
            if this.shownKey[slot] != key {
                img.SetAtlasResource(ResRef.FromString("nightmap\\tiles\\L" + ToString(lv) + "\\t_" + ToString(tix) + "_" + ToString(tiy) + ".inkatlas"));
                img.SetTexturePart(n"full");
                img.SetVisible(true);
                this.shownKey[slot] = key;
            }
            img.SetTranslation(cam.WorldToMap(ox + Cast<Float>(tix) * tw, otop - Cast<Float>(tiy) * tw));
            img.SetSize(new Vector2(size, size));
        }
    }

    // The slot already showing this tile, else the first free slot, else -1.
    private func SlotFor(key: Int32) -> Int32 {
        let free = -1;
        let s = 0;
        while s < ArraySize(this.shownKey) {
            if this.shownKey[s] == key {
                return s;
            }
            if free < 0 && this.shownKey[s] < 0 {
                free = s;
            }
            s += 1;
        }
        return free;
    }

    private func UpdateGrid(cam: ref<NMCamera>) {
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
