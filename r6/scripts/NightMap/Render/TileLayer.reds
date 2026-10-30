module NightMap

// One baked tile set (road, bfill, outline) as a map layer. Tiles are colourless masks: the colour comes from
// SetTint. Textures load asynchronously and the layer never waits for them.
//
// Each resident level has ONE container canvas sized to the level's whole grid (a 0x0 canvas would cull its children).
// Tiles sit in it at fixed level-local coordinates (ix * 512, iy * 512, 512 x 512 units of the level's texel grid), so
// panning and zooming is a single translation + scale on the container; the tiles never move. Tile widgets are only
// added or removed when the visible index range of a level changes. The fade opacity is on the container.
//
// Level choice is downscale-only (PickLevel). When the level changes the previous level stays resident underneath while
// the new one fades in on top over FadeMs; at most two levels are resident. The tiles are translucent masks, so two
// stacked levels would add up (and pop when the old one is dropped): the outgoing level is drawn at UnderOpacity, the
// exact opacity that keeps the combined coverage at the layer opacity all through the fade. It starts at the normal
// layer opacity and reaches 0 exactly when the incoming level reaches 1, where it is released. The outgoing level only
// follows the camera (transform and opacity): it never loads tiles and keeps the tile range it had.
//
// A pooled image keeps showing its old tile until a new texture has loaded, in its new place, so a tile stays hidden
// until the depot reports its atlas and texture loaded. The incoming level starts fading only once its tiles are in, so
// the outgoing one covers the map meanwhile. A load that never finishes gives up after LoadTimeoutMs.
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
    private let slotAtlas: array<ref<ResourceToken>>;
    private let slotTexture: array<ref<ResourceToken>>;
    private let slotWaiting: array<Bool>;
    private let slotAskedMs: array<Float>;
    private let slotFrames: array<Int32>;
    private let lvWaiting: array<Int32>;
    private let waiting: Int32;
    private let nowMs: Float;
    // Tiles of the next coarser level over the current view, so a zoom-out has them at once: the outgoing level only
    // covers what was on screen, and the wider view would show a bare ring around it until they load.
    private let preTokens: array<ref<ResourceToken>>;
    private let preKey: Int32;
    public let holdFade: Bool;       // the stack holds every set until all of them have their tiles
    public let skipLoadWait: Bool;   // test hook: fades run on time alone, as if every tile were in
    public let holdLoads: Bool;      // test hook: no load finishes
    private let cur: Int32;
    private let prev: Int32;
    private let aCur: Float;
    private let tint: HDRColor;
    private let opacity: Float;
    private let tintDirty: Bool;
    private let lastRev: Int32;
    // Levels coarser than the camera's pick this layer draws (0 for the road/bfill/outline sets). The glow set uses +2:
    // it is baked only at L2.., drawn upscaled by levelMpp / cam.mpp through the same container transform.
    private let levelOffset: Int32;

    public static func FadeMs() -> Float { return 150.0; }
    public static func LoadTimeoutMs() -> Float { return 1500.0; }
    // A loaded resource can take a frame or two to reach the widget.
    public static func RevealFrames() -> Int32 { return 2; }
    // Two resident levels at 4K (up to ~120 tiles each near a 2x ratio) with margin.
    public static func MaxSlots() -> Int32 { return 320; }

    public static func TilePath(setName: String, lv: Int32, ix: Int32, iy: Int32) -> String {
        return "nightmap\\tiles\\" + setName + "\\L" + ToString(lv) + "\\t_" + ToString(ix) + "_" + ToString(iy) + ".inkatlas";
    }

    // The UI atlas AND one tile the committed manifest lists (first tile of the coarsest level) must be in the depot: an
    // old or mismatched archive passes the first check alone and would give a silently blank map.
    public static func ArchiveAvailable() -> Bool {
        if !NMTileManifest.Available() || !GameInstance.GetResourceDepot().ResourceExists(NMTheme.UiAtlas()) {
            return false;
        }
        let lv = NMTileManifest.LevelCount() - 1;
        if lv < 0 {
            return false;
        }
        let nx = NMTileManifest.LevelNx(lv);
        let s = 0;
        while s < NMTileManifest.SetCount() {
            // Bind to a local: ArraySize/indexing of a call temporary reads 0 in-game.
            let tiles: array<Int32> = NMTileManifest.SetTiles(s, lv);
            if ArraySize(tiles) > 0 {
                let k = tiles[0];
                return GameInstance.GetResourceDepot().ResourceExists(ResRef.FromString(NMTileLayer.TilePath(NMTileManifest.SetName(s), lv, k % nx, k / nx)));
            }
            s += 1;
        }
        return false;
    }

    public static func MakeContainer(parent: ref<inkCanvas>) -> ref<inkCanvas> {
        let c = new inkCanvas();
        c.SetAnchor(inkEAnchor.Fill);
        c.SetInteractive(false);
        c.Reparent(parent);
        return c;
    }

    public static func Create(parent: ref<inkCanvas>, setIdx: Int32, levelOffset: Int32) -> ref<NMTileLayer> {
        let t = new NMTileLayer();
        t.setIdx = setIdx;
        t.levelOffset = Max(levelOffset, 0);
        t.setName = NMTileManifest.SetName(setIdx);
        t.lastRev = -1;
        t.preKey = -1;
        t.cur = -1;
        t.prev = -1;
        t.tint = NMTheme.TileTint(t.setName, 0);
        t.opacity = NMTheme.TileOpacity(t.setName);
        t.box = NMTileLayer.MakeContainer(parent);
        let base = 0;
        let l = 0;
        while l < NMTileManifest.LevelCount() {
            ArrayPush(t.levelBase, base);
            let n = NMTileManifest.LevelNx(l) * NMTileManifest.LevelNy(l);
            ArrayResize(t.slotOf, base + n);
            ArrayPush(t.cont, null);
            ArrayPush(t.lvWaiting, 0);
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

    // The level a layer with a level offset draws for a camera m/px: the picked level `offset` steps coarser, clamped to the
    // coarsest. offset 0 is PickLevel.
    public static func PickLevelOffset(mpp: Float, offset: Int32) -> Int32 {
        return Min(NMTileLayer.PickLevel(mpp) + Max(offset, 0), NMTileManifest.LevelCount() - 1);
    }

    public func LevelOffset() -> Int32 { return this.levelOffset; }

    // Crossfade ramp: one step of a linear 0..1 alpha. rising = fading in, else fading out.
    public static func FadeStep(a: Float, dtMs: Float, durMs: Float, rising: Bool) -> Float {
        let d = MaxF(dtMs, 0.0) / MaxF(durMs, 1.0);
        return ClampF(rising ? a + d : a - d, 0.0, 1.0);
    }

    // Opacity of the outgoing level while the incoming one is at alpha a: with the incoming level at op * a on top,
    // 1 - (1 - under) * (1 - op * a) = op for fully covered texels, so the pair never dims or brightens.
    public static func UnderOpacity(op: Float, a: Float) -> Float {
        if a >= 1.0 {
            return 0.0;
        }
        return ClampF(1.0 - (1.0 - op) / MaxF(1.0 - a * op, 0.0001), 0.0, 1.0);
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

    public func Alpha() -> Float { return this.aCur; }
    public func Waiting() -> Int32 { return this.waiting; }
    public func WaitingOnCurrent() -> Bool { return this.cur >= 0 && this.lvWaiting[this.cur] > 0; }
    public func CurrentLevel() -> Int32 { return this.cur; }
    public func PreviousLevel() -> Int32 { return this.prev; }

    public func Update(cam: ref<NMCamera>, dtMs: Float) {
        this.nowMs += MaxF(dtMs, 0.0);
        let fading = this.prev >= 0 || this.aCur < 1.0;
        if cam.revision == this.lastRev && !fading && !this.tintDirty && this.waiting == 0 {
            return;
        }
        this.lastRev = cam.revision;
        this.Reveal();
        let lv = NMTileLayer.PickLevelOffset(cam.mpp, this.levelOffset);
        let touch = this.tintDirty;
        let changed = false;
        if this.cur < 0 {
            this.cur = lv;
            this.aCur = 1.0;
        } else if lv != this.cur {
            if lv == this.prev {
                // Zoomed back into the level that is still fading out: swap roles. The returning level was shown at
                // UnderOpacity(aCur); as the incoming one it continues from the same opacity, and the other level
                // (shown at op * aCur) is then exactly what UnderOpacity of the new alpha gives.
                let tl = this.cur;
                this.aCur = this.opacity > 0.0001 ? NMTileLayer.UnderOpacity(this.opacity, this.aCur) / this.opacity : 1.0;
                this.cur = this.prev;
                this.prev = tl;
                touch = true;
                this.Container(this.cur).Reparent(this.box);   // incoming draws above outgoing
            } else {
                if this.prev >= 0 && this.aCur <= 0.0 {
                    this.ReleaseLevel(this.cur);   // never shown: what is on screen is still the outgoing level
                } else {
                    if this.prev >= 0 {
                        this.ReleaseLevel(this.prev);
                    }
                    this.prev = this.cur;
                }
                this.cur = lv;
                this.aCur = 0.0;
                changed = true;
                touch = true;
                this.Container(this.cur).Reparent(this.box);   // incoming draws above outgoing
            }
        }
        if this.aCur < 1.0 && !changed && (this.skipLoadWait || (!this.holdFade && this.lvWaiting[this.cur] == 0)) {
            this.aCur = NMTileLayer.FadeStep(this.aCur, dtMs, NMTileLayer.FadeMs(), true);
            touch = true;
        }
        if this.prev >= 0 && this.aCur >= 1.0 {
            this.ReleaseLevel(this.prev);
            this.prev = -1;
        }
        if this.tintDirty {
            let s = 0;
            while s < ArraySize(this.pool) {
                this.pool[s].SetTintColor(this.tint);
                s += 1;
            }
        }
        // The current level is placed first, so a full pool never starves the incoming level.
        this.PlaceLevel(cam, this.cur, this.opacity * this.aCur, touch, true);
        if this.prev >= 0 {
            this.PlaceLevel(cam, this.prev, NMTileLayer.UnderOpacity(this.opacity, this.aCur), touch, false);
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
    private func PlaceLevel(cam: ref<NMCamera>, lv: Int32, opac: Float, touch: Bool, load: Bool) {
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
            c.SetOpacity(opac);
        }
        if !load && shown {
            return;   // the outgoing level keeps its tile range: no new textures for a level that is about to vanish
        }
        let vis = cam.VisibleRect(0.0);
        let ix0 = Max(FloorF((vis.minX - ox) / tw), 0);
        let ix1 = Min(FloorF((vis.maxX - ox) / tw), nx - 1);
        let iy0 = Max(FloorF((otop - vis.maxY) / tw), 0);
        let iy1 = Min(FloorF((otop - vis.minY) / tw), ny - 1);
        if shown && this.rIx0[lv] == ix0 && this.rIx1[lv] == ix1 && this.rIy0[lv] == iy0 && this.rIy1[lv] == iy1 {
            return;
        }
        this.Preload(cam, lv + 1);
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
                        let path = NMTileLayer.TilePath(this.setName, lv, ix, iy);
                        let depot = GameInstance.GetResourceDepot();
                        img.Reparent(c);
                        img.SetAtlasResource(ResRef.FromString(path));
                        img.SetTexturePart(n"full");
                        img.SetTintColor(this.tint);
                        img.SetTranslation(new Vector2(Cast<Float>(ix) * 512.0, Cast<Float>(iy) * 512.0));
                        img.SetSize(new Vector2(512.0, 512.0));
                        this.slotAtlas[slot] = depot.LoadResource(ResRef.FromString(path));
                        this.slotTexture[slot] = depot.LoadResource(ResRef.FromString(StrReplace(path, ".inkatlas", ".xbm")));
                        this.slotWaiting[slot] = true;
                        this.slotAskedMs[slot] = this.nowMs;
                        this.slotFrames[slot] = 0;
                        this.lvWaiting[lv] += 1;
                        this.waiting += 1;
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

    private func Preload(cam: ref<NMCamera>, lv: Int32) {
        if lv >= NMTileManifest.LevelCount() {
            return;
        }
        let tw = 512.0 * NMTileManifest.LevelMpp(lv);
        let nx = NMTileManifest.LevelNx(lv);
        let vis = cam.VisibleRect(0.0);
        let ix0 = Max(FloorF((vis.minX - NMTileManifest.LevelOriginX(lv)) / tw) - 1, 0);
        let ix1 = Min(FloorF((vis.maxX - NMTileManifest.LevelOriginX(lv)) / tw) + 1, nx - 1);
        let iy0 = Max(FloorF((NMTileManifest.LevelOriginTop(lv) - vis.maxY) / tw) - 1, 0);
        let iy1 = Min(FloorF((NMTileManifest.LevelOriginTop(lv) - vis.minY) / tw) + 1, NMTileManifest.LevelNy(lv) - 1);
        let key = this.levelBase[lv] + iy0 * nx + ix0 + (ix1 - ix0) * 7 + (iy1 - iy0) * 977;
        if key == this.preKey {
            return;
        }
        this.preKey = key;
        ArrayClear(this.preTokens);
        let depot = GameInstance.GetResourceDepot();
        let iy = iy0;
        while iy <= iy1 {
            let ix = ix0;
            while ix <= ix1 {
                if this.Has(lv, ix, iy) {
                    let path = NMTileLayer.TilePath(this.setName, lv, ix, iy);
                    ArrayPush(this.preTokens, depot.LoadResource(ResRef.FromString(path)));
                    ArrayPush(this.preTokens, depot.LoadResource(ResRef.FromString(StrReplace(path, ".inkatlas", ".xbm"))));
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
        ArrayPush(this.slotAtlas, null);
        ArrayPush(this.slotTexture, null);
        ArrayPush(this.slotWaiting, false);
        ArrayPush(this.slotAskedMs, 0.0);
        ArrayPush(this.slotFrames, 0);
        ArrayPush(this.slotKey, -1);
        ArrayPush(this.slotLv, -1);
        ArrayPush(this.slotIx, 0);
        ArrayPush(this.slotIy, 0);
        return ArraySize(this.pool) - 1;
    }

    // Shows the tiles whose resources have arrived, or that have waited too long.
    private func Reveal() {
        if this.waiting == 0 {
            return;
        }
        let s = 0;
        while s < ArraySize(this.pool) {
            if this.slotWaiting[s] {
                if !this.holdLoads && this.slotAtlas[s].IsFinished() && this.slotTexture[s].IsFinished() {
                    this.slotFrames[s] += 1;
                }
                if this.slotFrames[s] > NMTileLayer.RevealFrames() || this.nowMs - this.slotAskedMs[s] >= NMTileLayer.LoadTimeoutMs() {
                    this.StopWaiting(s);
                    this.pool[s].SetVisible(true);
                }
            }
            s += 1;
        }
    }

    private func StopWaiting(s: Int32) {
        this.slotWaiting[s] = false;
        this.lvWaiting[this.slotLv[s]] -= 1;
        this.waiting -= 1;
    }

    private func ReleaseSlot(s: Int32) {
        if this.slotWaiting[s] {
            this.StopWaiting(s);
        }
        this.slotAtlas[s] = null;
        this.slotTexture[s] = null;
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
