module NightMap

// Linking new screenshots to photo mode sessions (spike findings, spec §10): V cannot move in photo mode, so
// every shot newer than the session's baseline gets the session's spot.
public abstract class NMPhotoLink {
    // Indices of entries newer than `baseline` whose hash is not in `known`, oldest first.
    public static func NewSince(hashes: array<Uint32>, created: array<Uint64>, baseline: Uint64, known: array<Uint32>) -> array<Int32> {
        let out: array<Int32>;
        let i = 0;
        while i < ArraySize(hashes) && i < ArraySize(created) {
            if created[i] > baseline && !ArrayContains(known, hashes[i]) {
                let k = 0;
                while k < ArraySize(out) && created[out[k]] <= created[i] {
                    k += 1;
                }
                ArrayInsert(out, k, i);
            }
            i += 1;
        }
        return out;
    }

    public static func Baseline(created: array<Uint64>) -> Uint64 {
        let b = 0ul;
        for c in created {
            if c > b { b = c; }
        }
        return b;
    }
}

// Saved photo spots and the open photo mode session. The game's screenshot list always comes through the HUD
// minimap controller's request handler (the photo mode controller's never delivers it).
public class NMPhotos extends IScriptable {
    private let spots: array<ref<NMPhotoSpot>>;
    private let exists: array<Bool>;
    private let loaded: Bool;
    private let rev: Int32;
    private let minimap: wref<MinimapContainerController>;
    private let registeredOn: wref<inkISystemRequestsHandler>;
    private let session: Bool;        // a photo mode session not yet resolved
    private let sessClosed: Bool;
    private let sessPos: Vector4;
    private let sessYaw: Float;
    private let sessDistrict: String;
    private let hasBaseline: Bool;
    private let baseline: Uint64;
    private let itemSpot: array<Int32>;   // layer item id -> index into spots (-1 free)
    private let syncedRev: Int32;
    private let lastHashes: array<Uint32>;   // hashes in the newest screenshot list
    private let perfSaved: Bool;
    private let perfSpots: array<ref<NMPhotoSpot>>;
    private let perfExists: array<Bool>;

    public static func LayerId() -> CName { return n"NightMap.Photos"; }
    public static func Category() -> CName { return n"Photos"; }
    // Shots load at full size (2560x1440), so only this many pins hold a thumbnail at once (spec §10).
    public static func ThumbCap() -> Int32 { return 24; }
    public static func ThumbAllowed(held: Int32, cap: Int32) -> Bool { return held < cap; }

    public func SetHandlerSource(m: wref<MinimapContainerController>) { this.minimap = m; }
    public func Spots() -> array<ref<NMPhotoSpot>> { this.EnsureLoaded(); return this.spots; }
    public func Exists(i: Int32) -> Bool { return i >= 0 && i < ArraySize(this.exists) && this.exists[i]; }
    public func Revision() -> Int32 { return this.rev; }
    public func SyncedRevision() -> Int32 { return this.syncedRev; }

    public func Handler() -> wref<inkISystemRequestsHandler> {
        if IsDefined(this.minimap) {
            return this.minimap.GetSystemRequestsHandler();
        }
        return null;
    }

    // Test seam: replaces the loaded spots without touching the file.
    public func SetSpotsForTest(spots: array<ref<NMPhotoSpot>>, exists: array<Bool>) {
        this.loaded = true;
        this.spots = spots;
        this.exists = exists;
        this.rev += 1;
    }

    // Perf suite: replaces the spots with n seeded ones spread over the city (cycling through the real shot hashes
    // so thumbnails really load). EndPerfSeed() puts the saved spots back.
    public func SeedForPerf(n: Int32) {
        this.EnsureLoaded();
        if !this.perfSaved {
            this.perfSpots = this.spots;
            this.perfExists = this.exists;
            this.perfSaved = true;
        }
        let spots: array<ref<NMPhotoSpot>>;
        let exists: array<Bool>;
        let seed = 12345;
        let i = 0;
        while i < n {
            seed = (seed * 1103515245 + 12345) & 2147483647;
            let x = -2600.0 + 4200.0 * Cast<Float>(seed % 10000) / 10000.0;
            seed = (seed * 1103515245 + 12345) & 2147483647;
            let y = -3200.0 + 5400.0 * Cast<Float>(seed % 10000) / 10000.0;
            let h = ArraySize(this.lastHashes) > 0 ? this.lastHashes[i % ArraySize(this.lastHashes)] : Cast<Uint32>(i + 1);
            ArrayPush(spots, NMPhotoSpot.Create(h, "photomode_01012077_000000.png", new Vector4(x, y, 20.0, 1.0), 0.0, Cast<Uint64>(i + 1)));
            ArrayPush(exists, true);
            i += 1;
        }
        this.spots = spots;
        this.exists = exists;
        this.rev += 1;
    }

