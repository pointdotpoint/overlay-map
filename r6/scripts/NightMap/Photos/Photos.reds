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
    private let hasBaseline: Bool;
    private let baseline: Uint64;

    public func SetHandlerSource(m: wref<MinimapContainerController>) { this.minimap = m; }
    public func Spots() -> array<ref<NMPhotoSpot>> { this.EnsureLoaded(); return this.spots; }
    public func Exists(i: Int32) -> Bool { return i >= 0 && i < ArraySize(this.exists) && this.exists[i]; }
    public func Revision() -> Int32 { return this.rev; }

    private func EnsureLoaded() {
        if this.loaded { return; }
        this.loaded = true;
        this.spots = NMPhotoStore.Load();
        ArrayClear(this.exists);
        for s in this.spots { ArrayPush(this.exists, true); }   // until the first list says otherwise
        this.rev += 1;
        NMLog.Info("photo|store|loaded " + ToString(ArraySize(this.spots)));
    }

    public func OnPhotoModeOpened(pos: Vector4, yaw: Float) {
        this.EnsureLoaded();
        if this.session {
            NMLog.Info("photo|link|dropped unresolved session");
        }
        this.session = true;
        this.sessClosed = false;
        this.sessPos = pos;
        this.sessYaw = yaw;
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
        let i = 0;
        while i < ArraySize(this.spots) {
            this.exists[i] = ArrayContains(hashes, this.spots[i].hash);
            i += 1;
        }
        this.rev += 1;
        return true;
    }
}
