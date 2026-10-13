module NightMap

// One baked tile set (road, bfill, glow, outline) as a map layer. Tiles are colourless masks: the colour comes from
// SetTint. Textures load asynchronously and the layer never waits for them.
//
// Each resident level has ONE container canvas sized to the level's whole grid (a 0x0 canvas would cull its children).
// Tiles sit in it at fixed level-local coordinates (ix * 512, iy * 512, 512 x 512 units of the level's texel grid), so
// panning and zooming is a single translation + scale on the container; the tiles never move. Tile widgets are only
// added or removed when the visible index range of a level changes. The fade opacity is on the container.
//
// Level choice is downscale-only (PickLevel). When the level changes the previous level stays resident and fades out
// over FadeMs while the new one fades in; at most two levels are resident.
public class NMTileLayer extends NMMapLayer {
    private let box: ref<inkCanvas>;
    private let setIdx: Int32;
    private let setName: String;
    // SetTiles of every level, concatenated; level l is keys[lvStart[l] .. lvEnd[l]) and sorted (iy * nx + ix).
    private let keys: array<Int32>;
    private let cont: array<ref<inkCanvas>>;
    private let rSet: array<Bool>;
    private let rIx0: array<Int32>;
    private let rIx1: array<Int32>;
    private let rIy0: array<Int32>;
    private let rIy1: array<Int32>;
    private let capLogged: Bool;
    private let lvStart: array<Int32>;
    private let lvEnd: array<Int32>;
    // Global tile id = levelBase[l] + iy * nx + ix. slotOf maps a global id to its pool slot + 1 (0 = none).
    private let levelBase: array<Int32>;
    private let slotOf: array<Int32>;
    private let pool: array<ref<inkImage>>;
    private let slotKey: array<Int32>;
    private let slotLv: array<Int32>;
    private let slotIx: array<Int32>;
    private let slotIy: array<Int32>;
    private let freeSlots: array<Int32>;
    private let cur: Int32;
    private let prev: Int32;
    private let aCur: Float;
    private let aPrev: Float;
    private let tint: HDRColor;
    private let opacity: Float;
    private let tintDirty: Bool;
    private let lastRev: Int32;

    public static func FadeMs() -> Float { return 150.0; }
    // Two resident levels at 4K (up to ~120 tiles each near a 2x ratio) with margin.
    public static func MaxSlots() -> Int32 { return 320; }

    public static func ArchiveAvailable() -> Bool {
        return NMTileManifest.Available() && GameInstance.GetResourceDepot().ResourceExists(NMTheme.UiAtlas());
    }

    public static func MakeContainer(parent: ref<inkCanvas>) -> ref<inkCanvas> {
        let c = new inkCanvas();
        c.SetAnchor(inkEAnchor.Fill);
        c.SetInteractive(false);
        c.Reparent(parent);
        return c;
    }

    public static func Create(parent: ref<inkCanvas>, setIdx: Int32) -> ref<NMTileLayer> {
        let t = new NMTileLayer();
        t.setIdx = setIdx;
        t.setName = NMTileManifest.SetName(setIdx);
        t.lastRev = -1;
        t.cur = -1;
        t.prev = -1;
        t.tint = NMTheme.TileTint(t.setName);
        t.opacity = NMTheme.TileOpacity(t.setName);
        t.box = NMTileLayer.MakeContainer(parent);
        let base = 0;
        let l = 0;
        while l < NMTileManifest.LevelCount() {
            ArrayPush(t.levelBase, base);
            let n = NMTileManifest.LevelNx(l) * NMTileManifest.LevelNy(l);
            ArrayResize(t.slotOf, base + n);
            ArrayPush(t.cont, null);
            ArrayPush(t.rSet, false);
            ArrayPush(t.rIx0, 0);
            ArrayPush(t.rIx1, 0);
            ArrayPush(t.rIy0, 0);
            ArrayPush(t.rIy1, 0);
            base += n;
            // Bind to a local: ArraySize/iteration of a call temporary reads 0 in-game.
            let tiles: array<Int32> = NMTileManifest.SetTiles(setIdx, l);
            ArrayPush(t.lvStart, ArraySize(t.keys));
            for idx in tiles {
                ArrayPush(t.keys, idx);
            }
            ArrayPush(t.lvEnd, ArraySize(t.keys));
            l += 1;
        }
        return t;
    }

    public func Name() -> String { return this.setName; }

    public func SetVisible(visible: Bool) {
        this.box.SetVisible(visible);
    }

    // Applied to every resident tile on the next Update, and to every tile assigned later.
    public func SetTint(color: HDRColor, opacity: Float) {
        this.tint = color;
        this.opacity = opacity;
        this.tintDirty = true;
    }

