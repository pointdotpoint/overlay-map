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

    // A closed session stays open this long, so shots still being written when photo mode closed are claimed.
    public static func SessionDone(closedAtMs: Float, nowMs: Float) -> Bool {
        return nowMs - closedAtMs >= 10000.0;
    }

    // Without a baseline every older screenshot would look new, so such a session claims nothing.
    public static func CanClaim(ss: ref<NMPhotoSession>) -> Bool {
        return IsDefined(ss) && ss.hasBaseline;
    }

    public static func Baseline(created: array<Uint64>) -> Uint64 {
        let b = 0ul;
        for c in created {
            if c > b { b = c; }
        }
        return b;
    }
}

// One photo mode session: where V stood, and the newest screenshot date before it (its baseline).
public class NMPhotoSession {
    public let pos: Vector4;
    public let yaw: Float;
    public let district: String;
    public let hasBaseline: Bool;
    public let baseline: Uint64;
    public let closed: Bool;
    public let closedAtMs: Float;
}

// Re-reads the screenshot list once a closed session's window has passed.
public class NMPhotoRelist extends DelayCallback {
    public let photos: wref<NMPhotos>;

    public func Call() {
        if IsDefined(this.photos) {
            this.photos.Relist();
        }
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
    private let session: ref<NMPhotoSession>;   // not yet resolved; null when none
    private let prev: ref<NMPhotoSession>;      // the session before, still inside its window
    private let hasNewest: Bool;                // newest creationDate seen in any list (baseline fallback)
    private let newest: Uint64;
    private let itemSpot: array<Int32>;   // layer item id -> index into spots (-1 free)
    private let syncedRev: Int32;
    private let sessionFresh: Bool;   // the current session has not seen a list yet
    private let lastHashes: array<Uint32>;   // hashes in the newest screenshot list
    private let perfSaved: Bool;
    private let perfSpots: array<ref<NMPhotoSpot>>;
    private let perfExists: array<Bool>;

    public static func LayerId() -> CName { return n"NightMap.Photos"; }
    public static func Category() -> CName { return n"Photos"; }
    // Shots load at full size (2560x1440), so only this many pins hold a thumbnail at once (spec §10).
    public static func ThumbCap() -> Int32 { return 24; }
    public static func ThumbAllowed(held: Int32, cap: Int32) -> Bool { return held < cap; }

    // The HUD minimap attached: read the list once now, so photo mode always has a baseline to fall back on.
    public func SetHandlerSource(m: wref<MinimapContainerController>) {
        this.minimap = m;
        if !this.hasNewest {
            this.RequestList("attach");
        }
    }
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

    public func IsPerfSeeded() -> Bool { return this.perfSaved; }

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
        L.SetTier(NightMapTier.Minor);
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
        if IsDefined(this.session) {
            if IsDefined(this.prev) {
                NMLog.Info("photo|link|dropped unresolved session");
            }
            this.prev = this.session;   // still claims its late shots on the next list
        }
        let ss = new NMPhotoSession();
        ss.pos = pos;
        ss.yaw = yaw;
        ss.district = district;
        ss.hasBaseline = this.hasNewest;   // fallback; the first list after open replaces it
        ss.baseline = this.newest;
        this.session = ss;
        this.sessionFresh = true;
        NMLog.Info("photo|session|open|baseline " + (ss.hasBaseline ? ToString(ss.baseline) : "none"));
        this.RequestList("photomode open");
    }

    public func OnPhotoModeClosed() {
        if !IsDefined(this.session) { return; }
        this.session.closed = true;
        this.session.closedAtMs = NMClock.NowMs();
        NMLog.Info("photo|session|close");
        this.RequestList("photomode close");
        let cb = new NMPhotoRelist();
        cb.photos = this;
        GameInstance.GetDelaySystem(GetGameInstance()).DelayCallback(cb, 11.0, false);
    }

    public func Relist() {
        this.RequestList("window");
    }

    public func OnMapOpened() {
        this.EnsureLoaded();
        this.RequestList("map open");
    }

    // Registers before every request, like the spike probe that received every list (a registration may be used up).
    private func RequestList(why: String) {
        let h: wref<inkISystemRequestsHandler>;
        if IsDefined(this.minimap) {
            h = this.minimap.GetSystemRequestsHandler();
        }
        if !IsDefined(h) {
            NMLog.Info("photo|list|no handler|" + why);
            return;
        }
        h.UnregisterFromCallback(n"OnScreenshotsForLoadReady", this, n"OnList");
        h.RegisterToCallback(n"OnScreenshotsForLoadReady", this, n"OnList");
        h.RequestGameScreenshotsForLoad();
        NMLog.Info("photo|list|requested|" + why);
    }

    // Every new shot since the session's baseline becomes a spot at the session's position.
    private func Claim(ss: ref<NMPhotoSession>, infos: array<GameScreenshotInfo>, hashes: array<Uint32>, created: array<Uint64>) {
        let known: array<Uint32>;
        for s in this.spots { ArrayPush(known, s.hash); }
        if this.perfSaved {
            for s in this.perfSpots { ArrayPush(known, s.hash); }
        }
        let added = 0;
        for i in NMPhotoLink.NewSince(hashes, created, ss.baseline, known) {
            let s = NMPhotoSpot.Create(hashes[i], infos[i].path, ss.pos, ss.yaw, created[i]);
            s.district = ss.district;
            if this.perfSaved {
                ArrayPush(this.perfSpots, s);
                ArrayPush(this.perfExists, true);
            } else {
                ArrayPush(this.spots, s);
                ArrayPush(this.exists, true);
            }
            if !NMPhotoStore.Append(s) {
                NMLog.Error("photo|store|append failed " + ToString(s.hash));
            }
            added += 1;
        }
        if added > 0 {
            NMLog.Info("photo|link|added " + ToString(added));
        }
    }

    protected cb func OnList(infos: array<GameScreenshotInfo>) -> Bool {
        this.EnsureLoaded();
        let hashes: array<Uint32>;
        let created: array<Uint64>;
        for inf in infos {
            ArrayPush(hashes, inf.pathHash);
            ArrayPush(created, inf.creationDate);
        }
        let now = NMClock.NowMs();
        NMLog.Info("photo|list|ready|" + ToString(ArraySize(infos)));
        if IsDefined(this.prev) {
            if NMPhotoLink.CanClaim(this.prev) {
                this.Claim(this.prev, infos, hashes, created);
            }
            if NMPhotoLink.SessionDone(this.prev.closedAtMs, now) { this.prev = null; }
        }
        if IsDefined(this.session) {
            let ss = this.session;
            if this.sessionFresh && !ss.closed {
                ss.baseline = NMPhotoLink.Baseline(created);   // after prev claimed its late shots above
                ss.hasBaseline = true;
            } else if !ss.hasBaseline {
                this.session = null;
                NMLog.Info("photo|link|no baseline");
            } else if ss.closed && NMPhotoLink.CanClaim(ss) {
                this.Claim(ss, infos, hashes, created);
                if NMPhotoLink.SessionDone(ss.closedAtMs, now) { this.session = null; }
            }
            this.sessionFresh = false;
        }
        if ArraySize(created) > 0 {
            this.newest = NMPhotoLink.Baseline(created);
            this.hasNewest = true;
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