    public func EndPerfSeed() {
        if !this.perfSaved { return; }
        this.spots = this.perfSpots;
        this.exists = this.perfExists;
        this.perfSaved = false;
        this.rev += 1;
    }

    // The spot behind a Photos layer item, or null.
    public func SpotOf(itemId: Int32) -> ref<NMPhotoSpot> {
        if itemId < 0 || itemId >= ArraySize(this.itemSpot) || this.itemSpot[itemId] < 0 {
            return null;
        }
        return this.spots[this.itemSpot[itemId]];
    }

    // One item per place (the newest existing shot within NMPhotoGroups.Radius()).
    public func SyncLayer(api: ref<NightMap>, visible: Bool) {
        this.EnsureLoaded();
        let L = api.CreateLayer(NMPhotos.LayerId(), "Photos", 60);
        L.SetClustering(false);
        L.SetCategory(NMPhotos.Category(), "PHOTO", NMTheme.Cyan());
        L.Clear();
        ArrayClear(this.itemSpot);
        for idx in NMPhotoGroups.Newest(this.spots, this.exists, NMPhotoGroups.Radius()) {
            let s = this.spots[idx];
            let id = L.Add(NightMapItem.Shot(s.Position(), NMPhotos.Category(), s.hash));
            if id >= 0 {
                while ArraySize(this.itemSpot) <= id { ArrayPush(this.itemSpot, -1); }
                this.itemSpot[id] = idx;
            }
        }
        L.SetVisible(visible);
        this.syncedRev = this.rev;
    }

    private func EnsureLoaded() {
        if this.loaded { return; }
        this.loaded = true;
        this.spots = NMPhotoStore.Load();
        ArrayClear(this.exists);
        for s in this.spots { ArrayPush(this.exists, true); }   // until the first list says otherwise
        this.rev += 1;
        NMLog.Info("photo|store|loaded " + ToString(ArraySize(this.spots)));
    }

    public func OnPhotoModeOpened(pos: Vector4, yaw: Float, district: String) {
        this.EnsureLoaded();
        if this.session {
            NMLog.Info("photo|link|dropped unresolved session");
        }
        this.session = true;
        this.sessClosed = false;
        this.sessPos = pos;
        this.sessYaw = yaw;
        this.sessDistrict = district;
        this.hasBaseline = false;
        this.RequestList();
    }

    public func OnPhotoModeClosed() {
        if !this.session { return; }
        this.sessClosed = true;
        this.RequestList();
    }

    public func OnMapOpened() {
        this.EnsureLoaded();
        this.RequestList();
    }

    private func RequestList() {
        let h: wref<inkISystemRequestsHandler>;
        if IsDefined(this.minimap) {
            h = this.minimap.GetSystemRequestsHandler();
        }
        if !IsDefined(h) {
            NMLog.Info("photo|list|no handler");
            return;
        }
        let cur: ref<inkISystemRequestsHandler> = this.registeredOn;
        let hs: ref<inkISystemRequestsHandler> = h;
        if cur != hs {
            h.RegisterToCallback(n"OnScreenshotsForLoadReady", this, n"OnList");
            this.registeredOn = h;
        }
        h.RequestGameScreenshotsForLoad();
    }

    protected cb func OnList(infos: array<GameScreenshotInfo>) -> Bool {
        this.EnsureLoaded();
        let hashes: array<Uint32>;
        let created: array<Uint64>;
        for inf in infos {
            ArrayPush(hashes, inf.pathHash);
            ArrayPush(created, inf.creationDate);
        }
        if this.session {
            if !this.hasBaseline {
                if this.sessClosed {
                    this.session = false;
                    NMLog.Info("photo|link|no baseline");
                } else {
                    this.baseline = NMPhotoLink.Baseline(created);
                    this.hasBaseline = true;
                }
            } else if this.sessClosed {
                let known: array<Uint32>;
                for s in this.spots { ArrayPush(known, s.hash); }
                let added = 0;
                for i in NMPhotoLink.NewSince(hashes, created, this.baseline, known) {
                    let s = NMPhotoSpot.Create(hashes[i], infos[i].path, this.sessPos, this.sessYaw, created[i]);
                    s.district = this.sessDistrict;
                    ArrayPush(this.spots, s);
                    ArrayPush(this.exists, true);
                    if !NMPhotoStore.Append(s) {
                        NMLog.Error("photo|store|append failed " + ToString(s.hash));
                    }
                    added += 1;
                }
                this.session = false;
                NMLog.Info("photo|link|added " + ToString(added));
            }
        }
        this.lastHashes = hashes;
        if this.perfSaved {
            this.rev += 1;
            return true;   // seeded perf spots: leave them alone
        }
        let i = 0;
        while i < ArraySize(this.spots) {
            this.exists[i] = ArrayContains(hashes, this.spots[i].hash);
            i += 1;
        }
        this.rev += 1;
        return true;
    }
}