    // Downscale only: the coarsest level whose m/px <= the camera's m/px, clamped to the finest. The 0.1 %
    // tolerance keeps float noise at an exact level boundary from picking the finer neighbour.
    public static func PickLevel(mpp: Float) -> Int32 {
        let n = NMTileManifest.LevelCount();
        let best = 0;
        let i = 1;
        while i < n {
            if NMTileManifest.LevelMpp(i) <= mpp * 1.001 {
                best = i;
            }
            i += 1;
        }
        return best;
    }

    // Crossfade ramp: one step of a linear 0..1 alpha. rising = fading in, else fading out.
    public static func FadeStep(a: Float, dtMs: Float, durMs: Float, rising: Bool) -> Float {
        let d = MaxF(dtMs, 0.0) / MaxF(durMs, 1.0);
        return ClampF(rising ? a + d : a - d, 0.0, 1.0);
    }

    // Is tile (ix, iy) of this set's level lv baked? Binary search in the sorted SetTiles list.
    public func Has(lv: Int32, ix: Int32, iy: Int32) -> Bool {
        if lv < 0 || lv >= ArraySize(this.lvStart) {
            return false;
        }
        let nx = NMTileManifest.LevelNx(lv);
        if ix < 0 || iy < 0 || ix >= nx || iy >= NMTileManifest.LevelNy(lv) {
            return false;
        }
        let key = iy * nx + ix;
        let lo = this.lvStart[lv];
        let hi = this.lvEnd[lv] - 1;
        while lo <= hi {
            let mid = (lo + hi) / 2;
            let v = this.keys[mid];
            if v == key {
                return true;
            }
            if v < key {
                lo = mid + 1;
            } else {
                hi = mid - 1;
            }
        }
        return false;
    }

    public func Resident() -> Int32 {
        return ArraySize(this.pool) - ArraySize(this.freeSlots);
    }

    public func CurrentLevel() -> Int32 { return this.cur; }
    public func PreviousLevel() -> Int32 { return this.prev; }

    public func Update(cam: ref<NMCamera>, dtMs: Float) {
        let fading = this.prev >= 0 || this.aCur < 1.0;
        if cam.revision == this.lastRev && !fading && !this.tintDirty {
            return;
        }
        this.lastRev = cam.revision;
        let lv = NMTileLayer.PickLevel(cam.mpp);
        if this.cur < 0 {
            this.cur = lv;
            this.aCur = 1.0;
        } else if lv != this.cur {
            if lv == this.prev {
                // Zoomed back into the level that is still fading out: swap roles, alphas stay continuous.
                let tl = this.cur;
                let ta = this.aCur;
                this.cur = this.prev;
                this.aCur = this.aPrev;
                this.prev = tl;
                this.aPrev = ta;
            } else {
                if this.prev >= 0 {
                    this.ReleaseLevel(this.prev);
                }
                this.prev = this.cur;
                this.aPrev = this.aCur;
                this.cur = lv;
                this.aCur = 0.0;
            }
        }
        let touch = this.tintDirty;
        if this.aCur < 1.0 {
            this.aCur = NMTileLayer.FadeStep(this.aCur, dtMs, NMTileLayer.FadeMs(), true);
            touch = true;
        }
        if this.prev >= 0 {
            this.aPrev = NMTileLayer.FadeStep(this.aPrev, dtMs, NMTileLayer.FadeMs(), false);
            touch = true;
            if this.aPrev <= 0.0 {
                this.ReleaseLevel(this.prev);
                this.prev = -1;
            }
        }
        if this.tintDirty {
            let s = 0;
            while s < ArraySize(this.pool) {
                this.pool[s].SetTintColor(this.tint);
                s += 1;
            }
        }
        // The current level is placed first, so a full pool never starves the incoming level.
        this.PlaceLevel(cam, this.cur, this.aCur, touch);
        if this.prev >= 0 {
            this.PlaceLevel(cam, this.prev, this.aPrev, touch);
        }
        this.tintDirty = false;
    }

    private func Container(lv: Int32) -> ref<inkCanvas> {
        if !IsDefined(this.cont[lv]) {
            let c = new inkCanvas();
            c.SetAnchor(inkEAnchor.TopLeft);
            c.SetInteractive(false);
            c.SetSize(new Vector2(Cast<Float>(NMTileManifest.LevelNx(lv)) * 512.0, Cast<Float>(NMTileManifest.LevelNy(lv)) * 512.0));
            c.SetRenderTransformPivot(new Vector2(0.0, 0.0));
            c.Reparent(this.box);
            this.cont[lv] = c;
        }
        return this.cont[lv];
    }

    // One transform per frame for the whole level; tile widgets change only when the visible index range changes.
    private func PlaceLevel(cam: ref<NMCamera>, lv: Int32, alpha: Float, touch: Bool) {
        let mpp = NMTileManifest.LevelMpp(lv);
        let tw = 512.0 * mpp;
        let ox = NMTileManifest.LevelOriginX(lv);
        let otop = NMTileManifest.LevelOriginTop(lv);
        let nx = NMTileManifest.LevelNx(lv);
        let ny = NMTileManifest.LevelNy(lv);
        let c = this.Container(lv);
        let shown = this.rSet[lv];
        if !shown {
            c.SetVisible(true);
        }
        let k = mpp / cam.mpp;
        c.SetScale(new Vector2(k, k));
        c.SetTranslation(cam.WorldToMap(ox, otop));
        if touch || !shown {
            c.SetOpacity(this.opacity * alpha);
        }
        let vis = cam.VisibleRect(0.0);
        let ix0 = Max(FloorF((vis.minX - ox) / tw), 0);
        let ix1 = Min(FloorF((vis.maxX - ox) / tw), nx - 1);
        let iy0 = Max(FloorF((otop - vis.maxY) / tw), 0);
        let iy1 = Min(FloorF((otop - vis.minY) / tw), ny - 1);
        if shown && this.rIx0[lv] == ix0 && this.rIx1[lv] == ix1 && this.rIy0[lv] == iy0 && this.rIy1[lv] == iy1 {
            return;
        }
        this.rSet[lv] = true;
        this.rIx0[lv] = ix0;
        this.rIx1[lv] = ix1;
        this.rIy0[lv] = iy0;
        this.rIy1[lv] = iy1;
        // Free the slots of this level that scrolled out of view.
        let s = 0;
        while s < ArraySize(this.pool) {
            if this.slotKey[s] >= 0 && this.slotLv[s] == lv
                && (this.slotIx[s] < ix0 || this.slotIx[s] > ix1 || this.slotIy[s] < iy0 || this.slotIy[s] > iy1) {
                this.ReleaseSlot(s);
            }
            s += 1;
        }
        let iy = iy0;
        while iy <= iy1 {
            let ix = ix0;
            while ix <= ix1 {
                let gk = this.levelBase[lv] + iy * nx + ix;
                if this.slotOf[gk] == 0 && this.Has(lv, ix, iy) {
                    let slot = this.AllocSlot();
                    if slot >= 0 {
                        let img = this.pool[slot];
                        img.Reparent(c);
                        img.SetAtlasResource(ResRef.FromString("nightmap\\tiles\\" + this.setName + "\\L" + ToString(lv)
                            + "\\t_" + ToString(ix) + "_" + ToString(iy) + ".inkatlas"));
                        img.SetTexturePart(n"full");
                        img.SetTintColor(this.tint);
                        img.SetTranslation(new Vector2(Cast<Float>(ix) * 512.0, Cast<Float>(iy) * 512.0));
                        img.SetSize(new Vector2(512.0, 512.0));
                        img.SetVisible(true);
                        this.slotKey[slot] = gk;
                        this.slotLv[slot] = lv;
                        this.slotIx[slot] = ix;
                        this.slotIy[slot] = iy;
                        this.slotOf[gk] = slot + 1;
                    } else if !this.capLogged {
                        this.capLogged = true;
                        NMLog.Error("tile pool exhausted in set " + this.setName + " (cap " + ToString(NMTileLayer.MaxSlots()) + "): some tiles will be missing");
                    }
                }
                ix += 1;
            }
            iy += 1;
        }
    }

    private func AllocSlot() -> Int32 {
        if ArraySize(this.freeSlots) > 0 {
            return ArrayPop(this.freeSlots);
        }
        if ArraySize(this.pool) >= NMTileLayer.MaxSlots() {
            return -1;
        }
        let img = new inkImage();
        img.SetAnchor(inkEAnchor.TopLeft);
        img.SetVisible(false);
        img.SetInteractive(false);
        img.Reparent(this.box);
        ArrayPush(this.pool, img);
        ArrayPush(this.slotKey, -1);
        ArrayPush(this.slotLv, -1);
        ArrayPush(this.slotIx, 0);
        ArrayPush(this.slotIy, 0);
        return ArraySize(this.pool) - 1;
    }

    private func ReleaseSlot(s: Int32) {
        this.pool[s].SetVisible(false);
        this.slotOf[this.slotKey[s]] = 0;
        this.slotKey[s] = -1;
        this.slotLv[s] = -1;
        ArrayPush(this.freeSlots, s);
    }

    private func ReleaseLevel(lv: Int32) {
        let s = 0;
        while s < ArraySize(this.pool) {
            if this.slotKey[s] >= 0 && this.slotLv[s] == lv {
                this.ReleaseSlot(s);
            }
            s += 1;
        }
        this.rSet[lv] = false;
        if IsDefined(this.cont[lv]) {
            this.cont[lv].SetVisible(false);
        }
    }
}
